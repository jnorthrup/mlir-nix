// Makes the golden data for the Confix scanner's test (confix-golden.ll): TrikeShed's own scanners, Syntax.scan0, Syntax.scanCbor0, Syntax.scanYaml0
// and buildTree, run on texts, and what they give written as LLVM IR data for confix-check.ll.  Build it with Kotlin/Native against TrikeShed's klib:
//   kotlinc-native confix-golden.kt -l <TrikeShed klib> -l <its dependencies> -o gen
//   gen run <seed> <start> <count>    one line per case, start until start + count (a case that never comes back is left out: run in
//                                     batches, and bisect a batch that does not end)
//   gen fixed                         one line per text of the lists of edge cases below
//   gen show <seed> <index>           the text of one random case
//   gen runy <seed> <start> <count>   as run, for YAML texts;  gen fixedy [k]  as fixed, for the YAML edge cases (all, or only the k-th, since a YAML
//                                     text can make Kotlin loop for ever or overflow its stack: run them one at a time under a timeout; exit status 3 when k
//                                     is past the last);  gen showy <seed> <index>  as show
//   gen ytexts                        YAML texts given as lines "<index> <hex of the text>" on stdin: the line of each, as run gives it
//   gen emit                          the lines on stdin as LLVM IR data on stdout
// A line:  <index> <j|c|y> <hex of the text> <status> <total> <rows: open close tag depth first count>* kids <kids>*
// status: ok, b<row> (a span past the text: Syntax.indexed's require), t (read past the end), r (additional information 28 to 30), and w
// (Backward: not from Kotlin, which never answers; written by hand).
import borg.trikeshed.cursor.IOMemento
import borg.trikeshed.lib.*
import borg.trikeshed.parse.confix.*
import kotlin.random.Random

fun codeOf(t: IOMemento): Int = when (t) {
    IOMemento.IoNothing -> 0; IOMemento.IoBoolean -> 1; IOMemento.IoLong -> 2; IOMemento.IoDouble -> 3
    IOMemento.IoString -> 4; IOMemento.IoObject -> 5; IOMemento.IoArray -> 6; IOMemento.IoBytes -> 7
    else -> 99
}

fun hex(b: ByteArray): String { val sb = StringBuilder(); for (x in b) { val v = x.toInt() and 0xFF; sb.append("0123456789abcdef"[v shr 4]).append("0123456789abcdef"[v and 15]) }; return sb.toString() }
fun unhex(h: String): ByteArray = ByteArray(h.length / 2) { h.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

/** What the real scanner gives for the text, as a spec tail; null when it throws something else (the case is left out). */
fun result(syn: Char, bytes: ByteArray): String? {
    val src: Series<Byte> = bytes.size j { bytes[it] }
    return try {
        val flat = when (syn) { 'j' -> Syntax.JSON.scan0(src).b; 'y' -> Syntax.YAML.scanYaml0(src).b; else -> Syntax.CBOR.scanCbor0(src).b }
        val total = flat.spans.size
        var bad = -1
        for (k in 0 until total) { val s = flat.spans[k]; if (!(s.b < s.a || (s.a >= 0 && s.b < src.size))) { bad = k; break } }
        val sb = StringBuilder(if (bad >= 0) "b$bad" else "ok").append(' ').append(total)
        val kids = StringBuilder(" kids")
        var first = 0
        for (k in 0 until total) {
            val s = flat.spans[k]; val ch = flat.childOf(k)
            sb.append(' ').append(s.a).append(' ').append(s.b).append(' ').append(codeOf(flat.tags[k])).append(' ').append(flat.depths[k]).append(' ').append(first).append(' ').append(ch.size)
            for (c in 0 until ch.size) kids.append(' ').append(ch[c])
            first += ch.size
        }
        sb.append(kids).toString()
    } catch (e: IllegalStateException) { "r 0 kids" } catch (e: IndexOutOfBoundsException) { "t 0 kids" } catch (e: Throwable) { null }
}

// ---- the texts
val jsonFixed = listOf(
    "", " ", "{}", "[]", "[1,2]", "{\"a\":true}", "[true,false,null]", "{\"a\":[1,2,{\"b\":\"x\\ny\"}],\"c\":null}", "\"abc\"", "\"a\\\"b\"", "\"\\\\\"", "\"\\\\\\\"\"",
    "]", "}", "][", "[}", "{]", "[[", "{{", "[1", "[1,", "{\"a", "\"", "\\", "\"\\", "tru", "true", "truex", "fals", "false", "nul", "null", "nulll", "-", "+", "-+-", "--1", "1.2.3", "1e5", "1E+5", "+7", "0x10",
    "[1 2]", "[1,,2]", "{\"a\":}", "{:1}", "[\"a\" \"b\"]", "\"a\"\"b\"", "12abc", "[12abc]", "tfn", "[t,f,n]", "[true,]", "-1.5e-3", "[-0,0.0]", "\u00e9", "\"\u00e9\"", "{\"k\":\"\\u00e9\"}", "\n\t [ \n 1 \t] \r\n",
)
val cborFixed = listOf(
    "00", "01", "0a", "17", "1818", "1819", "1864", "1903e8", "1a000f4240", "1b000000e8d4a51000", "1bffffffffffffffff", "c249010000000000000000", "3bffffffffffffffff", "c349010000000000000000", "20", "29", "3863", "3903e7",
    "f90000", "f98000", "f93c00", "fb3ff199999999999a", "f97bff", "fa47c35000", "f9c400", "f4", "f5", "f6", "f7", "f0", "f818", "f8ff", "c074323031332d30332d32315432303a30343a30305a", "c11a514b67b0", "d74401020304", "d818456449455446",
    "40", "4401020304", "60", "6161", "6449455446", "62225c", "62c3bc", "63e6b0b4", "64f0908591", "80", "83010203", "8301820203820405", "98190102030405060708090a0b0c0d0e0f101112131415161718181819", "a0", "a201020304", "a26161016162820203",
    "826161a161626163", "a56161614161626142616361436164614461656145", "5f42010243030405ff", "7f657374726561646d696e67ff", "9fff", "9f018202039f0405ffff", "9f01820203820405ff", "83018202039f0405ff", "83019f0203ff820405",
    "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff", "bf61610161629f0203ffff", "826161bf61626163ff", "bf6346756ef563416d7421ff",
    "1c", "3d", "5e", "7e", "9e", "be", "de", "fc", "fd", "fe", "7f", "5f", "ff", "9f", "bf", "bf01", "bf01ff", "bf0102", "bf010203ff", "9f01", "5f4102", "5f41", "7f6161", "c0", "d8", "d9", "da", "db", "18", "19", "1901", "1a", "1a000000", "1b", "1b00000000000000",
    "5affffffff", "5a80000000", "5a7fffffff", "5b0000000000000005 6162636465".replace(" ", ""), "5b000000010000000561626364 65".replace(" ", ""), "5b00000000ffffffff", "5b0000000000000000", "6180", "62616263", "4101", "410102", "8301", "82", "a101", "a1",
    "8200", "820000", "82008200", "81818181818181818100", "c0c0c0c000", "c0c0c0c0", "d8ffd8ff00", "f800", "f8", "f9", "f900", "fa", "fa000000", "fb", "fb00000000000000", "e0", "e1", "f4f5f6f7", "0000", "00 01 02".replace(" ", ""), "9f9f9f9fffffffff", "9f9f9f9fffffff", "bfbfbfbfffffffff",
    // lengths that wrap: four bytes of 0xFFFFFFFF are -1 and so indefinite; eight bytes of it are a positive Long whose low 32 bits are -1
    "9affffffff", "9affffffff01ff", "9affffffff0102ff", "baffffffff0102ff", "9bffffffffffffffff01ff", "9b00000000ffffffff01", "bb00000000ffffffff0102", "ba40000000", "ba400000000102", "ba7fffffff0102", "9a7fffffff", "9a80000000", "9a80000000ff",
    // a string whose length sends the position below zero (a read past the end) or just past the head
    "5b00000000fffffff6", "5b00000000fffffff8", "7b00000000fffffff6", "7b00000000fffffff8", "00005b00000000fffffff3", "00005b00000000fffffff8", "5bfffffffffffffff6", "5b0000000100000000", "5b0000000100000001 61".replace(" ", ""), "5a80000001", "5a80000001 6162".replace(" ", ""),
)

fun jsonAlphabet() = "{}[],:\"\\ \n\ttfnuelsa0123456789.+-E/".toCharArray()

fun randomJson(r: Random): ByteArray {
    val len = if (r.nextInt(8) == 0) r.nextInt(120) else r.nextInt(40)
    val al = jsonAlphabet()
    val sb = ArrayList<Byte>()
    for (i in 0 until len) sb.add(if (r.nextInt(16) == 0) r.nextInt(256).toByte() else al[r.nextInt(al.size)].code.toByte())
    return sb.toByteArray()
}

fun structJson(r: Random, d: Int, out: StringBuilder) {
    fun ws() { when (r.nextInt(6)) { 0 -> out.append(' '); 1 -> out.append('\n'); 2 -> out.append("\t "); else -> {} } }
    when (if (d > 4) r.nextInt(5) else r.nextInt(8)) {
        0 -> out.append(listOf("0", "-1", "12", "3.5", "-0.25", "1e5", "2E-3", "+4", "9223372036854775807", "123456789012345678901234567890")[r.nextInt(10)])
        1 -> { out.append('"'); for (i in 0 until r.nextInt(8)) out.append(listOf("a", "b", "xyz", "\\\"", "\\\\", "\\n", "\\u0041", "\u00e9", " ", "\\/")[r.nextInt(10)]); out.append('"') }
        2 -> out.append("true")
        3 -> out.append(if (r.nextBoolean()) "false" else "null")
        4 -> out.append(listOf("tru", "nul", "fals", "truee", "nulll")[r.nextInt(5)])
        5, 6 -> { out.append('['); ws(); for (i in 0 until r.nextInt(5)) { if (i > 0) { out.append(','); ws() }; structJson(r, d + 1, out); ws() }; out.append(']') }
        else -> { out.append('{'); ws(); for (i in 0 until r.nextInt(5)) { if (i > 0) { out.append(','); ws() }; structJson(r, d + 1, out); out.append(':'); ws(); structJson(r, d + 1, out); ws() }; out.append('}') }
    }
}

fun cborHead(r: Random, major: Int, value: Long, out: ArrayList<Byte>, wide: Boolean = false) {
    val m = major shl 5
    fun b(x: Int) { out.add(x.toByte()) }
    when {
        value < 24 && !wide -> b(m or value.toInt())
        value < 256 && !wide -> { b(m or 24); b(value.toInt()) }
        value < 65536 && !wide -> { b(m or 25); b((value shr 8).toInt()); b(value.toInt()) }
        value < 4294967296L && !wide -> { b(m or 26); for (s in intArrayOf(24, 16, 8, 0)) b((value shr s).toInt()) }
        else -> { b(m or 27); for (s in 56 downTo 0 step 8) b((value shr s).toInt()) }
    }
}

fun structCbor(r: Random, d: Int, out: ArrayList<Byte>) {
    when (if (d > 4) r.nextInt(6) else r.nextInt(12)) {
        0, 1 -> cborHead(r, r.nextInt(2), listOf(0L, 1L, 23L, 24L, 255L, 256L, 65535L, 65536L, 100000L, 4294967295L, 4294967296L, 1L shl 40)[r.nextInt(12)], out)
        2 -> { val n = r.nextInt(6); cborHead(r, 2, n.toLong(), out); for (i in 0 until n) out.add(r.nextInt(256).toByte()) }
        3 -> { val n = r.nextInt(6); cborHead(r, 3, n.toLong(), out); for (i in 0 until n) out.add(('a'.code + r.nextInt(26)).toByte()) }
        4 -> { val n = r.nextInt(5); cborHead(r, 4, n.toLong(), out); for (i in 0 until n) structCbor(r, d + 1, out) }
        5 -> { val n = r.nextInt(4); cborHead(r, 5, n.toLong(), out); for (i in 0 until n) { structCbor(r, d + 1, out); structCbor(r, d + 1, out) } }
        6 -> { cborHead(r, 6, r.nextInt(30).toLong(), out); structCbor(r, d + 1, out) }
        7 -> out.add((0xE0 or listOf(20, 21, 22, 23, 0, 19)[r.nextInt(6)]).toByte())
        8 -> { out.add((0xF8).toByte()); out.add(r.nextInt(256).toByte()) }
        9 -> { out.add(listOf(0xF9, 0xFA, 0xFB)[r.nextInt(3)].toByte()); for (i in 0 until listOf(2, 4, 8)[r.nextInt(3)]) out.add(r.nextInt(256).toByte()) }
        10 -> { out.add((0x9F).toByte()); for (i in 0 until r.nextInt(4)) structCbor(r, d + 1, out); out.add((0xFF).toByte()) }
        else -> { out.add((0xBF).toByte()); for (i in 0 until r.nextInt(3)) { structCbor(r, d + 1, out); structCbor(r, d + 1, out) }; out.add((0xFF).toByte()) }
    }
}

fun mutate(r: Random, b: ByteArray): ByteArray {
    var x = b
    for (m in 0 until r.nextInt(4)) {
        if (x.isEmpty()) break
        val at = r.nextInt(x.size)
        x = when (r.nextInt(5)) {
            0 -> x.copyOf().also { it[at] = r.nextInt(256).toByte() }
            1 -> x.copyOfRange(0, at) + x.copyOfRange(minOf(x.size, at + 1 + r.nextInt(3)), x.size)
            2 -> x.copyOfRange(0, at) + byteArrayOf(r.nextInt(256).toByte()) + x.copyOfRange(at, x.size)
            3 -> x.copyOfRange(0, at)
            else -> x.copyOf().also { it[at] = (it[at].toInt() xor (1 shl r.nextInt(8))).toByte() }
        }
    }
    return x
}

fun makeCase(seed: Long, idx: Int): Pair<Char, ByteArray> {
    val r = Random(seed * 1000003L + idx)
    return when (idx % 8) {
        0 -> 'j' to randomJson(r)
        1 -> 'j' to randomJson(r)
        2 -> { val sb = StringBuilder(); structJson(r, 0, sb); 'j' to mutate(r, sb.toString().encodeToByteArray()).let { if (r.nextInt(3) == 0) sb.toString().encodeToByteArray() else it } }
        3 -> 'j' to jsonFixed[r.nextInt(jsonFixed.size)].encodeToByteArray().let { if (r.nextBoolean()) it else mutate(r, it) }
        4 -> { val n = r.nextInt(20); 'c' to ByteArray(n) { if (it == 0 || r.nextInt(3) == 0) r.nextInt(256).toByte() else listOf(0, 1, 0x7f, 0x80, 0xff, 0x18, 0x19, 0x61, 0x62)[r.nextInt(9)].toByte() } }
        5 -> { val o = ArrayList<Byte>(); structCbor(r, 0, o); 'c' to o.toByteArray() }
        6 -> { val o = ArrayList<Byte>(); structCbor(r, 0, o); 'c' to mutate(r, o.toByteArray()) }
        else -> 'c' to unhex(cborFixed[r.nextInt(cborFixed.size)]).let { if (r.nextInt(3) == 0) mutate(r, it) else it }
    }
}


// ---- YAML texts
val yamlFixed = listOf(
    "", "\n", "\n\n", "   ", "a", "a: 1", "a: 1\nb: 2", "a:\n  b: 1\n  c: 2", "- a\n- b", "- a: 1\n  b: 2\n- c: 3", "a:\n- x\n- y", "a: [1, 2, 3]", "a: {b: 1, c: [2, 3]}",
    "# c\na: 1", "a: 1\n\nb: 2", "a: 1\n\n\n\nb: 2", "- \n- x", "-\n  - a", "- - a: b", "- - - a: b", "a: \"q\"", "a: 'q'", "a: true\nb: false\nc: null\nd: ~",
    "a: 1.5\nb: -2e3\nc: 0x1p3\nd: NaN\ne: Infinity\nf: 1d\ng: +.5\nh: 5.\ni: 1_0", "x\ny\nz", "text: a\n  b\n  c", "k: v # c", "[1, 2]", "{a: 1}", "  [x]", "\n\n{}", "a: [", "a: {", "a: [,,]",
    "a: [[1,2],[3]]", "a: {b: {c: d}}", "a: {b}", "a: {b: }", ":", "a:", "a: :", "- :", "-", "--", "---\na: 1", "...", "a: 1\r\nb: 2", "a: 1\rb: 2", "\ta: 1", " a: 1\n  b: 2\n c: 3",
    "a: 1\n  b: 2", "a: 1\nb:\n  c:\n    d: 1\n  e: 2\nf: 3", "- a\n  - b", "- 'x: y'", "- \"x: y\"", "- a # b", "#", "a: #x", "a: \"b\" c", "\"a\": 1", "'a': 1", "a: \"1\"", "a: \"true\"",
    "a: 1\n# c\n\nb: 2", "a:\n\n  b: 1", "a:\n  # c\n  b: 1", "- #x: y", "- # c\n- d", "- a: 1\n\n- b: 2", "- a: 1\n\n\n- b: 2", "- - a\n  - b\n- c", "a: [x, y\nb: 1", "a: [x]]", "a: {x: [1, {y: 2}], z}",
    "k: [ a , b ]", "k: [a,b,]", "k: [ ]", "k: { }", "k: {a: 1,, b: 2}", "k: [[[[1]]]]", "k: {a: {b: {c: {d: 1}}}}", "k: [a: 1]", "k: {a: [1, 2], b: {c: 3}}",
    "a: \u00e9\nb: \"\u00e9\"", "\u00e9: 1", "a: 1 \nb: 2  ", "a:\t1", "a:  \n b: 1", "  - a\n  - b", "- a\n-b", "-a", "- a\n - b", "a: b: c", "a: 'b: c'", "a b: c d", "a: -", "a: - b", "?", "? a\n: b",
    "a: |\n  x\n  y", "a: >\n  x", "a: &x 1\nb: *x", "a: !!str 1", "%YAML 1.2\n---\na: 1", "a: 0x1p3", "a: 0x1P-2", "a: 0x.8p1", "a: 0x1.p1", "a: 0x", "a: +Infinity", "a: -NaN", "a: 1e", "a: .e1", "a: 1e+5f",
    "a: true\n  b\n  c", "a: 1\n  2", "a: 1\n 2\n3", "x:\n  y\n  z", "x:\n  y: 1\n  z", "x:\n  - a\n  b", "- x:\n    y\n  z: 1",
)

fun yamlScalar(r: Random): String = listOf("1", "-2", "3.5", "1e3", "0x1p3", "NaN", "Infinity", "true", "false", "null", "~", "abc", "hello world", "\"quoted\"", "'single'", "a:b", "x #y", "\u00e9", "yes", "0", "-", "- x", "1.", ".5", "+7", "1f", "\"a: b\"", "a, b", "[x", "x]", "k=v", "\"\"")[r.nextInt(30)]

fun yamlFlow(r: Random, d: Int, out: StringBuilder) {
    fun sp() { if (r.nextInt(4) == 0) out.append(' ') }
    when (if (d > 3) r.nextInt(3) else r.nextInt(6)) {
        0, 1 -> out.append(yamlScalar(r).filter { it != '\n' })
        2 -> out.append(listOf("", "x", "1", "a b")[r.nextInt(4)])
        3, 4 -> { out.append('['); sp(); for (i in 0 until r.nextInt(4)) { if (i > 0) { out.append(','); sp() }; yamlFlow(r, d + 1, out); sp() }; if (r.nextInt(12) != 0) out.append(']') }
        else -> { out.append('{'); sp(); for (i in 0 until r.nextInt(4)) { if (i > 0) { out.append(','); sp() }; out.append(listOf("a", "b", "k", "\"q\"", "")[r.nextInt(5)]); if (r.nextInt(8) != 0) { out.append(':'); sp(); yamlFlow(r, d + 1, out) }; sp() }; if (r.nextInt(12) != 0) out.append('}') }
    }
}

fun yamlBlock(r: Random, d: Int, indent: Int, out: StringBuilder) {
    fun pad(n: Int) { for (i in 0 until n) out.append(if (r.nextInt(40) == 0) '\t' else ' ') }
    fun filler() {
        while (r.nextInt(6) == 0) out.append(if (r.nextBoolean()) "\n" else "\n" + " ".repeat(r.nextInt(4)) + "# c")
    }
    fun value(ind: Int, inSeq: Boolean) {
        when (r.nextInt(if (d > 3) 5 else 9)) {
            0, 1, 2 -> { out.append(' '); out.append(yamlScalar(r).filter { it != '\n' }) }
            3 -> { out.append(' '); yamlFlow(r, 0, out) }
            4 -> {}
            5, 6 -> { out.append('\n'); filler(); yamlBlock(r, d + 1, ind + listOf(2, 2, 2, 1, 4, 3)[r.nextInt(6)], out) }
            7 -> { out.append(' '); out.append(yamlScalar(r).filter { it != '\n' }); for (k in 0 until 1 + r.nextInt(2)) { out.append('\n'); pad(ind + 2); out.append(yamlScalar(r).filter { it != '\n' && it != ':' }) } }
            else -> { out.append('\n'); yamlBlock(r, d + 1, ind + 2, out) }
        }
    }
    val n = 1 + r.nextInt(3)
    val seq = r.nextInt(3) == 0
    for (i in 0 until n) {
        if (i > 0) { out.append('\n'); filler() }
        pad(indent)
        if (seq) {
            out.append('-')
            when (r.nextInt(6)) {
                0 -> { out.append(" k: "); out.append(yamlScalar(r).filter { it != '\n' }); if (r.nextBoolean()) { out.append('\n'); pad(indent + 2); out.append("m: "); out.append(yamlScalar(r).filter { it != '\n' }) } }
                1 -> { out.append(" - "); out.append(yamlScalar(r).filter { it != '\n' }) }
                else -> value(indent, true)
            }
        } else {
            out.append(listOf("a", "b", "key", "k2", "\"q\"", "x y", "")[r.nextInt(7)]); out.append(':')
            value(indent, false)
        }
    }
}

fun makeYamlCase(seed: Long, idx: Int): ByteArray {
    val r = Random(seed * 7000003L + idx)
    val sb = StringBuilder()
    when (idx % 6) {
        0, 1, 2 -> { if (r.nextInt(8) == 0) sb.append("# top\n"); yamlBlock(r, 0, if (r.nextInt(8) == 0) r.nextInt(3) else 0, sb); if (r.nextInt(3) != 0) sb.append('\n'); if (r.nextInt(10) == 0) sb.append('\n') }
        3 -> { val al = "ab: -\n #[]{},\"'1.e+x0 \t\r".toCharArray(); for (i in 0 until r.nextInt(60)) sb.append(al[r.nextInt(al.size)]) }
        4 -> sb.append(yamlFixed[r.nextInt(yamlFixed.size)])
        else -> { yamlBlock(r, 0, 0, sb) }
    }
    var b = sb.toString().let { if (r.nextInt(25) == 0) it.replace("\n", "\r\n") else it }.encodeToByteArray()
    if (idx % 6 == 4 || r.nextInt(4) == 0) b = mutate(r, b)
    return b
}

fun main(args: Array<String>) {
    when (args[0]) {
        "run" -> {
            val seed = args[1].toLong(); val start = args[2].toInt(); val count = args[3].toInt()
            for (idx in start until start + count) {
                val (syn, bytes) = makeCase(seed, idx)
                val res = result(syn, bytes) ?: continue
                println("$idx $syn ${hex(bytes)} $res")
            }
        }
        "show" -> { val (syn, bytes) = makeCase(args[1].toLong(), args[2].toInt()); println("$syn ${hex(bytes)}") }
        "runy" -> {
            val seed = args[1].toLong(); val start = args[2].toInt(); val count = args[3].toInt()
            for (idx in start until start + count) {
                val bytes = makeYamlCase(seed, idx)
                val res = result('y', bytes) ?: continue
                println("$idx y ${hex(bytes)} $res")
            }
        }
        "showy" -> println("y ${hex(makeYamlCase(args[1].toLong(), args[2].toInt()))}")
        "fixedy" -> {
            if (args.size > 1) { val k = args[1].toInt(); if (k >= yamlFixed.size) kotlin.system.exitProcess(3); val b = yamlFixed[k].encodeToByteArray(); result('y', b)?.let { println("${2000000 + k} y ${hex(b)} $it") } }
            else { var idx = 2000000
            for (t in yamlFixed) { val b = t.encodeToByteArray(); result('y', b)?.let { println("${idx++} y ${hex(b)} $it") } } }
        }
        "ytexts" -> generateSequence { readlnOrNull() }.forEach { ln ->
            val p = ln.split(' '); val b = unhex(p[1]); result('y', b)?.let { println("${p[0]} y ${p[1]} $it") }
        }
        "emit" -> emit()
        "fixed" -> {
            var idx = 1000000
            for (t in jsonFixed) { val b = t.encodeToByteArray(); result('j', b)?.let { println("${idx++} j ${hex(b)} $it") } }
            for (t in cborFixed) { val b = unhex(t); result('c', b)?.let { println("${idx++} c ${hex(b)} $it") } }
        }
    }
}

fun emit() {
    val lines = generateSequence { readlnOrNull() }.filter { it.isNotEmpty() && it[0] != '#' }.toList()
    val n = lines.size
    val data = StringBuilder(); val inOff = ArrayList<Int>(); val syn = ArrayList<Int>(); val exFault = ArrayList<Int>(); val exAt = ArrayList<Int>(); val exTotal = ArrayList<Int>()
    val rows = ArrayList<Int>(); val rowsOff = ArrayList<Int>(); val kids = ArrayList<Int>(); val kidsOff = ArrayList<Int>()
    var pos = 0; var maxn = 0
    for (ln in lines) {
        val p = ln.split(' ')
        syn.add(when (p[1]) { "j" -> 0; "y" -> 2; else -> 1 })
        val bytes = unhex(p[2]); maxn = maxOf(maxn, bytes.size)
        inOff.add(pos); pos += bytes.size
        for (b in bytes) data.append('\\').append("0123456789ABCDEF"[(b.toInt() and 0xFF) shr 4]).append("0123456789ABCDEF"[b.toInt() and 15])
        val st = p[3]
        exFault.add(when { st == "ok" -> 0; st == "t" -> 1; st == "r" -> 2; st == "w" -> 4; else -> 3 })
        exAt.add(if (st.startsWith("b")) st.substring(1).toInt() else 0)
        exTotal.add(p[4].toInt())
        rowsOff.add(rows.size / 6); kidsOff.add(kids.size)
        val kpos = p.indexOf("kids")
        for (i in 5 until kpos) rows.add(p[i].toInt())
        for (i in kpos + 1 until p.size) kids.add(p[i].toInt())
    }
    inOff.add(pos); rowsOff.add(rows.size / 6); kidsOff.add(kids.size)
    fun arr(name: String, t: String, v: List<Int>) = "@$name = constant [${maxOf(v.size, 1)} x $t] [" + (if (v.isEmpty()) "$t 0" else v.joinToString(", ") { "$t $it" }) + "]\n"
    val o = StringBuilder()
    o.append("; generated by gen.kt emit: $n cases\n")
    o.append("@ncases = constant i32 $n\n@maxn = constant i32 $maxn\n")
    o.append("@in_data = constant [${maxOf(pos, 1)} x i8] c\"${if (pos == 0) "\\00" else data}\"\n")
    o.append(arr("in_off", "i32", inOff)).append(arr("in_syn", "i32", syn)).append(arr("ex_fault", "i32", exFault)).append(arr("ex_at", "i32", exAt)).append(arr("ex_total", "i32", exTotal))
    o.append(arr("rows_off", "i32", rowsOff)).append(arr("ex_rows", "i32", rows)).append(arr("kids_off", "i32", kidsOff)).append(arr("ex_kids", "i32", kids))
    print(o)
}
