package borg.trikeshed.nixtruffle

import java.io.File

// The LLVM arm, first cut (docs/PRELOAD-DIALECTS.md step 3): a file's son-form module, as son-export writes it, written as
// an MLIR module in TrikeShed's ops, then lowered by `mlnix-opt --trikeshed-lower-cursors` and the stock MLIR pipeline to a
// native program that prints the value (scripts/nix-native.sh).  No C++ is added for it: this is Kotlin over the export the
// Graal arm reads, and the lowering is the one mlnixci's server is built with.
//
//   a list           genList's oracle, `trikeshed.series n { i -> f i }` (Series.kt's `n j { i -> ... }`)
//   foldl'           `trikeshed.fold` (Series.kt's fold), the step applied in its region
//   length, elemAt   `trikeshed.size`, `trikeshed.at`
//   an int, a bool   PRELOAD's plain elements, i64 and i1 (arith), each operation checked as Nix checks it
//   a lambda         nothing at run time: a closure is its row and its captures, known here, and an application is the
//                    body written in place; a body that calls itself is a func.func, and its calls func.call
//   if, &&, ||, ->   scf.if
//
// Laziness: a value is written where it is first needed, once per region, so what Nix never forces is never computed.
// Where a value is computed sooner, son says it may be: an argument computed before a call (son.body's arg_forced), a
// captured value passed to a body's function (forced_captures), a fold's first accumulator (the step forces it, itself or
// through the closure it returns).  A list's elements are computed when the list is made (a series lowers to a buffer),
// in order: so a list whose function may fail is refused wherever Nix might force fewer of them, or force them later
// (length, elemAt, foldl'), and kept only where it is the value printed, which forces each in order as `--strict` does.
// Whatever else it meets is refused, with what it met.
class NativeRefused(msg: String) : Exception(msg)

class Native(module: List<Op>) {
    private val expr: Op = module.firstOrNull { it.name == "nix.expr" } ?: throw NativeRefused("no nix.expr")
    private val rows: Map<String, Op> =
        module.filter { it.name == "son.pool" }.flatMap { it.regions[0][0].ops }.associateBy { it.str("sym_name")!! }

    private sealed class V
    private class VInt(val ssa: String) : V()
    private class VBool(val ssa: String) : V()
    /// A series of integers; `fallible`: computing an element may fail (so may making the list).
    private class VList(val ssa: String, val fallible: Boolean) : V()
    /// A closure: its row and its captures, each a V or a Ref (not computed until a use needs it).
    private class VFn(val row: Op, val caps: List<Any>) : V()

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

    private fun refuse(what: String): Nothing = throw NativeRefused(what)

    /// The module: the runtime's few externals, the bodies that became functions, and main, which prints the value.
    fun emit(): String {
        val s = Scope(null, "    ")
        val block = expr.regions[0][0]
        val frame = Frame(defs(block), emptyMap())
        val v = value(frame, block.ops.first { it.name == "nix.return" }.ins[0], s)
        print(v, s)
        val m = StringBuilder()
        m.append("// written by nix-truffle --emit-trikeshed from ${expr.str("source_path")}\nmodule {\n")
        m.append(PRELUDE)
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

    private fun int(v: V, what: String): String = (v as? VInt)?.ssa ?: refuse("$what is ${kind(v)}, not an integer")
    private fun bool(v: V, what: String): String = (v as? VBool)?.ssa ?: refuse("$what is ${kind(v)}, not a Boolean")
    private fun list(v: V, what: String): String {
        val l = v as? VList ?: refuse("$what is ${kind(v)}, not a list")
        if (l.fallible) refuse("$what has elements that may fail, and a list's elements are computed when the list is made")
        return l.ssa
    }
    private fun kind(v: V) = when (v) { is VInt -> "an integer"; is VBool -> "a Boolean"; is VList -> "a list"; is VFn -> "a function" }

    private fun const(s: Scope, x: Long): String { val r = ssa(); s.line("$r = arith.constant $x : i64"); return r }

    private fun emitOp(op: Op, frame: Frame, s: Scope): V {
        fun arg(k: Int) = value(frame, op.ins[k], s)
        op.str("prim_key")?.let { key -> return prim(key, op, frame, s) }
        return when (op.name) {
            "nix.int" -> VInt(const(s, (op.attrs["value"] as Number).toLong()))
            "nix.bool" -> bconst(s, op.attrs["value"] == true)
            "nix.builtin" -> when (op.str("name")) {
                "true" -> bconst(s, true); "false" -> bconst(s, false)
                else -> refuse("builtins.${op.str("name")} as a value")
            }
            "nix.concat_strings" -> {
                var acc = int(arg(0), "the first operand of +")
                for (k in 1 until op.ins.size) acc = checked("add", acc, int(arg(k), "an operand of +"), s)
                VInt(acc)
            }
            "nix.if" -> branch(bool(arg(0), "an if's condition"), op.ins[1], op.ins[2], frame, s)
            "nix.not" -> { val t = bconst(s, true).ssa; val r = ssa(); s.line("$r = arith.xori ${bool(arg(0), "!'s operand")}, $t : i1"); VBool(r) }
            "nix.and" -> logic(op, frame, s, 0)
            "nix.or" -> logic(op, frame, s, 1)
            "nix.impl" -> logic(op, frame, s, 2)
            "nix.eq", "nix.neq" -> {
                val a = arg(0); val b = arg(1)
                val pred = if (op.name == "nix.eq") "eq" else "ne"
                val r = ssa()
                when {
                    a is VInt && b is VInt -> s.line("$r = arith.cmpi $pred, ${a.ssa}, ${b.ssa} : i64")
                    a is VBool && b is VBool -> s.line("$r = arith.cmpi $pred, ${a.ssa}, ${b.ssa} : i1")
                    else -> refuse("== of ${kind(a)} and ${kind(b)}")
                }
                VBool(r)
            }
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

    private fun bconst(s: Scope, b: Boolean): VBool { val r = ssa(); s.line("$r = arith.constant $b"); return VBool(r) }

    /// `if`: each branch written in its own region, so only the taken one runs.
    private fun branch(c: String, t: Int, e: Int, frame: Frame, s: Scope): V {
        val st = s.child(); val se = s.child()
        val vt = value(frame, t, st); val ve = value(frame, e, se)
        return join(c, vt, st, ve, se, s)
    }

    private fun join(c: String, vt: V, st: Scope, ve: V, se: Scope, s: Scope): V {
        val (ty, a, b) = when {
            vt is VInt && ve is VInt -> Triple("i64", vt.ssa, ve.ssa)
            vt is VBool && ve is VBool -> Triple("i1", vt.ssa, ve.ssa)
            else -> refuse("an if whose branches are ${kind(vt)} and ${kind(ve)}")
        }
        if (st.fallible || se.fallible) s.fallible = true
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
        val a = bool(value(frame, op.ins[0], s), "a Boolean operator's first operand")
        val sb = s.child(); val sk = s.child()
        val vb = VBool(bool(value(frame, op.ins[1], sb), "a Boolean operator's second operand"))
        val vk = bconst(sk, which != 0) // && with a false: false; || with a true: true; -> with a false: true
        return if (which == 1) join(a, vk, sk, vb, sb, s) else join(a, vb, sb, vk, sk, s)
    }

    // ── arithmetic, checked as Nix checks it ───────────────────────────────────────────────────────────────────────

    private fun checked(what: String, a: String, b: String, s: Scope): String {
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
            "mul" -> {
                val hi = ssa(); val sh = ssa(); val c63 = const(s, 63)
                s.line("$r, $hi = arith.mulsi_extended $a, $b : i64")
                s.line("$sh = arith.shrsi $r, $c63 : i64")
                s.line("$bad = arith.cmpi ne, $hi, $sh : i64")
            }
            else -> refuse("arithmetic $what")
        }
        fail(bad, "nn_e_$what", a, b, s)
        return r
    }

    /// When `bad`: the error, as mlnix words it, and the program ends.
    private fun fail(bad: String, msg: String, a: String, b: String, s: Scope) {
        val p = ssa()
        s.line("scf.if $bad {")
        s.line("  $p = llvm.mlir.addressof @$msg : !llvm.ptr")
        s.line("  func.call @nn_fail($p, $a, $b) : (!llvm.ptr, i64, i64) -> ()")
        s.line("}")
        s.fallible = true
    }

    // ── builtins ───────────────────────────────────────────────────────────────────────────────────────────────────

    private fun prim(key: String, op: Op, frame: Frame, s: Scope): V {
        fun arg(k: Int) = value(frame, op.ins[k], s)
        return when (key) {
            "__add" -> VInt(checked("add", int(arg(0), "add's first operand"), int(arg(1), "add's second operand"), s))
            "__sub" -> VInt(checked("sub", int(arg(0), "sub's first operand"), int(arg(1), "sub's second operand"), s))
            "__mul" -> VInt(checked("mul", int(arg(0), "mul's first operand"), int(arg(1), "mul's second operand"), s))
            "__lessThan" -> {
                val a = int(arg(0), "lessThan's first operand"); val b = int(arg(1), "lessThan's second operand")
                val r = ssa(); s.line("$r = arith.cmpi slt, $a, $b : i64"); VBool(r)
            }
            "__genList" -> genList(arg(0), int(arg(1), "genList's length"), s)
            "__foldl'" -> foldl(arg(0), Ref(op.ins[1], frame), list(arg(2), "foldl''s list"), s)
            "__length" -> {
                val l = list(arg(0), "length's operand")
                val i = ssa(); val r = ssa()
                s.line("$i = trikeshed.size $l : !trikeshed.series<i64>")
                s.line("$r = arith.index_cast $i : index to i64")
                VInt(r)
            }
            "__elemAt" -> {
                val l = list(arg(0), "elemAt's list"); val k = int(arg(1), "elemAt's index")
                val i = ssa(); val n64 = ssa(); val z = const(s, 0)
                s.line("$i = trikeshed.size $l : !trikeshed.series<i64>")
                s.line("$n64 = arith.index_cast $i : index to i64")
                val lo = ssa(); val hi = ssa(); val bad = ssa()
                s.line("$lo = arith.cmpi slt, $k, $z : i64"); s.line("$hi = arith.cmpi sge, $k, $n64 : i64"); s.line("$bad = arith.ori $lo, $hi : i1")
                fail(bad, "nn_e_index", k, k, s)
                val at = ssa(); val r = ssa()
                s.line("$at = arith.index_cast $k : i64 to index")
                s.line("$r = trikeshed.at $l[$at] : !trikeshed.series<i64>, index -> i64")
                VInt(r)
            }
            else -> refuse("builtins.${key.removePrefix("__")}")
        }
    }

    /// genList f n: the series whose element i is f i, made at once, element by element in order.
    private fun genList(f: V, len: String, s: Scope): V {
        val z = const(s, 0); val neg = ssa()
        s.line("$neg = arith.cmpi slt, $len, $z : i64")
        fail(neg, "nn_e_size", len, len, s)
        val idx = ssa(); val r = ssa()
        s.line("$idx = arith.index_cast $len : i64 to index")
        val body = s.child()
        val i = ssa(); val i64 = ssa()
        body.line("$i64 = arith.index_cast $i : index to i64")
        val e = int(applyOne(f, VInt(i64), body), "genList's element")
        if (body.fallible) s.fallible = true
        s.line("$r = trikeshed.series $idx : !trikeshed.series<i64> {")
        s.line("^bb0($i: index):")
        s.out.append(body.out)
        s.line("  trikeshed.yield $e : i64")
        s.line("}")
        return VList(r, body.fallible)
    }

    /// foldl' op nul list: `trikeshed.fold`.  nul is computed before the fold, which son must allow: op forces its first
    /// argument (arg_forced), or the closure op returns forces it (forced_captures).
    private fun foldl(f: V, nul: Ref, l: String, s: Scope): V {
        val fn = f as? VFn ?: refuse("foldl' of ${kind(f)}")
        if (!forcesFirst(fn.row)) refuse("foldl' whose function does not force the accumulator (son)")
        val z = int(force(nul, s), "foldl''s first accumulator")
        val body = s.child()
        val acc = ssa(); val x = ssa()
        val r = int(applyOne(applyOne(fn, VInt(acc), body), VInt(x), body), "foldl''s accumulator")
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
        val fn = f as? VFn ?: refuse("an application of ${kind(f)}")
        if ((fn.row.attrs["lambda"] as Map<*, *>?)?.containsKey("formals") == true) refuse("a lambda with a set pattern")
        return if (fn.row in inlining) call(fn, arg, s) else inline(fn, arg, s)
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
        val a = int(force(arg, s), "the argument of a recursive call")
        for (c in caps) if (c is VFn && c.row != row && !valueFree(c, s, HashSet())) refuse("a recursive call of $name over a closure with values")
        val vals = caps.filter { it !is VFn }.map { int(it, "a captured value of $name") }
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
            val r = int(value(Frame(defs(b), bound), b.ops.first { it.name == "nix.return" }.ins[0], fs), "what $name returns")
            funcs.append("  func.func private $f(${params.joinToString(", ")}) -> i64 {\n").append(fs.out)
            funcs.append("    return $r : i64\n  }\n")
            inlining = saved
            f
        }
        val r = ssa()
        val all = vals + a
        s.line("$r = func.call $fname(${all.joinToString(", ")}) : (${all.joinToString(", ") { "i64" }}) -> i64")
        s.fallible = true
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

    private fun print(v: V, s: Scope) {
        val one = ssa()
        s.line("$one = arith.constant 1 : i32")
        fun say(fmt: String, vararg xs: String, sc: Scope = s) {
            val p = ssa(); val r = ssa()
            sc.line("$p = llvm.mlir.addressof @$fmt : !llvm.ptr")
            val types = (listOf("i32", "!llvm.ptr") + xs.map { "i64" }).joinToString(", ")
            sc.line("$r = llvm.call @dprintf($one, $p${xs.joinToString("") { ", $it" }}) vararg(!llvm.func<i32 (i32, ptr, ...)>) : ($types) -> i32")
        }
        when (v) {
            is VInt -> say("nn_fmt_int", v.ssa)
            is VBool -> {
                val t = s.child(); val f = s.child()
                say("nn_true", sc = t); say("nn_false", sc = f)
                s.line("scf.if ${v.ssa} {"); s.out.append(t.out)
                s.line("} else {"); s.out.append(f.out)
                s.line("}")
            }
            is VList -> {
                val n = ssa(); val c0 = ssa(); val c1 = ssa(); val i = ssa()
                say("nn_open")
                s.line("$n = trikeshed.size ${v.ssa} : !trikeshed.series<i64>")
                s.line("$c0 = arith.constant 0 : index"); s.line("$c1 = arith.constant 1 : index")
                s.line("scf.for $i = $c0 to $n step $c1 {")
                val body = s.child()
                val e = ssa()
                body.line("$e = trikeshed.at ${v.ssa}[$i] : !trikeshed.series<i64>, index -> i64")
                say("nn_elem", e, sc = body)
                s.out.append(body.out)
                s.line("}")
                say("nn_close")
            }
            is VFn -> say("nn_lambda")
        }
    }

    companion object {
        private fun lit(name: String, text: String): String {
            val bytes = text.toByteArray().size + 1
            val esc = text.replace("\n", "\\0A")
            return "  llvm.mlir.global internal constant @$name(\"$esc\\00\") : !llvm.array<$bytes x i8>\n"
        }

        private val PRELUDE = buildString {
            append("  llvm.func @dprintf(i32, !llvm.ptr, ...) -> i32\n")
            append("  llvm.func @exit(i32)\n")
            append(lit("nn_fmt_int", "%ld\n")); append(lit("nn_true", "true\n")); append(lit("nn_false", "false\n"))
            append(lit("nn_open", "[ ")); append(lit("nn_elem", "%ld ")); append(lit("nn_close", "]\n"))
            append(lit("nn_lambda", "<LAMBDA>\n"))
            append(lit("nn_e_add", "error: integer overflow in adding %ld + %ld\n"))
            append(lit("nn_e_sub", "error: integer overflow in subtracting %ld - %ld\n"))
            append(lit("nn_e_mul", "error: integer overflow in multiplying %ld * %ld\n"))
            append(lit("nn_e_size", "error: cannot create list of size %ld\n"))
            append(lit("nn_e_index", "error: list index %ld is out of bounds\n"))
            append("""  func.func private @nn_fail(%fmt: !llvm.ptr, %a: i64, %b: i64) {
    %two = arith.constant 2 : i32
    %x = llvm.call @dprintf(%two, %fmt, %a, %b) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i64, i64) -> i32
    %one = arith.constant 1 : i32
    llvm.call @exit(%one) : (i32) -> ()
    return
  }
""")
        }

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
