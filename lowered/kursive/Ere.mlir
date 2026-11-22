// The reader of POSIX extended regular expressions (builtins.match, builtins.split; --re2mlir) written in the kursive
// combinators it reads them into: a pattern is read token by token, each token the longest match of one of the two
// grammars below at the cursor (a walk of mlnix_kursive_walk from the cursor, as regex_search with the start held).
// The alternative that matched is the group that took part; its inner groups are the token's parts.  The actions on
// the tokens (counting the nodes and sets of the old compiler, the nesting of the groups, the ranges of a bracket) are
// re2mlir's (lib/Dialect/KursiveDialect.cpp), which compiles this module once with --kursive-to-program.
//
// A set is four 64-bit words: byte c is bit c % 64 of word c / 64.  What a token is follows libstdc++'s
// std::regex::extended as Nix's strict libstdc++ reads it: only the special characters .[\()*+?{|^$ may be escaped.

// Between the tokens of a pattern:
//   1 '.'   2 '[' and 3 a '^' after it   4 '^'   5 '$'   6 '('   7 ')'   8 '|'
//   9 '\' and 10 the special character it escapes (a '\' before anything else is no token: invalid)
//   11 '*', '+' or '?'
//   12 '{', 13 the digits after it, 14 a ',' and 15 the digits after that, 16 the '}' (each part as far as it goes;
//      the actions take a brace with no digits, or with no '}', as invalid)
//   17 any other byte: itself
kursive.regex @ere_main groups 17 {
  %dot = kursive.set [70368744177664, 0, 0, 0]                          // .
  %t1 = kursive.group 1 %dot
  %lbr = kursive.set [0, 134217728, 0, 0]                               // [
  %car = kursive.set [0, 1073741824, 0, 0]                              // ^
  %neg = kursive.group 3 %car
  %negq = kursive.repeat %neg[0, 1]
  %open = kursive.then %lbr, %negq
  %t2 = kursive.group 2 %open
  %bolc = kursive.set [0, 1073741824, 0, 0]                             // ^
  %t4 = kursive.group 4 %bolc
  %eolc = kursive.set [68719476736, 0, 0, 0]                            // $
  %t5 = kursive.group 5 %eolc
  %lp = kursive.set [1099511627776, 0, 0, 0]                            // (
  %t6 = kursive.group 6 %lp
  %rp = kursive.set [2199023255552, 0, 0, 0]                            // )
  %t7 = kursive.group 7 %rp
  %bar = kursive.set [0, 1152921504606846976, 0, 0]                     // |
  %t8 = kursive.group 8 %bar
  %bs = kursive.set [0, 268435456, 0, 0]                                // backslash
  %spc = kursive.set [-9223285106716704768, 1729382258386665472, 0, 0]  // .[\()*+?{|^$
  %esc = kursive.group 10 %spc
  %escape = kursive.then %bs, %esc
  %t9 = kursive.group 9 %escape
  %q = kursive.set [-9223358842715242496, 0, 0, 0]                      // * + ?
  %t11 = kursive.group 11 %q
  %lbrace = kursive.set [0, 576460752303423488, 0, 0]                   // {
  %d1 = kursive.set [287948901175001088, 0, 0, 0]                       // 0-9
  %d1s = kursive.repeat %d1[0, -1]
  %lo = kursive.group 13 %d1s
  %comma = kursive.set [17592186044416, 0, 0, 0]                        // ,
  %d2 = kursive.set [287948901175001088, 0, 0, 0]                       // 0-9
  %d2s = kursive.repeat %d2[0, -1]
  %hi = kursive.group 15 %d2s
  %upper = kursive.then %comma, %hi
  %ug = kursive.group 14 %upper
  %ugq = kursive.repeat %ug[0, 1]
  %rbrace = kursive.set [0, 2305843009213693952, 0, 0]                  // }
  %close = kursive.group 16 %rbrace
  %closeq = kursive.repeat %close[0, 1]
  %brace = kursive.then %lbrace, %lo, %ugq, %closeq
  %t12 = kursive.group 12 %brace
  %plain = kursive.set [9223285106716704767, -1729382258386665473, -1, -1] // any byte but .[\()*+?{|^$
  %t17 = kursive.group 17 %plain
  %tok = kursive.or longest %t1, %t2, %t4, %t5, %t6, %t7, %t8, %t9, %t11, %t12, %t17
  kursive.yield %tok
}

// Inside a bracket expression (after its '[' or '[^'), one element at a time:
//   1 a class '[:' 2 name ':]' (the name runs to the first ':]'; the actions take an unknown name as invalid)
//   3 '[:' with no ':]' after it: invalid
//   4 '[.' 5 c '.]' and 6 '[=' 7 c '=]': the byte c
//   8 '[.' or '[=' not so closed: invalid
//   9 any byte: itself (a ']' after the first element closes the bracket; a '-' between two elements is a range: the
//     actions')
kursive.regex @ere_bracket groups 9 {
  %open = kursive.lit "[:"
  %nc = kursive.set [-288230376151711745, -1, -1, -1]                   // any byte but :
  %col = kursive.set [288230376151711744, 0, 0, 0]                      // :
  %cols = kursive.repeat %col[1, -1]
  %ncr = kursive.set [-288230376151711745, -536870913, -1, -1]          // any byte but : and ]
  %colsx = kursive.then %cols, %ncr
  %unit = kursive.or longest %nc, %colsx
  %units = kursive.repeat %unit[0, -1]
  %col2 = kursive.set [288230376151711744, 0, 0, 0]                     // :
  %tail = kursive.repeat %col2[0, -1]
  %namet = kursive.then %units, %tail
  %name = kursive.group 2 %namet
  %shut = kursive.lit ":]"
  %class = kursive.then %open, %name, %shut
  %t1 = kursive.group 1 %class
  %bad = kursive.lit "[:"
  %t3 = kursive.group 3 %bad
  %copen = kursive.lit "[."
  %cany = kursive.set [-1, -1, -1, -1]
  %cbyte = kursive.group 5 %cany
  %cshut = kursive.lit ".]"
  %coll = kursive.then %copen, %cbyte, %cshut
  %t4 = kursive.group 4 %coll
  %eopen = kursive.lit "[="
  %eany = kursive.set [-1, -1, -1, -1]
  %ebyte = kursive.group 7 %eany
  %eshut = kursive.lit "=]"
  %equiv = kursive.then %eopen, %ebyte, %eshut
  %t6 = kursive.group 6 %equiv
  %blbr = kursive.set [0, 134217728, 0, 0]                              // [
  %bdeq = kursive.set [2305913377957871616, 0, 0, 0]                    // . =
  %badc = kursive.then %blbr, %bdeq
  %t8 = kursive.group 8 %badc
  %any = kursive.set [-1, -1, -1, -1]
  %t9 = kursive.group 9 %any
  %tok = kursive.or longest %t1, %t3, %t4, %t6, %t8, %t9
  kursive.yield %tok
}
