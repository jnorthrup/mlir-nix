// request-grammar.mlir -- what mlnixci reads of an HTTP/1.1 request, as TrikeShed's kursive combinators
// (borg.trikeshed.parse.kursive; mlir-nix include/NixDialect/Kursive.td).  `mlnix-opt --kursive-to-program` makes each
// regex the Step program (@X_steps, @X_sets, @X_counts) that lowered/nixeval/KursiveOps.mlir's mlnix_kursive_walk runs;
// src/request.mlir walks them over the request where it lies.  A set is four 64-bit words, byte c bit c % 64 of word
// c / 64.
//
//   rq_line    the request line: the method (group 1, every byte to the first ' '), ' ', the path (group 2, to the first
//              ' ' or '?'), the rest of the target, ' ' -- walked from the start of the head, its longest prefix
//   rq_length  a header line that is Content-Length, its name in any case (strncasecmp), then atol's reading of its
//              value: blanks, a sign (group 1), digits (group 2) -- walked from the start of each header line
//   rq_route   the method, ' ' and the path, whole: which route (the group that took part) -- the page (GET / or
//              /index.html), the query (POST, or GET without a body), the report, the three what-if edits, the facets

kursive.regex @rq_line groups 2 {
  %notSp = kursive.set [-4294967297, -1, -1, -1]               // [^ ]
  %method = kursive.repeat %notSp[0, -1]
  %g1 = kursive.group 1 %method
  %sp = kursive.lit " "
  %notSpQ = kursive.set [9223372032559808511, -1, -1, -1]      // [^ ?]
  %path = kursive.repeat %notSpQ[0, -1]
  %g2 = kursive.group 2 %path
  %notSp2 = kursive.set [-4294967297, -1, -1, -1]              // [^ ]: the query string, unread
  %query = kursive.repeat %notSp2[0, -1]
  %sp2 = kursive.lit " "
  %line = kursive.then %g1, %sp, %g2, %query, %sp2
  kursive.yield %line
}

kursive.regex @rq_length groups 2 {
  %C = kursive.set [0, 34359738376, 0, 0]                      // [Cc]
  %O = kursive.set [0, 140737488388096, 0, 0]                  // [Oo]
  %N = kursive.set [0, 70368744194048, 0, 0]                   // [Nn]
  %T = kursive.set [0, 4503599628419072, 0, 0]                 // [Tt]
  %E = kursive.set [0, 137438953504, 0, 0]                     // [Ee]
  %N2 = kursive.set [0, 70368744194048, 0, 0]                  // [Nn]
  %T2 = kursive.set [0, 4503599628419072, 0, 0]                // [Tt]
  %dash = kursive.lit "-"
  %L = kursive.set [0, 17592186048512, 0, 0]                   // [Ll]
  %E2 = kursive.set [0, 137438953504, 0, 0]                    // [Ee]
  %N3 = kursive.set [0, 70368744194048, 0, 0]                  // [Nn]
  %G = kursive.set [0, 549755814016, 0, 0]                     // [Gg]
  %T3 = kursive.set [0, 4503599628419072, 0, 0]                // [Tt]
  %H = kursive.set [0, 1099511628032, 0, 0]                    // [Hh]
  %colon = kursive.lit ":"
  %blank = kursive.lit " "
  %blanks = kursive.repeat %blank[0, -1]
  %minus = kursive.lit "-"
  %sign = kursive.repeat %minus[0, 1]
  %g1 = kursive.group 1 %sign
  %digit = kursive.set [287948901175001088, 0, 0, 0]           // [0-9]
  %digits = kursive.repeat %digit[0, -1]
  %g2 = kursive.group 2 %digits
  %line = kursive.then %C, %O, %N, %T, %E, %N2, %T2, %dash, %L, %E2, %N3, %G, %T3, %H, %colon, %blanks, %g1, %g2
  kursive.yield %line
}

kursive.regex @rq_route groups 8 {
  %root = kursive.lit "GET /"
  %index = kursive.lit "GET /index.html"
  %page = kursive.or longest %root, %index
  %r1 = kursive.group 1 %page
  %postQuery = kursive.lit "POST /api/query"
  %r2 = kursive.group 2 %postQuery
  %getQuery = kursive.lit "GET /api/query"
  %r3 = kursive.group 3 %getQuery
  %report = kursive.lit "GET /api/report"
  %r4 = kursive.group 4 %report
  %set = kursive.lit "POST /api/whatif/set"
  %r5 = kursive.group 5 %set
  %reset = kursive.lit "POST /api/whatif/reset"
  %r6 = kursive.group 6 %reset
  %clear = kursive.lit "POST /api/whatif/clear"
  %r7 = kursive.group 7 %clear
  %facet = kursive.lit "POST /api/facet"
  %r8 = kursive.group 8 %facet
  %route = kursive.or longest %r1, %r2, %r3, %r4, %r5, %r6, %r7, %r8
  kursive.yield %route
}
