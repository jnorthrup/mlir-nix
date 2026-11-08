package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.security.MessageDigest
import java.util.TreeMap
import java.util.regex.Pattern

// The builtins, keyed as NixPrims.irdl.mlir keys them (`__attrNames`, `map`, ...): one implementation for a primop op and for the
// value `builtins.attrNames`.  An implementation takes its arguments as cells and returns a value in weak head normal form.

object Prims {
    val byKey = HashMap<String, Prim>()
    private val extraGlobals = HashMap<String, Any>()
    lateinit var loader: Loader

    fun missing(key: String): Prim = Prim(key, 1) { throw Unsupported("builtin $key") }

    private fun def(key: String, arity: Int, impl: (Array<Any?>) -> Any) { byKey[key] = Prim(key, arity, impl) }

    /// A name of the base environment (`nix.builtin`).
    fun global(name: String): Any = when (name) {
        "builtins" -> builtins
        else -> extraGlobals[name] ?: byKey[name] ?: byKey["__$name"] ?: missing(name)
    }

    val builtins: NixAttrs by lazy {
        val m = TreeMap<String, Any?>()
        for ((k, p) in byKey) m[k.removePrefix("__")] = p
        m.putAll(extraGlobals)
        m["builtins"] = Lazy { builtins }
        NixAttrs(m)
    }

    private fun str(s: String) = NixString(s)
    private fun attrs(vararg kv: Pair<String, Any?>) = NixAttrs(TreeMap<String, Any?>().apply { for ((k, v) in kv) put(k, v) })
    private fun list(xs: List<Any?>) = NixList(xs.toTypedArray())
    private fun lazyCall(f: Any?, vararg a: Any?): Any? = Lazy { Apply.call(f, arrayOf(*a)) }
    private fun pathOrString(v: Any, s: String, keepPath: Boolean): Any = if (keepPath && v is NixPath) NixPath(s) else NixString(s)
    private fun num(v: Any?): Any = force(v).also { if (it !is Long && it !is Double) throw NixError("expected an integer but found ${showType(it)}") }

    @TruffleBoundary
    private fun arith(op: Char, a0: Any?, b0: Any?): Any {
        val a = num(a0); val b = num(b0)
        if (a is Long && b is Long) return when (op) {
            '+' -> Math.addExact(a, b); '-' -> Math.subtractExact(a, b); '*' -> Math.multiplyExact(a, b)
            else -> { if (b == 0L) throw NixError("division by zero"); a / b }
        }
        val x = (a as Number).toDouble(); val y = (b as Number).toDouble()
        return when (op) { '+' -> x + y; '-' -> x - y; '*' -> x * y; else -> { if (y == 0.0) throw NixError("division by zero"); x / y } }
    }

    private fun deep(v0: Any?, seen: java.util.IdentityHashMap<Any, Boolean> = java.util.IdentityHashMap()) {
        when (val v = force(v0)) {
            is NixList -> if (seen.put(v, true) == null) for (x in v.items) deep(x, seen)
            is NixAttrs -> if (seen.put(v, true) == null) for (x in v.map.values) deep(x, seen)
            else -> {}
        }
    }

    // Nix's version components: a run of digits, or a run of other characters; '.' and '-' separate.
    private fun components(s: String): List<String> {
        val out = ArrayList<String>(); var i = 0
        while (i < s.length) {
            if (s[i] == '.' || s[i] == '-') { i++; continue }
            val st = i
            if (s[i].isDigit()) while (i < s.length && s[i].isDigit()) i++
            else while (i < s.length && !s[i].isDigit() && s[i] != '.' && s[i] != '-') i++
            out.add(s.substring(st, i))
        }
        return out
    }
    private fun componentsLT(c1: String, c2: String): Boolean {
        val n1 = c1.toLongOrNull()?.takeIf { c1.all(Char::isDigit) }; val n2 = c2.toLongOrNull()?.takeIf { c2.all(Char::isDigit) }
        return when {
            n1 != null && n2 != null -> n1 < n2
            c1 == "" && n2 != null -> true
            c1 == "pre" && c2 != "pre" -> true
            c2 == "pre" -> false
            n2 != null -> true
            n1 != null -> false
            else -> c1 < c2
        }
    }
    fun compareVersions(a: String, b: String): Int {
        val x = components(a); val y = components(b)
        for (i in 0 until maxOf(x.size, y.size)) {
            val c1 = x.getOrElse(i) { "" }; val c2 = y.getOrElse(i) { "" }
            if (componentsLT(c1, c2)) return -1
            if (componentsLT(c2, c1)) return 1
        }
        return 0
    }

    @TruffleBoundary
    fun toJson(v0: Any?, out: StringBuilder) {
        when (val v = force(v0)) {
            is Long -> out.append(v); is Double -> out.append(formatG(v)); is Boolean -> out.append(v); NixNull -> out.append("null")
            is NixString -> json(v.s, out)
            is NixPath -> throw Unsupported("toJSON of a path (copied to the store)")
            is NixList -> { out.append('['); v.items.forEachIndexed { i, x -> if (i > 0) out.append(','); toJson(x, out) }; out.append(']') }
            is NixAttrs -> {
                v["__toString"]?.let { json(coerceToString(v, false), out); return }
                v["outPath"]?.let { toJson(it, out); return }
                out.append('{')
                var first = true
                for ((k, x) in v.map) { if (!first) out.append(','); first = false; json(k, out); out.append(':'); toJson(x, out) }
                out.append('}')
            }
            else -> throw NixError("cannot convert ${showType(v)} to JSON")
        }
    }
    private fun json(s: String, out: StringBuilder) {
        out.append('"')
        for (c in s) when {
            c == '"' -> out.append("\\\""); c == '\\' -> out.append("\\\\"); c == '\n' -> out.append("\\n"); c == '\r' -> out.append("\\r")
            c == '\t' -> out.append("\\t"); c == '\b' -> out.append("\\b"); c == '\u000c' -> out.append("\\f")
            c < ' ' -> out.append(String.format("\\u%04x", c.code))
            else -> out.append(c)
        }
        out.append('"')
    }
    private fun fromPlain(v: Any?): Any = when (v) {
        null -> NixNull
        is Map<*, *> -> NixAttrs(TreeMap<String, Any?>().apply { for ((k, x) in v) put(k as String, fromPlain(x)) })
        is List<*> -> NixList(Array(v.size) { fromPlain(v[it]) })
        is Int -> v.toLong(); is Long -> v; is Double -> v; is Float -> v.toDouble(); is Boolean -> v; is String -> NixString(v)
        else -> NixString(v.toString())
    }

    /// POSIX ERE as java.util.regex reads it: the bracket classes `[[:alpha:]]` and the like.
    private val regexCache = HashMap<String, Pattern>()
    private fun regex(re: String): Pattern = regexCache.getOrPut(re) {
        var r = re
        for ((k, v) in listOf("alpha" to "\\p{Alpha}", "digit" to "\\d", "alnum" to "\\p{Alnum}", "space" to "\\s", "upper" to "\\p{Upper}",
                "lower" to "\\p{Lower}", "punct" to "\\p{Punct}", "xdigit" to "\\p{XDigit}", "blank" to "[ \\t]", "cntrl" to "\\p{Cntrl}",
                "print" to "\\p{Print}", "graph" to "\\p{Graph}")) r = r.replace("[:$k:]", v)
        // POSIX '.' matches a newline
        try { Pattern.compile(r, Pattern.DOTALL) } catch (e: Exception) { throw NixError("invalid regular expression '$re'") }
    }

    private fun readDirType(p: Path): String = when {
        Files.isSymbolicLink(p) -> "symlink"
        Files.isDirectory(p, LinkOption.NOFOLLOW_LINKS) -> "directory"
        Files.isRegularFile(p, LinkOption.NOFOLLOW_LINKS) -> "regular"
        else -> "unknown"
    }

    private fun pathOf(v: Any?): String = when (val x = force(v)) {
        is NixPath -> x.p; is NixString -> x.s
        else -> coerceToString(x, false)
    }

    init {
        extraGlobals["true"] = true; extraGlobals["false"] = false; extraGlobals["null"] = NixNull
        extraGlobals["currentSystem"] = NixString("aarch64-darwin"); extraGlobals["langVersion"] = 6L
        extraGlobals["nixVersion"] = NixString("2.24.0"); extraGlobals["storeDir"] = NixString("/nix/store")
        extraGlobals["nixPath"] = NixList(arrayOf())

        // numbers
        def("__add", 2) { arith('+', it[0], it[1]) }
        def("__sub", 2) { arith('-', it[0], it[1]) }
        def("__mul", 2) { arith('*', it[0], it[1]) }
        def("__div", 2) { arith('/', it[0], it[1]) }
        def("__lessThan", 2) { lessThan(it[0], it[1]) }
        def("__bitAnd", 2) { forceInt(it[0]) and forceInt(it[1]) }
        def("__bitOr", 2) { forceInt(it[0]) or forceInt(it[1]) }
        def("__bitXor", 2) { forceInt(it[0]) xor forceInt(it[1]) }
        def("__floor", 1) { when (val x = num(it[0])) { is Long -> x; else -> Math.floor(x as Double).toLong() } }
        def("__ceil", 1) { when (val x = num(it[0])) { is Long -> x; else -> Math.ceil(x as Double).toLong() } }

        // types
        def("__typeOf", 1) { str(typeOf(force(it[0]))) }
        def("__isInt", 1) { force(it[0]) is Long }
        def("__isFloat", 1) { force(it[0]) is Double }
        def("__isBool", 1) { force(it[0]) is Boolean }
        def("__isString", 1) { force(it[0]) is NixString }
        def("__isPath", 1) { force(it[0]) is NixPath }
        def("__isList", 1) { force(it[0]) is NixList }
        def("__isAttrs", 1) { force(it[0]) is NixAttrs }
        def("__isFunction", 1) { isFunction(force(it[0])) }
        def("isNull", 1) { force(it[0]) === NixNull }

        // control
        def("throw", 1) { throw ThrowError(coerceToString(it[0], false)) }
        def("abort", 1) { throw AbortError("evaluation aborted with the following error message: '${coerceToString(it[0], false)}'") }
        def("__seq", 2) { force(it[0]); force(it[1]) }
        def("__deepSeq", 2) { deep(it[0]); force(it[1]) }
        def("__trace", 2) {
            val b = StringBuilder(); val v = force(it[0])
            if (v is NixString) b.append(v.s) else printValue(v, b, java.util.IdentityHashMap())
            System.err.println("trace: $b"); force(it[1])
        }
        def("__tryEval", 1) {
            try { attrs("success" to true, "value" to force(it[0])) }
            catch (e: ThrowError) { attrs("success" to false, "value" to false) }
            catch (e: AssertError) { attrs("success" to false, "value" to false) }
        }
        def("break", 1) { force(it[0]) }
        def("__functionArgs", 1) {
            when (val f = force(it[0])) {
                is Closure -> NixAttrs(TreeMap<String, Any?>().apply { f.formals?.forEachIndexed { i, n -> put(n, f.defaults!![i]) } })
                is Prim, is PrimApp -> NixAttrs.EMPTY
                else -> throw NixError("'functionArgs' requires a function")
            }
        }

        // attribute sets
        def("__attrNames", 1) { list(forceAttrs(it[0]).map.keys.map(::str)) }
        def("__attrValues", 1) { list(forceAttrs(it[0]).map.values.toList()) }
        def("__getAttr", 2) { val n = forceStr(it[0]); force(forceAttrs(it[1])[n] ?: throw NixError("attribute '$n' missing")) }
        def("__hasAttr", 2) { forceAttrs(it[1])[forceStr(it[0])] != null }
        def("removeAttrs", 2) {
            val m = TreeMap(forceAttrs(it[0]).map)
            for (n in forceList(it[1]).items) m.remove(forceStr(n))
            NixAttrs(m)
        }
        def("__intersectAttrs", 2) {
            val a = forceAttrs(it[0]); val b = forceAttrs(it[1])
            NixAttrs(TreeMap<String, Any?>().apply { for ((k, v) in b.map) if (a.map.containsKey(k)) put(k, v) })
        }
        def("__listToAttrs", 1) {
            val m = TreeMap<String, Any?>()
            for (e in forceList(it[0]).items) {
                val s = forceAttrs(e)
                val n = forceStr(s["name"] ?: throw NixError("attribute 'name' missing"))
                if (!m.containsKey(n)) m[n] = s["value"] ?: throw NixError("attribute 'value' missing")
            }
            NixAttrs(m)
        }
        def("__catAttrs", 2) { val n = forceStr(it[0]); list(forceList(it[1]).items.mapNotNull { e -> forceAttrs(e)[n] }) }
        def("__mapAttrs", 2) { val f = it[0]; NixAttrs(TreeMap<String, Any?>().apply { for ((k, v) in forceAttrs(it[1]).map) put(k, lazyCall(f, str(k), v)) }) }
        def("__zipAttrsWith", 2) {
            val f = it[0]
            val acc = TreeMap<String, ArrayList<Any?>>()
            for (s in forceList(it[1]).items) for ((k, v) in forceAttrs(s).map) acc.getOrPut(k) { ArrayList() }.add(v)
            NixAttrs(TreeMap<String, Any?>().apply { for ((k, vs) in acc) put(k, lazyCall(f, str(k), list(vs))) })
        }
        def("__unsafeGetAttrPos", 2) { NixNull } // the export drops source positions

        // lists
        def("__length", 1) { forceList(it[0]).size.toLong() }
        def("__head", 1) { val l = forceList(it[0]); if (l.size == 0) throw NixError("'builtins.head' called on an empty list"); force(l.items[0]) }
        def("__tail", 1) { val l = forceList(it[0]); if (l.size == 0) throw NixError("'builtins.tail' called on an empty list"); NixList(l.items.copyOfRange(1, l.size)) }
        def("__elemAt", 2) {
            val l = forceList(it[0]); val i = forceInt(it[1])
            if (i < 0 || i >= l.size) throw NixError("'builtins.elemAt' called with index $i on a list of size ${l.size}")
            force(l.items[i.toInt()])
        }
        def("__elem", 2) { val x = it[0]; forceList(it[1]).items.any { e -> eqValues(x, e) } }
        def("map", 2) { val f = it[0]; val l = forceList(it[1]); NixList(Array(l.size) { i -> lazyCall(f, l.items[i]) }) }
        def("__filter", 2) { val f = it[0]; list(forceList(it[1]).items.filter { e -> forceBool(Apply.call(f, arrayOf(e))) }) }
        def("__all", 2) { val f = it[0]; forceList(it[1]).items.all { e -> forceBool(Apply.call(f, arrayOf(e))) } }
        def("__any", 2) { val f = it[0]; forceList(it[1]).items.any { e -> forceBool(Apply.call(f, arrayOf(e))) } }
        def("__concatLists", 1) { list(forceList(it[0]).items.flatMap { l -> forceList(l).items.asList() }) }
        def("__concatMap", 2) { val f = it[0]; list(forceList(it[1]).items.flatMap { e -> forceList(Apply.call(f, arrayOf(e))).items.asList() }) }
        def("__genList", 2) {
            val f = it[0]; val n = forceInt(it[1])
            if (n < 0) throw NixError("cannot create list of size $n")
            NixList(Array(n.toInt()) { i -> lazyCall(f, i.toLong()) })
        }
        def("__foldl'", 3) {
            // the initial accumulator is not forced; each application's result is
            val f = it[0]; var acc: Any? = it[1]
            for (e in forceList(it[2]).items) acc = Apply.call(f, arrayOf(acc, e))
            force(acc)
        }
        def("__sort", 2) {
            val f = it[0]
            list(forceList(it[1]).items.sortedWith { a, b ->
                if (forceBool(Apply.call(f, arrayOf(a, b)))) -1 else if (forceBool(Apply.call(f, arrayOf(b, a)))) 1 else 0
            })
        }
        def("__partition", 2) {
            val f = it[0]; val r = ArrayList<Any?>(); val w = ArrayList<Any?>()
            for (e in forceList(it[1]).items) if (forceBool(Apply.call(f, arrayOf(e)))) r.add(e) else w.add(e)
            attrs("right" to list(r), "wrong" to list(w))
        }
        def("__groupBy", 2) {
            val f = it[0]; val acc = TreeMap<String, ArrayList<Any?>>()
            for (e in forceList(it[1]).items) acc.getOrPut(forceStr(Apply.call(f, arrayOf(e)))) { ArrayList() }.add(e)
            NixAttrs(TreeMap<String, Any?>().apply { for ((k, v) in acc) put(k, list(v)) })
        }
        def("__genericClosure", 1) {
            val args = forceAttrs(it[0])
            val op = args["operator"] ?: throw NixError("attribute 'operator' missing")
            val work = ArrayDeque(forceList(args["startSet"] ?: throw NixError("attribute 'startSet' missing")).items.asList())
            val keys = ArrayList<Any>(); val out = ArrayList<Any?>()
            while (work.isNotEmpty()) {
                val e = work.removeFirst()
                val key = force(forceAttrs(e)["key"] ?: throw NixError("attribute 'key' required"))
                if (keys.any { k -> eqValues(k, key) }) continue
                keys.add(key); out.add(e)
                work.addAll(forceList(Apply.call(op, arrayOf(e))).items.asList())
            }
            list(out)
        }

        // strings
        def("toString", 1) { str(coerceToString(it[0], true)) }
        def("__stringLength", 1) { coerceToString(it[0], false).length.toLong() }
        def("__substring", 3) {
            val st = forceInt(it[0]); val len = forceInt(it[1]); val s = coerceToString(it[2], false)
            if (st < 0) throw NixError("negative start position in 'substring'")
            if (st >= s.length) str("") else str(s.substring(st.toInt(), if (len < 0 || st + len > s.length) s.length else (st + len).toInt()))
        }
        def("__concatStringsSep", 2) { val sep = forceStr(it[0]); str(forceList(it[1]).items.joinToString(sep) { e -> coerceToString(e, false) }) }
        def("__replaceStrings", 3) {
            val from = forceList(it[0]).items.map(::forceStr); val to = forceList(it[1]).items
            if (from.size != to.size) throw NixError("'from' and 'to' arguments passed to builtins.replaceStrings have different lengths")
            val s = coerceToString(it[2], false); val b = StringBuilder(); var p = 0
            while (p <= s.length) {
                var found = false
                for ((i, f) in from.withIndex()) if (s.startsWith(f, p)) {
                    found = true; b.append(forceStr(to[i]))
                    if (f.isEmpty()) { if (p < s.length) b.append(s[p]); p++ } else p += f.length
                    break
                }
                if (!found) { if (p < s.length) b.append(s[p]); p++ }
            }
            str(b.toString())
        }
        def("__match", 2) {
            val m = regex(forceStr(it[0])).matcher(coerceToString(it[1], false))
            if (!m.matches()) NixNull else list((1..m.groupCount()).map { g -> m.group(g)?.let(::str) ?: NixNull })
        }
        def("__split", 2) {
            val m = regex(forceStr(it[0])).matcher(coerceToString(it[1], false))
            val s = coerceToString(it[1], false); val out = ArrayList<Any?>(); var last = 0
            // equal pieces are one NixString (a string has no identity): kif.nix's 1.43 M tokens of sumo.full are 143 k texts
            val memo = HashMap<String, NixString>()
            fun piece(x: String): NixString = memo.getOrPut(x) { NixString(x) }
            while (m.find()) {
                out.add(piece(s.substring(last, m.start())))
                out.add(list((1..m.groupCount()).map { g -> m.group(g)?.let(::piece) ?: NixNull }))
                last = m.end()
                if (m.end() == m.start()) { if (m.end() >= s.length) break; }
            }
            out.add(piece(s.substring(last))); list(out)
        }
        def("__compareVersions", 2) { compareVersions(forceStr(it[0]), forceStr(it[1])).toLong() }
        def("__splitVersion", 1) { list(components(forceStr(it[0])).map(::str)) }
        def("__parseDrvName", 1) {
            val s = forceStr(it[0])
            var i = 0
            while (i < s.length && !(s[i] == '-' && i + 1 < s.length && !s[i + 1].isLetter())) i++
            if (i < s.length) attrs("name" to str(s.substring(0, i)), "version" to str(s.substring(i + 1)))
            else attrs("name" to str(s), "version" to str(""))
        }
        def("__unsafeDiscardStringContext", 1) { str(coerceToString(it[0], false)) }
        def("__unsafeDiscardOutputDependency", 1) { str(coerceToString(it[0], false)) }
        def("__addDrvOutputDependencies", 1) { str(coerceToString(it[0], false)) }
        def("__getContext", 1) { coerceToString(it[0], false); NixAttrs.EMPTY }
        def("__hasContext", 1) { coerceToString(it[0], false); false }
        def("__appendContext", 2) { str(coerceToString(it[0], false)) }
        def("__hashString", 2) {
            val algo = when (val a = forceStr(it[0])) { "md5" -> "MD5"; "sha1" -> "SHA-1"; "sha256" -> "SHA-256"; "sha512" -> "SHA-512"; else -> throw NixError("unknown hash algorithm '$a'") }
            str(MessageDigest.getInstance(algo).digest(forceStr(it[1]).toByteArray()).joinToString("") { b -> "%02x".format(b) })
        }
        def("__hashFile", 2) {
            val algo = when (val a = forceStr(it[0])) { "md5" -> "MD5"; "sha1" -> "SHA-1"; "sha256" -> "SHA-256"; "sha512" -> "SHA-512"; else -> throw NixError("unknown hash algorithm '$a'") }
            str(MessageDigest.getInstance(algo).digest(File(pathOf(it[1])).readBytes()).joinToString("") { b -> "%02x".format(b) })
        }
        def("__toJSON", 1) { val b = StringBuilder(); toJson(it[0], b); str(b.toString()) }
        def("__fromJSON", 1) { fromPlain(Graph.parse(forceStr(it[0]).toByteArray())) }

        // paths and files
        def("baseNameOf", 1) {
            val v = force(it[0]); val s = coerceToString(v, true).let { s -> if (s.endsWith('/')) s.dropLast(1) else s } // one slash
            pathOrString(NixString(""), s.substring(s.lastIndexOf('/') + 1), false)
        }
        def("dirOf", 1) {
            val v = force(it[0]); val s = if (v is NixPath) v.p else coerceToString(v, false)
            val i = s.lastIndexOf('/')
            val d = if (i < 0) "." else if (i == 0) "/" else s.substring(0, i)
            pathOrString(v, d, true)
        }
        def("__toPath", 1) { str(canonPath(coerceToString(it[0], false))) }
        def("__pathExists", 1) { File(pathOf(it[0])).exists() }
        def("__readFile", 1) { str(File(pathOf(it[0])).readText()) }
        def("__readFileType", 1) { str(readDirType(Path.of(pathOf(it[0])))) }
        def("__readDir", 1) {
            val d = Path.of(pathOf(it[0]))
            NixAttrs(TreeMap<String, Any?>().apply { Files.list(d).use { s -> s.forEach { p -> put(p.fileName.toString(), str(readDirType(p))) } } })
        }
        def("__getEnv", 1) { str(System.getenv(forceStr(it[0])) ?: "") }
        def("import", 1) { loader.import(pathOf(it[0])) }
    }
}

/// Files to modules: `mlnix emit-mlir F | mlnix-opt --nix-defer --son-export`, then the module's expression, once per file.
class Loader(private val bin: String) {
    private val modules = HashMap<String, Module>()
    private val results = HashMap<String, Any>()

    fun reset() = results.clear()

    @TruffleBoundary
    fun module(file: String): Module = modules.getOrPut(file) {
        val p = ProcessBuilder("sh", "-c", "'$bin/mlnix' emit-mlir \"$1\" | '$bin/mlnix-opt' --nix-defer --son-export -o /dev/null", "sh", file)
            .redirectError(ProcessBuilder.Redirect.PIPE).start()
        val out = p.inputStream.readAllBytes(); val err = p.errorStream.readAllBytes()
        if (p.waitFor() != 0 || out.isEmpty()) throw NixError("export of $file failed: ${String(err).trim()}")
        Module(Graph.module(out), this)
    }

    @TruffleBoundary
    fun import(path0: String): Any {
        var path = canonPath(path0)
        if (File(path).isDirectory) path = "$path/default.nix"
        results[path]?.let { return it }
        val v = force(module(path).exprTarget.call())
        results[path] = v
        return v
    }
}
