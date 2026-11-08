package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.CallTarget
import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import java.util.Locale
import java.util.TreeMap

// Nix values on the JVM.  Every value is a JVM object made with `new`; nothing is freed by hand (docs/PRELOAD-DIALECTS.md, the
// splice rules): the collector frees what the program drops.  Scalars are boxed Long, Double, Boolean; null is NixNull.
//   string  NixString (its characters; string context is not kept)
//   path    NixPath
//   list    NixList: an array of lazy cells
//   set     NixAttrs: names in order to lazy cells
//   lambda  Closure (a son.body's CallTarget and its captures); a primop Prim, a partly applied one PrimApp
// A lazy cell is a value or a Thunk; force() makes it a value (weak head normal form).

object NixNull { override fun toString() = "null" }

class NixString(@JvmField val s: String) { override fun toString() = s }
class NixPath(@JvmField val p: String) { override fun toString() = p }
/// A list: its cells, or the join of two lists (`++`) that has not been read yet.  A join is O(1) and copies nothing (TrikeShed's
/// Join of two Series, immutable); the first read of its cells flattens it once into an array and lets the two sides go, as a
/// thunk is replaced by its value.  kif.nix's `[ t ] ++ cur`, once per token, then allocates a node per token instead of a copy of
/// `cur` per token (17 GB on sumo.full).  The size is known without flattening.
class NixList private constructor(private var flat: Array<Any?>?, private var left: NixList?, private var right: NixList?,
                                  @JvmField val size: Int) {
    constructor(items: Array<Any?>) : this(items, null, null, items.size)

    val items: Array<Any?>
        get() {
            flat?.let { return it }
            val out = arrayOfNulls<Any?>(size)
            // iteratively: a fold of `[ x ] ++ acc` is a spine as deep as the list is long
            val stack = ArrayDeque<NixList>()
            stack.addLast(this)
            var at = 0
            while (stack.isNotEmpty()) {
                val l = stack.removeLast()
                val f = l.flat
                if (f != null) { System.arraycopy(f, 0, out, at, f.size); at += f.size; continue }
                stack.addLast(l.right!!); stack.addLast(l.left!!)
            }
            flat = out; left = null; right = null
            return out
        }

    companion object {
        fun concat(a: NixList, b: NixList): NixList =
            if (a.size == 0) b else if (b.size == 0) a else NixList(null, a, b, a.size + b.size)
    }
}
class NixAttrs(@JvmField val map: TreeMap<String, Any?>) {
    operator fun get(k: String): Any? = map[k]
    val size get() = map.size
    companion object { @JvmField val EMPTY = NixAttrs(TreeMap()) }
}

/// A lambda: its body's CallTarget (a son.body), the values it closed over, and the pattern it binds.
class Closure(
    @JvmField val target: CallTarget, @JvmField val captures: Array<Any?>,
    @JvmField val formals: Array<String>?, @JvmField val defaults: BooleanArray?, @JvmField val ellipsis: Boolean,
    @JvmField val name: String?,
)
class Prim(@JvmField val key: String, @JvmField val arity: Int, @JvmField val impl: (Array<Any?>) -> Any) {
    val name get() = key.removePrefix("__")
}
class PrimApp(@JvmField val prim: Prim, @JvmField val args: Array<Any?>)

abstract class Thunk { abstract fun force(): Any }
/// A value already computed but held as a cell (an imported file's result, a primop's lazy result).
class Lazy(private var fn: (() -> Any)?) : Thunk() {
    private var v: Any? = null
    @TruffleBoundary
    override fun force(): Any {
        v?.let { return it }
        val f = fn ?: throw NixError("infinite recursion encountered")
        fn = null
        val r = f()
        v = r
        return r
    }
}

open class NixError(msg: String) : RuntimeException(msg, null, false, false)
class ThrowError(msg: String) : NixError(msg)      // `throw`: tryEval catches it
class AssertError(msg: String) : NixError(msg)     // a failed `assert`: tryEval catches it
class AbortError(msg: String) : NixError(msg)
class Unsupported(msg: String) : NixError("nix-truffle: unsupported: $msg")

fun force(v: Any?): Any = when (v) {
    is Thunk -> v.force()
    null -> throw NixError("internal: an unbound cell")
    else -> v
}

@TruffleBoundary
fun typeOf(v: Any): String = when (v) {
    is Long -> "int"; is Double -> "float"; is Boolean -> "bool"; NixNull -> "null"; is NixString -> "string"; is NixPath -> "path"
    is NixList -> "list"; is NixAttrs -> "set"; is Closure, is Prim, is PrimApp -> "lambda"
    else -> "unknown"
}
fun showType(v: Any): String = when (v) {
    is Long -> "an integer"; is Double -> "a float"; is Boolean -> "a Boolean"; NixNull -> "null"; is NixString -> "a string"
    is NixPath -> "a path"; is NixList -> "a list"; is NixAttrs -> "a set"; is Closure -> "a function"
    is Prim -> "a built-in function"; is PrimApp -> "a partially applied built-in function"
    else -> "a value"
}

fun forceInt(v: Any?): Long = force(v).let { it as? Long ?: throw NixError("expected an integer but found ${showType(it)}") }
fun forceBool(v: Any?): Boolean = force(v).let { it as? Boolean ?: throw NixError("expected a Boolean but found ${showType(it)}") }
fun forceList(v: Any?): NixList = force(v).let { it as? NixList ?: throw NixError("expected a list but found ${showType(it)}") }
fun forceAttrs(v: Any?): NixAttrs = force(v).let { it as? NixAttrs ?: throw NixError("expected a set but found ${showType(it)}") }
fun forceStr(v: Any?): String = force(v).let { (it as? NixString)?.s ?: throw NixError("expected a string but found ${showType(it)}") }
fun isFunction(v: Any) = v is Closure || v is Prim || v is PrimApp

// ── strings ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// C's "%g" (Nix prints floats with it); Java's %g keeps trailing zeros.
@TruffleBoundary
fun formatG(d: Double): String {
    if (d.isNaN()) return if (1.0 / d < 0 || d.toRawBits() < 0) "-nan" else "nan"
    if (d.isInfinite()) return if (d > 0) "inf" else "-inf"
    if (d == 0.0) return if (1.0 / d < 0) "-0" else "0"
    val e = String.format(Locale.ROOT, "%.5e", d)
    val exp = e.substring(e.indexOf('e') + 1).toInt()
    fun strip(s: String) = if (s.contains('.')) s.trimEnd('0').trimEnd('.') else s
    return if (exp < -4 || exp >= 6) {
        val mant = strip(e.substring(0, e.indexOf('e')))
        val ae = Math.abs(exp)
        mant + "e" + (if (exp < 0) "-" else "+") + (if (ae < 10) "0$ae" else "$ae")
    } else strip(String.format(Locale.ROOT, "%.${5 - exp}f", d))
}

@TruffleBoundary
fun literalString(s: String): String {
    val b = StringBuilder(s.length + 2).append('"')
    for (i in s.indices) {
        val c = s[i]
        when {
            c == '"' -> b.append("\\\""); c == '\\' -> b.append("\\\\"); c == '\n' -> b.append("\\n"); c == '\r' -> b.append("\\r")
            c == '\t' -> b.append("\\t"); c == '$' && i + 1 < s.length && s[i + 1] == '{' -> b.append("\\$")
            else -> b.append(c)
        }
    }
    return b.append('"').toString()
}

private val keywords = setOf("if", "then", "else", "assert", "with", "let", "in", "rec", "inherit")
fun identifier(s: String): String {
    if (s.isEmpty()) return "\"\""
    if (s in keywords) return "\"$s\""
    val c = s[0]
    val ok = (c in 'a'..'z' || c in 'A'..'Z' || c == '_') && s.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' || it == '\'' || it == '-' }
    return if (ok) s else literalString(s)
}

/// `--eval --strict`'s printer: values forced as they print, a set or list met before is «repeated».
@TruffleBoundary
fun printValue(v0: Any?, out: StringBuilder, seen: java.util.IdentityHashMap<Any, Boolean>) {
    when (val v = force(v0)) {
        is Long -> out.append(v)
        is Boolean -> out.append(if (v) "true" else "false")
        is NixString -> out.append(literalString(v.s))
        is NixPath -> out.append(v.p)
        NixNull -> out.append("null")
        is Double -> out.append(formatG(v))
        is NixAttrs -> if (v.size > 0 && seen.put(v, true) != null) out.append("«repeated»") else {
            out.append("{ ")
            for ((k, x) in v.map) { out.append(identifier(k)).append(" = "); printValue(x, out, seen); out.append("; ") }
            out.append('}')
        }
        is NixList -> if (v.size > 0 && seen.put(v, true) != null) out.append("«repeated»") else {
            out.append("[ ")
            for (x in v.items) { printValue(x, out, seen); out.append(' ') }
            out.append(']')
        }
        is Closure -> out.append("<LAMBDA>")
        is Prim -> out.append("<PRIMOP>")
        is PrimApp -> out.append("<PRIMOP-APP>")
        else -> out.append("<?>")
    }
}

// ── equality, order, coercion ───────────────────────────────────────────────────────────────────────────────────────────

/// Nix's `==`.  Two cells of a list or set that are one object are equal without a look (so `[f] == [f]` is true while `f == f`,
/// two functions, is false): `cells` says the operands are such cells.
@TruffleBoundary
fun eqValues(a0: Any?, b0: Any?, cells: Boolean = false): Boolean {
    if (cells && a0 === b0) return true
    val a = force(a0); val b = force(b0)
    if (a is Long && b is Double) return a.toDouble() == b
    if (a is Double && b is Long) return a == b.toDouble()
    return when (a) {
        is Long -> b is Long && a == b
        is Double -> b is Double && a == b
        is Boolean -> b is Boolean && a == b
        NixNull -> b === NixNull
        is NixString -> b is NixString && a.s == b.s
        is NixPath -> b is NixPath && a.p == b.p
        is NixList -> b is NixList && a.size == b.size && a.items.indices.all { eqValues(a.items[it], b.items[it], true) }
        is NixAttrs -> {
            if (b !is NixAttrs) return false
            if (isDerivation(a) && isDerivation(b)) { val i = a["outPath"]; val j = b["outPath"]; if (i != null && j != null) return eqValues(i, j, true) }
            if (a.size != b.size) return false
            val ia = a.map.entries.iterator(); val ib = b.map.entries.iterator()
            while (ia.hasNext()) { val x = ia.next(); val y = ib.next(); if (x.key != y.key || !eqValues(x.value, y.value, true)) return false }
            true
        }
        else -> false
    }
}

fun isDerivation(a: NixAttrs): Boolean = a["type"]?.let { (force(it) as? NixString)?.s == "derivation" } ?: false

@TruffleBoundary
fun lessThan(a0: Any?, b0: Any?): Boolean {
    val a = force(a0); val b = force(b0)
    if (a is Long && b is Double) return a.toDouble() < b
    if (a is Double && b is Long) return a < b.toDouble()
    return when {
        a is Long && b is Long -> a < b
        a is Double && b is Double -> a < b
        a is NixString && b is NixString -> a.s < b.s
        a is NixPath && b is NixPath -> a.p < b.p
        a is NixList && b is NixList -> {
            var i = 0
            while (true) {
                if (i == b.size) return false
                if (i == a.size) return true
                if (!eqValues(a.items[i], b.items[i], true)) return lessThan(a.items[i], b.items[i])
                i++
            }
            @Suppress("UNREACHABLE_CODE") false
        }
        typeOf(a) != typeOf(b) -> throw NixError("cannot compare ${showType(a)} with ${showType(b)}")
        else -> throw NixError("cannot compare ${showType(a)} with ${showType(b)}; values of that type are incomparable")
    }
}

/// coerceToString: `more` is toString's coercion (ints, floats, Booleans, null, lists); interpolation is the narrow one.
@TruffleBoundary
fun coerceToString(v0: Any?, more: Boolean): String {
    val v = force(v0)
    return when (v) {
        is NixString -> v.s
        is NixPath -> if (more) v.p else throw Unsupported("a path interpolated into a string (it is copied to the store)")
        is NixAttrs -> {
            v["__toString"]?.let { return coerceToString(Apply.call(it, arrayOf(v)), more) }
            v["outPath"]?.let { return coerceToString(it, more) }
            throw NixError("cannot coerce a set to a string")
        }
        else -> if (more) when (v) {
            is Long -> v.toString()
            is Double -> String.format(Locale.ROOT, "%f", v)
            is Boolean -> if (v) "1" else ""
            NixNull -> ""
            is NixList -> {
                // Nix: a space after each element but the last, and none after an empty list
                val b = StringBuilder()
                for ((i, x) in v.items.withIndex()) {
                    b.append(coerceToString(x, true))
                    val e = force(x)
                    if (i + 1 < v.size && !(e is NixList && e.size == 0)) b.append(' ')
                }
                b.toString()
            }
            else -> throw NixError("cannot coerce ${showType(v)} to a string")
        } else throw NixError("cannot coerce ${showType(v)} to a string")
    }
}

/// Nix's canonPath for an absolute path: no `.`, `..` or repeated slashes, no trailing slash.
fun canonPath(p: String): String {
    val parts = ArrayList<String>()
    for (c in p.split('/')) when (c) { "", "." -> {}; ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.size - 1); else -> parts.add(c) }
    return "/" + parts.joinToString("/")
}
