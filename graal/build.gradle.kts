// The Graal arm of docs/PRELOAD-DIALECTS.md (step 3): a Truffle interpreter that runs the son-form IR mlnix exports
// (`mlnix emit-mlir F | mlnix-opt --nix-defer --son-export -o /dev/null`).  Graal compiles it; the JVM's collector frees what
// the program drops.  Built with its own Gradle wrapper (copied from TrikeShed):
//   cd graal && ./gradlew installDist
plugins {
    kotlin("jvm") version "2.4.21"
    application
}

repositories {
    mavenLocal() // borg.trikeshed:TrikeShed-jvm (Confix reads the export)
    mavenCentral()
}

val truffle = "25.4.4.1.1" // matches the Oracle GraalVM 25.4 this runs on (its compiler and the Truffle runtime must agree)

dependencies {
    implementation("org.graalvm.truffle:truffle-api:$truffle")
    runtimeOnly("org.graalvm.truffle:truffle-runtime:$truffle")
    // Confix only: the artifact's Compose UI dependencies are not needed (and not all are on Maven Central)
    implementation("borg.trikeshed:TrikeShed-jvm:0.1.0-SNAPSHOT") { isTransitive = false }
}

kotlin { jvmToolchain(25) }

application {
    mainClass.set("borg.trikeshed.nixtruffle.MainKt")
    applicationDefaultJvmArgs = listOf("--enable-native-access=ALL-UNNAMED", "--sun-misc-unsafe-memory-access=allow")
}
