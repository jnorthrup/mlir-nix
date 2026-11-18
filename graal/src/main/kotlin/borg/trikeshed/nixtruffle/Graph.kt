package borg.trikeshed.nixtruffle

import borg.trikeshed.cursor.IOMemento
import borg.trikeshed.lib.size
import borg.trikeshed.lib.get
import borg.trikeshed.parse.confix.*

// The son-form IR as mlnix-opt's son-export writes it, read with TrikeShed's Confix.  An op is
// {"op", "res", "ins", "types", "attrs", "regions"}; a region a list of blocks {"args", "ops"}; a value a number unique in the module.

class Block(@JvmField val args: IntArray, @JvmField val ops: List<Op>)
class Op(
    @JvmField val name: String, @JvmField val res: IntArray, @JvmField val ins: IntArray, @JvmField val types: List<String>,
    @JvmField val attrs: Map<String, Any?>, @JvmField val regions: List<List<Block>>,
) {
    fun str(k: String): String? = attrs[k] as String?
    @Suppress("UNCHECKED_CAST") fun list(k: String): List<Any?>? = attrs[k] as List<Any?>?
    fun segments(): IntArray? = list("operandSegmentSizes")?.map { (it as Number).toInt() }?.toIntArray()
}

object Graph {
    /// A cell as plain Kotlin: a Map for an object, a List for an array, else the scalar.
    fun plain(c: ConfixCell): Any? = when (c.row.tag) {
        IOMemento.IoObject -> {
            val kids = c.cellKids
            val m = LinkedHashMap<String, Any?>()
            var i = 0
            while (i + 1 < kids.size) { m[kids[i].reify() as String] = plain(kids[i + 1]); i += 2 }
            m
        }
        IOMemento.IoArray -> { val kids = c.cellKids; List(kids.size) { plain(kids[it]) } }
        IOMemento.IoInt -> (c.reify() as Number).toLong()
        IOMemento.IoDouble -> integer(c) ?: c.reify()
        else -> c.reify()
    }

    /// Confix tags every JSON number IoDouble, and reify reads it as a Double: an integer past 2^53 would lose its low bits
    /// (`9223372036854775800` read as Long.MAX_VALUE).  A number written as an optional minus and digits that fit 64 bits
    /// is the Long it spells (ConfixColumns.memberTag's rule; the TrikeShed jar the arm builds with predates it).
    private fun integer(c: ConfixCell): Long? {
        val src = c.b
        var i = c.row.open
        val close = c.row.close
        val negative = i <= close && src[i].toInt().toChar() == '-'
        if (negative) i++
        if (i > close) return null
        var v = 0L // accumulated negative, so Long.MIN_VALUE fits
        while (i <= close) {
            val d = src[i++].toInt().toChar() - '0'
            if (d < 0 || d > 9 || v < Long.MIN_VALUE / 10) return null
            v *= 10
            if (v < Long.MIN_VALUE + d) return null
            v -= d
        }
        return if (negative) v else if (v == Long.MIN_VALUE) null else -v
    }

    fun parse(json: ByteArray): Any? {
        val doc = confixDoc(json, Syntax.JSON)
        return plain(doc.rootCell ?: throw NixError("son-export: empty document"))
    }

    @Suppress("UNCHECKED_CAST")
    private fun ints(v: Any?): IntArray = (v as List<Any?>).map { (it as Number).toInt() }.toIntArray()

    @Suppress("UNCHECKED_CAST")
    fun op(m: Map<String, Any?>): Op = Op(
        m["op"] as String, ints(m["res"]), ints(m["ins"]), m["types"] as List<String>, m["attrs"] as Map<String, Any?>,
        (m["regions"] as List<List<Map<String, Any?>>>).map { r -> r.map { b -> Block(ints(b["args"]), (b["ops"] as List<Map<String, Any?>>).map(::op)) } },
    )

    /// A file's son-form module: `mlnix emit-mlir F | mlnix-opt --nix-defer PASSES --son-export`.
    fun export(bin: String, file: String, passes: String): List<Op> {
        val p = ProcessBuilder("sh", "-c", "'$bin/mlnix' emit-mlir \"$1\" | '$bin/mlnix-opt' --nix-defer $passes --son-export -o /dev/null", "sh", file)
            .redirectError(ProcessBuilder.Redirect.PIPE).start()
        val out = p.inputStream.readAllBytes(); val err = p.errorStream.readAllBytes()
        if (p.waitFor() != 0 || out.isEmpty()) throw NixError("export of $file failed: ${String(err).trim()}")
        return module(out)
    }

    @Suppress("UNCHECKED_CAST")
    fun module(json: ByteArray): List<Op> = ((parse(json) as Map<String, Any?>)["module"] as List<Map<String, Any?>>).map(::op)
}
