// The kursive combinators (include/NixDialect/Kursive.td): --re2mlir reads POSIX extended regular expressions into
// them, as Kursive.h's compiler reads them (libstdc++'s std::regex::extended, what builtins.match takes); a pattern it
// does not take is a kursive.rejected with the compiler's reason.  The round trip prints and reads every op.
// RUN: mlnix-opt %s --re2mlir | FileCheck %s
// RUN: mlnix-opt %s --re2mlir | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s --re2mlir=set-cap=3 | FileCheck %s --check-prefix=ROOM

// An alternation is POSIX alternation (`longest`); a group is a capture; `*` is repeat [0, -1].
// CHECK-LABEL: kursive.regex @alt groups 1 {
// CHECK-NEXT:    %[[A:.*]] = kursive.set [0, 8589934592, 0, 0]
// CHECK-NEXT:    %[[B:.*]] = kursive.set [0, 17179869184, 0, 0]
// CHECK-NEXT:    %[[OR:.*]] = kursive.or longest %[[A]], %[[B]]
// CHECK-NEXT:    %[[G:.*]] = kursive.group 1 %[[OR]]
// CHECK-NEXT:    %[[R:.*]] = kursive.repeat %[[G]][0, -1]
// CHECK-NEXT:    %[[C:.*]] = kursive.set [0, 34359738368, 0, 0]
// CHECK-NEXT:    %[[T:.*]] = kursive.then %[[R]], %[[C]]
// CHECK-NEXT:    kursive.yield %[[T]]
kursive.pattern @alt "(a|b)*c"

// Bytes in a row are one kursive.lit; a byte with a repetition after it is a set of its own; [[:digit:]] is the set
// of '0'..'9'; {2,3} is repeat [2, 3].
// CHECK-LABEL: kursive.regex @lit groups 0 {
// CHECK-NEXT:    %[[L:.*]] = kursive.lit "foo"
// CHECK-NEXT:    %[[D:.*]] = kursive.set [287948901175001088, 0, 0, 0]
// CHECK-NEXT:    %[[P:.*]] = kursive.repeat %[[D]][1, -1]
// CHECK-NEXT:    %[[X:.*]] = kursive.set [0, 72057594037927936, 0, 0]
// CHECK-NEXT:    %[[Q:.*]] = kursive.repeat %[[X]][2, 3]
// CHECK-NEXT:    kursive.then %[[L]], %[[P]], %[[Q]]
kursive.pattern @lit "foo[[:digit:]]+x{2,3}"

// Anchors, an empty alternative, '.' (any byte but NUL), a negated bracket with ']' first, an escaped special.
// CHECK-LABEL: kursive.regex @anchors groups 1 {
// CHECK:         kursive.bol
// CHECK:         kursive.empty
// CHECK:         kursive.or longest
// CHECK:         kursive.set [-2, -1, -1, -1]
// CHECK:         kursive.set [-1, -536870913, -1, -1]
// CHECK:         kursive.set [70368744177664, 0, 0, 0]
// CHECK:         kursive.eol
kursive.pattern @anchors "^(x|).[^]]\\.$"

// What the compiler rejected: a bound below its start, a quantifier with nothing before it, an unknown class, a
// stray ')', an escaped ordinary character (Nix's libstdc++ is strict); a bound past 100000 is out of room.
// CHECK: kursive.rejected @bound "a{2,1}" "invalid"
// CHECK: kursive.rejected @star "*a" "invalid"
// CHECK: kursive.rejected @class "{{.*}}:foo:{{.*}}" "invalid"
// CHECK: kursive.rejected @paren "a)" "invalid"
// CHECK: kursive.rejected @escape "\\n" "invalid"
// CHECK: kursive.rejected @big "a{100001}" "space"
kursive.pattern @bound "a{2,1}"
kursive.pattern @star "*a"
kursive.pattern @class "[[:foo:]]"
kursive.pattern @paren "a)"
kursive.pattern @escape "\\n"
kursive.pattern @big "a{100001}"

// With room for three sets, the fourth is out of room (the compiler's Space): "foo" takes a set per byte.
// ROOM: kursive.regex @alt groups 1
// ROOM: kursive.rejected @lit "foo{{.*}}" "space"
