package borg.trikeshed.nixtruffle

import java.io.File
import java.util.IdentityHashMap

// The LLVM arm (docs/PRELOAD-DIALECTS.md step 3): a file's son-form module, as son-export writes it, written as an MLIR module
// in TrikeShed's ops, then lowered by `mlnix-opt --trikeshed-lower-cursors` and the stock MLIR pipeline to a native program
// that prints the value (scripts/nix-native.sh).  No C++ is added for it: this is Kotlin over the export the Graal arm
// reads, and the lowering is the one mlnixci's server is built with.
//
//   a list           genList's oracle, `trikeshed.series n { i -> f i }` (Series.kt's `n j { i -> ... }`)
//   foldl'           `trikeshed.fold` (Series.kt's fold), the step applied in its region
//   length, elemAt   `trikeshed.size`, `trikeshed.at`
//   an int, a bool   PRELOAD's plain elements, i64 and i1 (arith), each operation checked as Nix checks it; known values
//                    are folded here, and an `if` on a known condition is only its branch
//   a set            PRELOAD's attrs, its names joined to its cells, known here: a select, `?`, `//`, `with` and a set
//                    pattern are settled while writing, and only the values they reach are computed, where needed
//   a lambda         nothing at run time: a closure is its row and its captures, known here, and an application is the
//                    body written in place; a body that calls itself is a func.func, and its calls func.call
//   if, &&, ||, ->   scf.if
//
// Laziness: a value is written where it is first needed, once per region, so what Nix never forces is never computed.
// Where a value is computed sooner, son says it may be: an argument computed before a call (son.body's arg_forced), a
// captured value passed to a body's function (forced_captures), a fold's first accumulator (the step forces it, itself or
// through the closure it returns).  A list's elements are computed when the list is made (a series lowers to a buffer),
// in order: so a list whose function may fail is refused wherever Nix might force fewer of them, or force them later
// (length, elemAt, foldl'), and kept only where it is printed, which forces each in order as `--strict` does.
// A failure known while writing (a missing attribute, a set pattern's missing argument) is written where it is forced,
// and what it leaves (VNever) is never seen at run time.  Whatever else it meets is refused, with what it met.
class NativeRefused(msg: String) : Exception(msg)

class Native(module: List<Op>) {
    private val expr: Op = module.firstOrNull { it.name == "nix.expr" } ?: throw NativeRefused("no nix.expr")
    private val rows: Map<String, Op> =
        module.filter { it.name == "son.pool" }.flatMap { it.regions[0][0].ops }.associateBy { it.str("sym_name")!! }

    private sealed class V
    /// An integer; `k`, its value when it is known here (a literal, or arithmetic on known values).
    private class VInt(val ssa: String, val k: Long? = null) : V()
    private class VBool(val ssa: String, val k: Boolean? = null) : V()
    /// A series of integers; `fallible`: computing an element may fail (so may making the list); `size` when known here.
    private class VList(val ssa: String, val fallible: Boolean, val size: Long? = null) : V()
    /// A closure: its row and its captures, each a V or a Ref (not computed until a use needs it).
    private class VFn(val row: Op, val caps: List<Any>) : V()
    /// A set whose names are known here: its names in byte order (mlnix prints them so), each joined to its cell, a V or a
    /// Ref computed when something first needs it.  Its identity is the set's: «repeated» and `x // { }` see it.
    private class VSet(val names: Array<String>, val cells: Array<Any>) : V() {
        fun cell(name: String): Any? { val i = names.binarySearch(name, BYTES); return if (i >= 0) cells[i] else null }
    }
    /// What a failure known here leaves: the failure is written before it, so no run gets past it.
    private object VNever : V()

    /// A value of one written-in-place body: computed where a use first needs it.
    private class Ref(val id: Int, val frame: Frame)
    /// One body written in place: its ops by result, and its block arguments bound (to a V or a Ref).
    private class Frame(val defs: Map<Int, Op>, val bound: Map<Int, Any>)

    /// A region being written: its lines, and the values written in it (a value written in a region is used there and in
    /// the regions inside it, never beside it).
    private class Scope(val parent: Scope?, val indent: String) {
        val out = StringBuilder()
        private val memo = HashMap<Frame, HashMap<Int, V>>()
        var fallible = false
        fun get(f: Frame, id: Int): V? = memo[f]?.get(id) ?: parent?.get(f, id)
        fun put(f: Frame, id: Int, v: V) { memo.getOrPut(f) { HashMap() }[id] = v }
        fun line(s: String) { out.append(indent).append(s).append('\n') }
        fun child() = Scope(this, "$indent  ")
    }

    private var n = 0
    private fun ssa() = "%v${n++}"
    private val funcs = StringBuilder()
    private val specs = HashMap<String, String>()
    private var inlining = ArrayList<Op>()
    /// The failures written so far (checks, failures known here, calls): a computation may fail if it added to this.
    private var fails = 0
    /// The constant texts (dprintf formats, Nix's errors), each an LLVM global.
    private val texts = LinkedHashMap<String, String>()
    private fun text(t: String): String = texts.getOrPut(t) { "nn_t${texts.size}" }

    private fun refuse(what: String): Nothing = throw NativeRefused(what)

    /// The module: the runtime's few externals, the texts, the bodies that became functions, and main, which prints the value.
    fun emit(): String {
        val s = Scope(null, "    ")
        val block = expr.regions[0][0]
        val top = Ref(block.ops.first { it.name == "nix.return" }.ins[0], Frame(defs(block), emptyMap()))
        print(top, force(top, s), s)
        val m = StringBuilder()
        m.append("// written by nix-truffle --emit-trikeshed from ${expr.str("source_path")}\nmodule {\n")
        m.append(PRELUDE)
        for ((t, g) in texts) m.append(lit(g, t))
        m.append(funcs)
        m.append("  func.func @main() -> i32 {\n").append(s.out)
        m.append("    %ok = arith.constant 0 : i32\n    return %ok : i32\n  }\n}\n")
        return m.toString()
    }

    private fun defs(b: Block): Map<Int, Op> {
        val d = HashMap<Int, Op>()
        for (o in b.ops) for (r in o.res) d[r] = o
        return d
    }

    // ── values ─────────────────────────────────────────────────────────────────────────────────────────────────────

    private fun value(frame: Frame, id: Int, s: Scope): V {
        s.get(frame, id)?.let { return it }
        val v = when (val b = frame.bound[id]) {
            is V -> b
            is Ref -> value(b.frame, b.id, s)
            else -> emitOp(frame.defs[id] ?: refuse("value $id has no definition"), frame, s)
        }
        s.put(frame, id, v)
        return v
    }

    private fun force(c: Any, s: Scope): V = when (c) { is V -> c; is Ref -> value(c.frame, c.id, s); else -> refuse("cell $c") }

    // A VNever where a value of some type is needed is past a failure already written: a placeholder of that type stands in.
    private fun int(v: V, what: String, s: Scope): String = when (v) {
        is VInt -> v.ssa
        VNever -> const(s, 0)
        else -> refuse("$what is ${kind(v)}, not an integer")
    }
    private fun bool(v: V, what: String, s: Scope): String = when (v) {
        is VBool -> v.ssa
        VNever -> bconst(s, false).ssa
        else -> refuse("$what is ${kind(v)}, not a Boolean")
    }
    private fun list(v: V, what: String): String { // its callers have passed a VNever by
        val l = v as? VList ?: refuse("$what is ${kind(v)}, not a list")
        if (l.fallible) refuse("$what has elements that may fail, and a list's elements are computed when the list is made")
        return l.ssa
    }
    private fun kind(v: V) = when (v) {
        is VInt -> "an integer"; is VBool -> "a Boolean"; is VList -> "a list"; is VFn -> "a function"; is VSet -> "a set"
        VNever -> "a failure"
    }

    private fun const(s: Scope, x: Long): String { val r = ssa(); s.line("$r = arith.constant $x : i64"); return r }
    private fun bconst(s: Scope, b: Boolean): VBool { val r = ssa(); s.line("$r = arith.constant $b"); return VBool(r, b) }
    private fun known(s: Scope, x: Long) = VInt(const(s, x), x)

    private fun emitOp(op: Op, frame: Frame, s: Scope): V {
        fun arg(k: Int) = value(frame, op.ins[k], s)
        op.str("prim_key")?.let { key -> return prim(key, op, frame, s) }
        return when (op.name) {
            "nix.int" -> known(s, (op.attrs["value"] as Number).toLong())
            "nix.bool" -> bconst(s, op.attrs["value"] == true)
            "nix.builtin" -> when (op.str("name")) {
                "true" -> bconst(s, true); "false" -> bconst(s, false)
                else -> refuse("builtins.${op.str("name")} as a value")
            }
            "nix.concat_strings" -> {
                var acc = arg(0)
                for (k in 1 until op.ins.size) acc = arith("add", acc, arg(k), s, "an operand of +")
                acc
            }
            "nix.if" -> {
                val c = arg(0)
                when {
                    c === VNever -> VNever
                    c is VBool && c.k != null -> value(frame, if (c.k) op.ins[1] else op.ins[2], s)
                    else -> branch(bool(c, "an if's condition", s), op.ins[1], op.ins[2], frame, s)
                }
            }
            "nix.not" -> when (val a = arg(0)) {
                VNever -> VNever
                is VBool -> if (a.k != null) bconst(s, !a.k) else {
                    val t = bconst(s, true).ssa; val r = ssa(); s.line("$r = arith.xori ${a.ssa}, $t : i1"); VBool(r)
                }
                else -> refuse("!'s operand is ${kind(a)}, not a Boolean")
            }
            "nix.and" -> logic(op, frame, s, 0)
            "nix.or" -> logic(op, frame, s, 1)
            "nix.impl" -> logic(op, frame, s, 2)
            "nix.eq", "nix.neq" -> {
                val a = arg(0); val b = arg(1)
                val eq = op.name == "nix.eq"
                when {
                    a === VNever || b === VNever -> VNever
                    a is VInt && b is VInt && a.k != null && b.k != null -> bconst(s, (a.k == b.k) == eq)
                    a is VBool && b is VBool && a.k != null && b.k != null -> bconst(s, (a.k == b.k) == eq)
                    a is VInt && b is VInt -> cmp(if (eq) "eq" else "ne", a.ssa, b.ssa, "i64", s)
                    a is VBool && b is VBool -> cmp(if (eq) "eq" else "ne", a.ssa, b.ssa, "i1", s)
                    else -> refuse("== of ${kind(a)} and ${kind(b)}")
                }
            }
            "nix.attrs" -> {
                val seg = op.segments()!!
                if (seg[1] != 0) refuse("a set with names computed at run time")
                @Suppress("UNCHECKED_CAST") val names = op.attrs["names"] as List<String>
                set(names.indices.map { names[it] to Ref(op.ins[it], frame) })
            }
            "nix.select" -> {
                val seg = op.segments()!!
                select(arg(0), path(op), if (seg[2] == 1) Ref(op.ins[1 + seg[1]], frame) else null, s)
            }
            "nix.has_attr" -> hasAttr(arg(0), path(op), s)
            "nix.update" -> update(op, frame, s)
            "nix.formal" -> {
                val a = arg(0)
                if (a === VNever) return VNever
                val set = a as? VSet ?: refuse("a formal of ${kind(a)}")
                val name = op.str("name")!!
                val c = set.cell(name)
                when {
                    c != null -> force(c, s)
                    op.ins.size > 1 -> value(frame, op.ins[1], s)
                    else -> refuse("formal '$name' missing after the call's check")
                }
            }
            "nix.with_var" -> withVar(op.str("name")!!, op.ins.map { Ref(it, frame) }, s)
            "son.defer" -> {
                val row = rows[(op.attrs["row"] as List<*>).last() as String] ?: refuse("son.defer of an unknown row")
                VFn(row, op.ins.map { Ref(it, frame) })
            }
            "nix.apply" -> {
                var f = arg(0)
                for (k in 1 until op.ins.size) f = applyOne(f, Ref(op.ins[k], frame), s)
                f
            }
            else -> refuse(op.name)
        }
    }

    private fun cmp(pred: String, a: String, b: String, ty: String, s: Scope): V {
        val r = ssa(); s.line("$r = arith.cmpi $pred, $a, $b : $ty"); return VBool(r)
    }

    /// `if`: each branch written in its own region, so only the taken one runs.
    private fun branch(c: String, t: Int, e: Int, frame: Frame, s: Scope): V {
        val st = s.child(); val se = s.child()
        val vt = value(frame, t, st); val ve = value(frame, e, se)
        return join(c, vt, st, ve, se, s)
    }

    private fun join(c: String, vt: V, st: Scope, ve: V, se: Scope, s: Scope): V {
        if (st.fallible || se.fallible) s.fallible = true
        if (vt === VNever && ve === VNever) {
            s.line("scf.if $c {"); s.out.append(st.out); s.line("} else {"); s.out.append(se.out); s.line("}")
            return VNever
        }
        val ty = when (if (vt === VNever) ve else vt) {
            is VInt -> "i64"; is VBool -> "i1"
            else -> refuse("an if whose branches are ${kind(vt)} and ${kind(ve)}")
        }
        fun yielded(v: V, sc: Scope): String =
            if (ty == "i64") int(v, "an if's branch", sc) else bool(v, "an if's branch", sc)
        val a = yielded(vt, st); val b = yielded(ve, se)
        val r = ssa()
        s.line("$r = scf.if $c -> ($ty) {")
        s.out.append(st.out); s.line("  scf.yield $a : $ty")
        s.line("} else {")
        s.out.append(se.out); s.line("  scf.yield $b : $ty")
        s.line("}")
        return if (ty == "i64") VInt(r) else VBool(r)
    }

    /// `a && b`, `a || b`, `a -> b`: b only when a does not decide.
    private fun logic(op: Op, frame: Frame, s: Scope, which: Int): V {
        val av = value(frame, op.ins[0], s)
        if (av === VNever) return VNever
        val a = av as? VBool ?: refuse("a Boolean operator's first operand is ${kind(av)}")
        val decides = which == 1 // || is decided by a true, && and -> by a false
        val decided = which != 0 // && decided: false; || and -> decided: true
        if (a.k != null) {
            if (a.k == decides) return bconst(s, decided)
            val b = value(frame, op.ins[1], s)
            return if (b === VNever) VNever else (b as? VBool ?: refuse("a Boolean operator's second operand is ${kind(b)}"))
        }
        val sb = s.child(); val sk = s.child()
        val vb = value(frame, op.ins[1], sb)
        val b: V = if (vb === VNever) VNever else VBool(bool(vb, "a Boolean operator's second operand", sb))
        val k = bconst(sk, decided)
        return if (which == 1) join(a.ssa, k, sk, b, sb, s) else join(a.ssa, b, sb, k, sk, s)
    }

    // ── sets ───────────────────────────────────────────────────────────────────────────────────────────────────────

    private fun set(pairs: List<Pair<String, Any>>): VSet {
        val sorted = pairs.sortedWith { x, y -> BYTES.compare(x.first, y.first) }
        return VSet(Array(sorted.size) { sorted[it].first }, Array(sorted.size) { sorted[it].second })
    }

    private fun path(op: Op): List<String> {
        @Suppress("UNCHECKED_CAST") val p = op.attrs["path"] as List<String?>
        return p.map { it ?: refuse("an attribute name computed at run time") }
    }

    /// `e.a.b or d` (SelectNode's walk): each attribute forced on the way; a missing one, or a value that is not a set,
    /// gives the default when there is one, else Nix's error.
    private fun select(base: V, path: List<String>, default: Ref?, s: Scope): V {
        var v = base
        for (name in path) {
            if (v === VNever) return VNever
            val set = v as? VSet
            val c = set?.cell(name)
            if (c == null) {
                if (default != null) return force(default, s)
                return if (set == null) notASet(v, s) else failNow("error: attribute '${pct(name)}' missing", s)
            }
            v = force(c, s)
        }
        return v
    }

    /// `e ? a.b`: the attributes on the way are forced, the last is not.
    private fun hasAttr(base: V, path: List<String>, s: Scope): V {
        var v = base
        for ((i, name) in path.withIndex()) {
            if (v === VNever) return VNever
            val c = (v as? VSet)?.cell(name) ?: return bconst(s, false)
            if (i == path.lastIndex) return bconst(s, true)
            v = force(c, s)
        }
        return bconst(s, true)
    }

    /// `a // b`: a forced and checked, then b; b's value where both have the name.  An empty side gives the other side
    /// itself, as Nix does (so «repeated» sees the same set).
    private fun update(op: Op, frame: Frame, s: Scope): V {
        val a = value(frame, op.ins[0], s)
        if (a === VNever) return VNever
        val x = a as? VSet ?: return notASet(a, s)
        val b = value(frame, op.ins[1], s)
        if (b === VNever) return VNever
        val y = b as? VSet ?: return notASet(b, s)
        if (x.names.isEmpty()) return y
        if (y.names.isEmpty()) return x
        val m = java.util.TreeMap<String, Any>(BYTES)
        for (i in x.names.indices) m[x.names[i]] = x.cells[i]
        for (i in y.names.indices) m[y.names[i]] = y.cells[i]
        return VSet(m.keys.toTypedArray(), m.values.toTypedArray())
    }

    /// A name `with` binds (WithVarNode): each scope forced in turn, innermost first, until one has it.
    private fun withVar(name: String, scopes: List<Ref>, s: Scope): V {
        for (r in scopes) {
            val v = force(r, s)
            if (v === VNever) return VNever
            val set = v as? VSet ?: return notASet(v, s)
            set.cell(name)?.let { return force(it, s) }
        }
        return failNow("error: undefined variable '${pct(name)}'", s)
    }

    /// Nix's error for a value that is not a set where one is needed, with the value as mlnix prints it there.
    private fun notASet(v: V, s: Scope): V = when (v) {
        is VInt -> if (v.k != null) failNow("error: expected a set but found an integer: ${v.k}", s)
                   else failNow("error: expected a set but found an integer: %ld", s, v.ssa)
        is VBool -> if (v.k != null) failNow("error: expected a set but found a Boolean: ${v.k}", s) else {
            val t = s.child(); val f = s.child()
            failNow("error: expected a set but found a Boolean: true", t); failNow("error: expected a set but found a Boolean: false", f)
            s.line("scf.if ${v.ssa} {"); s.out.append(t.out); s.line("} else {"); s.out.append(f.out); s.line("}")
            VNever
        }
        VNever -> VNever
        else -> refuse("a set expected where the value is ${kind(v)} (Nix's error prints it, which is not written here)")
    }

    // ── failures ───────────────────────────────────────────────────────────────────────────────────────────────────

    /// '%' as dprintf reads it, in a text that is data.
    private fun pct(x: String) = x.replace("%", "%%")

    /// When `bad`: the error, as mlnix words it (a format of up to two integers), and the program ends.
    private fun fail(bad: String, fmt: String, a: String, b: String, s: Scope) {
        val p = ssa()
        s.line("scf.if $bad {")
        s.line("  $p = llvm.mlir.addressof @${text("$fmt\n")} : !llvm.ptr")
        s.line("  func.call @nn_fail($p, $a, $b) : (!llvm.ptr, i64, i64) -> ()")
        s.line("}")
        s.fallible = true; fails++
    }

    /// A failure known here: when a run reaches this point, the error (a format of up to one integer), and the program ends.
    private fun failNow(fmt: String, s: Scope, a: String? = null): V {
        val p = ssa(); val x = a ?: const(s, 0)
        s.line("$p = llvm.mlir.addressof @${text("$fmt\n")} : !llvm.ptr")
        s.line("func.call @nn_fail($p, $x, $x) : (!llvm.ptr, i64, i64) -> ()")
        s.fallible = true; fails++
        return VNever
    }

    // ── arithmetic, checked as Nix checks it ───────────────────────────────────────────────────────────────────────

    private val verbs = mapOf("add" to ("adding" to "+"), "sub" to ("subtracting" to "-"), "mul" to ("multiplying" to "*"))

    /// `a + b`, `a - b`, `a * b` on integers: folded when both are known, else checked at run time.
    private fun arith(what: String, av: V, bv: V, s: Scope, ctx: String): V {
        if (av === VNever) return VNever
        val a = av as? VInt ?: refuse("$ctx is ${kind(av)}, not an integer")
        if (bv === VNever) return VNever
        val b = bv as? VInt ?: refuse("$ctx is ${kind(bv)}, not an integer")
        val (verb, sym) = verbs[what]!!
        if (a.k != null && b.k != null) {
            val r = try {
                when (what) { "add" -> Math.addExact(a.k, b.k); "sub" -> Math.subtractExact(a.k, b.k); else -> Math.multiplyExact(a.k, b.k) }
            } catch (e: ArithmeticException) { null }
            return if (r != null) known(s, r) else failNow("error: integer overflow in $verb ${a.k} $sym ${b.k}", s)
        }
        return VInt(checked(what, a.ssa, b.ssa, s, "error: integer overflow in $verb %ld $sym %ld"))
    }

    private fun checked(what: String, a: String, b: String, s: Scope, fmt: String): String {
        val r = ssa(); val z = const(s, 0)
        val bad = ssa()
        when (what) {
            "add" -> {
                s.line("$r = arith.addi $a, $b : i64")
                val x = ssa(); val y = ssa(); val w = ssa()
                s.line("$x = arith.xori $a, $r : i64"); s.line("$y = arith.xori $b, $r : i64"); s.line("$w = arith.andi $x, $y : i64")
                s.line("$bad = arith.cmpi slt, $w, $z : i64")
            }
            "sub" -> {
                s.line("$r = arith.subi $a, $b : i64")
                val x = ssa(); val y = ssa(); val w = ssa()
                s.line("$x = arith.xori $a, $b : i64"); s.line("$y = arith.xori $a, $r : i64"); s.line("$w = arith.andi $x, $y : i64")
                s.line("$bad = arith.cmpi slt, $w, $z : i64")
            }
            else -> {
                val hi = ssa(); val sh = ssa(); val c63 = const(s, 63)
                s.line("$r, $hi = arith.mulsi_extended $a, $b : i64")
                s.line("$sh = arith.shrsi $r, $c63 : i64")
                s.line("$bad = arith.cmpi ne, $hi, $sh : i64")
            }
        }
        fail(bad, fmt, a, b, s)
        return r
    }

    // ── builtins ───────────────────────────────────────────────────────────────────────────────────────────────────

    private fun prim(key: String, op: Op, frame: Frame, s: Scope): V {
        fun arg(k: Int) = value(frame, op.ins[k], s)
        return when (key) {
            "__add" -> arith("add", arg(0), arg(1), s, "an operand of add")
            "__sub" -> arith("sub", arg(0), arg(1), s, "an operand of sub")
            "__mul" -> arith("mul", arg(0), arg(1), s, "an operand of mul")
            "__lessThan" -> {
                val av = arg(0); val bv = arg(1)
                if (av === VNever || bv === VNever) return VNever
                val a = av as? VInt ?: refuse("lessThan's first operand is ${kind(av)}")
                val b = bv as? VInt ?: refuse("lessThan's second operand is ${kind(bv)}")
                if (a.k != null && b.k != null) bconst(s, a.k < b.k) else cmp("slt", a.ssa, b.ssa, "i64", s)
            }
            "__genList" -> { val len = arg(1); val f = arg(0); genList(f, len, s) } // the length first, as Nix forces them
            "__foldl'" -> { val f = arg(0); val l = arg(2); foldl(f, Ref(op.ins[1], frame), l, s) }
            "__length" -> {
                val lv = arg(0)
                if (lv === VNever) return VNever
                val l = list(lv, "length's operand")
                (lv as VList).size?.let { return known(s, it) }
                val i = ssa(); val r = ssa()
                s.line("$i = trikeshed.size $l : !trikeshed.series<i64>")
                s.line("$r = arith.index_cast $i : index to i64")
                VInt(r)
            }
            "__elemAt" -> {
                val lv = arg(0); val kv = arg(1)
                if (lv === VNever || kv === VNever) return VNever
                val l = list(lv, "elemAt's list"); val k = int(kv, "elemAt's index", s)
                val i = ssa(); val n64 = ssa(); val z = const(s, 0)
                s.line("$i = trikeshed.size $l : !trikeshed.series<i64>")
                s.line("$n64 = arith.index_cast $i : index to i64")
                val lo = ssa(); val hi = ssa(); val bad = ssa()
                s.line("$lo = arith.cmpi slt, $k, $z : i64"); s.line("$hi = arith.cmpi sge, $k, $n64 : i64"); s.line("$bad = arith.ori $lo, $hi : i1")
                fail(bad, "error: list index %ld is out of bounds", k, k, s)
                val at = ssa(); val r = ssa()
                s.line("$at = arith.index_cast $k : i64 to index")
                s.line("$r = trikeshed.at $l[$at] : !trikeshed.series<i64>, index -> i64")
                VInt(r)
            }
            else -> refuse("builtins.${key.removePrefix("__")}")
        }
    }

    /// genList f n: the series whose element i is f i, made at once, element by element in order.
    private fun genList(f: V, lenV: V, s: Scope): V {
        if (lenV === VNever || f === VNever) return VNever
        val len = lenV as? VInt ?: refuse("genList's length is ${kind(lenV)}")
        if (len.k != null && len.k < 0) return failNow("error: cannot create list of size ${len.k}", s)
        if (len.k == null) {
            val z = const(s, 0); val neg = ssa()
            s.line("$neg = arith.cmpi slt, ${len.ssa}, $z : i64")
            fail(neg, "error: cannot create list of size %ld", len.ssa, len.ssa, s)
        }
        val idx = ssa(); val r = ssa()
        s.line("$idx = arith.index_cast ${len.ssa} : i64 to index")
        val body = s.child()
        val i = ssa(); val i64 = ssa()
        body.line("$i64 = arith.index_cast $i : index to i64")
        val e = int(applyOne(f, VInt(i64), body), "genList's element", body)
        if (body.fallible) s.fallible = true
        s.line("$r = trikeshed.series $idx : !trikeshed.series<i64> {")
        s.line("^bb0($i: index):")
        s.out.append(body.out)
        s.line("  trikeshed.yield $e : i64")
        s.line("}")
        return VList(r, body.fallible, len.k)
    }

    /// foldl' op nul list: `trikeshed.fold`.  nul is computed before the fold, which son must allow: op forces its first
    /// argument (arg_forced), or the closure op returns forces it (forced_captures).
    private fun foldl(f: V, nul: Ref, lv: V, s: Scope): V {
        if (f === VNever || lv === VNever) return VNever
        val fn = f as? VFn ?: refuse("foldl' of ${kind(f)}")
        val l = list(lv, "foldl''s list")
        if (!forcesFirst(fn.row)) refuse("foldl' whose function does not force the accumulator (son)")
        val zv = force(nul, s)
        if (zv === VNever) return VNever
        val z = int(zv, "foldl''s first accumulator", s)
        val body = s.child()
        val acc = ssa(); val x = ssa()
        val r = int(applyOne(applyOne(fn, VInt(acc), body), VInt(x), body), "foldl''s accumulator", body)
        if (body.fallible) s.fallible = true
        val out = ssa()
        s.line("$out = trikeshed.fold $l, $z : !trikeshed.series<i64>, i64 -> i64 {")
        s.line("^bb0($acc: i64, $x: i64):")
        s.out.append(body.out)
        s.line("  trikeshed.yield $r : i64")
        s.line("}")
        return VInt(out)
    }

    /// The row forces its argument, or returns a closure that forces it (Module.forcedAfter's first step, in the arm).
    private fun forcesFirst(row: Op): Boolean {
        if (row.attrs["arg_forced"] == true) return true
        val b = row.regions[0][0]
        val arg = b.args[(row.attrs["captures"] as Number).toInt()]
        val ret = b.ops.firstOrNull { it.name == "nix.return" }?.ins?.get(0) ?: return false
        val d = b.ops.firstOrNull { ret in it.res && it.name == "son.defer" } ?: return false
        val k = d.ins.indexOf(arg)
        val next = rows[(d.attrs["row"] as List<*>).last() as String] ?: return false
        @Suppress("UNCHECKED_CAST")
        return k >= 0 && (next.attrs["forced_captures"] as List<Number>?)?.any { it.toInt() == k } == true
    }

    // ── application ────────────────────────────────────────────────────────────────────────────────────────────────

    private fun applyOne(f: V, arg: Any, s: Scope): V {
        if (f === VNever) return VNever
        val fn = f as? VFn ?: refuse("an application of ${kind(f)}")
        val lam = fn.row.attrs["lambda"] as Map<*, *>?
        @Suppress("UNCHECKED_CAST") val formals = lam?.get("formals") as List<String>?
        if (formals != null) return applySet(fn, lam, formals, arg, s)
        return if (fn.row in inlining) call(fn, arg, s) else inline(fn, arg, s)
    }

    /// A set pattern (Apply.one's check, in Nix's order): the argument forced, a missing argument without a default named
    /// first (by name), then an unexpected one when there is no `...`; then the body, its formals read from the set.
    private fun applySet(fn: VFn, lam: Map<*, *>, formals: List<String>, arg: Any, s: Scope): V {
        if (fn.row in inlining) refuse("a recursive call of a lambda with a set pattern")
        val a = force(arg, s)
        if (a === VNever) return VNever
        val set = a as? VSet ?: return notASet(a, s)
        @Suppress("UNCHECKED_CAST") val defaults = lam["formal_defaults"] as List<Boolean>
        val who = pct(lam["name"] as String? ?: "anonymous lambda")
        formals.indices.filter { !defaults[it] && set.cell(formals[it]) == null }.map { formals[it] }.minWithOrNull(BYTES)?.let {
            return failNow("error: function '$who' called without required argument '${pct(it)}'", s)
        }
        if (lam["ellipsis"] != true) set.names.firstOrNull { it !in formals }?.let {
            return failNow("error: function '$who' called with unexpected argument '${pct(it)}'", s)
        }
        return inline(fn, set, s)
    }

    /// The body written in place: its captures and its argument bound as they are (not computed until needed).
    private fun inline(fn: VFn, arg: Any, s: Scope): V {
        val b = fn.row.regions[0][0]
        val nc = (fn.row.attrs["captures"] as Number).toInt()
        val bound = HashMap<Int, Any>()
        for (k in 0 until nc) bound[b.args[k]] = fn.caps[k]
        bound[b.args[nc]] = arg
        val frame = Frame(defs(b), bound)
        inlining.add(fn.row)
        try {
            return value(frame, b.ops.first { it.name == "nix.return" }.ins[0], s)
        } finally {
            inlining.removeAt(inlining.size - 1)
        }
    }

    /// A body that calls itself: a func.func of its integer argument and the captured integers, written once per row.
    /// Its argument is computed before the call (son.body's arg_forced) and so are the captured values (forced_captures);
    /// captured closures are known, and stay out of its parameters.
    private fun call(fn: VFn, arg: Any, s: Scope): V {
        val row = fn.row
        val name = row.str("sym_name")!!
        if (row.attrs["arg_forced"] != true) refuse("a recursive call of $name, whose body does not force its argument")
        @Suppress("UNCHECKED_CAST")
        val forced = (row.attrs["forced_captures"] as List<Number>?)?.map { it.toInt() }?.toSet() ?: emptySet()
        val caps = fn.caps.mapIndexed { k, c ->
            if (isClosure(c)) force(c, s) else if (k in forced) force(c, s) else refuse("a recursive call of $name over a capture it may not force")
        }
        val av = force(arg, s)
        if (av === VNever || caps.any { it === VNever }) return VNever
        val a = int(av, "the argument of a recursive call", s)
        for (c in caps) if (c is VFn && c.row != row && !valueFree(c, s, HashSet())) refuse("a recursive call of $name over a closure with values")
        val vals = caps.filter { it !is VFn }.map { int(it, "a captured value of $name", s) }
        val key = "$name/${caps.map { if (it is VFn) it.row.str("sym_name") else "i64" }}"
        val fname = specs[key] ?: run {
            val f = "@nn_$name"
            if (specs.values.contains(f)) refuse("$name called over different captures")
            specs[key] = f
            val saved = inlining
            inlining = arrayListOf(row)
            val fs = Scope(null, "    ")
            val b = row.regions[0][0]
            val nc = (row.attrs["captures"] as Number).toInt()
            val bound = HashMap<Int, Any>()
            var p = 0
            val params = ArrayList<String>()
            // Inside the function its captures are its parameters (a value) or the closures they are; where the body names
            // itself, it is this row over those same captures (its caller's would name the caller's values).
            val inner = ArrayList<Any>()
            for (k in 0 until nc) inner.add(if (caps[k] is VFn) caps[k] else VInt("%p${p++}").also { params.add("${it.ssa}: i64") })
            for (k in 0 until nc) if ((caps[k] as? VFn)?.row == row) inner[k] = VFn(row, inner)
            for (k in 0 until nc) bound[b.args[k]] = inner[k]
            bound[b.args[nc]] = VInt("%parg").also { params.add("%parg: i64") }
            val r = int(value(Frame(defs(b), bound), b.ops.first { it.name == "nix.return" }.ins[0], fs), "what $name returns", fs)
            funcs.append("  func.func private $f(${params.joinToString(", ")}) -> i64 {\n").append(fs.out)
            funcs.append("    return $r : i64\n  }\n")
            inlining = saved
            f
        }
        val r = ssa()
        val all = vals + a
        s.line("$r = func.call $fname(${all.joinToString(", ")}) : (${all.joinToString(", ") { "i64" }}) -> i64")
        s.fallible = true; fails++
        return VInt(r)
    }

    /// A closure whose captures are closures all the way down: it may be bound inside a function, which sees none of its
    /// caller's values.
    private fun valueFree(c: Any, s: Scope, seen: HashSet<Op>): Boolean {
        val f = (if (isClosure(c)) force(c, s) else null) as? VFn ?: return false
        if (!seen.add(f.row)) return true
        return f.caps.all { valueFree(it, s, seen) }
    }

    private fun isClosure(c: Any): Boolean = when (c) {
        is VFn -> true
        is V -> false
        is Ref -> when (val b = c.frame.bound[c.id]) {
            null -> c.frame.defs[c.id]?.name == "son.defer"
            else -> isClosure(b)
        }
        else -> false
    }

    // ── the value printed, as `--eval --strict` prints it ─────────────────────────────────────────────────────────

    /// mlnix's `--eval --strict`: the value computed through first (forceValueDeep), then printed (printValue).
    private fun print(top: Ref, v: V, s: Scope) {
        if (!deep(v, s, IdentityHashMap())) return // a failure every run reaches: nothing is printed
        val p = Printer(s)
        show(cellOf(top), v, p, s, IdentityHashMap(), HashSet())
        p.lit("\n"); p.flush()
    }

    /// forceValueDeep: each set's values, each list's elements (a series has them already).  False when a failure known
    /// here is reached.  mlnix forces a set's values in its symbols' order, which puts the names it interned before the
    /// program (`type`, the builtins' names, ...) first: so a set two of whose values may fail is refused, since which error
    /// comes first is not the program's to say.
    private fun deep(v: V, s: Scope, seen: IdentityHashMap<VSet, Boolean>): Boolean {
        if (v === VNever) return false
        if (v !is VSet || seen.put(v, true) != null) return true
        var mayFail = 0
        var reached = true
        for (c in v.cells) {
            val before = fails
            if (!deep(force(c, s), s, seen)) reached = false
            if (fails > before) mayFail++
        }
        if (mayFail > 1) refuse("a printed set two of whose values may fail: mlnix forces them in its symbols' order, which the program does not show")
        return reached
    }

    /// The cell a value is reached through, as mlnix's printer tells lists apart: a Ref followed through what binds it to
    /// the op that made the value (a select makes its own cell; a variable passes on the cell it names).
    private fun cellOf(c: Any): Any {
        var r = c
        while (r is Ref) { val b = r.frame.bound[r.id] ?: return Pair(r.frame, r.id); r = b }
        return r
    }

    /// printValue: sets by name, «repeated» for a non-empty set met again, or a non-empty list's cell met again.
    private fun show(cell: Any, v: V, p: Printer, s: Scope, sets: IdentityHashMap<VSet, Boolean>, lists: HashSet<Any>) {
        when (v) {
            is VInt -> if (v.k != null) p.lit(v.k.toString()) else p.int(v.ssa)
            is VBool -> if (v.k != null) p.lit(v.k.toString()) else p.bool(v.ssa)
            is VFn -> p.lit("<LAMBDA>")
            is VSet -> when {
                v.names.isEmpty() -> p.lit("{ }")
                sets.put(v, true) != null -> p.lit("«repeated»")
                else -> {
                    p.lit("{ ")
                    for (i in v.names.indices) {
                        p.lit(identifier(v.names[i])); p.lit(" = ")
                        show(cellOf(v.cells[i]), force(v.cells[i], s), p, s, sets, lists)
                        p.lit("; ")
                    }
                    p.lit("}")
                }
            }
            is VList -> if (lists.add(cell)) p.list(v.ssa) else when (v.size) {
                null -> p.repeatedList(v.ssa)
                0L -> p.lit("[ ]")
                else -> p.lit("«repeated»")
            }
            VNever -> {}
        }
    }

    /// Text to stdout: constant text gathered into one dprintf format, written when a run-time value comes.
    private inner class Printer(val s: Scope) {
        private val fmt = StringBuilder()
        private val one = ssa().also { s.line("$it = arith.constant 1 : i32") }

        fun lit(t: String) { fmt.append(pct(t)) }
        fun int(x: String) { fmt.append("%ld"); flush(x) }
        fun flush(vararg xs: String) {
            if (fmt.isEmpty()) return
            write(s, fmt.toString(), *xs)
            fmt.setLength(0)
        }
        private fun write(sc: Scope, f: String, vararg xs: String) {
            val p = ssa(); val r = ssa()
            sc.line("$p = llvm.mlir.addressof @${text(f)} : !llvm.ptr")
            val types = (listOf("i32", "!llvm.ptr") + xs.map { "i64" }).joinToString(", ")
            sc.line("$r = llvm.call @dprintf($one, $p${xs.joinToString("") { ", $it" }}) vararg(!llvm.func<i32 (i32, ptr, ...)>) : ($types) -> i32")
        }
        private fun either(c: String, t: String, e: String) {
            flush()
            val st = s.child(); val se = s.child()
            write(st, pct(t)); write(se, pct(e))
            s.line("scf.if $c {"); s.out.append(st.out); s.line("} else {"); s.out.append(se.out); s.line("}")
        }
        fun bool(c: String) = either(c, "true", "false")
        fun list(l: String) {
            lit("[ "); flush()
            val n = ssa(); val c0 = ssa(); val c1 = ssa(); val i = ssa()
            s.line("$n = trikeshed.size $l : !trikeshed.series<i64>")
            s.line("$c0 = arith.constant 0 : index"); s.line("$c1 = arith.constant 1 : index")
            s.line("scf.for $i = $c0 to $n step $c1 {")
            val body = s.child(); val e = ssa()
            body.line("$e = trikeshed.at $l[$i] : !trikeshed.series<i64>, index -> i64")
            write(body, "%ld ", e)
            s.out.append(body.out)
            s.line("}")
            lit("]")
        }
        /// A list's cell met again: «repeated», unless it is empty (mlnix's printer passes an empty list by).
        fun repeatedList(l: String) {
            val n = ssa(); val c0 = ssa(); val e = ssa()
            s.line("$n = trikeshed.size $l : !trikeshed.series<i64>")
            s.line("$c0 = arith.constant 0 : index"); s.line("$e = arith.cmpi eq, $n, $c0 : index")
            either(e, "[ ]", "«repeated»")
        }
    }

    companion object {
        /// Names in byte order (UTF-8, unsigned), as mlnix sorts and prints them.
        private val BYTES = Comparator<String> { a, b -> java.util.Arrays.compareUnsigned(a.toByteArray(), b.toByteArray()) }

        private val RESERVED = setOf("if", "then", "else", "assert", "with", "let", "in", "rec", "inherit")

        /// An attribute name as mlnix prints it (Source.cpp's printIdentifier).
        private fun identifier(s: String): String {
            if (s.isEmpty()) return "\"\""
            if (s in RESERVED) return "\"$s\""
            val c = s[0]
            val valid = (c in 'a'..'z' || c in 'A'..'Z' || c == '_') &&
                s.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' || it == '\'' || it == '-' }
            if (valid) return s
            val b = StringBuilder("\"")
            for (i in s.indices) {
                val x = s[i]
                when {
                    x == '"' -> b.append("\\\""); x == '\\' -> b.append("\\\\"); x == '\n' -> b.append("\\n")
                    x == '\r' -> b.append("\\r"); x == '\t' -> b.append("\\t")
                    x == '$' && i + 1 < s.length && s[i + 1] == '{' -> b.append("\\$")
                    else -> b.append(x)
                }
            }
            return b.append('"').toString()
        }

        /// A constant text as an LLVM global: its UTF-8 bytes, each outside printable ASCII (and `"`, `\`) as \XX.
        private fun lit(name: String, text: String): String {
            val bytes = text.toByteArray()
            val esc = StringBuilder()
            for (x in bytes) {
                val c = x.toInt() and 0xFF
                if (c in 0x20..0x7E && c != '"'.code && c != '\\'.code) esc.append(c.toChar()) else esc.append('\\').append("%02X".format(c))
            }
            return "  llvm.mlir.global internal constant @$name(\"$esc\\00\") : !llvm.array<${bytes.size + 1} x i8>\n"
        }

        private val PRELUDE = """  llvm.func @dprintf(i32, !llvm.ptr, ...) -> i32
  llvm.func @exit(i32)
  func.func private @nn_fail(%fmt: !llvm.ptr, %a: i64, %b: i64) {
    %two = arith.constant 2 : i32
    %x = llvm.call @dprintf(%two, %fmt, %a, %b) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i64, i64) -> i32
    %one = arith.constant 1 : i32
    llvm.call @exit(%one) : (i32) -> ()
    return
  }
"""

        /// F's son-form module with son's facts (arg_forced, forced_captures: `--son-release`), as a program.
        fun main(bin: String, file: String): Int = try {
            print(Native(Graph.export(bin, File(file).absolutePath, "--son-release")).emit())
            0
        } catch (e: NativeRefused) {
            System.err.println("nix-truffle --emit-trikeshed: refused: ${e.message}")
            2
        } catch (e: NixError) {
            System.err.println("nix-truffle --emit-trikeshed: ${e.message}")
            1
        }
    }
}
