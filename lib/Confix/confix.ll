; lib/Confix/confix.ll - TrikeShed's Confix scanner, in LLVM IR, over a CharSeries.
;
; Taken from the IR Kotlin/Native makes of borg.trikeshed.parse.confix.Syntax (scan0, scanCbor0 with readLength and parseItem, buildTree, and the
; bounds check of indexed), with the Kotlin runtime taken out: no object headers, no safepoints, no boxed Joins; the lists the Kotlin code
; grows are the arrays of the Flat record the caller hands in.  What is left is the Kotlin scan, step for step.  It uses nothing outside this
; file: no libc, no allocation, no recursion (the open containers of a CBOR text are frames in `work`), no strings.
;
;   i32 @confix_scan_json(ptr cs, ptr flat)     Syntax.scan0      + buildTree + the bounds check
;   i32 @confix_scan_cbor(ptr cs, ptr flat)     Syntax.scanCbor0  + buildTree + the bounds check
;
; cs is a CharSeries (include/Composite/CharSeries.h): its size and its data are read, from offset 0; pos, limit and mark are not.  The size is
; at most 2^31 - 1, as a Kotlin Int is.  flat is the record include/NixDialect/Confix.td describes.  The result is the fault (0 for none), also in flat.
;
; As Kotlin scans: nothing is checked.  A `]` with nothing open closes nothing, `-+-` is a number, every JSON number is a Double, a CBOR break
; with no indefinite item waiting is a Nothing, a CBOR length of 2^31 or more from four bytes is negative and so indefinite (the Int the four
; bytes make is sign-extended), and the length of a string is the low 32 bits of its Long.  Where Kotlin throws (a read past the end, the
; additional information 28 to 30) there is a fault; where it would never come back (a length that sends the position to or before the
; item) there is the fault Backward.

%confix.chars = type { i32, ptr, i32, i32, i32 }
%confix.flat = type { i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr }

attributes #0 = { nounwind "no-builtins" }
attributes #1 = { alwaysinline nounwind "no-builtins" }

; ---- the Flat record's arrays

define internal i8 @at8(ptr %s, i32 %i) #1 {
  %z = zext i32 %i to i64
  %q = getelementptr inbounds i8, ptr %s, i64 %z
  %c = load i8, ptr %q, align 1
  ret i8 %c
}

define internal void @put(ptr %span, ptr %tag, i32 %r, i32 %open, i32 %close, i8 %t) #1 {
  %rz = zext i32 %r to i64
  %r2 = shl i64 %rz, 1
  %sp = getelementptr inbounds i32, ptr %span, i64 %r2
  store i32 %open, ptr %sp, align 4
  %sp1 = getelementptr inbounds i32, ptr %sp, i64 1
  store i32 %close, ptr %sp1, align 4
  %tp = getelementptr inbounds i8, ptr %tag, i64 %rz
  store i8 %t, ptr %tp, align 1
  ret void
}

define internal void @setclose(ptr %span, i32 %r, i32 %close) #1 {
  %rz = zext i32 %r to i64
  %r2 = shl i64 %rz, 1
  %sp = getelementptr inbounds i32, ptr %span, i64 %r2
  %sp1 = getelementptr inbounds i32, ptr %sp, i64 1
  store i32 %close, ptr %sp1, align 4
  ret void
}

define internal i32 @getclose(ptr %span, i32 %r) #1 {
  %rz = zext i32 %r to i64
  %r2 = shl i64 %rz, 1
  %sp = getelementptr inbounds i32, ptr %span, i64 %r2
  %sp1 = getelementptr inbounds i32, ptr %sp, i64 1
  %v = load i32, ptr %sp1, align 4
  ret i32 %v
}

define internal i32 @getopen(ptr %span, i32 %r) #1 {
  %rz = zext i32 %r to i64
  %r2 = shl i64 %rz, 1
  %sp = getelementptr inbounds i32, ptr %span, i64 %r2
  %v = load i32, ptr %sp, align 4
  ret i32 %v
}

; a row for an element whose open and close are known (the `add` of Kotlin's scans); false when the record has no room for it
define internal i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %open, i32 %close, i8 %t) #1 {
entry:
  %r = load i32, ptr %rows, align 4
  %full = icmp uge i32 %r, %room
  br i1 %full, label %no, label %yes
yes:
  call void @put(ptr %span, ptr %tag, i32 %r, i32 %open, i32 %close, i8 %t)
  %r1 = add i32 %r, 1
  store i32 %r1, ptr %rows, align 4
  ret i1 true
no:
  ret i1 false
}

; ---- Syntax.buildTree: the rows are in the order of their opens already, so the sort is the identity; then the stack sweep
; (a span's parent is the innermost open span that still covers it), the child counts, their prefix sums, and the fill.
define internal void @build_tree(ptr %flat, i32 %total) #0 {
entry:
  %p4 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 4
  %span = load ptr, ptr %p4, align 8
  %p6 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 6
  %depth = load ptr, ptr %p6, align 8
  %p7 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 7
  %start = load ptr, ptr %p7, align 8
  %p8 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 8
  %kid = load ptr, ptr %p8, align 8
  %p9 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 9
  %stack = load ptr, ptr %p9, align 8
  %tz = zext i32 %total to i64
  %parent = getelementptr inbounds i32, ptr %stack, i64 %tz
  %t2 = shl i64 %tz, 1
  %fill = getelementptr inbounds i32, ptr %stack, i64 %t2
  br label %zero
zero:
  %zi = phi i32 [ 0, %entry ], [ %zi1, %zerob ]
  %zc = icmp ule i32 %zi, %total
  br i1 %zc, label %zerob, label %sweep
zerob:
  %zz = zext i32 %zi to i64
  %zp = getelementptr inbounds i32, ptr %start, i64 %zz
  store i32 0, ptr %zp, align 4
  %zi1 = add i32 %zi, 1
  br label %zero
sweep:
  %k = phi i32 [ 0, %zero ], [ %k1, %next ]
  %top0 = phi i32 [ 0, %zero ], [ %top2, %next ]
  %kc = icmp ult i32 %k, %total
  br i1 %kc, label %body, label %prefix
body:
  %ck = call i32 @getclose(ptr %span, i32 %k)
  br label %pop
pop:
  %top = phi i32 [ %top0, %body ], [ %topm, %popb ]
  %has = icmp ne i32 %top, 0
  br i1 %has, label %popchk, label %popdone
popchk:
  %ti = sub i32 %top, 1
  %tiz = zext i32 %ti to i64
  %srp = getelementptr inbounds i32, ptr %stack, i64 %tiz
  %srow = load i32, ptr %srp, align 4
  %cs = call i32 @getclose(ptr %span, i32 %srow)
  %less = icmp slt i32 %cs, %ck
  br i1 %less, label %popb, label %popdone
popb:
  %topm = sub i32 %top, 1
  br label %pop
popdone:
  %kz = zext i32 %k to i64
  %hast = icmp ne i32 %top, 0
  br i1 %hast, label %hasparent, label %havepar
hasparent:
  %tj = sub i32 %top, 1
  %tjz = zext i32 %tj to i64
  %pp = getelementptr inbounds i32, ptr %stack, i64 %tjz
  %prow = load i32, ptr %pp, align 4
  br label %havepar
havepar:
  %par = phi i32 [ -1, %popdone ], [ %prow, %hasparent ]
  %pap = getelementptr inbounds i32, ptr %parent, i64 %kz
  store i32 %par, ptr %pap, align 4
  %dp = getelementptr inbounds i32, ptr %depth, i64 %kz
  store i32 %top, ptr %dp, align 4
  br i1 %hast, label %count, label %push
count:
  %par1 = add i32 %par, 1
  %par1z = zext i32 %par1 to i64
  %scp = getelementptr inbounds i32, ptr %start, i64 %par1z
  %sc = load i32, ptr %scp, align 4
  %sc1 = add i32 %sc, 1
  store i32 %sc1, ptr %scp, align 4
  br label %push
push:
  %topz = zext i32 %top to i64
  %stp = getelementptr inbounds i32, ptr %stack, i64 %topz
  store i32 %k, ptr %stp, align 4
  %top2 = add i32 %top, 1
  br label %next
next:
  %k1 = add i32 %k, 1
  br label %sweep
prefix:
  %q = phi i32 [ 0, %sweep ], [ %q1, %prefixb ]
  %qc = icmp ult i32 %q, %total
  br i1 %qc, label %prefixb, label %copy
prefixb:
  %qz = zext i32 %q to i64
  %qp = getelementptr inbounds i32, ptr %start, i64 %qz
  %qa = load i32, ptr %qp, align 4
  %qp1 = getelementptr inbounds i32, ptr %qp, i64 1
  %qb = load i32, ptr %qp1, align 4
  %qs = add i32 %qb, %qa
  store i32 %qs, ptr %qp1, align 4
  %q1 = add i32 %q, 1
  br label %prefix
copy:
  %ci = phi i32 [ 0, %prefix ], [ %ci1, %copyb ]
  %cc = icmp ult i32 %ci, %total
  br i1 %cc, label %copyb, label %kids
copyb:
  %cz = zext i32 %ci to i64
  %cs0 = getelementptr inbounds i32, ptr %start, i64 %cz
  %cv = load i32, ptr %cs0, align 4
  %cf = getelementptr inbounds i32, ptr %fill, i64 %cz
  store i32 %cv, ptr %cf, align 4
  %ci1 = add i32 %ci, 1
  br label %copy
kids:
  %ki = phi i32 [ 0, %copy ], [ %ki1, %kidnext ]
  %kcnd = icmp ult i32 %ki, %total
  br i1 %kcnd, label %kidb, label %done
kidb:
  %kiz = zext i32 %ki to i64
  %kpp = getelementptr inbounds i32, ptr %parent, i64 %kiz
  %kpar = load i32, ptr %kpp, align 4
  %kok = icmp sge i32 %kpar, 0
  br i1 %kok, label %kidput, label %kidnext
kidput:
  %kparz = zext i32 %kpar to i64
  %kfp = getelementptr inbounds i32, ptr %fill, i64 %kparz
  %kslot = load i32, ptr %kfp, align 4
  %kslotz = zext i32 %kslot to i64
  %kkp = getelementptr inbounds i32, ptr %kid, i64 %kslotz
  store i32 %ki, ptr %kkp, align 4
  %kslot1 = add i32 %kslot, 1
  store i32 %kslot1, ptr %kfp, align 4
  br label %kidnext
kidnext:
  %ki1 = add i32 %ki, 1
  br label %kids
done:
  ret void
}

; Syntax.indexed's check, for the rows in order: the first row whose span is past the text, else -1.
define internal i32 @bounds(ptr %span, i32 %total, i32 %n) #0 {
entry:
  br label %loop
loop:
  %k = phi i32 [ 0, %entry ], [ %k1, %next ]
  %c = icmp ult i32 %k, %total
  br i1 %c, label %body, label %none
body:
  %o = call i32 @getopen(ptr %span, i32 %k)
  %e = call i32 @getclose(ptr %span, i32 %k)
  %rev = icmp slt i32 %e, %o
  %nn = icmp sge i32 %o, 0
  %inb = icmp slt i32 %e, %n
  %fit = and i1 %nn, %inb
  %ok = or i1 %rev, %fit
  br i1 %ok, label %next, label %bad
next:
  %k1 = add i32 %k, 1
  br label %loop
bad:
  ret i32 %k
none:
  ret i32 -1
}

; the end of every scan: the tree and the check when nothing went wrong, then total, fault and at into the record
define internal i32 @fin(ptr %flat, i32 %total, i32 %n, i32 %fault, i32 %at) #0 {
entry:
  %ok = icmp eq i32 %fault, 0
  br i1 %ok, label %tree, label %out
tree:
  call void @build_tree(ptr %flat, i32 %total)
  %p4 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 4
  %span = load ptr, ptr %p4, align 8
  %bad = call i32 @bounds(ptr %span, i32 %total, i32 %n)
  %isbad = icmp sge i32 %bad, 0
  %f2 = select i1 %isbad, i32 3, i32 0
  %a2 = select i1 %isbad, i32 %bad, i32 0
  br label %out
out:
  %ff = phi i32 [ %fault, %entry ], [ %f2, %tree ]
  %aa = phi i32 [ %at, %entry ], [ %a2, %tree ]
  %q0 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 0
  store i32 %total, ptr %q0, align 4
  %q1 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 1
  store i32 %ff, ptr %q1, align 4
  %q2 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 2
  store i32 %aa, ptr %q2, align 4
  ret i32 %ff
}

; ---- Syntax.scan0

; Kotlin's push: a row for an element that is still open, on the stack of open rows (the stack is the front of `work`)
define internal i1 @jpush(ptr %span, ptr %tag, ptr %work, ptr %rows, ptr %sp, i32 %room, i32 %open, i8 %t) #1 {
entry:
  %r = load i32, ptr %rows, align 4
  %full = icmp uge i32 %r, %room
  br i1 %full, label %no, label %yes
yes:
  call void @put(ptr %span, ptr %tag, i32 %r, i32 %open, i32 %open, i8 %t)
  %s0 = load i32, ptr %sp, align 4
  %sz = zext i32 %s0 to i64
  %wp = getelementptr inbounds i32, ptr %work, i64 %sz
  store i32 %r, ptr %wp, align 4
  %s1 = add i32 %s0, 1
  store i32 %s1, ptr %sp, align 4
  %r1 = add i32 %r, 1
  store i32 %r1, ptr %rows, align 4
  ret i1 true
no:
  ret i1 false
}

; Kotlin's pop: with nothing open it does nothing
define internal void @jpop(ptr %span, ptr %work, ptr %sp, i32 %close) #1 {
entry:
  %s0 = load i32, ptr %sp, align 4
  %z = icmp eq i32 %s0, 0
  br i1 %z, label %out, label %go
go:
  %s1 = sub i32 %s0, 1
  store i32 %s1, ptr %sp, align 4
  %sz = zext i32 %s1 to i64
  %wp = getelementptr inbounds i32, ptr %work, i64 %sz
  %r = load i32, ptr %wp, align 4
  call void @setclose(ptr %span, i32 %r, i32 %close)
  br label %out
out:
  ret void
}

define i32 @confix_scan_json(ptr %cs, ptr %flat) #0 {
entry:
  %n = load i32, ptr %cs, align 8
  %dp = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 1
  %s = load ptr, ptr %dp, align 8
  %rp = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 3
  %room = load i32, ptr %rp, align 4
  %p4 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 4
  %span = load ptr, ptr %p4, align 8
  %p5 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 5
  %tag = load ptr, ptr %p5, align 8
  %p9 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 9
  %work = load ptr, ptr %p9, align 8
  %rows = alloca i32, align 4
  %sp = alloca i32, align 4
  %i = alloca i32, align 4
  %inq = alloca i1, align 1
  %esc = alloca i1, align 1
  store i32 0, ptr %rows, align 4
  store i32 0, ptr %sp, align 4
  store i32 0, ptr %i, align 4
  store i1 false, ptr %inq, align 1
  store i1 false, ptr %esc, align 1
  br label %loop

loop:
  %iv = load i32, ptr %i, align 4
  %end = icmp uge i32 %iv, %n
  br i1 %end, label %flush, label %body

body:
  %c = call i8 @at8(ptr %s, i32 %iv)
  %q = load i1, ptr %inq, align 1
  br i1 %q, label %inquote, label %outside

inquote:
  %e = load i1, ptr %esc, align 1
  br i1 %e, label %unesc, label %q2
unesc:
  store i1 false, ptr %esc, align 1
  br label %next
q2:
  %isbs = icmp eq i8 %c, 92
  br i1 %isbs, label %setesc, label %q3
setesc:
  store i1 true, ptr %esc, align 1
  br label %next
q3:
  %isq = icmp eq i8 %c, 34
  br i1 %isq, label %closestr, label %next
closestr:
  store i1 false, ptr %inq, align 1
  call void @jpop(ptr %span, ptr %work, ptr %sp, i32 %iv)
  br label %next

outside:
  switch i8 %c, label %other [
    i8 123, label %open_obj
    i8 91, label %open_arr
    i8 125, label %shut
    i8 93, label %shut
    i8 34, label %open_str
    i8 116, label %lit_t
    i8 102, label %lit_f
    i8 110, label %lit_n
    i8 45, label %number
    i8 43, label %number
  ]
other:
  %dd = sub i8 %c, 48
  %isd = icmp ule i8 %dd, 9
  br i1 %isd, label %number, label %next

open_obj:
  %okA = call i1 @jpush(ptr %span, ptr %tag, ptr %work, ptr %rows, ptr %sp, i32 %room, i32 %iv, i8 5)
  br i1 %okA, label %next, label %roomfault
open_arr:
  %okB = call i1 @jpush(ptr %span, ptr %tag, ptr %work, ptr %rows, ptr %sp, i32 %room, i32 %iv, i8 6)
  br i1 %okB, label %next, label %roomfault
shut:
  call void @jpop(ptr %span, ptr %work, ptr %sp, i32 %iv)
  br label %next
open_str:
  %okC = call i1 @jpush(ptr %span, ptr %tag, ptr %work, ptr %rows, ptr %sp, i32 %room, i32 %iv, i8 4)
  store i1 true, ptr %inq, align 1
  br i1 %okC, label %next, label %roomfault

lit_t:
  %rt = sub i32 %n, %iv
  %okt = icmp ugt i32 %rt, 3
  br i1 %okt, label %lt1, label %next
lt1:
  %t1i = add i32 %iv, 1
  %t1 = call i8 @at8(ptr %s, i32 %t1i)
  %t1ok = icmp eq i8 %t1, 114
  %t2i = add i32 %iv, 2
  %t2 = call i8 @at8(ptr %s, i32 %t2i)
  %t2ok = icmp eq i8 %t2, 117
  %t3i = add i32 %iv, 3
  %t3 = call i8 @at8(ptr %s, i32 %t3i)
  %t3ok = icmp eq i8 %t3, 101
  %ta = and i1 %t1ok, %t2ok
  %tb = and i1 %ta, %t3ok
  br i1 %tb, label %lt_ok, label %next
lt_ok:
  %okD = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %iv, i32 %t3i, i8 1)
  store i32 %t3i, ptr %i, align 4
  br i1 %okD, label %next, label %roomfault

lit_f:
  %rf = sub i32 %n, %iv
  %okf = icmp ugt i32 %rf, 4
  br i1 %okf, label %lf1, label %next
lf1:
  %f1i = add i32 %iv, 1
  %f1 = call i8 @at8(ptr %s, i32 %f1i)
  %f1ok = icmp eq i8 %f1, 97
  %f2i = add i32 %iv, 2
  %f2 = call i8 @at8(ptr %s, i32 %f2i)
  %f2ok = icmp eq i8 %f2, 108
  %f3i = add i32 %iv, 3
  %f3 = call i8 @at8(ptr %s, i32 %f3i)
  %f3ok = icmp eq i8 %f3, 115
  %f4i = add i32 %iv, 4
  %f4 = call i8 @at8(ptr %s, i32 %f4i)
  %f4ok = icmp eq i8 %f4, 101
  %fa = and i1 %f1ok, %f2ok
  %fb = and i1 %f3ok, %f4ok
  %fc = and i1 %fa, %fb
  br i1 %fc, label %lf_ok, label %next
lf_ok:
  %okE = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %iv, i32 %f4i, i8 1)
  store i32 %f4i, ptr %i, align 4
  br i1 %okE, label %next, label %roomfault

lit_n:
  %rn = sub i32 %n, %iv
  %okn = icmp ugt i32 %rn, 3
  br i1 %okn, label %ln1, label %next
ln1:
  %n1i = add i32 %iv, 1
  %n1 = call i8 @at8(ptr %s, i32 %n1i)
  %n1ok = icmp eq i8 %n1, 117
  %n2i = add i32 %iv, 2
  %n2 = call i8 @at8(ptr %s, i32 %n2i)
  %n2ok = icmp eq i8 %n2, 108
  %n3i = add i32 %iv, 3
  %n3 = call i8 @at8(ptr %s, i32 %n3i)
  %n3ok = icmp eq i8 %n3, 108
  %na = and i1 %n1ok, %n2ok
  %nb = and i1 %na, %n3ok
  br i1 %nb, label %ln_ok, label %next
ln_ok:
  %okF = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %iv, i32 %n3i, i8 0)
  store i32 %n3i, ptr %i, align 4
  br i1 %okF, label %next, label %roomfault

number:
  br label %numl
numl:
  %j = phi i32 [ %iv, %number ], [ %j1, %numb ]
  %jin = icmp ult i32 %j, %n
  br i1 %jin, label %numc, label %numend
numc:
  %d = call i8 @at8(ptr %s, i32 %j)
  %dg = sub i8 %d, 48
  %d1 = icmp ule i8 %dg, 9
  %d2 = icmp eq i8 %d, 46
  %dl = or i8 %d, 32
  %d3 = icmp eq i8 %dl, 101
  %d4 = icmp eq i8 %d, 43
  %d5 = icmp eq i8 %d, 45
  %da = or i1 %d1, %d2
  %db = or i1 %d3, %d4
  %dc = or i1 %db, %d5
  %dd2 = or i1 %da, %dc
  br i1 %dd2, label %numb, label %numend
numb:
  %j1 = add i32 %j, 1
  br label %numl
numend:
  %je = phi i32 [ %j, %numl ], [ %j, %numc ]
  %jm = sub i32 %je, 1
  %okG = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %iv, i32 %jm, i8 3)
  store i32 %je, ptr %i, align 4
  br i1 %okG, label %loop, label %roomfault

next:
  %ivn = load i32, ptr %i, align 4
  %ip1 = add i32 %ivn, 1
  store i32 %ip1, ptr %i, align 4
  br label %loop

flush:
  %nm1 = sub i32 %n, 1
  br label %fl
fl:
  %fs = load i32, ptr %sp, align 4
  %fnz = icmp ne i32 %fs, 0
  br i1 %fnz, label %flb, label %built
flb:
  call void @jpop(ptr %span, ptr %work, ptr %sp, i32 %nm1)
  br label %fl
built:
  %total = load i32, ptr %rows, align 4
  %r = call i32 @fin(ptr %flat, i32 %total, i32 %n, i32 0, i32 0)
  ret i32 %r

roomfault:
  %rtot = load i32, ptr %rows, align 4
  %rat = load i32, ptr %i, align 4
  %rr = call i32 @fin(ptr %flat, i32 %rtot, i32 %n, i32 5, i32 %rat)
  ret i32 %rr
}

; ---- Syntax.scanCbor0

; Kotlin's readLength at `p`, for the additional information `ai`: { the Long, where the text goes on, the fault }.  On a fault the second
; is the offset it was found at.  The fault is 1 for a read past the end, 2 for the additional information 28 to 30 (Kotlin's error).
define internal { i64, i32, i32 } @readlen(ptr %s, i32 %n, i32 %p, i32 %ai) #0 {
entry:
  %small = icmp ule i32 %ai, 23
  br i1 %small, label %direct, label %wide
direct:
  %dv = zext i32 %ai to i64
  %d0 = insertvalue { i64, i32, i32 } undef, i64 %dv, 0
  %d1 = insertvalue { i64, i32, i32 } %d0, i32 %p, 1
  %d2 = insertvalue { i64, i32, i32 } %d1, i32 0, 2
  ret { i64, i32, i32 } %d2
wide:
  %pz = zext i32 %p to i64
  %nz = zext i32 %n to i64
  switch i32 %ai, label %reserved [
    i32 24, label %a24
    i32 25, label %a25
    i32 26, label %a26
    i32 27, label %a27
    i32 31, label %a31
  ]
a24:
  %e24 = add i64 %pz, 1
  %o24 = icmp ule i64 %e24, %nz
  br i1 %o24, label %a24ok, label %trunc
a24ok:
  %b24 = call i8 @at8(ptr %s, i32 %p)
  %v24 = zext i8 %b24 to i64
  %x24 = add i32 %p, 1
  %r24a = insertvalue { i64, i32, i32 } undef, i64 %v24, 0
  %r24b = insertvalue { i64, i32, i32 } %r24a, i32 %x24, 1
  %r24c = insertvalue { i64, i32, i32 } %r24b, i32 0, 2
  ret { i64, i32, i32 } %r24c
a25:
  %e25 = add i64 %pz, 2
  %o25 = icmp ule i64 %e25, %nz
  br i1 %o25, label %a25ok, label %trunc
a25ok:
  %b250 = call i8 @at8(ptr %s, i32 %p)
  %p251 = add i32 %p, 1
  %b251 = call i8 @at8(ptr %s, i32 %p251)
  %z250 = zext i8 %b250 to i32
  %z251 = zext i8 %b251 to i32
  %h250 = shl i32 %z250, 8
  %v25i = or i32 %h250, %z251
  %v25 = sext i32 %v25i to i64
  %x25 = add i32 %p, 2
  %r25a = insertvalue { i64, i32, i32 } undef, i64 %v25, 0
  %r25b = insertvalue { i64, i32, i32 } %r25a, i32 %x25, 1
  %r25c = insertvalue { i64, i32, i32 } %r25b, i32 0, 2
  ret { i64, i32, i32 } %r25c
a26:
  %e26 = add i64 %pz, 4
  %o26 = icmp ule i64 %e26, %nz
  br i1 %o26, label %a26ok, label %trunc
a26ok:
  %b260 = call i8 @at8(ptr %s, i32 %p)
  %p261 = add i32 %p, 1
  %b261 = call i8 @at8(ptr %s, i32 %p261)
  %p262 = add i32 %p, 2
  %b262 = call i8 @at8(ptr %s, i32 %p262)
  %p263 = add i32 %p, 3
  %b263 = call i8 @at8(ptr %s, i32 %p263)
  %z260 = zext i8 %b260 to i32
  %z261 = zext i8 %b261 to i32
  %z262 = zext i8 %b262 to i32
  %z263 = zext i8 %b263 to i32
  %h260 = shl i32 %z260, 24
  %h261 = shl i32 %z261, 16
  %h262 = shl i32 %z262, 8
  %m260 = or i32 %h260, %h261
  %m261 = or i32 %m260, %h262
  %v26i = or i32 %m261, %z263
  %v26 = sext i32 %v26i to i64
  %x26 = add i32 %p, 4
  %r26a = insertvalue { i64, i32, i32 } undef, i64 %v26, 0
  %r26b = insertvalue { i64, i32, i32 } %r26a, i32 %x26, 1
  %r26c = insertvalue { i64, i32, i32 } %r26b, i32 0, 2
  ret { i64, i32, i32 } %r26c
a27:
  %e27 = add i64 %pz, 8
  %o27 = icmp ule i64 %e27, %nz
  br i1 %o27, label %a27l, label %trunc
a27l:
  %k27 = phi i32 [ 0, %a27 ], [ %k271, %a27b ]
  %acc = phi i64 [ 0, %a27 ], [ %acc2, %a27b ]
  %kc27 = icmp ult i32 %k27, 8
  br i1 %kc27, label %a27b, label %a27d
a27b:
  %pk = add i32 %p, %k27
  %bk = call i8 @at8(ptr %s, i32 %pk)
  %zk = zext i8 %bk to i64
  %sh = shl i64 %acc, 8
  %acc2 = or i64 %sh, %zk
  %k271 = add i32 %k27, 1
  br label %a27l
a27d:
  %x27 = add i32 %p, 8
  %r27a = insertvalue { i64, i32, i32 } undef, i64 %acc, 0
  %r27b = insertvalue { i64, i32, i32 } %r27a, i32 %x27, 1
  %r27c = insertvalue { i64, i32, i32 } %r27b, i32 0, 2
  ret { i64, i32, i32 } %r27c
a31:
  %r31a = insertvalue { i64, i32, i32 } undef, i64 -1, 0
  %r31b = insertvalue { i64, i32, i32 } %r31a, i32 %p, 1
  %r31c = insertvalue { i64, i32, i32 } %r31b, i32 0, 2
  ret { i64, i32, i32 } %r31c
reserved:
  %hp = sub i32 %p, 1
  %rra = insertvalue { i64, i32, i32 } undef, i64 0, 0
  %rrb = insertvalue { i64, i32, i32 } %rra, i32 %hp, 1
  %rrc = insertvalue { i64, i32, i32 } %rrb, i32 2, 2
  ret { i64, i32, i32 } %rrc
trunc:
  %ge = icmp uge i32 %p, %n
  %at = select i1 %ge, i32 %p, i32 %n
  %tra = insertvalue { i64, i32, i32 } undef, i64 0, 0
  %trb = insertvalue { i64, i32, i32 } %tra, i32 %at, 1
  %trc = insertvalue { i64, i32, i32 } %trb, i32 1, 2
  ret { i64, i32, i32 } %trc
}

; The scan is Kotlin's parseItem with its recursion turned into frames.  A frame is three u32 in `work`: the row of the open container, how many
; items it still takes (a definite one) and flags: 1 indefinite, 2 a map, 4 "its next item is a value": in an indefinite map the key and its
; value are read with one test of the break byte between pairs, not one between them.  Rows are made as their elements open, so they are in the
; order of their opens as buildTree needs, which is the order Kotlin sorts them into.
define i32 @confix_scan_cbor(ptr %cs, ptr %flat) #0 {
entry:
  %n = load i32, ptr %cs, align 8
  %dp = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 1
  %s = load ptr, ptr %dp, align 8
  %rp = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 3
  %room = load i32, ptr %rp, align 4
  %p4 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 4
  %span = load ptr, ptr %p4, align 8
  %p5 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 5
  %tag = load ptr, ptr %p5, align 8
  %p9 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 9
  %work = load ptr, ptr %p9, align 8
  %pos = alloca i32, align 4
  %rows = alloca i32, align 4
  %fp = alloca i32, align 4
  %fault = alloca i32, align 4
  %fat = alloca i32, align 4
  store i32 0, ptr %pos, align 4
  store i32 0, ptr %rows, align 4
  store i32 0, ptr %fp, align 4
  store i32 0, ptr %fault, align 4
  store i32 0, ptr %fat, align 4
  br label %top

top:
  %fpv = load i32, ptr %fp, align 4
  %noframe = icmp eq i32 %fpv, 0
  br i1 %noframe, label %top_root, label %top_frame

top_root:
  %pr = load i32, ptr %pos, align 4
  %more = icmp slt i32 %pr, %n
  br i1 %more, label %parse, label %end

top_frame:
  %fi = sub i32 %fpv, 1
  %fz = zext i32 %fi to i64
  %f3 = mul i64 %fz, 3
  %fb = getelementptr inbounds i32, ptr %work, i64 %f3
  %frow = load i32, ptr %fb, align 4
  %fremp = getelementptr inbounds i32, ptr %fb, i64 1
  %frem = load i32, ptr %fremp, align 4
  %fflp = getelementptr inbounds i32, ptr %fb, i64 2
  %ffl = load i32, ptr %fflp, align 4
  %fi1 = and i32 %ffl, 1
  %indef = icmp ne i32 %fi1, 0
  br i1 %indef, label %f_indef, label %f_def

f_def:
  %rem_gt = icmp sgt i32 %frem, 0
  br i1 %rem_gt, label %f_def_take, label %finish
f_def_take:
  %rem1 = sub i32 %frem, 1
  store i32 %rem1, ptr %fremp, align 4
  br label %parse

f_indef:
  %pd = and i32 %ffl, 4
  %pending = icmp ne i32 %pd, 0
  br i1 %pending, label %f_value, label %f_chk
f_value:
  %fl_clr = and i32 %ffl, -5
  store i32 %fl_clr, ptr %fflp, align 4
  br label %parse
f_chk:
  %pc = load i32, ptr %pos, align 4
  %lt = icmp slt i32 %pc, %n
  br i1 %lt, label %f_chk2, label %finish
f_chk2:
  %inr = icmp ult i32 %pc, %n
  br i1 %inr, label %f_chk3, label %trunc_pc
f_chk3:
  %bb = call i8 @at8(ptr %s, i32 %pc)
  %isbrk = icmp eq i8 %bb, -1
  br i1 %isbrk, label %finish, label %f_take
f_take:
  %fm = and i32 %ffl, 2
  %ismap = icmp ne i32 %fm, 0
  %fl_set = or i32 %ffl, 4
  %fl_new = select i1 %ismap, i32 %fl_set, i32 %ffl
  store i32 %fl_new, ptr %fflp, align 4
  br label %parse

finish:
  %pf = load i32, ptr %pos, align 4
  %inb = icmp slt i32 %pf, %n
  %consume = and i1 %indef, %inb
  %pf1 = add i32 %pf, 1
  %pf2 = select i1 %consume, i32 %pf1, i32 %pf
  store i32 %pf2, ptr %pos, align 4
  %fclose = sub i32 %pf2, 1
  call void @setclose(ptr %span, i32 %frow, i32 %fclose)
  store i32 %fi, ptr %fp, align 4
  br label %top

parse:
  %pp = load i32, ptr %pos, align 4
  %pin = icmp ult i32 %pp, %n
  br i1 %pin, label %head, label %trunc_pp

head:
  %ib = call i8 @at8(ptr %s, i32 %pp)
  %ibz = zext i8 %ib to i32
  %major = lshr i32 %ibz, 5
  %ai = and i32 %ibz, 31
  %p1h = add i32 %pp, 1
  switch i32 %major, label %m7 [
    i32 0, label %m01
    i32 1, label %m01
    i32 2, label %m23
    i32 3, label %m23
    i32 4, label %m45
    i32 5, label %m45
    i32 6, label %m6
  ]

m01:
  %r01 = call { i64, i32, i32 } @readlen(ptr %s, i32 %n, i32 %p1h, i32 %ai)
  %f01 = extractvalue { i64, i32, i32 } %r01, 2
  %bad01 = icmp ne i32 %f01, 0
  br i1 %bad01, label %rl_fault01, label %m01b
rl_fault01:
  %a01 = extractvalue { i64, i32, i32 } %r01, 1
  br label %rl_fault
m01b:
  %nx01 = extractvalue { i64, i32, i32 } %r01, 1
  %c01 = sub i32 %nx01, 1
  %ok01 = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %pp, i32 %c01, i8 2)
  br i1 %ok01, label %m01c, label %roomfault
m01c:
  store i32 %nx01, ptr %pos, align 4
  br label %top

m23:
  %r23 = call { i64, i32, i32 } @readlen(ptr %s, i32 %n, i32 %p1h, i32 %ai)
  %f23 = extractvalue { i64, i32, i32 } %r23, 2
  %bad23 = icmp ne i32 %f23, 0
  br i1 %bad23, label %rl_fault23, label %m23b
rl_fault23:
  %a23 = extractvalue { i64, i32, i32 } %r23, 1
  br label %rl_fault
m23b:
  %len23 = extractvalue { i64, i32, i32 } %r23, 0
  %nx23 = extractvalue { i64, i32, i32 } %r23, 1
  %indef23 = icmp slt i64 %len23, 0
  br i1 %indef23, label %m23_skip, label %m23_item
m23_skip:
  store i32 %nx23, ptr %pos, align 4
  br label %top
m23_item:
  %l32 = trunc i64 %len23 to i32
  %np23 = add i32 %nx23, %l32
  %c23 = sub i32 %np23, 1
  %fwd = icmp sgt i32 %np23, %pp
  br i1 %fwd, label %m23_add, label %m23_back
m23_back:
  %negp = icmp slt i32 %np23, 0
  br i1 %negp, label %trunc_np, label %backward
m23_add:
  %is2 = icmp eq i32 %major, 2
  %t23 = select i1 %is2, i8 7, i8 4
  %ok23 = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %pp, i32 %c23, i8 %t23)
  br i1 %ok23, label %m23_done, label %roomfault
m23_done:
  store i32 %np23, ptr %pos, align 4
  br label %top

m45:
  %r45 = call { i64, i32, i32 } @readlen(ptr %s, i32 %n, i32 %p1h, i32 %ai)
  %f45 = extractvalue { i64, i32, i32 } %r45, 2
  %bad45 = icmp ne i32 %f45, 0
  br i1 %bad45, label %rl_fault45, label %m45b
rl_fault45:
  %a45 = extractvalue { i64, i32, i32 } %r45, 1
  br label %rl_fault
m45b:
  %len45 = extractvalue { i64, i32, i32 } %r45, 0
  %nx45 = extractvalue { i64, i32, i32 } %r45, 1
  %is4 = icmp eq i32 %major, 4
  %t45 = select i1 %is4, i8 6, i8 5
  %ok45 = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %pp, i32 %pp, i8 %t45)
  br i1 %ok45, label %m45c, label %roomfault
m45c:
  %row45 = load i32, ptr %rows, align 4
  %rowid = sub i32 %row45, 1
  %ind45 = icmp slt i64 %len45, 0
  %l45 = trunc i64 %len45 to i32
  %dbl = shl i32 %l45, 1
  %cnt = select i1 %is4, i32 %l45, i32 %dbl
  %neg = icmp slt i32 %cnt, 0
  %cnt1 = select i1 %neg, i32 0, i32 %cnt
  %rem45 = select i1 %ind45, i32 0, i32 %cnt1
  %fl_i = select i1 %ind45, i32 1, i32 0
  %fl_m = select i1 %is4, i32 0, i32 2
  %fl45 = or i32 %fl_i, %fl_m
  %fpn = load i32, ptr %fp, align 4
  %fnz = zext i32 %fpn to i64
  %fn3 = mul i64 %fnz, 3
  %nb = getelementptr inbounds i32, ptr %work, i64 %fn3
  store i32 %rowid, ptr %nb, align 4
  %nbr = getelementptr inbounds i32, ptr %nb, i64 1
  store i32 %rem45, ptr %nbr, align 4
  %nbf = getelementptr inbounds i32, ptr %nb, i64 2
  store i32 %fl45, ptr %nbf, align 4
  %fpn1 = add i32 %fpn, 1
  store i32 %fpn1, ptr %fp, align 4
  store i32 %nx45, ptr %pos, align 4
  br label %top

m6:
  %r6 = call { i64, i32, i32 } @readlen(ptr %s, i32 %n, i32 %p1h, i32 %ai)
  %f6 = extractvalue { i64, i32, i32 } %r6, 2
  %bad6 = icmp ne i32 %f6, 0
  br i1 %bad6, label %rl_fault6, label %m6b
rl_fault6:
  %a6 = extractvalue { i64, i32, i32 } %r6, 1
  br label %rl_fault
m6b:
  %nx6 = extractvalue { i64, i32, i32 } %r6, 1
  store i32 %nx6, ptr %pos, align 4
  br label %parse

m7:
  %e20 = icmp eq i32 %ai, 20
  %e21 = icmp eq i32 %ai, 21
  %e24 = icmp eq i32 %ai, 24
  %e25 = icmp eq i32 %ai, 25
  %e26 = icmp eq i32 %ai, 26
  %e27 = icmp eq i32 %ai, 27
  %isbool = or i1 %e20, %e21
  %isdbl1 = or i1 %e25, %e26
  %isdbl = or i1 %isdbl1, %e27
  %t7a = select i1 %isdbl, i8 3, i8 0
  %t7 = select i1 %isbool, i8 1, i8 %t7a
  %z24 = select i1 %e24, i32 1, i32 0
  %z25 = select i1 %e25, i32 2, i32 %z24
  %z26 = select i1 %e26, i32 4, i32 %z25
  %sz7 = select i1 %e27, i32 8, i32 %z26
  %c7 = add i32 %pp, %sz7
  %ok7 = call i1 @add(ptr %span, ptr %tag, ptr %rows, i32 %room, i32 %pp, i32 %c7, i8 %t7)
  br i1 %ok7, label %m7b, label %roomfault
m7b:
  %np7a = add i32 %pp, 1
  %np7 = add i32 %np7a, %sz7
  store i32 %np7, ptr %pos, align 4
  br label %top

end:
  %total = load i32, ptr %rows, align 4
  %rend = call i32 @fin(ptr %flat, i32 %total, i32 %n, i32 0, i32 0)
  ret i32 %rend

rl_fault:
  %rlf = phi i32 [ %f01, %rl_fault01 ], [ %f23, %rl_fault23 ], [ %f45, %rl_fault45 ], [ %f6, %rl_fault6 ]
  %rla = phi i32 [ %a01, %rl_fault01 ], [ %a23, %rl_fault23 ], [ %a45, %rl_fault45 ], [ %a6, %rl_fault6 ]
  %rlt = load i32, ptr %rows, align 4
  %rlr = call i32 @fin(ptr %flat, i32 %rlt, i32 %n, i32 %rlf, i32 %rla)
  ret i32 %rlr
trunc_pc:
  %tct = load i32, ptr %rows, align 4
  %tcr = call i32 @fin(ptr %flat, i32 %tct, i32 %n, i32 1, i32 %pc)
  ret i32 %tcr
trunc_np:
  %tnt = load i32, ptr %rows, align 4
  %tnr = call i32 @fin(ptr %flat, i32 %tnt, i32 %n, i32 1, i32 %np23)
  ret i32 %tnr
trunc_pp:
  %tpt = load i32, ptr %rows, align 4
  %tpr = call i32 @fin(ptr %flat, i32 %tpt, i32 %n, i32 1, i32 %pp)
  ret i32 %tpr
backward:
  %bwt = load i32, ptr %rows, align 4
  %bwr = call i32 @fin(ptr %flat, i32 %bwt, i32 %n, i32 4, i32 %pp)
  ret i32 %bwr
roomfault:
  %rmt = load i32, ptr %rows, align 4
  %rmp = load i32, ptr %pos, align 4
  %rmr = call i32 @fin(ptr %flat, i32 %rmt, i32 %n, i32 5, i32 %rmp)
  ret i32 %rmr
}
