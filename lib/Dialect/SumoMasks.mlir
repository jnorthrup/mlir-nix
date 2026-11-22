// SumoClassifier.kt's INSTANCES and DISJOINT masks over a theory's relations, as compositions of TrikeShed's ops
// (PRELOAD-DIALECTS step 6): no new op and no C++.  Each mask is one trikeshed.closure (ClosureIndex) over a graph of
// layers of the term rows 0 ..< n, so the closure's walk, which meets each node once, is what makes each class appear
// once in a mask:
//
//   instance types  T(x) -> U(k) for (instance x k), U(c) -> U(p) for (subclass c p): what T(x) reaches is x's classes
//                   and their ancestors, sumo.nix's `isInstance x c` (SumoClassifier's instanceTypes, closed upward)
//   disjoint        U(c) -> U(p) up the subclass edges, U(a) -> D(d) for each class d declared disjoint from a,
//                   D(p) -> D(c) down them: what U(c) reaches in D is every class disjoint from c or from one of its
//                   ancestors, with their descendants (SumoClassifier's disjointMask), less n
//
// Both read the relations as sumo.relation gives them (sumo.nix's reading of an argument: anything but a list), and
// return the DirectChildren shape trikeshed.closure does: per term row a (first, count) into the members.
//
// A query takes these functions in beside its own: `mlnix-kif F.kif.. --query lib/Dialect/SumoMasks.mlir --query Q.mlir`
// (test/mlir/sumo-masks.mlir).

!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!terms = !trikeshed.cursor<"KifTerm", [i8, !tp, !tp]>
!tk = !trikeshed.colkey<"KifTerm">
!facts = !trikeshed.cursor<"KifFact", [i32, i32]>
!fk = !trikeshed.colkey<"KifFact">

// xs with n added to each row: the same nodes in the layer above n
func.func private @sumo_masks_shifted(%xs: !s32, %n: index) -> !s32 {
  %n32 = arith.index_cast %n : index to i32
  %up = trikeshed.alpha %xs : !s32 -> !s32 {
  ^bb0(%x: i32):
    %y = arith.addi %x, %n32 : i32
    trikeshed.yield %y : i32
  }
  return %up : !s32
}

// The instance types of every term row: for row x, (first, count) into the classes x is an instance of, its classes'
// ancestors included, each once.  child/parent: the subclass rows; thing/class: the instance rows; n: the term rows.
func.func private @sumo_instance_types(%child: !s32, %parent: !s32, %thing: !s32, %class: !s32, %n: index) -> (!sp, !s32) {
  %tthing = func.call @sumo_masks_shifted(%thing, %n) : (!s32, index) -> !s32
  %from = trikeshed.combine %child, %tthing : !s32, !s32 -> !s32
  %to = trikeshed.combine %parent, %class : !s32, !s32 -> !s32
  %n2 = arith.addi %n, %n : index
  %index, %ends = trikeshed.adjacency %from, %to over %n2 : !s32, !s32 -> !sp, !s32
  %closed, %members = trikeshed.closure %index, %ends : !sp, !s32 -> !sp, !s32
  %types = trikeshed.slice %closed[%n, %n] : !sp -> !sp
  return %types, %members : !sp, !s32
}

// The lower bound of x in the ascending distinct rows xs: how many are below x.
func.func private @sumo_masks_below(%xs: !s32, %x: i32) -> i32 {
  %r = trikeshed.bisect %xs, %x : !s32, i32 -> index
  %c0 = arith.constant 0 : index
  %found = arith.cmpi sge, %r, %c0 : index
  %c1 = arith.constant 1 : index
  %neg = arith.subi %c0, %r : index
  %ins = arith.subi %neg, %c1 : index
  %at = arith.select %found, %r, %ins : index
  %at32 = arith.index_cast %at : index to i32
  return %at32 : i32
}

// The disjoint mask of every term row: for row c, (first, count) into the classes disjoint from c or from an ancestor of
// c, their descendants included, each once.  child/parent: the subclass rows; a/d: the declared disjointness, directed
// (a pair (A, B) is given both ways); n: the term rows.
func.func private @sumo_disjoint(%child: !s32, %parent: !s32, %a: !s32, %d: !s32, %n: index) -> (!sp, !s32) {
  %dd = func.call @sumo_masks_shifted(%d, %n) : (!s32, index) -> !s32
  %pd = func.call @sumo_masks_shifted(%parent, %n) : (!s32, index) -> !s32
  %cd = func.call @sumo_masks_shifted(%child, %n) : (!s32, index) -> !s32
  %from = trikeshed.combine %child, %a, %pd : !s32, !s32, !s32 -> !s32
  %to = trikeshed.combine %parent, %dd, %cd : !s32, !s32, !s32 -> !s32
  %n2 = arith.addi %n, %n : index
  %index, %ends = trikeshed.adjacency %from, %to over %n2 : !s32, !s32 -> !sp, !s32
  %closed, %members = trikeshed.closure %index, %ends : !sp, !s32 -> !sp, !s32
  // the members in the down layer, by their places in members (ascending), and as rows
  %n32 = arith.index_cast %n : index to i32
  %nm = trikeshed.size %members : !s32
  %places = trikeshed.series %nm : !s32 {
  ^bb0(%i: index):
    %i32 = arith.index_cast %i : index to i32
    trikeshed.yield %i32 : i32
  }
  %down = trikeshed.where %places : !s32 -> !s32 {
  ^bb0(%i: i32):
    %m = trikeshed.at %members[%i] : !s32, i32 -> i32
    %isDown = arith.cmpi sge, %m, %n32 : i32
    trikeshed.yield %isDown : i1
  }
  %shifted = trikeshed.project %members[%down] : !s32, !s32 -> !s32
  %zero = arith.constant 0 : i32
  %minusN = arith.subi %zero, %n32 : i32
  %minusNi = arith.index_cast %minusN : i32 to index
  %rows = func.call @sumo_masks_shifted(%shifted, %minusNi) : (!s32, index) -> !s32
  %masks = trikeshed.series %n : !sp {
  ^bb0(%k: index):
    %fc = trikeshed.at %closed[%k] : !sp, index -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %c = trikeshed.second %fc : !tp -> i32
    %e = arith.addi %f, %c : i32
    %lo = func.call @sumo_masks_below(%down, %f) : (!s32, i32) -> i32
    %hi = func.call @sumo_masks_below(%down, %e) : (!s32, i32) -> i32
    %count = arith.subi %hi, %lo : i32
    %p = trikeshed.j %lo, %count : i32, i32 -> !tp
    trikeshed.yield %p : !tp
  }
  return %masks, %rows : !sp, !s32
}

// The directed disjointness the parts of a relation like partition declare: for each top-level fact (rel W P1 .. Pm),
// m >= 2, none of its arguments a list, every (Pi, Pj) with i != j by place (a part named twice is disjoint from itself, as
// SumoClassifier pairs parts by place).  As two columns: the a and the d of @sumo_disjoint.
func.func private @sumo_parts_disjoint(%rel: i32, %facts: !facts, %terms: !terms, %kid: !s32) -> (!s32, !s32) {
  %f0 = trikeshed.key 0 : !fk
  %forms = trikeshed.column %facts[%f0] : !facts, !fk -> !s32
  %t0 = trikeshed.key 0 : !tk
  %t2 = trikeshed.key 2 : !tk
  %tag = trikeshed.column %terms[%t0] : !terms, !tk -> !s8
  %kids = trikeshed.column %terms[%t2] : !terms, !tk -> !sp
  %list = arith.constant 2 : i8
  %no = arith.constant false
  %kept = trikeshed.where %forms : !s32 -> !s32 {
  ^bb0(%t: i32):
    %tg = trikeshed.at %tag[%t] : !s8, i32 -> i8
    %isList = arith.cmpi eq, %tg, %list : i8
    %ok = scf.if %isList -> (i1) {
      %fc = trikeshed.at %kids[%t] : !sp, i32 -> !tp
      %first = trikeshed.first %fc : !tp -> i32
      %count = trikeshed.second %fc : !tp -> i32
      %four = arith.constant 4 : i32
      %long = arith.cmpi sge, %count, %four : i32
      %okLong = scf.if %long -> (i1) {
        %h = trikeshed.at %kid[%first] : !s32, i32 -> i32
        %isRel = arith.cmpi eq, %h, %rel : i32
        %one = arith.constant 1 : i32
        %a1 = arith.addi %first, %one : i32
        %na = arith.subi %count, %one : i32
        %a1i = arith.index_cast %a1 : i32 to index
        %nai = arith.index_cast %na : i32 to index
        %args = trikeshed.slice %kid[%a1i, %nai] : !s32 -> !s32
        %flat = trikeshed.fold %args, %isRel : !s32, i1 -> i1 {
        ^bb0(%acc: i1, %x: i32):
          %xt = trikeshed.at %tag[%x] : !s8, i32 -> i8
          %notList = arith.cmpi ne, %xt, %list : i8
          %both = arith.andi %acc, %notList : i1
          trikeshed.yield %both : i1
        }
        scf.yield %flat : i1
      } else {
        scf.yield %no : i1
      }
      scf.yield %okLong : i1
    } else {
      scf.yield %no : i1
    }
    trikeshed.yield %ok : i1
  }
  %nk = trikeshed.size %kept : !s32
  %pairs, %at = trikeshed.combineAll %nk : !sp, !sp {
  ^bb0(%k: index):
    %t = trikeshed.at %kept[%k] : !s32, index -> i32
    %fc = trikeshed.at %kids[%t] : !sp, i32 -> !tp
    %first = trikeshed.first %fc : !tp -> i32
    %count = trikeshed.second %fc : !tp -> i32
    // the parts: kid[first + 2 ..< first + count], m of them; m (m - 1) ordered pairs, pair r = (r / (m - 1), r % (m - 1))
    // with the second place moved past the first
    %one = arith.constant 1 : i32
    %two = arith.constant 2 : i32
    %m = arith.subi %count, %two : i32
    %m1 = arith.subi %m, %one : i32
    %np = arith.muli %m, %m1 : i32
    %npi = arith.index_cast %np : i32 to index
    %p0 = arith.addi %first, %two : i32
    %part = trikeshed.series %npi : !sp {
    ^bb0(%r: index):
      %r32 = arith.index_cast %r : index to i32
      %i = arith.divui %r32, %m1 : i32
      %jj = arith.remui %r32, %m1 : i32
      %past = arith.cmpi sge, %jj, %i : i32
      %jp = arith.addi %jj, %one : i32
      %j = arith.select %past, %jp, %jj : i32
      %xi = arith.addi %p0, %i : i32
      %xj = arith.addi %p0, %j : i32
      %x = trikeshed.at %kid[%xi] : !s32, i32 -> i32
      %y = trikeshed.at %kid[%xj] : !s32, i32 -> i32
      %xy = trikeshed.j %x, %y : i32, i32 -> !tp
      trikeshed.yield %xy : !tp
    }
    trikeshed.yield %part : !sp
  }
  %as = trikeshed.alpha %pairs : !sp -> !s32 {
  ^bb0(%p: !tp):
    %x = trikeshed.first %p : !tp -> i32
    trikeshed.yield %x : i32
  }
  %ds = trikeshed.alpha %pairs : !sp -> !s32 {
  ^bb0(%p: !tp):
    %y = trikeshed.second %p : !tp -> i32
    trikeshed.yield %y : i32
  }
  return %as, %ds : !s32, !s32
}

// The different rows of xs, ascending: sorted, then the places where a run starts.
func.func private @sumo_distinct(%xs: !s32) -> !s32 {
  %sorted = trikeshed.sorted %xs : !s32 -> !s32
  %n = trikeshed.size %sorted : !s32
  %places = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %starts = trikeshed.where %places : !s32 -> !s32 {
  ^bb0(%i: i32):
    %zero = arith.constant 0 : i32
    %first = arith.cmpi eq, %i, %zero : i32
    %start = scf.if %first -> (i1) {
      %yes = arith.constant true
      scf.yield %yes : i1
    } else {
      %one = arith.constant 1 : i32
      %ip = arith.subi %i, %one : i32
      %x = trikeshed.at %sorted[%i] : !s32, i32 -> i32
      %xp = trikeshed.at %sorted[%ip] : !s32, i32 -> i32
      %differs = arith.cmpi ne, %x, %xp : i32
      scf.yield %differs : i1
    }
    trikeshed.yield %start : i1
  }
  %rows = trikeshed.project %sorted[%starts] : !s32, !s32 -> !s32
  return %rows : !s32
}

// The rows of xs in the order of their names: bytes unsigned, then the shorter first (Nix's attrNames order).
func.func private @sumo_by_name(%xs: !s32, %names: !sp, %text: !s8) -> !s32 {
  %sorted = trikeshed.sorted %xs : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %pa = trikeshed.at %names[%a] : !sp, i32 -> !tp
    %pb = trikeshed.at %names[%b] : !sp, i32 -> !tp
    %sa = trikeshed.first %pa : !tp -> i32
    %na = trikeshed.second %pa : !tp -> i32
    %sb = trikeshed.first %pb : !tp -> i32
    %nb = trikeshed.second %pb : !tp -> i32
    %sai = arith.index_cast %sa : i32 to index
    %nai = arith.index_cast %na : i32 to index
    %sbi = arith.index_cast %sb : i32 to index
    %nbi = arith.index_cast %nb : i32 to index
    %ta = trikeshed.slice %text[%sai, %nai] : !s8 -> !s8
    %tb = trikeshed.slice %text[%sbi, %nbi] : !s8 -> !s8
    %c = trikeshed.compare %ta, %tb unsigned : !s8, !s8
    trikeshed.yield %c : i32
  }
  return %sorted : !s32
}

// The counts of a DirectChildren-shaped series at the rows xs: one i32 each.
func.func private @sumo_counts(%sets: !sp, %xs: !s32) -> !s32 {
  %counts = trikeshed.alpha %xs : !s32 -> !s32 {
  ^bb0(%r: i32):
    %fc = trikeshed.at %sets[%r] : !sp, i32 -> !tp
    %n = trikeshed.second %fc : !tp -> i32
    trikeshed.yield %n : i32
  }
  return %counts : !s32
}
