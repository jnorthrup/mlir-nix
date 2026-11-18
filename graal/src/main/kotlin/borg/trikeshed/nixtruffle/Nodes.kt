package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.CallTarget
import com.oracle.truffle.api.CompilerDirectives
import com.oracle.truffle.api.CompilerDirectives.CompilationFinal
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

// Escape: a Frame and its slots are allocated per call, and Graal's partial escape analysis keeps them virtual -- no allocation,
// the slots as values in registers -- on every path on which the frame does not escape.  The frame escapes into a cell made over it
// (lazy: a LocalThunk holds it until forced) and into any call that is not inlined.  So no op hands the frame to a boundary: an op
// reads its operands here, with slot indices that are constants (CompilationFinal arrays, exploded loops), and passes the boundary
// values; and the release at the return (BodyRoot) takes its boundary only when a cell of the frame is still unforced -- never when
// son.release keeps nothing.  A call computes the argument of a callee son says forces it (son.body's arg_forced) before the call,
// and makes no cell for it (ApplyNode).  Small arity only: past EXPLODE operands an op keeps its boundary over the frame (code size).
const val EXPLODE = 32

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

/// An argument computed before its call (ApplyNode) that threw: the callee gets this cell instead, and forcing it throws the same
/// error where the callee would have computed it, so a callee that throws before it forces the argument still throws its own.
class Failed(@JvmField val error: NixError) : Thunk() { override fun force(): Any = throw error }

/// The value of slot `s`, computed now if it is not yet.  From outside the body's graph (a cell forced later): the ops come from the
/// frame.  An op of the body reads them from itself (OpNode.strict), a constant when compiled.
fun strict(f: Frame, s: Int): Any = strictIn(f, f.ops, s)

/// strict with the body's ops given: compiled, `ops[s]` is a constant node and its exec is inlined, so the frame is not handed to a
/// call it cannot see into (Graal keeps it virtual: no Frame, no slots array).
fun strictIn(f: Frame, ops: Array<OpNode?>, s: Int): Any {
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
        val r = ops[s]!!.exec(f)
        f.slots[s] = r
        if (own) { (v as LocalThunk).value = r; v.frame = null } // the cell that stood for the slot holds the value from now on
        return r
    } catch (e: Throwable) {
        f.slots[s] = v // a later force runs it again (and fails again): tryEval may have caught this one
        throw e
    }
}

/// Slot `s` as a cell, without forcing it.
fun lazy(f: Frame, s: Int): Any? = lazyIn(f, f.ops, s)

/// `door`: the op that passes the cell on, counted under NIXTRUFFLE_CHECK_RELEASE=1 (ReleaseCheck.DOORS).
fun lazyIn(f: Frame, ops: Array<OpNode?>, s: Int, door: Int = 0): Any? {
    val v = f.slots[s]
    if (v is LocalThunk && v.value != null) return v.value
    if (v == null || v === Blackhole) {
        val op = ops[s]
        if (op is ConstNode) { f.slots[s] = op.value; return op.value } // a literal is its value: no cell, no frame held (son: fixed)
        val t = LocalThunk(f, s)
        if (ReleaseCheck.on) ReleaseCheck.cell(door)
        if (v == null) f.slots[s] = t
        return t
    }
    return v
}

abstract class OpNode : Node() {
    /// The ops of the body this op belongs to (BodyRoot sets it once, before any call): compiled, a constant.
    @CompilationFinal @JvmField var rootOps: Array<OpNode?>? = null
    /// The op's value, in weak head normal form.
    abstract fun exec(f: Frame): Any
    /// strict and lazy of the body's slots, its ops read from this node, not from the frame (strictIn).
    fun strict(f: Frame, s: Int): Any = strictIn(f, rootOps!!, s)
    fun lazy(f: Frame, s: Int, door: Int = 0): Any? = lazyIn(f, rootOps!!, s, door)
}

class BodyRoot(
    @JvmField val label: String, @JvmField val nslots: Int, @JvmField val ncaptures: Int, @JvmField val hasArg: Boolean,
    @JvmField val ret: Int, @field:Children @JvmField val ops: Array<OpNode?>,
    @JvmField val operands: Array<IntArray>, // per slot, the slots its op reads (none for an argument)
    @JvmField val keepable: BooleanArray?, // the slots son.release names (mlnix-opt --son-release), when the export has one
) : RootNode(null) {
    /// son.release keeps nothing: every cell of the frame is forced on every path on which the call returns, so nothing reads the
    /// frame after it and there is nothing to drop (the schedule's half of the lifecycle, SonDialect.cpp MustForce).
    @JvmField val releaseNoop: Boolean = keepable != null && keepable.none { it }
    @JvmField val smallFrame: Boolean = nslots <= 2 * EXPLODE
    init { for (o in ops) o?.rootOps = ops }

    override fun execute(frame: VirtualFrame): Any {
        val a = frame.arguments
        val slots = arrayOfNulls<Any?>(nslots)
        if (ncaptures > 0) System.arraycopy(a[0] as Array<Any?>, 0, slots, 0, ncaptures)
        if (hasArg) slots[ncaptures] = a[1]
        val f = Frame(slots, ops)
        val r = strictIn(f, ops, ret)
        if (ReleaseCheck.on) ReleaseCheck.call(releaseNoop, pendingAny(f))
        else if (releaseNoop) return r
        if (smallFrame) {
            if (!pendingSmall(f)) { clearSmall(f); return r } // no cell escaped unforced: the frame is garbage, and stays virtual
        }
        release(f)
        return r
    }

    /// A cell of this frame, still unforced, sits in a slot: someone may read the frame after the return.
    @ExplodeLoop
    private fun pendingSmall(f: Frame): Boolean {
        val s = f.slots
        for (i in 0 until nslots) { val v = s[i]; if (v is LocalThunk && v.frame === f && v.value == null) return true }
        return false
    }
    @ExplodeLoop
    private fun clearSmall(f: Frame) { val s = f.slots; for (i in 0 until nslots) s[i] = null }
    @TruffleBoundary
    private fun pendingAny(f: Frame): Boolean {
        val s = f.slots
        for (i in s.indices) { val v = s[i]; if (v is LocalThunk && v.frame === f && v.value == null) return true }
        return false
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
        if (ReleaseCheck.on && keepable != null) ReleaseCheck.frame(label, s, keep, keepable)
        for (i in s.indices) if (!keep[i] && s[i] != null) s[i] = Released
    }
    override fun getName() = label
    override fun toString() = label
}

/// NIXTRUFFLE_CHECK_RELEASE=1: each release is checked against son.release, the IR's account of the frame (son-release):
/// a slot kept here that son.release does not name is a fault of the IR; the counts say how much of the release the IR
/// already decides.  Printed to stderr at exit.
object ReleaseCheck {
    @JvmField val on = System.getenv("NIXTRUFFLE_CHECK_RELEASE") == "1"
    var frames = 0L; var slots = 0L; var keptHere = 0L; var namedByIr = 0L; var faults = 0L
    var calls = 0L; var noopCalls = 0L; var noopPending = 0L; var pendingCalls = 0L
    var applies = 0L; var toForced = 0L; var early = 0L; var earlyFailed = 0L; var operands = 0L; var operandsFailed = 0L
    var laterEarly = 0L; var laterFailed = 0L; var throughReturn = 0L
    /// The cells made over a frame, by the op that passes them on: each one makes its frame escape (it holds the frame until forced).
    val DOORS = arrayOf("other", "list elements", "attribute values", "a call's first argument", "a call's later arguments",
        "captures", "builtin operands", "a curried call's first argument")
    val cells = LongArray(DOORS.size)
    val faulty = LinkedHashSet<String>()
    init { if (on) Runtime.getRuntime().addShutdownHook(Thread { System.err.println(
        "release check: $frames frames with an unforced cell at return, $slots slots holding a value: kept $keptHere; " +
        "son.release named $namedByIr; kept outside son.release $faults" + (if (faulty.isEmpty()) "" else " in ${faulty.joinToString()}") +
        "\nrelease calls: $calls returns, $pendingCalls with a cell of the frame unforced; son.release empty (no release at all) in " +
        "$noopCalls, of which with a cell unforced $noopPending" +
        "\ncalls: $applies, to a body arg_forced $toForced (forced by the closure it returns, applied by the call: $throughReturn), " +
        "its argument computed before the call (an op of the caller) in $early, " +
        "of which it threw in $earlyFailed; a curried call's later arguments computed first (their body arg_forced) $laterEarly, " +
        "of which threw $laterFailed; builtin operands computed first (nix.strict, nix.first) $operands, of which threw $operandsFailed" +
        "\ncells made over a frame: " + DOORS.indices.joinToString { "${DOORS[it]} ${cells[it]}" }) }) }
    @TruffleBoundary
    fun call(noop: Boolean, pending: Boolean) { calls++; if (pending) pendingCalls++; if (noop) { noopCalls++; if (pending) noopPending++ } }
    @TruffleBoundary
    fun cell(door: Int) { cells[door]++ }
    @TruffleBoundary
    fun operand(threw: Boolean) { operands++; if (threw) operandsFailed++ }
    @TruffleBoundary
    fun later(threw: Boolean) { laterEarly++; if (threw) laterFailed++ }
    @TruffleBoundary
    fun apply(forced: Boolean, computed: Boolean, threw: Boolean, through: Boolean = false) {
        applies++; if (forced) toForced++; if (computed) early++; if (threw) earlyFailed++; if (through) throughReturn++
    }
    fun frame(label: String, s: Array<Any?>, keep: BooleanArray, keepable: BooleanArray) {
        frames++
        for (i in s.indices) {
            if (s[i] == null) continue
            slots++
            if (keepable[i]) namedByIr++
            if (keep[i]) { keptHere++; if (!keepable[i]) { faults++; faulty.add(label) } }
        }
    }
}

// ── constants ───────────────────────────────────────────────────────────────────────────────────────────────────────────

class ConstNode(@JvmField val value: Any) : OpNode() { override fun exec(f: Frame) = value }

// ── control and logic ───────────────────────────────────────────────────────────────────────────────────────────────────

class IfNode(@JvmField val c: Int, @JvmField val t: Int, @JvmField val e: Int) : OpNode() {
    // Two reads, each of a constant slot: `strict(f, if (..) t else e)` would read a slot the compiler cannot name, and hand the
    // frame to a call of either arm's op.
    override fun exec(f: Frame): Any = if (forceBool(strict(f, c))) strict(f, t) else strict(f, e)
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

class ListNode(@field:CompilationFinal(dimensions = 1) @JvmField val elems: IntArray) : OpNode() {
    @JvmField val small = elems.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    @ExplodeLoop
    private fun execSmall(f: Frame): Any { val a = arrayOfNulls<Any?>(elems.size); for (i in elems.indices) a[i] = lazy(f, elems[i], 1); return NixList(a) }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any = NixList(Array(elems.size) { lazy(f, elems[it], 1) })
}
class ConcatListsNode(@JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    override fun exec(f: Frame): Any {
        return NixList.concat(forceList(strict(f, a)), forceList(strict(f, b)))
    }
}
class UpdateNode(@JvmField val a: Int, @JvmField val b: Int) : OpNode() {
    override fun exec(f: Frame): Any { val x = forceAttrs(strict(f, a)); val y = forceAttrs(strict(f, b)); return update(x, y) }
    companion object {
        @TruffleBoundary
        fun update(x: NixAttrs, y: NixAttrs): Any {
            if (x.size == 0) return y
            if (y.size == 0) return x
            val m = TreeMap(x.map); m.putAll(y.map)
            return NixAttrs(m)
        }
    }
}
class AttrsNode(@field:CompilationFinal(dimensions = 1) @JvmField val names: Array<String>,
                @field:CompilationFinal(dimensions = 1) @JvmField val values: IntArray,
                @field:CompilationFinal(dimensions = 1) @JvmField val dynNames: IntArray,
                @field:CompilationFinal(dimensions = 1) @JvmField val dynValues: IntArray) : OpNode() {
    @JvmField val small = values.size + dynNames.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    /// The cells and the dynamic names read here; the map built behind boundaries that see values, not the frame.  The order is
    /// execLarge's: the static cells, then each dynamic name forced, checked and its cell put, in turn.
    @ExplodeLoop
    private fun execSmall(f: Frame): Any {
        val cells = arrayOfNulls<Any?>(values.size)
        for (i in values.indices) cells[i] = lazy(f, values[i], 2)
        val m = statics(names, cells)
        for (i in dynNames.indices) {
            val n = strict(f, dynNames[i])
            if (n === NixNull) continue
            val k = dynKey(m, n)
            put(m, k, lazy(f, dynValues[i], 2))
        }
        return NixAttrs(m)
    }
    companion object {
        @TruffleBoundary
        fun statics(names: Array<String>, cells: Array<Any?>): TreeMap<String, Any?> {
            val m = TreeMap<String, Any?>()
            for (i in names.indices) m[names[i]] = cells[i]
            return m
        }
        @TruffleBoundary
        fun dynKey(m: TreeMap<String, Any?>, n: Any): String {
            val k = (n as? NixString)?.s ?: throw NixError("expected a string but found ${showType(n)}")
            if (m.containsKey(k)) throw NixError("dynamic attribute '$k' already defined")
            return k
        }
        @TruffleBoundary
        fun put(m: TreeMap<String, Any?>, k: String, cell: Any?) { m[k] = cell }
    }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any {
        val m = TreeMap<String, Any?>()
        for (i in names.indices) m[names[i]] = lazy(f, values[i], 2)
        for (i in dynNames.indices) {
            val n = strict(f, dynNames[i])
            if (n === NixNull) continue
            val k = (n as? NixString)?.s ?: throw NixError("expected a string but found ${showType(n)}")
            if (m.containsKey(k)) throw NixError("dynamic attribute '$k' already defined")
            m[k] = lazy(f, dynValues[i], 2)
        }
        return NixAttrs(m)
    }
}

/// `e.a.b or d`, and `e ? a.b` when `test`: a null path component takes the next dynamic key.
class SelectNode(@JvmField val base: Int, @field:CompilationFinal(dimensions = 1) @JvmField val path: Array<String?>,
                 @field:CompilationFinal(dimensions = 1) @JvmField val keys: IntArray, @JvmField val default: Int,
                 @JvmField val test: Boolean) : OpNode() {
    @JvmField val small = path.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    /// execLarge's walk, with the frame read here and the attribute looked up behind a boundary over values.
    @ExplodeLoop
    private fun execSmall(f: Frame): Any {
        var v: Any = strict(f, base)
        var k = 0
        var depth = 0
        for (p in path) {
            val name = p ?: forceStr(strict(f, keys[k++]))
            val cell = attrOf(v, name)
            if (cell == null) {
                if (test) return false
                if (default >= 0) return strict(f, default)
                missing(v, name)
            }
            if (test) { if (++depth == path.size) return true } // `e ? a.b`: the last attribute is not forced
            v = force(cell)
        }
        return if (test) true else v
    }
    companion object {
        @TruffleBoundary
        fun attrOf(v: Any, name: String): Any? = (v as? NixAttrs)?.get(name)
        @TruffleBoundary
        fun missing(v: Any, name: String): Nothing {
            if (v !is NixAttrs) throw NixError("expected a set but found ${showType(v)}")
            throw NixError("attribute '$name' missing")
        }
    }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any {
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

class WithVarNode(@JvmField val name: String, @field:CompilationFinal(dimensions = 1) @JvmField val scopes: IntArray) : OpNode() {
    @JvmField val small = scopes.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    @ExplodeLoop
    private fun execSmall(f: Frame): Any {
        for (s in scopes) lookup(forceAttrs(strict(f, s)), name)?.let { return force(it) }
        undefined(name)
    }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any {
        for (s in scopes) forceAttrs(strict(f, s))[name]?.let { return force(it) }
        undefined(name)
    }
    companion object {
        @TruffleBoundary
        fun lookup(set: NixAttrs, name: String): Any? = set[name]
        @TruffleBoundary
        fun undefined(name: String): Nothing = throw NixError("undefined variable '$name'")
    }
}

/// `+`, one op for a chain `a + b + c` (and a path with string parts): the first part's kind decides; a path is canonical once,
/// at the end (ExprConcatStrings).
class AddNode(@field:CompilationFinal(dimensions = 1) @JvmField val parts: IntArray) : OpNode() {
    @JvmField val small = parts.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    /// execLarge's order: each part forced, then added (or appended to the path) before the next part is forced.
    @ExplodeLoop
    private fun execSmall(f: Frame): Any {
        val first = strict(f, parts[0])
        if (first is NixPath) {
            val b = pathStart(first)
            for (i in 1 until parts.size) pathPart(b, strict(f, parts[i]))
            return pathEnd(b)
        }
        var acc = first
        for (i in 1 until parts.size) acc = add(acc, strict(f, parts[i]))
        return acc
    }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any {
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
        fun pathStart(p: NixPath): StringBuilder = StringBuilder(p.p)
        @TruffleBoundary
        fun pathPart(b: StringBuilder, v: Any) { when (v) { is NixPath -> b.append(v.p); else -> b.append(coerceToString(v, false)) } }
        @TruffleBoundary
        fun pathEnd(b: StringBuilder): Any = NixPath(canonPath(b.toString()))
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
class InterpolateNode(@field:CompilationFinal(dimensions = 1) @JvmField val parts: IntArray) : OpNode() {
    @JvmField val small = parts.size <= EXPLODE
    override fun exec(f: Frame): Any = if (small) execSmall(f) else execLarge(f)
    /// execLarge's order: each part forced and coerced before the next is forced.
    @ExplodeLoop
    private fun execSmall(f: Frame): Any {
        val first = strict(f, parts[0])
        if (first is NixPath) { // `./a/${x}`: a path
            val b = AddNode.pathStart(first)
            for (i in 1 until parts.size) strPart(b, strict(f, parts[i]))
            return AddNode.pathEnd(b)
        }
        val b = strStart()
        strPart(b, first)
        for (i in 1 until parts.size) strPart(b, strict(f, parts[i]))
        return strEnd(b)
    }
    companion object {
        @TruffleBoundary
        fun strStart(): StringBuilder = StringBuilder()
        @TruffleBoundary
        fun strPart(b: StringBuilder, v: Any) { b.append(coerceToString(v, false)) }
        @TruffleBoundary
        fun strEnd(b: StringBuilder): Any = NixString(b.toString())
    }
    @TruffleBoundary
    private fun execLarge(f: Frame): Any {
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

/// son.defer: a lambda over its captures.  Its row's body is TrikeShed's anchor (trikeshed.anchor, Series.h `anchor`; Kotlin's `↺`): the
/// first evaluation mints it from the pool (Module.body), and every one after reads the constant that made, a compilation constant here,
/// so a compiled closure is made with no lookup of its row.
class DeferNode(@JvmField val module: Module, @JvmField val row: Int,
                @field:CompilationFinal(dimensions = 1) @JvmField val captures: IntArray) : OpNode() {
    @JvmField val small = captures.size <= EXPLODE
    @CompilationFinal @JvmField var body: Module.Body? = null
    override fun exec(f: Frame): Any {
        val b = body ?: anchor()
        return Closure(b.target, if (small) cellsSmall(f) else cellsLarge(f), b.formals, b.defaults, b.ellipsis, b.name, b.argForced,
            b.forcedAfter)
    }
    private fun anchor(): Module.Body {
        CompilerDirectives.transferToInterpreterAndInvalidate()
        return module.body(row).also { body = it }
    }
    @ExplodeLoop
    private fun cellsSmall(f: Frame): Array<Any?> { val a = arrayOfNulls<Any?>(captures.size); for (i in captures.indices) a[i] = lazy(f, captures[i], 5); return a }
    @TruffleBoundary
    private fun cellsLarge(f: Frame): Array<Any?> = Array(captures.size) { lazy(f, captures[it], 5) }
}

/// A call.  The callee's strictness is son's, read off the body that arrives (son.body's arg_forced): a body that forces its argument
/// on every path on which it returns gets it computed here, before the call, when it is an op of this body: no cell over this frame is
/// made for it, so the frame can stay virtual.  (An argument of this body is passed on as it came; computing it first would save no cell.)  The guess is the closure that arrives, and each way is compiled only once a call has gone it: a call site that
/// has met only such callees makes no cell for its first argument.  An argument that throws is passed as the error (Failed).
/// A curried call (`f a b`) applies its arguments one at a time and reads each later one the same way, off the function the
/// application before it returned: the body that takes `b` is known only once `f a` has returned it.
class ApplyNode(@JvmField val callee: Int, @field:CompilationFinal(dimensions = 1) @JvmField val args: IntArray) : OpNode() {
    @JvmField val small = args.size <= EXPLODE
    @CompilationFinal @JvmField var sawEarly = false // a callee whose body forces its argument has arrived here
    @CompilationFinal @JvmField var sawCells = false // a callee son says nothing of has
    @CompilationFinal @JvmField var sawLater = false // a later argument has gone to a body that forces it
    override fun exec(f: Frame): Any {
        val fn = strict(f, callee)
        if (args.isNotEmpty() && fn is Closure && (fn.argForced || fn.forcedAfter in 1 until args.size)) { // (no argument: an apply that only forces its callee)
            if (!sawEarly) { CompilerDirectives.transferToInterpreterAndInvalidate(); sawEarly = true }
            val s = args[0]
            val own = rootOps!![s] != null // an op of this body; an argument of it is passed as it came, the caller's cell, no frame of this call
            val a = if (!own) lazy(f, s, 3) else try { strict(f, s) } catch (e: NixError) { Failed(e) }
            if (ReleaseCheck.on) ReleaseCheck.apply(true, own, a is Failed, !fn.argForced)
            val r = Apply.one(fn, a)
            return if (args.size == 1) r else if (small) laterSmall(f, r) else laterLarge(f, r)
        }
        if (!sawCells) { CompilerDirectives.transferToInterpreterAndInvalidate(); sawCells = true }
        if (ReleaseCheck.on) ReleaseCheck.apply(false, false, false)
        if (args.size <= 1) return Apply.call(fn, if (args.isEmpty()) arrayOfNulls(0) else arrayOf(lazy(f, args[0], 3)))
        val r = Apply.one(fn, lazy(f, args[0], 7))
        return if (small) laterSmall(f, r) else laterLarge(f, r)
    }
    /// The arguments after the first, each against the function the application before it returned.  Each goes through Apply.call,
    /// as all of them did before: applied with Apply.one, a cell made curried.nix without son 50% slower (measured, not understood).
    @ExplodeLoop
    private fun laterSmall(f: Frame, r0: Any): Any { var r = r0; for (i in 1 until args.size) r = Apply.call(r, arrayOf(later(f, r, i))); return r }
    @TruffleBoundary
    private fun laterLarge(f: Frame, r0: Any): Any { var r = r0; for (i in 1 until args.size) r = Apply.call(r, arrayOf(later(f, r, i))); return r }
    private fun later(f: Frame, fn: Any, i: Int): Any? {
        val s = args[i]
        if (!(fn is Closure && (fn.argForced || fn.forcedAfter in 1 until args.size - i)) || rootOps!![s] == null) return lazy(f, s, 4)
        if (!sawLater) { CompilerDirectives.transferToInterpreterAndInvalidate(); sawLater = true }
        val a = try { strict(f, s) } catch (e: NixError) { Failed(e) }
        if (ReleaseCheck.on) ReleaseCheck.later(a is Failed)
        return a
    }
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

/// A primop op (nix-prims made it from a call): the builtin applied to its operands.  `strict` and `first` are its declaration's
/// modes, exported with the op (NixPrims.irdl.mlir: nix.strict, every operand forced before the op returns; nix.first, the
/// operand it forces before anything else, one more than its index).  Applied to all its operands, the builtin gets such an
/// operand computed when it is an op of this body: no cell over this frame is made for it.  One that throws is passed as the
/// error (Failed), which the builtin throws where it forces it.  The rest are cells, as before.
class PrimNode(@JvmField val prim: Prim, @field:CompilationFinal(dimensions = 1) @JvmField val args: IntArray,
               @JvmField val strict: Int, @JvmField val first: Int) : OpNode() {
    @JvmField val small = args.size <= EXPLODE
    @JvmField val full = args.size == prim.arity
    override fun exec(f: Frame): Any {
        val a = if (small) cellsSmall(f) else cellsLarge(f)
        return if (full) prim.impl(a) else Apply.call(prim, a)
    }
    private fun operand(f: Frame, i: Int): Any? {
        val s = args[i]
        val forced = full && (first == i + 1 || i < 32 && ((strict ushr i) and 1) != 0) // on every path on which the builtin returns
        if (!forced || rootOps!![s] == null) return lazy(f, s, 6)
        val a = try { strict(f, s) } catch (e: NixError) { Failed(e) }
        if (ReleaseCheck.on) ReleaseCheck.operand(a is Failed)
        return a
    }
    @ExplodeLoop
    private fun cellsSmall(f: Frame): Array<Any?> { val a = arrayOfNulls<Any?>(args.size); for (i in args.indices) a[i] = operand(f, i); return a }
    @TruffleBoundary
    private fun cellsLarge(f: Frame): Array<Any?> = Array(args.size) { operand(f, it) }
}

// ── building ────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// One exported file: its expression and its pool of lambda bodies.  The pool is TrikeShed's (TrikeShed.td PoolCol, Series.h's
/// Cursor): its rows appended in the order son.pool holds them (trikeshed.append: a row is its index, what a son.defer refers to), each
/// row's body anchored (trikeshed.anchor): made into a RootNode the first time it is needed, and that body from then on.
class Module(@JvmField val ops: List<Op>, @JvmField val loader: Loader) {
    class Body(val target: CallTarget, val formals: Array<String>?, val defaults: BooleanArray?, val ellipsis: Boolean, val name: String?,
               val argForced: Boolean, val forcedAfter: Int)

    private val rows: Array<Op>
    private val bodies: Array<Body?>
    private val rowOf = HashMap<String, Int>() // a son.defer's symbol, read once when its node is built
    @JvmField val expr: Op

    init {
        var e: Op? = null
        var pool: List<Op> = emptyList()
        for (o in ops) when (o.name) {
            "nix.expr" -> e = o
            "son.pool" -> pool = o.regions[0][0].ops
        }
        rows = pool.toTypedArray()
        for ((i, b) in rows.withIndex()) rowOf[b.str("sym_name")!!] = i
        bodies = arrayOfNulls(rows.size)
        expr = e ?: throw NixError("son-export: no nix.expr")
    }

    /// The row a son.defer's symbol names.
    fun row(sym: String): Int = rowOf[sym] ?: throw NixError("son-export: no row $sym")

    val baseDir: String get() = expr.str("base_dir") ?: "/"
    val exprTarget: CallTarget by lazy { build("expr", expr.regions[0][0], 0, false).callTarget }

    /// Row i's body: the anchor's mint the first time, the constant after.
    fun body(i: Int): Body = bodies[i] ?: mint(i).also { bodies[i] = it }

    @Suppress("UNCHECKED_CAST")
    private fun mint(i: Int): Body {
        val o = rows[i]
        val row = o.str("sym_name")!!
        val lam = o.attrs["lambda"] as Map<String, Any?>
        val formals = (lam["formals"] as List<String>?)?.toTypedArray()
        val defaults = (lam["formal_defaults"] as List<Boolean>?)?.toBooleanArray() ?: formals?.let { BooleanArray(it.size) }
        val ncaptures = (o.attrs["captures"] as Number).toInt()
        val root = build((lam["name"] as String?) ?: row, o.regions[0][0], ncaptures, true)
        val argForced = o.attrs["arg_forced"] == true
        return Body(root.callTarget, formals, defaults, lam["ellipsis"] == true, lam["name"] as String?, argForced,
            if (argForced) -1 else forcedAfter(o, ncaptures, 3))
    }

    /// How many applications of what the row returns pass before its block argument `arg` is forced, or -1.  0: the body forces it
    /// itself (son.body's arg_forced for the argument, forced_captures for a capture).  n + 1: the body returns a closure it makes
    /// (son.defer) over it, and that row forces the capture after n.  Read off the IR as exported; `depth` bounds the chain.
    @Suppress("UNCHECKED_CAST")
    private fun forcedAfter(o: Op, arg: Int, depth: Int): Int {
        val ncaptures = (o.attrs["captures"] as Number).toInt()
        if (if (arg == ncaptures) o.attrs["arg_forced"] == true else (o.attrs["forced_captures"] as List<Number>?)?.any { it.toInt() == arg } == true)
            return 0
        if (depth == 0) return -1
        val block = o.regions[0][0]
        val ret = block.ops.lastOrNull { it.name == "nix.return" } ?: return -1
        val defer = block.ops.firstOrNull { it.name == "son.defer" && it.res.firstOrNull() == ret.ins[0] } ?: return -1
        val next = rows[rowOf[(defer.attrs["row"] as List<String>).last()] ?: return -1]
        for ((i, c) in defer.ins.withIndex()) if (c == block.args[arg]) forcedAfter(next, i, depth - 1).let { if (it >= 0) return it + 1 }
        return -1
    }

    private fun build(label: String, block: Block, ncaptures: Int, hasArg: Boolean): BodyRoot {
        val slot = HashMap<Int, Int>()
        for (a in block.args) slot[a] = slot.size
        for (o in block.ops) for (r in o.res) slot[r] = slot.size
        val nodes = arrayOfNulls<OpNode>(slot.size)
        var ret = -1
        var keepable: BooleanArray? = null
        for (o in block.ops) {
            if (o.name == "nix.return") { ret = slot[o.ins[0]]!!; continue }
            if (o.name == "son.release") { keepable = BooleanArray(slot.size).also { k -> for (v in o.ins) k[slot[v]!!] = true }; continue }
            nodes[slot[o.res[0]]!!] = node(o, IntArray(o.ins.size) { slot[o.ins[it]]!! })
        }
        val operands = Array(slot.size) { IntArray(0) }
        for (o in block.ops) if (o.name != "nix.return" && o.name != "son.release") operands[slot[o.res[0]]!!] = IntArray(o.ins.size) { slot[o.ins[it]]!! }
        return BodyRoot(label, slot.size, ncaptures, hasArg, ret, nodes, operands, keepable)
    }

    @Suppress("UNCHECKED_CAST")
    private fun node(o: Op, ins: IntArray): OpNode {
        o.str("prim_key")?.let {
            val m = o.attrs["prim_modes"] as List<Number>? // [nix.strict mask, nix.first + 1] of its declaration
            return PrimNode(Prims.byKey[it] ?: Prims.missing(it), ins, m?.get(0)?.toInt() ?: 0, m?.get(1)?.toInt() ?: 0)
        }
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
            "son.defer" -> DeferNode(this, row((a["row"] as List<String>).last()), ins)
            else -> throw Unsupported("op ${o.name}")
        }
    }
}
