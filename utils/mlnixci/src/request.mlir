// request.mlir -- an HTTP/1.1 request's framing, read where it lies in its connection's buffer: where the head ends,
// what Content-Length says, the request line's method and path, and the route they name.  The grammar is kursive
// combinators (src/request-grammar.mlir, the Step programs --kursive-to-program makes of it), walked by mlir-nix's
// mlnix_kursive_walk (lowered/nixeval/KursiveOps.mlir); the lines are TrikeShed's ops over the request's text.
// Compiled with request-grammar.mlir's programs by mlnix-opt --trikeshed-lower-cursors.
//
//   rq_frame(in, out) -> 0  not all here yet: no blank line, or less body than Content-Length says
//                        1  Content-Length over 1 MiB (413 "request too large")
//                        2  no request line: fewer than two ' ' before the blank line (400 "bad request line")
//                        3  framed: out = method [start, end), path [start, end) (the target to its '?'), body
//                           [start, end) (end - start is what Content-Length says), route (rq_route's group, 0 none)
// http.mlir answers each; its connection keeps the buffer, so a request is framed again as more of it arrives.
//
//   rq_body(rows, kids, text, want) -> (code, segments, value): a what-if's body {"path": [segments], "value": json} read
//                        through its Confix index (index.mlir's rows and kids; KeyToChild is its ix_member): code 0 when
//                        it is one, else what it lacks (2 not an object, 3 "path" not an array, 4 "path" empty, 5 a
//                        segment not a string, 6 no "value" when one is wanted); each segment's inside (TwinPacked) and
//                        the value as written.  (1, not JSON, is api.mlir's: there is no index.)

!text = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">

// Kursive.h's walk: the programs' steps and sets, the groups and loops they count, the text, where to start, whether the
// whole text must match, the marks, the loop states, the checkpoints and a budget; 1 a match, 0 none, 2 out of room
func.func private @mlnix_kursive_walk(!llvm.ptr, !llvm.ptr, i32, i32, !llvm.ptr, i32, i32, i32, i32, !llvm.ptr, !llvm.ptr,
                                      !llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32

func.func private @rq_p8(%m: memref<?xi8>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi8> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
func.func private @rq_p32(%m: memref<?xi32>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi32> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
func.func private @rq_p64(%m: memref<?xi64>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi64> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// One walk of a program over text[0, n) from start (exact: the whole of it); its marks land in best.  The scratch is the
// frame's: the marks being made, the loops' states, the checkpoints (room for cap) and the budget.
func.func private @rq_walk(%steps: memref<?xi32>, %sets: memref<?xi64>, %counts: memref<5xi32>, %text: !llvm.ptr,
                           %n: index, %start: index, %exact: i32, %best: memref<?xi32>, %caps: memref<?xi32>,
                           %loops: memref<?xi32>, %stack: memref<?xi32>, %cap: i32, %budget: memref<?xi64>) -> i32 {
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %z = arith.constant 0 : i32
  %groups = memref.load %counts[%c2] : memref<5xi32>
  %nloops = memref.load %counts[%c3] : memref<5xi32>
  %n32 = arith.index_cast %n : index to i32
  %s32 = arith.index_cast %start : index to i32
  %ps = func.call @rq_p32(%steps) : (memref<?xi32>) -> !llvm.ptr
  %pt = func.call @rq_p64(%sets) : (memref<?xi64>) -> !llvm.ptr
  %pc = func.call @rq_p32(%caps) : (memref<?xi32>) -> !llvm.ptr
  %pb = func.call @rq_p32(%best) : (memref<?xi32>) -> !llvm.ptr
  %pl = func.call @rq_p32(%loops) : (memref<?xi32>) -> !llvm.ptr
  %pk = func.call @rq_p32(%stack) : (memref<?xi32>) -> !llvm.ptr
  %pg = func.call @rq_p64(%budget) : (memref<?xi64>) -> !llvm.ptr
  %r = func.call @mlnix_kursive_walk(%ps, %pt, %groups, %nloops, %text, %n32, %s32, %exact, %z, %pc, %pb, %pl, %pk, %cap, %pg)
      : (!llvm.ptr, !llvm.ptr, i32, i32, !llvm.ptr, i32, i32, i32, i32, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i32,
         !llvm.ptr) -> i32
  return %r : i32
}

// a group's mark as an index (a group that took no part has ~0)
func.func private @rq_mark(%best: memref<?xi32>, %k: index) -> index {
  %m = memref.load %best[%k] : memref<?xi32>
  %i = arith.index_castui %m : i32 to index
  return %i : index
}

func.func @rq_frame(%in: memref<?xi8>, %out: memref<?xi64>) -> i64 attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %c8 = arith.constant 8 : index
  %c15 = arith.constant 15 : index
  %c16 = arith.constant 16 : index
  %c18 = arith.constant 18 : index
  %c64 = arith.constant 64 : index
  %c256 = arith.constant 256 : index
  %z64 = arith.constant 0 : i64
  %m1 = arith.constant -1 : i64
  %v0 = arith.constant 0 : i64
  %v1 = arith.constant 1 : i64
  %v2 = arith.constant 2 : i64
  %v3 = arith.constant 3 : i64
  %v4 = arith.constant 4 : i64
  %v10 = arith.constant 10 : i64
  %v48 = arith.constant 48 : i64
  %one = arith.constant 1 : i32
  %zero = arith.constant 0 : i32
  %none32 = arith.constant -1 : i32
  %cr = arith.constant 13 : i8
  %lf = arith.constant 10 : i8
  %t = trikeshed.text %in : memref<?xi8> -> !text
  %n = trikeshed.size %t : !text
  %n64 = arith.index_cast %n : index to i64
  // where the head ends: the first "\r\n\r\n"
  %fits = arith.cmpi uge, %n, %c3 : index
  %n3 = arith.subi %n, %c3 : index
  %starts = arith.select %fits, %n3, %c0 : index
  %at = trikeshed.series %starts : !s64 {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    trikeshed.yield %k64 : i64
  }
  %blanks = trikeshed.where %at : !s64 -> !s64 {
  ^bb0(%k64: i64):
    %k = arith.index_cast %k64 : i64 to index
    %k1 = arith.addi %k, %c1 : index
    %k2 = arith.addi %k, %c2 : index
    %k3 = arith.addi %k, %c3 : index
    %b0 = trikeshed.at %t[%k] : !text, index -> i8
    %b1 = trikeshed.at %t[%k1] : !text, index -> i8
    %b2 = trikeshed.at %t[%k2] : !text, index -> i8
    %b3 = trikeshed.at %t[%k3] : !text, index -> i8
    %e0 = arith.cmpi eq, %b0, %cr : i8
    %e1 = arith.cmpi eq, %b1, %lf : i8
    %e2 = arith.cmpi eq, %b2, %cr : i8
    %e3 = arith.cmpi eq, %b3, %lf : i8
    %e01 = arith.andi %e0, %e1 : i1
    %e23 = arith.andi %e2, %e3 : i1
    %e = arith.andi %e01, %e23 : i1
    trikeshed.yield %e : i1
  }
  %nb = trikeshed.size %blanks : !s64
  %headless = arith.cmpi eq, %nb, %c0 : index
  %verdict = scf.if %headless -> (i64) {
    scf.yield %v0 : i64
  } else {
    %end64 = trikeshed.at %blanks[%c0] : !s64, index -> i64
    %end = arith.index_cast %end64 : i64 to index
    %ptext = func.call @rq_p8(%in) : (memref<?xi8>) -> !llvm.ptr
    // the frame's scratch for every walk: marks for up to 8 groups, loop states, a checkpoint for each byte of the head
    // twice over (a repeat keeps one an iteration), a budget no request reaches
    %best = memref.alloc(%c18) : memref<?xi32>
    %caps = memref.alloc(%c18) : memref<?xi32>
    %loops = memref.alloc(%c64) : memref<?xi32>
    %capN = arith.addi %end, %end : index
    %capR = arith.addi %capN, %c256 : index
    %cap = arith.index_cast %capR : index to i32
    %stackN = arith.muli %capR, %c3 : index
    %stack = memref.alloc(%stackN) : memref<?xi32>
    %budget = memref.alloc(%c1) : memref<?xi64>
    %b0 = arith.constant 17179869184 : i64
    memref.store %b0, %budget[%c0] : memref<?xi64>
    // the header lines, each after a "\r\n" before the blank line: the last that is Content-Length, its value as atol
    // reads it (0 when none says)
    %breaks = trikeshed.series %end : !s64 {
    ^bb0(%k: index):
      %k64 = arith.index_cast %k : index to i64
      trikeshed.yield %k64 : i64
    }
    %lines = trikeshed.where %breaks : !s64 -> !s64 {
    ^bb0(%k64: i64):
      %k = arith.index_cast %k64 : i64 to index
      %k1 = arith.addi %k, %c1 : index
      %x0 = trikeshed.at %t[%k] : !text, index -> i8
      %x1 = trikeshed.at %t[%k1] : !text, index -> i8
      %y0 = arith.cmpi eq, %x0, %cr : i8
      %y1 = arith.cmpi eq, %x1, %lf : i8
      %y = arith.andi %y0, %y1 : i1
      trikeshed.yield %y : i1
    }
    %lsG = memref.get_global @rq_length_steps : memref<120xi32>
    %lsS = memref.cast %lsG : memref<120xi32> to memref<?xi32>
    %leG = memref.get_global @rq_length_sets : memref<72xi64>
    %leS = memref.cast %leG : memref<72xi64> to memref<?xi64>
    %lc = memref.get_global @rq_length_counts : memref<5xi32>
    %length = trikeshed.fold %lines, %z64 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %k64: i64):
      %k = arith.index_cast %k64 : i64 to index
      %from = arith.addi %k, %c2 : index
      %r = func.call @rq_walk(%lsS, %leS, %lc, %ptext, %end, %from, %zero, %best, %caps, %loops, %stack, %cap, %budget)
          : (memref<?xi32>, memref<?xi64>, memref<5xi32>, !llvm.ptr, index, index, i32, memref<?xi32>, memref<?xi32>,
             memref<?xi32>, memref<?xi32>, i32, memref<?xi64>) -> i32
      %named = arith.cmpi eq, %r, %one : i32
      %v = scf.if %named -> (i64) {
        // a line of the name alone (15 bytes, then its "\r\n") is not one
        %f15 = arith.addi %from, %c15 : index
        %f16 = arith.addi %from, %c16 : index
        %a = trikeshed.at %t[%f15] : !text, index -> i8
        %b = trikeshed.at %t[%f16] : !text, index -> i8
        %ea = arith.cmpi eq, %a, %cr : i8
        %eb = arith.cmpi eq, %b, %lf : i8
        %bare = arith.andi %ea, %eb : i1
        %val = scf.if %bare -> (i64) {
          scf.yield %acc : i64
        } else {
          %s0 = memref.load %best[%c2] : memref<?xi32>
          %s1 = memref.load %best[%c3] : memref<?xi32>
          %signed0 = arith.cmpi ne, %s0, %none32 : i32
          %signed1 = arith.cmpi ne, %s0, %s1 : i32
          %negative = arith.andi %signed0, %signed1 : i1
          %d0 = memref.load %best[%c4] : memref<?xi32>
          %d1 = memref.load %best[%c5] : memref<?xi32>
          %some = arith.cmpi ne, %d0, %none32 : i32
          %ds = arith.index_castui %d0 : i32 to index
          %de = arith.index_castui %d1 : i32 to index
          %dl0 = arith.subi %de, %ds : index
          %dl = arith.select %some, %dl0, %c0 : index
          %dsx = arith.select %some, %ds, %c0 : index
          %digits = trikeshed.slice %t[%dsx, %dl] : !text -> !text
          %mag = trikeshed.fold %digits, %z64 : !text, i64 -> i64 {
          ^bb0(%m: i64, %d: i8):
            %d64 = arith.extui %d : i8 to i64
            %dv = arith.subi %d64, %v48 : i64
            %m10 = arith.muli %m, %v10 : i64
            %next = arith.addi %m10, %dv : i64
            trikeshed.yield %next : i64
          }
          %neg = arith.subi %z64, %mag : i64
          %signedv = arith.select %negative, %neg, %mag : i64
          scf.yield %signedv : i64
        }
        scf.yield %val : i64
      } else {
        scf.yield %acc : i64
      }
      trikeshed.yield %v : i64
    }
    %max = arith.constant 1048576 : i64
    %tooBig = arith.cmpi sgt, %length, %max : i64
    %v = scf.if %tooBig -> (i64) {
      scf.yield %v1 : i64
    } else {
      %bodyAt = arith.addi %end64, %v4 : i64
      %need = arith.addi %bodyAt, %length : i64
      %short = arith.cmpi slt, %n64, %need : i64
      %w = scf.if %short -> (i64) {
        scf.yield %v0 : i64
      } else {
        // the request line, from the head's start: its method and its path
        %rsG = memref.get_global @rq_line_steps : memref<72xi32>
        %rsS = memref.cast %rsG : memref<72xi32> to memref<?xi32>
        %reG = memref.get_global @rq_line_sets : memref<20xi64>
        %reS = memref.cast %reG : memref<20xi64> to memref<?xi64>
        %rc = memref.get_global @rq_line_counts : memref<5xi32>
        %r = func.call @rq_walk(%rsS, %reS, %rc, %ptext, %end, %c0, %zero, %best, %caps, %loops, %stack, %cap, %budget)
            : (memref<?xi32>, memref<?xi64>, memref<5xi32>, !llvm.ptr, index, index, i32, memref<?xi32>, memref<?xi32>,
               memref<?xi32>, memref<?xi32>, i32, memref<?xi64>) -> i32
        %lined = arith.cmpi eq, %r, %one : i32
        %x = scf.if %lined -> (i64) {
          %me = func.call @rq_mark(%best, %c3) : (memref<?xi32>, index) -> index
          %ps = func.call @rq_mark(%best, %c4) : (memref<?xi32>, index) -> index
          %pe = func.call @rq_mark(%best, %c5) : (memref<?xi32>, index) -> index
          // the route: the method, ' ' and the path, matched whole
          %osG = memref.get_global @rq_route_steps : memref<712xi32>
          %osS = memref.cast %osG : memref<712xi32> to memref<?xi32>
          %oeG = memref.get_global @rq_route_sets : memref<572xi64>
          %oeS = memref.cast %oeG : memref<572xi64> to memref<?xi64>
          %oc = memref.get_global @rq_route_counts : memref<5xi32>
          %rr = func.call @rq_walk(%osS, %oeS, %oc, %ptext, %pe, %c0, %one, %best, %caps, %loops, %stack, %cap, %budget)
              : (memref<?xi32>, memref<?xi64>, memref<5xi32>, !llvm.ptr, index, index, i32, memref<?xi32>, memref<?xi32>,
                 memref<?xi32>, memref<?xi32>, i32, memref<?xi64>) -> i32
          %routed = arith.cmpi eq, %rr, %one : i32
          %groups = trikeshed.series %c8 : !s64 {
          ^bb0(%g: index):
            %g1 = arith.addi %g, %c1 : index
            %g64 = arith.index_cast %g1 : index to i64
            trikeshed.yield %g64 : i64
          }
          %route = trikeshed.fold %groups, %z64 : !s64, i64 -> i64 {
          ^bb0(%which: i64, %g64: i64):
            %g = arith.index_cast %g64 : i64 to index
            %gm = arith.addi %g, %g : index
            %mark = memref.load %best[%gm] : memref<?xi32>
            %took = arith.cmpi ne, %mark, %none32 : i32
            %first = arith.cmpi eq, %which, %z64 : i64
            %this = arith.andi %took, %first : i1
            %w2 = arith.select %this, %g64, %which : i64
            trikeshed.yield %w2 : i64
          }
          %route0 = arith.select %routed, %route, %z64 : i64
          %me64 = arith.index_cast %me : index to i64
          %ps64 = arith.index_cast %ps : index to i64
          %pe64 = arith.index_cast %pe : index to i64
          memref.store %z64, %out[%c0] : memref<?xi64>
          memref.store %me64, %out[%c1] : memref<?xi64>
          memref.store %ps64, %out[%c2] : memref<?xi64>
          memref.store %pe64, %out[%c3] : memref<?xi64>
          memref.store %bodyAt, %out[%c4] : memref<?xi64>
          memref.store %need, %out[%c5] : memref<?xi64>
          memref.store %route0, %out[%c6] : memref<?xi64>
          scf.yield %v3 : i64
        } else {
          scf.yield %v2 : i64
        }
        scf.yield %x : i64
      }
      scf.yield %w : i64
    }
    scf.yield %v : i64
  }
  return %verdict : i64
}

// ---- a what-if's body, through its index

// index.mlir's KeyToChild: the value row of the key, or -1
func.func private @ix_member(!ix, !s32, !text, i64, !text) -> i64

memref.global "private" constant @rq_path : memref<4xi8> = dense<"0x70617468">  // path
memref.global "private" constant @rq_value : memref<5xi8> = dense<"0x76616C7565">  // value

func.func @rq_body(%rows: !ix, %kids: !s32, %t: !text, %want: i64) -> (i64, !s64, i64) attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %z64 = arith.constant 0 : i64
  %m1 = arith.constant -1 : i64
  %v1 = arith.constant 1 : i64
  %v2 = arith.constant 2 : i64
  %v3 = arith.constant 3 : i64
  %v4 = arith.constant 4 : i64
  %v5 = arith.constant 5 : i64
  %v6 = arith.constant 6 : i64
  %v32 = arith.constant 32 : i64
  %mask = arith.constant 4294967295 : i64
  %one32 = arith.constant 1 : i32
  %string = arith.constant 4 : i8
  %object = arith.constant 5 : i8
  %array = arith.constant 6 : i8
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !trikeshed.series<i8>
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %pathG = memref.get_global @rq_path : memref<4xi8>
  %kPath = trikeshed.text %pathG : memref<4xi8> -> !text
  %valueG = memref.get_global @rq_value : memref<5xi8>
  %kValue = trikeshed.text %valueG : memref<5xi8> -> !text
  // the root an object, its "path" an array of strings, not empty
  %tag0 = trikeshed.at %tags[%c0] : !trikeshed.series<i8>, index -> i8
  %isObj = arith.cmpi eq, %tag0, %object : i8
  %p = scf.if %isObj -> (i64) {
    %r = func.call @ix_member(%rows, %kids, %t, %z64, %kPath) : (!ix, !s32, !text, i64, !text) -> i64
    scf.yield %r : i64
  } else {
    scf.yield %m1 : i64
  }
  %hasP = arith.cmpi sge, %p, %z64 : i64
  %isArr = scf.if %hasP -> (i1) {
    %pt = trikeshed.at %tags[%p] : !trikeshed.series<i8>, i64 -> i8
    %a = arith.cmpi eq, %pt, %array : i8
    scf.yield %a : i1
  } else {
    %no = arith.constant false
    scf.yield %no : i1
  }
  %first, %ns = scf.if %isArr -> (index, index) {
    %fc = trikeshed.at %kc[%p] : !trikeshed.series<!tp>, i64 -> !tp
    %f32 = trikeshed.first %fc : !tp -> i32
    %n32 = trikeshed.second %fc : !tp -> i32
    %f = arith.index_castui %f32 : i32 to index
    %n = arith.index_castui %n32 : i32 to index
    scf.yield %f, %n : index, index
  } else {
    scf.yield %c0, %c0 : index, index
  }
  %segRows = trikeshed.slice %kids[%first, %ns] : !s32 -> !s32
  // each segment's inside, between its quotes, as TwinPacked (start << 32 | length)
  %segs = trikeshed.series %ns : !s64 {
  ^bb0(%k: index):
    %row = trikeshed.at %segRows[%k] : !s32, index -> i32
    %sp = trikeshed.at %spans[%row] : !trikeshed.series<!tw>, i32 -> !tw
    %o = trikeshed.first %sp : !tw -> i32
    %c = trikeshed.second %sp : !tw -> i32
    %in = arith.addi %o, %one32 : i32
    %s64 = arith.extui %in : i32 to i64
    %e64 = arith.extui %c : i32 to i64
    %len = arith.subi %e64, %s64 : i64
    %lo = arith.andi %len, %mask : i64
    %hi = arith.shli %s64, %v32 : i64
    %tw = arith.ori %hi, %lo : i64
    trikeshed.yield %tw : i64
  }
  %strings = trikeshed.fold %segRows, %v1 : !s32, i64 -> i64 {
  ^bb0(%all: i64, %row: i32):
    %st = trikeshed.at %tags[%row] : !trikeshed.series<i8>, i32 -> i8
    %isS = arith.cmpi eq, %st, %string : i8
    %s = arith.select %isS, %all, %z64 : i64
    trikeshed.yield %s : i64
  }
  %ns64 = arith.index_cast %ns : index to i64
  %empty = arith.cmpi eq, %ns64, %z64 : i64
  %allStrings = arith.cmpi ne, %strings, %z64 : i64
  %wanted = arith.cmpi ne, %want, %z64 : i64
  %shaped = arith.andi %isArr, %allStrings : i1
  %nonEmpty = arith.cmpi ne, %ns64, %z64 : i64
  %pathOk = arith.andi %shaped, %nonEmpty : i1
  %look = arith.andi %pathOk, %wanted : i1
  %v = scf.if %look -> (i64) {
    %r = func.call @ix_member(%rows, %kids, %t, %z64, %kValue) : (!ix, !s32, !text, i64, !text) -> i64
    scf.yield %r : i64
  } else {
    scf.yield %m1 : i64
  }
  %hasV = arith.cmpi sge, %v, %z64 : i64
  // the value as written: [open, close + 1)
  %vt = scf.if %hasV -> (i64) {
    %sp = trikeshed.at %spans[%v] : !trikeshed.series<!tw>, i64 -> !tw
    %o = trikeshed.first %sp : !tw -> i32
    %c = trikeshed.second %sp : !tw -> i32
    %s64 = arith.extui %o : i32 to i64
    %c64 = arith.extui %c : i32 to i64
    %e64 = arith.addi %c64, %v1 : i64
    %len = arith.subi %e64, %s64 : i64
    %lo = arith.andi %len, %mask : i64
    %hi = arith.shli %s64, %v32 : i64
    %tw = arith.ori %hi, %lo : i64
    scf.yield %tw : i64
  } else {
    scf.yield %z64 : i64
  }
  // what it lacks first: an object, an array, a segment, strings, a value
  %noV = arith.cmpi slt, %v, %z64 : i64
  %lacksV = arith.andi %look, %noV : i1
  %e6 = arith.select %lacksV, %v6, %z64 : i64
  %notStrings = arith.cmpi eq, %strings, %z64 : i64
  %e5 = arith.select %notStrings, %v5, %e6 : i64
  %e4 = arith.select %empty, %v4, %e5 : i64
  %e3 = arith.select %isArr, %e4, %v3 : i64
  %code = arith.select %isObj, %e3, %v2 : i64
  return %code, %segs, %vt : i64, !s64, i64
}
