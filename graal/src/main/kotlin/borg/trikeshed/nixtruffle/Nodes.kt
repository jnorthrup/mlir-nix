package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.CallTarget
import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import com.oracle.truffle.api.frame.VirtualFrame
import com.oracle.truffle.api.nodes.ExplodeLoop
import com.oracle.truffle.api.nodes.Node
import com.oracle.truffle.api.nodes.RootNode
import java.util.TreeMap

// The Truffle nodes.  A son.body (and the file's nix.expr) is a RootNode; its ops are its children, one per result.  A graph region
// reads values before their definition, and Nix is lazy, so a call's values live in a Frame of slots, one per block argument and
// op result, filled when first forced: an op runs at most once per call, when something needs its value.

class Frame(@JvmField val slots: Array<Any?>, @JvmField val ops: Array<OpNode?>)

/// A slot no op will compute again: its op ran, the value was dropped when the call returned (BodyRoot.release).
private object Released

private object Blackhole

/// A slot not yet computed, as a cell for an op that stores without forcing (a list element, an attribute, an argument).
class LocalThunk(frame: Frame, @JvmField val slot: Int) : Thunk() {
    // The frame, until the cell is forced: then only the value.  A forced cell that kept its frame kept every slot of it, and
    // through them the cells of the call before (kif.nix's fold state: each `[ t ] ++ cur` held the previous state, so all 1.4 M
    // copies of `cur` stayed reachable and the collector could free none of them).
    @JvmField var frame: Frame? = frame
    @JvmField var value: Any? = null
    // A boundary: forcing a cell is a call into another frame's graph; inlined, strict → force → strict never ends (Graal: "Too
    // deep inlining").  The op that fills a slot of this frame is still compiled into the body.
    @TruffleBoundary
    override fun force(): Any {
        value?.let { return it }
        val f = frame!!
        val v = strict(f, slot)
        value = v
        frame = null
        return v
    }
}

/// The value of slot `s`, computed now if it is not yet.
fun strict(f: Frame, s: Int): Any {
    val v = f.slots[s]
    if (v === Released) throw NixError("internal: a released slot was read")
    if (v != null && v !is Thunk && v !== Blackhole) return v
    if (v === Blackhole) throw NixError("infinite recursion encountered")
    if (v is LocalThunk && v.value != null) { f.slots[s] = v.value; return v.value!! }
    val own = v is LocalThunk && v.frame === f && v.slot == s
    if (v is Thunk && !own) {
        val r = v.force()
        f.slots[s] = r
        return r
    }
    f.slots[s] = Blackhole
    try {
        val r = f.ops[s]!!.exec(f)
        f.slots[s] = r
        if (own) { (v as LocalThunk).value = r; v.frame = null } // the cell that stood for the slot holds the value from now on
        return r
    } catch (e: Throwable) {
        f.slots[s] = v // a later force runs it again (and fails again): tryEval may have caught this one
        throw e
    }
}

/// Slot `s` as a cell, without forcing it.
fun lazy(f: Frame, s: Int): Any? {
    val v = f.slots[s]
    if (v is LocalThunk && v.value != null) return v.value
    if (v == null || v === Blackhole) {
        val t = LocalThunk(f, s)
        if (v == null) f.slots[s] = t
        return t
    }
    return v
}

abstract class OpNode : Node() {
    /// The op's value, in weak head normal form.
    abstract fun exec(f: Frame): Any
}

class BodyRoot(
    @JvmField val label: String, @JvmField val nslots: Int, @JvmField val ncaptures: Int, @JvmField val hasArg: Boolean,
    @JvmField val ret: Int, @field:Children @JvmField val ops: Array<OpNode?>,
    @JvmField val operands: Array<IntArray>, // per slot, the slots its op reads (none for an argument)
) : RootNode(null) {
    override fun execute(frame: VirtualFrame): Any {
        val a = frame.arguments
        val slots = arrayOfNulls<Any?>(nslots)
        if (ncaptures > 0) System.arraycopy(a[0] as Array<Any?>, 0, slots, 0, ncaptures)
        if (hasArg) slots[ncaptures] = a[1]
        val f = Frame(slots, ops)
        val r = strict(f, ret)
        release(f)
        return r
    }

    /// After the call: the frame keeps what its pending cells will read, and nothing else.  A pending slot (its op not run: empty,
    /// or this frame's unforced cell) needs its op's operands; an operand already computed is kept as it is (its own operands are
    /// not needed again), a pending one is followed.  Every other slot is dropped, so a cell that escaped (a list element, an
    /// attribute, a closure's capture) holds the values it reads, as Nix's thunk holds its environment, and not the temporaries of
    /// the whole call: kif.nix's fold kept each step's copy of `cur` alive through cells like `[ (reverse st.cur) ]` otherwise.
    @TruffleBoundary
    private fun release(f: Frame) {
        val s = f.slots
        fun pending(i: Int): Boolean { val v = s[i]; return (v == null && ops[i] != null) || (v is LocalThunk && v.frame === f && v.value == null) }
        var any = false
        for (i in s.indices) if (pending(i) && s[i] != null) { any = true; break }
        if (!any) { // no cell of this frame escaped unforced: nothing will read it again
            for (i in s.indices) s[i] = null
            return
        }
        val keep = BooleanArray(s.size)
        val work = IntArray(s.size); var n = 0
        for (i in s.indices) if (s[i] is LocalThunk && pending(i)) { keep[i] = true; work[n++] = i }
        while (n > 0) {
            val i = work[--n]
            for (o in operands[i]) {
                if (keep[o]) continue
                keep[o] = true
                if (pending(o)) work[n++] = o
            }
        }
        for (i in s.indices) if (!keep[i] && s[i] != null) s[i] = Released
    }
    override fun getName() = label
    override fun toString() = label
}

// ── constants ───────────────────────────────────────────────────────────────────────────────────────────────────────────

class ConstNode(@JvmField val value: Any) : OpNode() { override fun exec(f: Frame) = value }

// ── control and logic ───────────────────────────────────────────────────────────────────────────────────────────────────

class IfNode(@JvmField val c: Int, @JvmField val t: Int, @JvmField val e: Int) : OpNode() {
    override fun exec(f: Frame): Any = strict(f, if (forceBool(strict(f, c))) t else e)
}
class AssertNode(@JvmField val c: Int, @JvmField val body: Int, @JvmField val text: String) : OpNode() {
    override fun exec(f: Frame): Any {
        if (!forceBool(strict(f, c))) throw AssertError("assertion '$text' failed")
        return strict(f, body)
    }
}
class NotNode(@JvmField val a: Int) : OpNode() { override fun exec(f: Frame): Any = !forceBool(strict(f, a)) }
class LogicNode(@JvmField val kind: Int, @JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    override fun exec(f: Frame): Any {
        val x = forceBool(strict(f, a))
        return when (kind) {
            0 -> x && forceBool(strict(f, b))    // and
            1 -> x || forceBool(strict(f, b))    // or
            else -> !x || forceBool(strict(f, b)) // impl
        }
    }
}
class EqNode(@JvmField val neg: Boolean, @JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    override fun exec(f: Frame): Any = eqValues(strict(f, a), strict(f, b)) != neg
}

// ── values ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

class ListNode(@JvmField val elems: IntArray) : OpNode() {
    @ExplodeLoop
    override fun exec(f: Frame): Any = NixList(Array(elems.size) { lazy(f, elems[it]) })
}
class ConcatListsNode(@JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    override fun exec(f: Frame): Any {
        return NixList.concat(forceList(strict(f, a)), forceList(strict(f, b)))
    }
}
class UpdateNode(@JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    @TruffleBoundary
    override fun exec(f: Frame): Any {
        val x = forceAttrs(strict(f, a)); val y = forceAttrs(strict(f, b))
        if (x.size == 0) return y
        if (y.size == 0) return x
        val m = TreeMap(x.map); m.putAll(y.map)
        return NixAttrs(m)
    }
}
class AttrsNode(@JvmField val names: Array<String>, @JvmField val values: IntArray, @JvmField val dynNames: IntArray,
                @JvmField val dynValues: IntArray) : OpNode() {
    @TruffleBoundary
    override fun exec(f: Frame): Any {
        val m = TreeMap<String, Any?>()
        for (i in names.indices) m[names[i]] = lazy(f, values[i])
        for (i in dynNames.indices) {
            val n = strict(f, dynNames[i])
            if (n === NixNull) continue
            val k = (n as? NixString)?.s ?: throw NixError("expected a string but found ${showType(n)}")
            if (m.containsKey(k)) throw NixError("dynamic attribute '$k' already defined")
            m[k] = lazy(f, dynValues[i])
        }
        return NixAttrs(m)
    }
}

/// `e.a.b or d`, and `e ? a.b` when `test`: a null path component takes the next dynamic key.
class SelectNode(@JvmField val base: Int, @JvmField val path: Array<String?>, @JvmField val keys: IntArray, @JvmField val default: Int,
                 @JvmField val test: Boolean) : OpNode() {
    @TruffleBoundary
    override fun exec(f: Frame): Any {
        var v: Any = strict(f, base)
        var k = 0
        var depth = 0
        for (p in path) {
            val name = p ?: forceStr(strict(f, keys[k++]))
            val a = v as? NixAttrs
            val cell = a?.get(name)
            if (cell == null) {
                if (test) return false
                if (default >= 0) return strict(f, default)
                if (a == null) throw NixError("expected a set but found ${showType(v)}")
                throw NixError("attribute '$name' missing")
            }
            if (test) { if (++depth == path.size) return true } // `e ? a.b`: the last attribute is not forced
            v = force(cell)
        }
        return if (test) true else v
    }
}

class FormalNode(@JvmField val arg: Int, @JvmField val name: String, @JvmField val default: Int) : OpNode() {
    override fun exec(f: Frame): Any {
        val a = forceAttrs(strict(f, arg))
        val cell = a[name]
        if (cell != null) return force(cell)
        if (default >= 0) return strict(f, default)
        throw NixError("function called without required argument '$name'")
    }
}

class WithVarNode(@JvmField val name: String, @JvmField val scopes: IntArray) : OpNode() {
    override fun exec(f: Frame): Any {
        for (s in scopes) forceAttrs(strict(f, s))[name]?.let { return force(it) }
        throw NixError("undefined variable '$name'")
    }
}

/// `+`, one op for a chain `a + b + c` (and a path with string parts): the first part's kind decides; a path is canonical once,
/// at the end (ExprConcatStrings).
class AddNode(@JvmField val parts: IntArray) : OpNode() {
    @TruffleBoundary
    override fun exec(f: Frame): Any {
        val first = strict(f, parts[0])
        if (first is NixPath) {
            val b = StringBuilder(first.p)
            for (i in 1 until parts.size) when (val v = strict(f, parts[i])) {
                is NixPath -> b.append(v.p)
                else -> b.append(coerceToString(v, false))
            }
            return NixPath(canonPath(b.toString()))
        }
        var acc = first
        for (i in 1 until parts.size) acc = add(acc, strict(f, parts[i]))
        return acc
    }
    companion object {
        @TruffleBoundary
        fun add(x: Any, y: Any): Any = when {
            x is Long && y is Long -> try { Math.addExact(x, y) } catch (e: ArithmeticException) { throw NixError("integer overflow in adding $x + $y") }
            x is Long && y is Double -> x + y
            x is Double && y is Long -> x + y
            x is Double && y is Double -> x + y
            x is NixPath && y is NixString -> NixPath(canonPath(x.p + y.s))
            x is NixPath && y is NixPath -> NixPath(canonPath(x.p + y.p))
            x is NixString -> NixString(x.s + coerceToString(y, false))
            x is NixPath -> NixPath(canonPath(x.p + coerceToString(y, false)))
            else -> throw NixError("cannot add ${showType(y)} to ${showType(x)}")
        }
    }
}
class InterpolateNode(@JvmField val parts: IntArray) : OpNode() {
    @TruffleBoundary
    override fun exec(f: Frame): Any {
        val first = strict(f, parts[0])
        if (first is NixPath) { // `./a/${x}`: a path
            val b = StringBuilder(first.p)
            for (i in 1 until parts.size) b.append(coerceToString(strict(f, parts[i]), false))
            return NixPath(canonPath(b.toString()))
        }
        val b = StringBuilder()
        for (p in parts) b.append(coerceToString(strict(f, p), false))
        return NixString(b.toString())
    }
}

// ── functions ───────────────────────────────────────────────────────────────────────────────────────────────────────────

/// son.defer: a lambda over its captures; the body's CallTarget is made on the first call (the module mints rows on demand).
class DeferNode(@JvmField val module: Module, @JvmField val row: String, @JvmField val captures: IntArray) : OpNode() {
    override fun exec(f: Frame): Any {
        val b = module.body(row)
        return Closure(b.target, Array(captures.size) { lazy(f, captures[it]) }, b.formals, b.defaults, b.ellipsis, b.name)
    }
}

class ApplyNode(@JvmField val callee: Int, @JvmField val args: IntArray) : OpNode() {
    override fun exec(f: Frame): Any = Apply.call(strict(f, callee), Array(args.size) { lazy(f, args[it]) })
}

object Apply {
    @TruffleBoundary
    fun call(fn0: Any?, args: Array<Any?>): Any {
        var fn = force(fn0)
        for (a in args) fn = one(fn, a)
        return fn
    }

    @TruffleBoundary
    fun one(fn: Any, arg: Any?): Any = when (fn) {
        is Closure -> {
            if (fn.formals != null) {
                val set = forceAttrs(arg)
                if (!fn.ellipsis) for (k in set.map.keys) if (k !in fn.formals)
                    throw NixError("function '${fn.name ?: "anonymous lambda"}' called with unexpected argument '$k'")
                for ((i, n) in fn.formals.withIndex()) if (!fn.defaults!![i] && set[n] == null)
                    throw NixError("function '${fn.name ?: "anonymous lambda"}' called without required argument '$n'")
            }
            fn.target.call(fn.captures, arg)
        }
        is Prim -> if (fn.arity == 1) fn.impl(arrayOf(arg)) else PrimApp(fn, arrayOf(arg))
        is PrimApp -> {
            val all = arrayOf(*fn.args, arg)
            if (all.size == fn.prim.arity) fn.prim.impl(all) else PrimApp(fn.prim, all)
        }
        is NixAttrs -> {
            val functor = fn["__functor"] ?: throw NixError("attempt to call something which is not a function but a set")
            one(one(force(functor), fn), arg)
        }
        else -> throw NixError("attempt to call something which is not a function but ${showType(fn)}")
    }
}

/// A primop op (nix-prims made it from a call): the builtin applied to its operands.
class PrimNode(@JvmField val prim: Prim, @JvmField val args: IntArray) : OpNode() {
    override fun exec(f: Frame): Any {
        val a = Array(args.size) { lazy(f, args[it]) }
        return if (a.size == prim.arity) prim.impl(a) else Apply.call(prim, a)
    }
}

// ── building ────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// One exported file: its expression and its pool of lambda bodies, made into RootNodes the first time each is needed.
class Module(@JvmField val ops: List<Op>, @JvmField val loader: Loader) {
    class Body(val target: CallTarget, val formals: Array<String>?, val defaults: BooleanArray?, val ellipsis: Boolean, val name: String?)

    private val rows = HashMap<String, Op>()
    private val bodies = HashMap<String, Body>()
    @JvmField val expr: Op

    init {
        var e: Op? = null
        for (o in ops) when (o.name) {
            "nix.expr" -> e = o
            "son.pool" -> for (b in o.regions[0][0].ops) rows[b.str("sym_name")!!] = b
        }
        expr = e ?: throw NixError("son-export: no nix.expr")
    }

    val baseDir: String get() = expr.str("base_dir") ?: "/"
    val exprTarget: CallTarget by lazy { build("expr", expr.regions[0][0], 0, false).callTarget }

    @Suppress("UNCHECKED_CAST")
    fun body(row: String): Body = bodies.getOrPut(row) {
        val o = rows[row] ?: throw NixError("son-export: no row $row")
        val lam = o.attrs["lambda"] as Map<String, Any?>
        val formals = (lam["formals"] as List<String>?)?.toTypedArray()
        val defaults = (lam["formal_defaults"] as List<Boolean>?)?.toBooleanArray() ?: formals?.let { BooleanArray(it.size) }
        val root = build((lam["name"] as String?) ?: row, o.regions[0][0], (o.attrs["captures"] as Number).toInt(), true)
        Body(root.callTarget, formals, defaults, lam["ellipsis"] == true, lam["name"] as String?)
    }

    private fun build(label: String, block: Block, ncaptures: Int, hasArg: Boolean): BodyRoot {
        val slot = HashMap<Int, Int>()
        for (a in block.args) slot[a] = slot.size
        for (o in block.ops) for (r in o.res) slot[r] = slot.size
        val nodes = arrayOfNulls<OpNode>(slot.size)
        var ret = -1
        for (o in block.ops) {
            if (o.name == "nix.return") { ret = slot[o.ins[0]]!!; continue }
            nodes[slot[o.res[0]]!!] = node(o, IntArray(o.ins.size) { slot[o.ins[it]]!! })
        }
        val operands = Array(slot.size) { IntArray(0) }
        for (o in block.ops) if (o.name != "nix.return") operands[slot[o.res[0]]!!] = IntArray(o.ins.size) { slot[o.ins[it]]!! }
        return BodyRoot(label, slot.size, ncaptures, hasArg, ret, nodes, operands)
    }

    @Suppress("UNCHECKED_CAST")
    private fun node(o: Op, ins: IntArray): OpNode {
        o.str("prim_key")?.let { return PrimNode(Prims.byKey[it] ?: Prims.missing(it), ins) }
        val a = o.attrs
        return when (o.name) {
            "nix.int" -> ConstNode((a["value"] as Number).toLong())
            "nix.float" -> ConstNode((a["value"] as Number).toDouble())
            "nix.bool" -> ConstNode(a["value"] as Boolean)
            "nix.null" -> ConstNode(NixNull)
            "nix.str" -> ConstNode(NixString(a["value"] as String))
            "nix.path" -> ConstNode(NixPath(a["value"] as String))
            "nix.builtin" -> ConstNode(Prims.global(a["name"] as String))
            "nix.if" -> IfNode(ins[0], ins[1], ins[2])
            "nix.assert" -> AssertNode(ins[0], ins[1], (a["text"] as String?) ?: "")
            "nix.not" -> NotNode(ins[0])
            "nix.and" -> LogicNode(0, ins[0], ins[1])
            "nix.or" -> LogicNode(1, ins[0], ins[1])
            "nix.impl" -> LogicNode(2, ins[0], ins[1])
            "nix.eq" -> EqNode(false, ins[0], ins[1])
            "nix.neq" -> EqNode(true, ins[0], ins[1])
            "nix.list" -> ListNode(ins)
            "nix.concat_lists" -> ConcatListsNode(ins[0], ins[1])
            "nix.update" -> UpdateNode(ins[0], ins[1])
            "nix.concat_strings" -> AddNode(ins)
            "nix.interpolate" -> InterpolateNode(ins)
            "nix.attrs" -> {
                val seg = o.segments()!!
                AttrsNode((a["names"] as List<String>).toTypedArray(), ins.copyOfRange(0, seg[0]),
                    ins.copyOfRange(seg[0], seg[0] + seg[1]), ins.copyOfRange(seg[0] + seg[1], seg[0] + seg[1] + seg[2]))
            }
            "nix.select" -> {
                val seg = o.segments()!!
                SelectNode(ins[0], (a["path"] as List<String?>).toTypedArray(), ins.copyOfRange(1, 1 + seg[1]),
                    if (seg[2] == 1) ins[1 + seg[1]] else -1, false)
            }
            "nix.has_attr" -> SelectNode(ins[0], (a["path"] as List<String?>).toTypedArray(), ins.copyOfRange(1, ins.size), -1, true)
            "nix.formal" -> FormalNode(ins[0], a["name"] as String, if (ins.size > 1) ins[1] else -1)
            "nix.with_var" -> WithVarNode(a["name"] as String, ins)
            "nix.apply" -> ApplyNode(ins[0], ins.copyOfRange(1, ins.size))
            "son.defer" -> DeferNode(this, (a["row"] as List<String>).last(), ins)
            else -> throw Unsupported("op ${o.name}")
        }
    }
}
