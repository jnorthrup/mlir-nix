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
        else -> c.reify()
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

    @Suppress("UNCHECKED_CAST")
    fun module(json: ByteArray): List<Op> = ((parse(json) as Map<String, Any?>)["module"] as List<Map<String, Any?>>).map(::op)
}
