// LexRules.h's matchDefault (the lexer's longest-match choice among the rules that can begin a token in the default
// state, Nix's lexer as Parser.cpp and the Confix scan read it) written in the kursive combinators.  Each rule is one
// group; the token is the longest match of the alternatives at the cursor, and a tie goes to the earlier group
// (kursive.or longest keeps the first solution of the longest length).  The group that took part is the rule: group
// g is Rule g - 1 (R_KEYWORD+k = 0..9, R_OPERATOR+k = 10..21, R_ID 30, R_INT 31, R_FLOAT 32, R_DOLLAR_CURLY 33,
// R_RBRACE 34, R_LBRACE 35, R_DQUOTE 36, R_IND_OPEN 37, R_PATH_START 38, R_PATH 39, R_HPATH 40, R_SPATH 41, R_URI 42,
// R_COMMENT 43, R_CHAR 99).  The fallback is any byte (R_CHAR), so a match always exists inside the text.
// The bridge is nixfe_confix_match (lib/Frontend/Confix.cpp): mlir::kursive::lexDefault, which compiles this module
// once per process by kursive-to-program (KursiveLexDefault.inc) and walks it with mlnix_kursive_walk.
//
// A set is four 64-bit words: byte c is bit c % 64 of word c / 64.

kursive.regex @lex_default groups 100 {
  %v0 = kursive.lit "if"  // if
  %v1 = kursive.group 1 %v0  // rule R_KEYWORD+0 'if'
  %v2 = kursive.lit "then"  // then
  %v3 = kursive.group 2 %v2  // rule R_KEYWORD+1 'then'
  %v4 = kursive.lit "else"  // else
  %v5 = kursive.group 3 %v4  // rule R_KEYWORD+2 'else'
  %v6 = kursive.lit "assert"  // assert
  %v7 = kursive.group 4 %v6  // rule R_KEYWORD+3 'assert'
  %v8 = kursive.lit "with"  // with
  %v9 = kursive.group 5 %v8  // rule R_KEYWORD+4 'with'
  %v10 = kursive.lit "let"  // let
  %v11 = kursive.group 6 %v10  // rule R_KEYWORD+5 'let'
  %v12 = kursive.lit "in"  // in
  %v13 = kursive.group 7 %v12  // rule R_KEYWORD+6 'in'
  %v14 = kursive.lit "rec"  // rec
  %v15 = kursive.group 8 %v14  // rule R_KEYWORD+7 'rec'
  %v16 = kursive.lit "inherit"  // inherit
  %v17 = kursive.group 9 %v16  // rule R_KEYWORD+8 'inherit'
  %v18 = kursive.lit "or"  // or
  %v19 = kursive.group 10 %v18  // rule R_KEYWORD+9 'or'
  %v20 = kursive.lit "..."  // ...
  %v21 = kursive.group 11 %v20  // rule R_OPERATOR+0 '...'
  %v22 = kursive.lit "=="  // ==
  %v23 = kursive.group 12 %v22  // rule R_OPERATOR+1 '=='
  %v24 = kursive.lit "!="  // !=
  %v25 = kursive.group 13 %v24  // rule R_OPERATOR+2 '!='
  %v26 = kursive.lit "<="  // <=
  %v27 = kursive.group 14 %v26  // rule R_OPERATOR+3 '<='
  %v28 = kursive.lit ">="  // >=
  %v29 = kursive.group 15 %v28  // rule R_OPERATOR+4 '>='
  %v30 = kursive.lit "&&"  // &&
  %v31 = kursive.group 16 %v30  // rule R_OPERATOR+5 '&&'
  %v32 = kursive.lit "||"  // ||
  %v33 = kursive.group 17 %v32  // rule R_OPERATOR+6 '||'
  %v34 = kursive.lit "->"  // ->
  %v35 = kursive.group 18 %v34  // rule R_OPERATOR+7 '->'
  %v36 = kursive.lit "//"  // //
  %v37 = kursive.group 19 %v36  // rule R_OPERATOR+8 '//'
  %v38 = kursive.lit "++"  // ++
  %v39 = kursive.group 20 %v38  // rule R_OPERATOR+9 '++'
  %v40 = kursive.lit "<|"  // <|
  %v41 = kursive.group 21 %v40  // rule R_OPERATOR+10 '<|'
  %v42 = kursive.lit "|>"  // |>
  %v43 = kursive.group 22 %v42  // rule R_OPERATOR+11 '|>'
  %v44 = kursive.set [0, 576460745995190270, 0, 0]  // [a-zA-Z_]
  %v45 = kursive.set [287984635302903808, 576460745995190270, 0, 0]  // [a-zA-Z0-9_'-]
  %v46 = kursive.repeat %v45[0, -1]
  %v47 = kursive.then %v44, %v46
  %v48 = kursive.group 31 %v47  // rule R_ID
  %v49 = kursive.set [287948901175001088, 0, 0, 0]  // [0-9]
  %v50 = kursive.repeat %v49[1, -1]
  %v51 = kursive.group 32 %v50  // rule R_INT
  %v52 = kursive.set [287667426198290432, 0, 0, 0]  // [1-9]
  %v53 = kursive.set [287948901175001088, 0, 0, 0]  // [0-9]
  %v54 = kursive.repeat %v53[0, -1]
  %v55 = kursive.set [70368744177664, 0, 0, 0]  // .
  %v56 = kursive.set [287948901175001088, 0, 0, 0]  // [0-9]
  %v57 = kursive.repeat %v56[0, -1]
  %v58 = kursive.then %v52, %v54, %v55, %v57
  %v59 = kursive.set [281474976710656, 0, 0, 0]  // 0
  %v60 = kursive.repeat %v59[0, 1]
  %v61 = kursive.set [70368744177664, 0, 0, 0]  // .
  %v62 = kursive.set [287948901175001088, 0, 0, 0]  // [0-9]
  %v63 = kursive.repeat %v62[1, -1]
  %v64 = kursive.then %v60, %v61, %v63
  %v65 = kursive.or longest %v58, %v64
  %v66 = kursive.set [0, 137438953504, 0, 0]  // [Ee]
  %v67 = kursive.set [43980465111040, 0, 0, 0]  // [+-]
  %v68 = kursive.repeat %v67[0, 1]
  %v69 = kursive.set [287948901175001088, 0, 0, 0]  // [0-9]
  %v70 = kursive.repeat %v69[1, -1]
  %v71 = kursive.then %v66, %v68, %v70
  %v72 = kursive.repeat %v71[0, 1]
  %v73 = kursive.then %v65, %v72
  %v74 = kursive.group 33 %v73  // rule R_FLOAT
  %v75 = kursive.lit "${"  // ${
  %v76 = kursive.group 34 %v75  // rule R_DOLLAR_CURLY
  %v77 = kursive.lit "}"  // }
  %v78 = kursive.group 35 %v77  // rule R_RBRACE
  %v79 = kursive.lit "{"  // {
  %v80 = kursive.group 36 %v79  // rule R_LBRACE
  %v81 = kursive.lit "\22"  // "
  %v82 = kursive.group 37 %v81  // rule R_DQUOTE
  %v83 = kursive.lit "''"  // ''
  %v84 = kursive.set [4294967296, 0, 0, 0]  //  
  %v85 = kursive.repeat %v84[0, -1]
  %v86 = kursive.set [1024, 0, 0, 0]  // newline
  %v87 = kursive.then %v83, %v85, %v86
  %v88 = kursive.lit "''"  // ''
  %v89 = kursive.or longest %v87, %v88
  %v90 = kursive.group 38 %v89  // rule R_IND_OPEN
  %v91 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v92 = kursive.repeat %v91[0, -1]
  %v93 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v94 = kursive.lit "${"  // ${
  %v95 = kursive.then %v92, %v93, %v94
  %v96 = kursive.lit "~/${"  // ~/${
  %v97 = kursive.or longest %v95, %v96
  %v98 = kursive.group 39 %v97  // rule R_PATH_START
  %v99 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v100 = kursive.repeat %v99[0, -1]
  %v101 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v102 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v103 = kursive.repeat %v102[1, -1]
  %v104 = kursive.then %v101, %v103
  %v105 = kursive.repeat %v104[1, -1]
  %v106 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v107 = kursive.repeat %v106[0, 1]
  %v108 = kursive.then %v100, %v105, %v107
  %v109 = kursive.group 40 %v108  // rule R_PATH
  %v110 = kursive.set [0, 4611686018427387904, 0, 0]  // ~
  %v111 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v112 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v113 = kursive.repeat %v112[1, -1]
  %v114 = kursive.then %v111, %v113
  %v115 = kursive.repeat %v114[1, -1]
  %v116 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v117 = kursive.repeat %v116[0, 1]
  %v118 = kursive.then %v110, %v115, %v117
  %v119 = kursive.group 41 %v118  // rule R_HPATH
  %v120 = kursive.set [1152921504606846976, 0, 0, 0]  // <
  %v121 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v122 = kursive.repeat %v121[1, -1]
  %v123 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v124 = kursive.set [288063250384289792, 576460745995190270, 0, 0]  // [a-zA-Z0-9._+-]
  %v125 = kursive.repeat %v124[1, -1]
  %v126 = kursive.then %v123, %v125
  %v127 = kursive.repeat %v126[0, -1]
  %v128 = kursive.set [4611686018427387904, 0, 0, 0]  // >
  %v129 = kursive.then %v120, %v122, %v127, %v128
  %v130 = kursive.group 42 %v129  // rule R_SPATH
  %v131 = kursive.set [0, 576460743847706622, 0, 0]  // [a-zA-Z]
  %v132 = kursive.set [288063250384289792, 576460743847706622, 0, 0]  // [a-zA-Z0-9+.-]
  %v133 = kursive.repeat %v132[0, -1]
  %v134 = kursive.lit ":"  // :
  %v135 = kursive.set [-6341071634002083839, 5188146764422578175, 0, 0]  // uri characters (and NUL, as strchr answers)
  %v136 = kursive.repeat %v135[1, -1]
  %v137 = kursive.then %v131, %v133, %v134, %v136
  %v138 = kursive.group 43 %v137  // rule R_URI
  %v139 = kursive.lit "/*"  // /*
  %v140 = kursive.set [-4398046511105, -1, -1, -1]  // any byte but *
  %v141 = kursive.set [4398046511104, 0, 0, 0]  // *
  %v142 = kursive.repeat %v141[1, -1]
  %v143 = kursive.set [-145135534866433, -1, -1, -1]  // any byte but * and /
  %v144 = kursive.then %v142, %v143
  %v145 = kursive.or longest %v140, %v144
  %v146 = kursive.repeat %v145[0, -1]
  %v147 = kursive.set [4398046511104, 0, 0, 0]  // *
  %v148 = kursive.repeat %v147[1, -1]
  %v149 = kursive.set [140737488355328, 0, 0, 0]  // /
  %v150 = kursive.then %v139, %v146, %v148, %v149
  %v151 = kursive.group 44 %v150  // rule R_COMMENT
  %v152 = kursive.set [-1, -1, -1, -1]  // any byte
  %v153 = kursive.group 100 %v152  // rule R_CHAR
  %v154 = kursive.or longest %v1, %v3, %v5, %v7, %v9, %v11, %v13, %v15, %v17, %v19, %v21, %v23, %v25, %v27, %v29, %v31, %v33, %v35, %v37, %v39, %v41, %v43, %v48, %v51, %v74, %v76, %v78, %v80, %v82, %v90, %v98, %v109, %v119, %v130, %v138, %v151, %v153  // longest match; the earlier rule wins a tie
  kursive.yield %v154
}
