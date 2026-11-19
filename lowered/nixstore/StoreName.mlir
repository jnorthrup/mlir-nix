// The pure store-path naming algebra of lib/Store/StorePaths.cpp hollowed into the TrikeShed dialect: checkName (the
// name rules: empty, the 211 cap, the leading-dot/period rules, the character whitelist), outputPathName (drvName plus
// "-output" unless the output is "out"), isStorePath (the store-path name format), storePathName and storePathHashPart
// (the basename's name / hash parts).  StorePaths.cpp keeps only the bridges: checkName's error wording stays there (the
// scan answers a code and the first illegal index), the others size the composite::Text and adopt the drained bytes.
// The algebra is here, in trikeshed.at / slice / text / compare / combine / drain over series<i8>, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Nix semantics, byte for byte the old C++:
//   checkName: empty -> 1; longer than 211 -> 2; "." -> 3; ".-..." -> 4; ".." -> 5; "..-..." -> 6; else the first byte
//   outside [0-9a-zA-Z+-.?_=] -> 7 with its index at *bad; else 0.  The dot rules run before the whitelist scan, as the
//   C++ throws do; the reads of bytes 1 and 2 are guarded by the size checks, so every read is in bounds.
//   outputPathName: drvName, then "-" and output unless output == "out" (trikeshed.compare against the constant text).
//   isStorePath: isInStore (the IsInStore.mlir entry), no '/' in the basename, at least 34 bytes with '-' at 32, 32
//   nix32 chars, then checkName on the rest — a nonzero code is false, as the C++ catch made it.
//   storePathName / storePathHashPart: the basename (one trailing slash stripped, PathOps.mlir's rules), its bytes from
//   33 when longer than 33, else all / its first min(32, len) bytes.
//
// Each draining entry writes into room the caller reserved (the Encoders.mlir way) and returns the byte count.  Nothing
// throws: the naming algebra is pure.  A descriptor is built inline as a struct (returning it allocates nothing and
// clones nothing) and cast to the strided memref at the use site.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @name_out_g : memref<3xi8> = dense<[111, 117, 116]>
memref.global "private" constant @name_dash_g : memref<1xi8> = dense<45>
// the whitelist [0-9a-zA-Z+-.?_=]: 1 at a legal byte, 0 elsewhere (a byte >= 128 is illegal, as the signed-char C++
// range checks made it)
memref.global "private" constant @name_legal_g : memref<256xi8> =
  dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>
// Nix's base32 alphabet "0123456789abcdfghijklmnpqrsvwxyz" as membership: 1 at a member byte (0 is not one, as the
// C++ `|| !base[i]` made it)
memref.global "private" constant @name_nix32_g : memref<256xi8> =
  dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>

// the descriptor of n i8 cells at p
func.func private @name_desc8(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// the last index below hi whose byte is '/', else -1 (PathOps.mlir's path_rfind)
func.func private @name_rfind(%ss: !s, %hi: index) -> i64 {
  %cm1 = arith.constant -1 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c47 = arith.constant 47 : i8
  %r = scf.for %i = %zi to %hi step %oi iter_args(%found = %cm1) -> i64 {
    %ch = trikeshed.at %ss[%i] : !s, index -> i8
    %hit = arith.cmpi eq, %ch, %c47 : i8
    %i64 = arith.index_cast %i : index to i64
    %next = arith.select %hit, %i64, %found : i64
    scf.yield %next : i64
  }
  return %r : i64
}

// the basename's (from, len) within the path: one trailing slash stripped (a lone "/" keeps it), then after the last
// slash; (0, 0) for the empty path, whose bytes are never read
func.func private @name_base(%ss: !s, %n: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %empty = arith.cmpi eq, %n, %c0 : i64
  %r:2 = scf.if %empty -> (i64, i64) {
    scf.yield %c0, %c0 : i64, i64
  } else {
    %ni = arith.index_cast %n : i64 to index
    %c1i = arith.constant 1 : index
    %nm1 = arith.subi %ni, %c1i : index
    %lastch = trikeshed.at %ss[%nm1] : !s, index -> i8
    %c47 = arith.constant 47 : i8
    %isslash = arith.cmpi eq, %lastch, %c47 : i8
    %c1 = arith.constant 1 : i64
    %gt1b = arith.cmpi ugt, %n, %c1 : i64
    %strip = arith.andi %isslash, %gt1b : i1
    %lasti = scf.if %strip -> index {
      scf.yield %nm1 : index
    } else {
      scf.yield %ni : index
    }
    %pos = func.call @name_rfind(%ss, %lasti) : (!s, index) -> i64
    %has = arith.cmpi sge, %pos, %c0 : i64
    %pos1 = arith.addi %pos, %c1 : i64
    %from = arith.select %has, %pos1, %c0 : i64
    %last64 = arith.index_cast %lasti : index to i64
    %len = arith.subi %last64, %from : i64
    scf.yield %from, %len : i64, i64
  }
  return %r#0, %r#1 : i64, i64
}

// nixstore::checkName's scan: the code (0 ok, 1 empty, 2 long, 3 ".", 4 ".-", 5 "..", 6 "..-", 7 illegal) and, for 7,
// the first illegal byte's index at *bad.  The bridge keeps the error wording.
func.func @nixstore_ts_checkname(%p: !llvm.ptr, %n: i64, %bad: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i64
  %c032 = arith.constant 0 : i32
  %c132 = arith.constant 1 : i32
  %c232 = arith.constant 2 : i32
  %empty = arith.cmpi eq, %n, %c0 : i64
  %r = scf.if %empty -> i32 {
    scf.yield %c132 : i32
  } else {
    %c211 = arith.constant 211 : i64
    %long = arith.cmpi ugt, %n, %c211 : i64
    %r2 = scf.if %long -> i32 {
      scf.yield %c232 : i32
    } else {
      %d = func.call @name_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
      %mm = builtin.unrealized_conversion_cast %d : !d to !m
      %ss = builtin.unrealized_conversion_cast %mm : !m to !s
      %zi = arith.constant 0 : index
      %ch0 = trikeshed.at %ss[%zi] : !s, index -> i8
      %c46 = arith.constant 46 : i8
      %isdot = arith.cmpi eq, %ch0, %c46 : i8
      // the leading-dot rules, in the C++ throw order; bytes 1 and 2 read only past the size checks
      %dotcode = scf.if %isdot -> i32 {
        %c1 = arith.constant 1 : i64
        %n1 = arith.cmpi eq, %n, %c1 : i64
        %a = scf.if %n1 -> i32 {
          %c332 = arith.constant 3 : i32
          scf.yield %c332 : i32
        } else {
          %oi = arith.constant 1 : index
          %ch1 = trikeshed.at %ss[%oi] : !s, index -> i8
          %c45 = arith.constant 45 : i8
          %isdash = arith.cmpi eq, %ch1, %c45 : i8
          %b = scf.if %isdash -> i32 {
            %c432 = arith.constant 4 : i32
            scf.yield %c432 : i32
          } else {
            %isdot2 = arith.cmpi eq, %ch1, %c46 : i8
            %c = scf.if %isdot2 -> i32 {
              %c2 = arith.constant 2 : i64
              %n2 = arith.cmpi eq, %n, %c2 : i64
              %e = scf.if %n2 -> i32 {
                %c532 = arith.constant 5 : i32
                scf.yield %c532 : i32
              } else {
                %ti = arith.constant 2 : index
                %ch2 = trikeshed.at %ss[%ti] : !s, index -> i8
                %isdash2 = arith.cmpi eq, %ch2, %c45 : i8
                %f = scf.if %isdash2 -> i32 {
                  %c632 = arith.constant 6 : i32
                  scf.yield %c632 : i32
                } else {
                  scf.yield %c032 : i32
                }
                scf.yield %f : i32
              }
              scf.yield %e : i32
            } else {
              scf.yield %c032 : i32
            }
            scf.yield %c : i32
          }
          scf.yield %b : i32
        }
        scf.yield %a : i32
      } else {
        scf.yield %c032 : i32
      }
      %hasdot = arith.cmpi ne, %dotcode, %c032 : i32
      %r3 = scf.if %hasdot -> i32 {
        scf.yield %dotcode : i32
      } else {
        // the whitelist scan: the first illegal byte wins
        %g = memref.get_global @name_legal_g : memref<256xi8>
        %tab = trikeshed.text %g : memref<256xi8> -> !s
        %ni = arith.index_cast %n : i64 to index
        %oi = arith.constant 1 : index
        %cm1 = arith.constant -1 : i64
        %found = scf.for %i = %zi to %ni step %oi iter_args(%f = %cm1) -> i64 {
          %ch = trikeshed.at %ss[%i] : !s, index -> i8
          %cu = arith.extui %ch : i8 to i64
          %ci = arith.index_cast %cu : i64 to index
          %ok = trikeshed.at %tab[%ci] : !s, index -> i8
          %c18 = arith.constant 1 : i8
          %illegal = arith.cmpi ne, %ok, %c18 : i8
          %first = arith.cmpi slt, %f, %c0 : i64
          %hit = arith.andi %illegal, %first : i1
          %i64 = arith.index_cast %i : index to i64
          %next = arith.select %hit, %i64, %f : i64
          scf.yield %next : i64
        }
        %badfound = arith.cmpi sge, %found, %c0 : i64
        %r4 = scf.if %badfound -> i32 {
          llvm.store %found, %bad : i64, !llvm.ptr
          %c732 = arith.constant 7 : i32
          scf.yield %c732 : i32
        } else {
          scf.yield %c032 : i32
        }
        scf.yield %r4 : i32
      }
      scf.yield %r3 : i32
    }
    scf.yield %r2 : i32
  }
  return %r : i32
}

// nixstore::outputPathName: drvName, then "-" and output unless output == "out".  The combine drains its parts in turn
// into the caller's room; nothing is copied twice.
func.func @nixstore_ts_outputname(%dp: !llvm.ptr, %dn: i64, %op: !llvm.ptr, %on: i64, %out: !llvm.ptr) -> i64 {
  %dd = func.call @name_desc8(%dp, %dn) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %ds = builtin.unrealized_conversion_cast %dm : !m to !s
  %od = func.call @name_desc8(%op, %on) : (!llvm.ptr, i64) -> !d
  %om0 = builtin.unrealized_conversion_cast %od : !d to !m
  %os = builtin.unrealized_conversion_cast %om0 : !m to !s
  %g = memref.get_global @name_out_g : memref<3xi8>
  %outs = trikeshed.text %g : memref<3xi8> -> !s
  %cmp = trikeshed.compare %os, %outs unsigned : !s, !s
  %c032 = arith.constant 0 : i32
  %isout = arith.cmpi eq, %cmp, %c032 : i32
  %r = scf.if %isout -> i64 {
    %om = func.call @name_desc8(%out, %dn) : (!llvm.ptr, i64) -> !d
    %omm = builtin.unrealized_conversion_cast %om : !d to !m
    %e = trikeshed.drain %ds, %omm : !s, !m -> index
    scf.yield %dn : i64
  } else {
    %dg = memref.get_global @name_dash_g : memref<1xi8>
    %dash = trikeshed.text %dg : memref<1xi8> -> !s
    %all = trikeshed.combine %ds, %dash, %os : !s, !s, !s -> !s
    %c1 = arith.constant 1 : i64
    %sum = arith.addi %dn, %c1 : i64
    %len = arith.addi %sum, %on : i64
    %om = func.call @name_desc8(%out, %len) : (!llvm.ptr, i64) -> !d
    %omm = builtin.unrealized_conversion_cast %om : !d to !m
    %e = trikeshed.drain %all, %omm : !s, !m -> index
    scf.yield %len : i64
  }
  return %r : i64
}

// nixstore::isStorePath: in the store, the basename at least 34 bytes with '-' at 32, 32 nix32 chars, then checkName on
// the rest (a nonzero code is false, as the C++ catch made it).  isInStore is the IsInStore.mlir entry, linked beside.
func.func private @mlnix_isInStore(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
func.func @nixstore_ts_isstorepath(%sd: !llvm.ptr, %ss: i64, %pd: !llvm.ptr, %ps: i64) -> i1 {
  %false = arith.constant false
  %true = arith.constant true
  %in = func.call @mlnix_isInStore(%sd, %ss, %pd, %ps) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %r = scf.if %in -> i1 {
    %c1 = arith.constant 1 : i64
    %from = arith.addi %ss, %c1 : i64
    %len = arith.subi %ps, %from : i64
    %d = func.call @name_desc8(%pd, %ps) : (!llvm.ptr, i64) -> !d
    %mm = builtin.unrealized_conversion_cast %d : !d to !m
    %pathss = builtin.unrealized_conversion_cast %mm : !m to !s
    %fromi = arith.index_cast %from : i64 to index
    %leni = arith.index_cast %len : i64 to index
    %bases = trikeshed.slice %pathss[%fromi, %leni] : !s -> !s
    // no '/' anywhere in the basename (the C++ find check, which runs first)
    %zi = arith.constant 0 : index
    %oi = arith.constant 1 : index
    %noslash = scf.for %i = %zi to %leni step %oi iter_args(%ok = %true) -> i1 {
      %ch = trikeshed.at %bases[%i] : !s, index -> i8
      %c47 = arith.constant 47 : i8
      %notslash = arith.cmpi ne, %ch, %c47 : i8
      %next = arith.andi %ok, %notslash : i1
      scf.yield %next : i1
    }
    %r2 = scf.if %noslash -> i1 {
      %c34 = arith.constant 34 : i64
      %oklen = arith.cmpi uge, %len, %c34 : i64
      %r3 = scf.if %oklen -> i1 {
        %c32i = arith.constant 32 : index
        %dashch = trikeshed.at %bases[%c32i] : !s, index -> i8
        %c45 = arith.constant 45 : i8
        %dashok = arith.cmpi eq, %dashch, %c45 : i8
        %r4 = scf.if %dashok -> i1 {
          %g = memref.get_global @name_nix32_g : memref<256xi8>
          %tab = trikeshed.text %g : memref<256xi8> -> !s
          %all = scf.for %i = %zi to %c32i step %oi iter_args(%ok2 = %true) -> i1 {
            %ch2 = trikeshed.at %bases[%i] : !s, index -> i8
            %cu = arith.extui %ch2 : i8 to i64
            %ci = arith.index_cast %cu : i64 to index
            %mb = trikeshed.at %tab[%ci] : !s, index -> i8
            %c18 = arith.constant 1 : i8
            %hit = arith.cmpi eq, %mb, %c18 : i8
            %next2 = arith.andi %ok2, %hit : i1
            scf.yield %next2 : i1
          }
          %r5 = scf.if %all -> i1 {
            %c33 = arith.constant 33 : i64
            %off = arith.addi %from, %c33 : i64
            %np = llvm.getelementptr %pd[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %restlen = arith.subi %len, %c33 : i64
            %c1i = arith.constant 1 : i64
            %badp = llvm.alloca %c1i x i64 : (i64) -> !llvm.ptr
            %code = func.call @nixstore_ts_checkname(%np, %restlen, %badp) : (!llvm.ptr, i64, !llvm.ptr) -> i32
            %c032 = arith.constant 0 : i32
            %nameok = arith.cmpi eq, %code, %c032 : i32
            scf.yield %nameok : i1
          } else {
            scf.yield %false : i1
          }
          scf.yield %r5 : i1
        } else {
          scf.yield %false : i1
        }
        scf.yield %r4 : i1
      } else {
        scf.yield %false : i1
      }
      scf.yield %r3 : i1
    } else {
      scf.yield %false : i1
    }
    scf.yield %r2 : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

// nixstore::storePathName: the basename's bytes from 33 when it is longer than 33, else all of it.
func.func @nixstore_ts_storename(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @name_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %from, %len = func.call @name_base(%ss, %n) : (!s, i64) -> (i64, i64)
  %c33 = arith.constant 33 : i64
  %gt = arith.cmpi ugt, %len, %c33 : i64
  %r:2 = scf.if %gt -> (i64, i64) {
    %f = arith.addi %from, %c33 : i64
    %l = arith.subi %len, %c33 : i64
    scf.yield %f, %l : i64, i64
  } else {
    scf.yield %from, %len : i64, i64
  }
  %fromi = arith.index_cast %r#0 : i64 to index
  %leni = arith.index_cast %r#1 : i64 to index
  %sl = trikeshed.slice %ss[%fromi, %leni] : !s -> !s
  %od = func.call @name_desc8(%out, %r#1) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %e = trikeshed.drain %sl, %om : !s, !m -> index
  return %r#1 : i64
}

// nixstore::storePathHashPart: the basename's first min(32, len) bytes (substr(0, 32) clamps).
func.func @nixstore_ts_storehash(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @name_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %from, %len = func.call @name_base(%ss, %n) : (!s, i64) -> (i64, i64)
  %c32 = arith.constant 32 : i64
  %take = arith.minsi %len, %c32 : i64
  %fromi = arith.index_cast %from : i64 to index
  %takei = arith.index_cast %take : i64 to index
  %sl = trikeshed.slice %ss[%fromi, %takei] : !s -> !s
  %od = func.call @name_desc8(%out, %take) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %e = trikeshed.drain %sl, %om : !s, !m -> index
  return %take : i64
}
