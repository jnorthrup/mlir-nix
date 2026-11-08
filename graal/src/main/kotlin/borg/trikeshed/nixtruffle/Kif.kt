package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import com.oracle.truffle.api.frame.VirtualFrame
import com.oracle.truffle.api.nodes.Node
import com.oracle.truffle.api.nodes.RootNode
import java.io.File

// The Graal arm of kif-chase (lib/Dialect/KifChase.cpp): a kif.theory read from mlnix's son-export, its rules made into Truffle
// node trees (one RootNode per rule; a premise is a node: and, not, equal, exists, instance, a pattern), chained forward to a
// fixpoint with the same order of everything as datalog.nix and the pass, so the closures and their proofs are equal.

/// Interned terms: an atom (a variable is an atom whose text starts with ? and has a name after it), or a list of terms.
class KTerms {
    val text = ArrayList<String?>()        // an atom's text; null for a list
    val kids = ArrayList<IntArray?>()      // a list's elements
    private val atoms = HashMap<String, Int>()
    private val lists = HashMap<List<Int>, Int>()
    private val shown = HashMap<Int, String>()
    private val groundMemo = HashMap<Int, Boolean>()

    fun atom(s: String): Int = atoms.getOrPut(s) { text.add(s); kids.add(null); text.size - 1 }
    fun lookupAtom(s: String): Int = atoms[s] ?: -1
    fun list(es: IntArray): Int = lists.getOrPut(es.toList()) { text.add(null); kids.add(es); text.size - 1 }
    fun isList(t: Int) = kids[t] != null
    fun isVar(t: Int) = text[t]?.let { it.length >= 2 && it[0] == '?' } ?: false
    fun size(t: Int) = kids[t]?.size ?: 0
    fun at(t: Int, i: Int) = kids[t]!![i]
    fun head(t: Int) = kids[t]?.let { if (it.isEmpty()) -1 else it[0] } ?: -1
    fun show(t: Int): String = text[t] ?: shown.getOrPut(t) { kids[t]!!.joinToString(" ", "(", ")") { show(it) } }
    fun ground(t: Int): Boolean = groundMemo.getOrPut(t) { if (isList(t)) kids[t]!!.all { ground(it) } else !isVar(t) }
}

/// Code-point order: the order of UTF-8 bytes, which is how Nix and the pass compare the printed facts.
val codePointOrder = Comparator<String> { a, b ->
    var i = 0; var j = 0
    while (i < a.length && j < b.length) {
        val x = a.codePointAt(i); val y = b.codePointAt(j)
        if (x != y) return@Comparator x.compareTo(y)
        i += Character.charCount(x); j += Character.charCount(y)
    }
    (a.length - i).compareTo(b.length - j)
}

class KState(@JvmField val b: IntArray, @JvmField val used: IntArray) { // b: variable, value, variable, value ...
    fun get(v: Int): Int { var i = 0; while (i < b.size) { if (b[i] == v) return b[i + 1]; i += 2 }; return -1 }
    fun bind(v: Int, x: Int) = KState(b + intArrayOf(v, x), used)
    fun use(f: Int) = KState(b, used + f)
}

class KEntry(val fact: Int, val rule: Int, val round: Int, val from: IntArray)

/// One round's view of the facts (datalog.nix's `index`).
class KRound(val c: KChase) {
    val sorted: IntArray
    val byHead = HashMap<Int, ArrayList<Int>>()
    val byFirst = HashMap<Long, ArrayList<Int>>()
    init {
        val T = c.T
        sorted = c.entries.indices.sortedWith(Comparator { x, y -> codePointOrder.compare(T.show(c.entries[x].fact), T.show(c.entries[y].fact)) }).toIntArray()
        for (e in sorted) {
            val f = c.entries[e].fact
            byHead.getOrPut(T.head(f)) { ArrayList() }.add(e)
            if (T.isList(f) && T.size(f) > 1 && !T.isList(T.at(f, 1))) byFirst.getOrPut(key(T.head(f), T.at(f, 1))) { ArrayList() }.add(e)
        }
    }
    companion object { fun key(h: Int, a: Int) = (h.toLong() shl 32) or (a.toLong() and 0xffffffffL) }
}

class KChase(val T: KTerms) {
    val entries = ArrayList<KEntry>()
    val idx = HashMap<Int, Int>()
    val parents = HashMap<String, ArrayList<String>>()
    var hasOntology = false
    private val ancestorsMemo = HashMap<String, HashSet<String>>()

    fun ancestors(c: String): Set<String> = ancestorsMemo.getOrPut(c) {
        val out = HashSet<String>(); val work = ArrayDeque(parents[c] ?: emptyList())
        while (work.isNotEmpty()) { val p = work.removeLast(); if (out.add(p)) parents[p]?.let { work.addAll(it) } }
        out
    }
    fun isSubclass(c: Int, a: Int): Boolean {
        if (c == a) return true
        val x = T.text[c] ?: return false; val y = T.text[a] ?: return false
        return y in ancestors(x)
    }

    @TruffleBoundary
    fun subst(s: KState, t: Int): Int {
        if (!T.isList(t)) { if (!T.isVar(t)) return t; val x = s.get(t); return if (x < 0) t else x }
        if (T.ground(t)) return t
        return T.list(IntArray(T.size(t)) { subst(s, T.at(t, it)) })
    }

    /// unify: the bindings that make pattern p equal to term f, or null.
    @TruffleBoundary
    fun unify(s: KState, p: Int, f: Int): KState? {
        if (!T.isList(p)) {
            if (T.isVar(p)) { val x = s.get(p); return if (x >= 0) (if (x == f) s else null) else s.bind(p, f) }
            return if (p == f) s else null
        }
        if (!T.isList(f) || T.size(p) != T.size(f)) return null
        var t: KState = s
        for (i in 0 until T.size(p)) t = unify(t, T.at(p, i), T.at(f, i)) ?: return null
        return t
    }

    @TruffleBoundary
    fun candidates(r: KRound, s: KState, p: Int): List<Int> {
        val q = subst(s, p); val h = T.head(q)
        if (T.ground(q)) return idx[q]?.let { listOf(it) } ?: emptyList()
        if (h >= 0 && !T.isList(h) && !T.isVar(h)) {
            if (T.size(q) > 1 && !T.isList(T.at(q, 1)) && !T.isVar(T.at(q, 1))) return r.byFirst[KRound.key(h, T.at(q, 1))] ?: emptyList()
            return r.byHead[h] ?: emptyList()
        }
        return r.sorted.asList()
    }
}

// ── premises as Truffle nodes ───────────────────────────────────────────────────────────────────────────────────────────

abstract class Premise : Node() {
    abstract fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>)
}
class AndPremise(@field:Children @JvmField val parts: Array<Premise>) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) {
        var sols: List<KState> = listOf(s)
        for (p in parts) {
            val next = ArrayList<KState>()
            for (t in sols) p.solve(c, r, t, next)
            sols = next
            if (sols.isEmpty()) break
        }
        out.addAll(sols)
    }
}
class NotPremise(@field:Child @JvmField var p: Premise) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) {
        val sub = ArrayList<KState>(); p.solve(c, r, s, sub); if (sub.isEmpty()) out.add(s)
    }
}
class ExistsPremise(@field:Child @JvmField var p: Premise) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) = p.solve(c, r, s, out)
}
class EqualPremise(@JvmField val a: Int, @JvmField val b: Int) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) { if (c.subst(s, a) == c.subst(s, b)) out.add(s) }
}
/// (instance X Class) with an ontology: X is an instance of Class when an instance fact names a subclass of Class.  When Class
/// is still a variable it is a pattern like any other.
class InstancePremise(@JvmField val p: Int, @field:Child @JvmField var asPattern: PatternPremise) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) {
        val T = c.T
        val cls = c.subst(s, T.at(p, 2))
        if (T.isVar(cls)) return asPattern.solve(c, r, s, out)
        val inst = r.byHead[T.head(p)] ?: return
        for (e in inst) {
            val f = c.entries[e].fact
            if (T.size(f) != 3 || !c.isSubclass(T.at(f, 2), cls)) continue
            val t = c.unify(s, T.at(p, 1), T.at(f, 1)) ?: continue
            out.add(t.use(f))
        }
    }
}
class PatternPremise(@JvmField val p: Int) : Premise() {
    override fun solve(c: KChase, r: KRound, s: KState, out: MutableList<KState>) {
        for (e in c.candidates(r, s, p)) {
            val f = c.entries[e].fact
            val t = c.unify(s, p, f) ?: continue
            out.add(t.use(f))
        }
    }
}

/// A rule: its antecedent's node tree under a RootNode, called once a round; it returns the solutions.
class RuleRoot(val id: String, val consequent: Int, @field:Child @JvmField var antecedent: Premise) : RootNode(null) {
    override fun execute(frame: VirtualFrame): Any {
        val c = frame.arguments[0] as KChase; val r = frame.arguments[1] as KRound
        val out = ArrayList<KState>()
        antecedent.solve(c, r, KState(IntArray(0), IntArray(0)), out)
        return out
    }
    override fun getName() = id
}

object KifEngine {
    /// A premise term as nodes, by its relation (datalog.nix's step).
    fun premise(T: KTerms, c: KChase, p: Int): Premise {
        val h = T.head(p); val name = if (h >= 0) T.text[h] else null
        return when {
            name == "and" -> AndPremise(Array(T.size(p) - 1) { premise(T, c, T.at(p, it + 1)) })
            name == "exists" -> ExistsPremise(premise(T, c, T.at(p, 2)))
            name == "not" -> NotPremise(premise(T, c, T.at(p, 1)))
            name == "equal" -> EqualPremise(T.at(p, 1), T.at(p, 2))
            name == "instance" && c.hasOntology && T.size(p) == 3 -> InstancePremise(p, PatternPremise(p))
            else -> PatternPremise(p)
        }
    }

    class Theory(val name: String, val ontology: String?, val facts: IntArray, val rules: List<Pair<Int, Int>>, val subclass: List<Pair<String, String>>)

    /// The theories of a son-export of mlnix-kif's module.
    fun read(json: ByteArray, T: KTerms): List<Theory> {
        val out = ArrayList<Theory>()
        for (t in Graph.module(json)) {
            if (t.name != "kif.theory") continue
            val term = HashMap<Int, Int>()
            val ops = t.regions[0][0].ops
            val def = HashMap<Int, Op>(); for (o in ops) for (r in o.res) def[r] = o
            fun of(v: Int): Int = term[v] ?: run {
                val o = def[v]!!
                val id = when (o.name) {
                    "kif.atom", "kif.var" -> T.atom(o.str("name")!!)
                    else -> T.list(IntArray(o.ins.size) { of(o.ins[it]) })
                }
                term[v] = id; id
            }
            val facts = ArrayList<Int>(); val rules = ArrayList<Pair<Int, Int>>(); val sub = ArrayList<Pair<String, String>>()
            for (o in ops) when (o.name) {
                "kif.fact" -> {
                    val f = of(o.ins[0]); facts.add(f)
                    if (T.size(f) == 3 && T.text[T.head(f)] == "subclass" && !T.isList(T.at(f, 1)) && !T.isList(T.at(f, 2)))
                        sub.add(T.text[T.at(f, 1)]!! to T.text[T.at(f, 2)]!!)
                }
                "kif.rule" -> rules.add(of(o.ins[0]) to of(o.ins[1]))
                "sumo.subclass" -> sub.add(o.str("child")!! to o.str("parent")!!)
            }
            out.add(Theory(t.str("sym_name")!!, t.attrs["ontology"]?.let { (it as List<*>)[0] as String }, facts.toIntArray(), rules, sub))
        }
        return out
    }

    /// The closure of a theory: asserted entries, then the derived ones in the order found; rule ids as datalog.nix names them.
    fun chase(T: KTerms, th: Theory, onto: Theory?): Pair<KChase, List<String>> {
        val c = KChase(T)
        if (onto != null) { c.hasOntology = true; for ((a, b) in onto.subclass) c.parents.getOrPut(a) { ArrayList() }.add(b) }
        for (f in th.facts) if (f !in c.idx) { c.idx[f] = c.entries.size; c.entries.add(KEntry(f, -1, 0, IntArray(0))) }
        val ids = th.rules.mapIndexed { i, (_, cons) -> (if (T.head(cons) >= 0) T.show(T.head(cons)) else "") + "#" + (i + 1) }
        val roots = th.rules.mapIndexed { i, (ante, cons) -> RuleRoot(ids[i], cons, premise(T, c, ante)) }
        val targets = roots.map { it.callTarget }
        var round = 1
        while (true) {
            val r = KRound(c)
            val fresh = LinkedHashMap<Int, KEntry>()
            for ((i, root) in roots.withIndex()) {
                @Suppress("UNCHECKED_CAST") val sols = targets[i].call(c, r) as List<KState>
                for (s in sols) {
                    val f = c.subst(s, root.consequent)
                    if (!T.ground(f)) throw NixError("rule ${root.id}: the consequent keeps a variable (${T.show(f)})")
                    if (f in c.idx || f in fresh) continue
                    fresh[f] = KEntry(f, i, round, s.used)
                }
            }
            if (fresh.isEmpty()) break
            for ((f, e) in fresh) { c.idx[f] = c.entries.size; c.entries.add(e) }
            round++
        }
        return c to ids
    }

    fun dump(T: KTerms, c: KChase, ids: List<String>): List<String> =
        c.entries.map { e ->
            if (e.rule < 0) T.show(e.fact) + "\t-"
            else (listOf(T.show(e.fact), ids[e.rule]) + e.from.map { T.show(it) }).joinToString("\t")
        }.distinct().sortedWith(Comparator { a, b -> codePointOrder.compare(a.substringBefore('\t'), b.substringBefore('\t')) })

    /// nix-truffle --kif [--chase] --dump [--ontology F]... F...: mlnix-kif makes the module, mlnix-opt exports it.
    fun main(bin: String, args: List<String>) {
        val onto = ArrayList<String>(); val kb = ArrayList<String>()
        var i = 0
        while (i < args.size) { when (args[i]) { "--ontology" -> onto.add(args[++i]); "--chase", "--dump" -> {}; else -> kb.add(args[i]) }; i++ }
        val mlir = File.createTempFile("kif", ".mlir"); mlir.deleteOnExit()
        val cmd = listOf("$bin/mlnix-kif") + onto.flatMap { listOf("--ontology", it) } + kb + listOf("-o", mlir.path)
        val p1 = ProcessBuilder(cmd).inheritIO().start()
        if (p1.waitFor() != 0) throw NixError("mlnix-kif failed")
        val p2 = ProcessBuilder("$bin/mlnix-opt", mlir.path, "--son-export", "-o", "/dev/null").redirectError(ProcessBuilder.Redirect.INHERIT).start()
        val json = p2.inputStream.readAllBytes()
        if (p2.waitFor() != 0) throw NixError("son-export failed")
        val T = KTerms()
        val theories = KifEngine.read(json, T)
        val kbT = theories.first { it.name == "kb" }
        val (c, ids) = chase(T, kbT, theories.firstOrNull { it.name == kbT.ontology })
        val out = System.out.bufferedWriter(Charsets.UTF_8)
        for (l in dump(T, c, ids)) { out.write(l); out.write("\n") }
        out.flush()
    }
}
