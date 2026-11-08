package borg.trikeshed.nixtruffle

import com.oracle.truffle.api.Truffle
import java.io.File

// nix-truffle: evaluate Nix files from mlnix's son-form export and print them as `nix-instantiate --eval --strict` does.
//   nix-truffle --bin DIR --out OUTDIR F.nix...   each result to OUTDIR/<name>.out (or the error to .err)
//   nix-truffle --bin DIR --bench N F.nix          N evaluations in one JVM, the time of each (Graal compiles hot bodies)
//   nix-truffle --bin DIR --kif [--ontology F]... F.kif...   the closure of the theory, as mlnix-kif --chase --dump prints it
fun main(args: Array<String>) {
    var bin = "build/bin"; var out: String? = null; var bench = 0
    val files = ArrayList<String>()
    var i = 0
    while (i < args.size) {
        when (args[i]) {
            "--bin" -> bin = args[++i]
            "--out" -> out = args[++i]
            "--bench" -> bench = args[++i].toInt()
            else -> files.add(args[i])
        }
        i++
    }
    if (args.contains("--kif")) { // the Graal arm of kif-chase (Kif.kt)
        val i = args.indexOf("--bin")
        KifEngine.main(File(if (i >= 0) args[i + 1] else "build/bin").absolutePath,
            args.filterIndexed { j, s -> s != "--kif" && j != i && j != i + 1 })
        return
    }
    System.err.println("truffle runtime: ${Truffle.getRuntime().name}")
    val loader = Loader(File(bin).absolutePath)
    Prims.loader = loader
    if (bench > 0) {
        val f = File(files[0]).absolutePath
        for (n in 1..bench) {
            loader.reset()
            val t0 = System.nanoTime()
            val b = StringBuilder()
            printValue(loader.import(f), b, java.util.IdentityHashMap())
            val ms = (System.nanoTime() - t0) / 1e6
            System.err.println("run $n: %.1f ms (%d chars)".format(ms, b.length))
            if (n == bench) println(b)
        }
        return
    }
    for (f in files) {
        val name = File(f).name.removeSuffix(".nix")
        loader.reset()
        val text = try {
            val b = StringBuilder()
            printValue(loader.import(File(f).absolutePath), b, java.util.IdentityHashMap())
            b.append('\n').toString() to true
        } catch (e: NixError) {
            "error: ${e.message}\n" to false
        } catch (e: StackOverflowError) {
            "error: stack overflow\n" to false
        } catch (e: Exception) {
            "error: internal: $e\n" to false
        }
        if (out == null) print(text.first) else File(out, "$name.${if (text.second) "out" else "err"}").writeText(text.first)
    }
}
