// Kotlin's ordered choice (kursive.or without `longest`) is a combinator, but the Step program has no form for it yet:
// kursive-to-program refuses it rather than run it as POSIX alternation.
// RUN: mlnix-opt %s --kursive-to-program --verify-diagnostics

kursive.regex @peg groups 0 {
  %a = kursive.set [0, 8589934592, 0, 0]
  %b = kursive.lit "ab"
  // expected-error @+1 {{kursive-to-program: an ordered choice (kursive.or without `longest`) has no Step form}}
  %c = kursive.or %a, %b
  kursive.yield %c
}
