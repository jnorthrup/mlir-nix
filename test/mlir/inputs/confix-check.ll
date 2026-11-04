; Checks the Confix scanner (lib/Confix/confix.ll) against what TrikeShed's own scanners gave (confix-golden.ll, confix-golden-yaml.ll).  For every case
; it runs confix_scan_json, confix_scan_cbor or confix_scan_yaml and compares the whole Flat record; then twice more for the cases that scan through, once with the arrays
; of exactly the row count (a write past one is a fault under AddressSanitizer) and once with one row too few (the fault must be Room).  Exit
; status 0 when every case agrees.  A disagreement prints "case what" and a newline: what is 1 the fault, 2 the offset of a Bounds fault, 3
; the row count, 4 an open, 5 a close, 6 a tag, 7 a depth, 8 where the children start, 9 how many children, 10 a child, 11 no Room fault, 12 a
; nonzero offset after a scan without a fault, or after a YAML scan that stopped with a fault; plus 100 in the second run and 200 in the third.  This is test code: it reports with write(2).
; A YAML case gets room 3 * its size + 1 + its row count in the first run (the rows of a YAML text are not bounded by its size), and work of
; max(9 * (size + 1), 3 * room) words.

%confix.chars = type { i32, ptr, i32, i32, i32 }
%confix.flat = type { i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr }

declare i64 @write(i32, ptr, i64)
declare i32 @confix_scan_json(ptr, ptr)
declare i32 @confix_scan_cbor(ptr, ptr)
declare i32 @confix_scan_yaml(ptr, ptr)

@ncases = external constant i32
@in_data = external constant i8
@in_off = external constant i32
@in_syn = external constant i32
@ex_fault = external constant i32
@ex_at = external constant i32
@ex_total = external constant i32
@rows_off = external constant i32
@ex_rows = external constant i32
@kids_off = external constant i32
@ex_kids = external constant i32

define internal i32 @max1(i32 %x) alwaysinline {
  %z = icmp eq i32 %x, 0
  %r = select i1 %z, i32 1, i32 %x
  ret i32 %r
}

define internal i32 @ld(ptr %base, i32 %i) alwaysinline {
  %z = zext i32 %i to i64
  %q = getelementptr inbounds i32, ptr %base, i64 %z
  %v = load i32, ptr %q, align 4
  ret i32 %v
}

; v in decimal at buf[pos...]; the new pos
define internal i32 @dec(ptr %buf, i32 %pos, i32 %v) {
entry:
  %tmp = alloca [12 x i8], align 1
  br label %dl
dl:
  %i = phi i32 [ 12, %entry ], [ %i1, %dl ]
  %x = phi i32 [ %v, %entry ], [ %x1, %dl ]
  %i1 = sub i32 %i, 1
  %d = urem i32 %x, 10
  %x1 = udiv i32 %x, 10
  %c = add i32 %d, 48
  %cb = trunc i32 %c to i8
  %iz = zext i32 %i1 to i64
  %tp = getelementptr inbounds i8, ptr %tmp, i64 %iz
  store i8 %cb, ptr %tp, align 1
  %more = icmp ne i32 %x1, 0
  br i1 %more, label %dl, label %cp
cp:
  %j = phi i32 [ %i1, %dl ], [ %j1, %cpb ]
  %o = phi i32 [ %pos, %dl ], [ %o1, %cpb ]
  %jc = icmp ult i32 %j, 12
  br i1 %jc, label %cpb, label %out
cpb:
  %jz = zext i32 %j to i64
  %sp = getelementptr inbounds i8, ptr %tmp, i64 %jz
  %b = load i8, ptr %sp, align 1
  %oz = zext i32 %o to i64
  %dp = getelementptr inbounds i8, ptr %buf, i64 %oz
  store i8 %b, ptr %dp, align 1
  %j1 = add i32 %j, 1
  %o1 = add i32 %o, 1
  br label %cp
out:
  ret i32 %o
}

define internal void @report(i32 %case, i32 %what) {
  %buf = alloca [40 x i8], align 1
  %p1 = call i32 @dec(ptr %buf, i32 0, i32 %case)
  %p1z = zext i32 %p1 to i64
  %sp = getelementptr inbounds i8, ptr %buf, i64 %p1z
  store i8 32, ptr %sp, align 1
  %p2 = add i32 %p1, 1
  %p3 = call i32 @dec(ptr %buf, i32 %p2, i32 %what)
  %p3z = zext i32 %p3 to i64
  %nl = getelementptr inbounds i8, ptr %buf, i64 %p3z
  store i8 10, ptr %nl, align 1
  %p4 = add i32 %p3, 1
  %n = zext i32 %p4 to i64
  %w = call i64 @write(i32 2, ptr %buf, i64 %n)
  ret void
}

; 0 when case i agrees; else the number of what disagrees first.  Mode 0 gives the record room for a row a byte; mode 1 exactly as many rows as the
; case has (every array of the record of exactly its size); mode 2 one row too few, and the scan must give the fault Room.  Modes 1 and 2 are
; for the cases that scan through.
define internal i32 @check(i32 %i, i32 %mode) {
entry:
  %cs = alloca %confix.chars, align 8
  %flat = alloca %confix.flat, align 8
  %off = call i32 @ld(ptr @in_off, i32 %i)
  %i1 = add i32 %i, 1
  %end = call i32 @ld(ptr @in_off, i32 %i1)
  %size = sub i32 %end, %off
  %offz = zext i32 %off to i64
  %data = getelementptr inbounds i8, ptr @in_data, i64 %offz
  %wf0 = call i32 @ld(ptr @ex_fault, i32 %i)
  %wt0 = call i32 @ld(ptr @ex_total, i32 %i)
  %isz = icmp eq i32 %wf0, 0
  %is3 = icmp eq i32 %wf0, 3
  %fullscan = or i1 %isz, %is3
  %hasrows = icmp ne i32 %wt0, 0
  %rowsok = and i1 %fullscan, %hasrows
  %mode0 = icmp eq i32 %mode, 0
  %runs = or i1 %mode0, %rowsok
  br i1 %runs, label %setup, label %skipped
skipped:
  ret i32 0
setup:
  ; the text, the arrays of the record: each of exactly the size the scanner may use, so that a read or a write past it is a fault under
  ; AddressSanitizer (the text is copied out of the data module for the same reason)
  %mode1 = icmp eq i32 %mode, 1
  %wtm1 = sub i32 %wt0, 1
  %r12 = select i1 %mode1, i32 %wt0, i32 %wtm1
  %syn00 = call i32 @ld(ptr @in_syn, i32 %i)
  %isy0 = icmp eq i32 %syn00, 2
  %sz3 = mul i32 %size, 3
  %szy0 = add i32 %sz3, 1
  %szy = add i32 %szy0, %wt0
  %size_r = select i1 %isy0, i32 %szy, i32 %size
  %roomv = select i1 %mode0, i32 %size_r, i32 %r12
  %m = call i32 @max1(i32 %roomv)
  %tm = call i32 @max1(i32 %size)
  %m2 = shl i32 %m, 1
  %m3a = mul i32 %m, 3
  %syn0 = call i32 @ld(ptr @in_syn, i32 %i)
  %isy = icmp eq i32 %syn0, 2
  %sz1 = add i32 %size, 1
  %yw = mul i32 %sz1, 9
  %ywz = select i1 %isy, i32 %yw, i32 0
  %bigger = icmp ugt i32 %ywz, %m3a
  %m3 = select i1 %bigger, i32 %ywz, i32 %m3a
  %m1 = add i32 %m, 1
  %txt = alloca i8, i32 %tm, align 16
  %spanb = alloca i32, i32 %m2, align 16
  %tagb = alloca i8, i32 %m, align 16
  %depthb = alloca i32, i32 %m, align 16
  %startb = alloca i32, i32 %m1, align 16
  %kidb = alloca i32, i32 %m, align 16
  %workb = alloca i32, i32 %m3, align 16
  br label %copy
copy:
  %ci = phi i32 [ 0, %setup ], [ %ci1, %copyb ]
  %cc = icmp ult i32 %ci, %size
  br i1 %cc, label %copyb, label %ready
copyb:
  %ciz = zext i32 %ci to i64
  %sp = getelementptr inbounds i8, ptr %data, i64 %ciz
  %sb = load i8, ptr %sp, align 1
  %dp = getelementptr inbounds i8, ptr %txt, i64 %ciz
  store i8 %sb, ptr %dp, align 1
  %ci1 = add i32 %ci, 1
  br label %copy
ready:
  store i32 %size, ptr %cs, align 8
  %cd = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 1
  store ptr %txt, ptr %cd, align 8
  %c2 = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 2
  store i32 0, ptr %c2, align 4
  %c3 = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 3
  store i32 %size, ptr %c3, align 4
  %c4 = getelementptr inbounds %confix.chars, ptr %cs, i32 0, i32 4
  store i32 -1, ptr %c4, align 4
  %room = add i32 %roomv, 0
  %f3 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 3
  store i32 %room, ptr %f3, align 4
  %f4 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 4
  store ptr %spanb, ptr %f4, align 8
  %f5 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 5
  store ptr %tagb, ptr %f5, align 8
  %f6 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 6
  store ptr %depthb, ptr %f6, align 8
  %f7 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 7
  store ptr %startb, ptr %f7, align 8
  %f8 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 8
  store ptr %kidb, ptr %f8, align 8
  %f9 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 9
  store ptr %workb, ptr %f9, align 8
  %syn = call i32 @ld(ptr @in_syn, i32 %i)
  switch i32 %syn, label %cbor [
    i32 0, label %json
    i32 2, label %yaml
  ]
json:
  %rj = call i32 @confix_scan_json(ptr %cs, ptr %flat)
  br label %scanned
cbor:
  %rc = call i32 @confix_scan_cbor(ptr %cs, ptr %flat)
  br label %scanned
yaml:
  %ry = call i32 @confix_scan_yaml(ptr %cs, ptr %flat)
  br label %scanned
scanned:
  %got = phi i32 [ %rj, %json ], [ %rc, %cbor ], [ %ry, %yaml ]
  %short = icmp eq i32 %mode, 2
  br i1 %short, label %shortcheck, label %fullcheck
shortcheck:
  %isroom = icmp eq i32 %got, 5
  %rs = select i1 %isroom, i32 0, i32 11
  ret i32 %rs
fullcheck:
  %want = call i32 @ld(ptr @ex_fault, i32 %i)
  %fok = icmp eq i32 %got, %want
  br i1 %fok, label %f_ok, label %r1
r1:
  ret i32 1
f_ok:
  %wint = icmp eq i32 %want, 3
  %wnone = icmp eq i32 %want, 0
  %full = or i1 %wint, %wnone
  br i1 %full, label %cmp_at, label %chk_fault
chk_fault:
  ; a YAML scan that stops with a fault reports no offset
  %synf = call i32 @ld(ptr @in_syn, i32 %i)
  %isyf = icmp eq i32 %synf, 2
  br i1 %isyf, label %cmp_atf, label %pass
cmp_atf:
  %fa1 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 2
  %gat1 = load i32, ptr %fa1, align 4
  %a1ok = icmp eq i32 %gat1, 0
  br i1 %a1ok, label %pass, label %bad12
cmp_at:
  br i1 %wint, label %cmp_at2, label %cmp_at0
cmp_at0:
  %fa0 = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 2
  %gat0 = load i32, ptr %fa0, align 4
  %a0ok = icmp eq i32 %gat0, 0
  br i1 %a0ok, label %cmp_total, label %bad12
bad12:
  ret i32 12
cmp_at2:
  %fa = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 2
  %gat = load i32, ptr %fa, align 4
  %wat = call i32 @ld(ptr @ex_at, i32 %i)
  %aok = icmp eq i32 %gat, %wat
  br i1 %aok, label %cmp_total, label %r2
r2:
  ret i32 2
cmp_total:
  %ft = getelementptr inbounds %confix.flat, ptr %flat, i32 0, i32 0
  %gt = load i32, ptr %ft, align 4
  %wt = call i32 @ld(ptr @ex_total, i32 %i)
  %tok = icmp eq i32 %gt, %wt
  br i1 %tok, label %rows, label %r3
r3:
  ret i32 3
rows:
  %ro = call i32 @ld(ptr @rows_off, i32 %i)
  br label %rl
rl:
  %k = phi i32 [ 0, %rows ], [ %k1, %rl_next ]
  %kc = icmp ult i32 %k, %wt
  br i1 %kc, label %rb, label %kidscheck
rb:
  %wr = add i32 %ro, %k
  %wr6 = mul i32 %wr, 6
  %k2 = shl i32 %k, 1
  %go = call i32 @ld(ptr %spanb, i32 %k2)
  %k2p = add i32 %k2, 1
  %gc = call i32 @ld(ptr %spanb, i32 %k2p)
  %wo = call i32 @ld(ptr @ex_rows, i32 %wr6)
  %w1 = add i32 %wr6, 1
  %wc = call i32 @ld(ptr @ex_rows, i32 %w1)
  %kz = zext i32 %k to i64
  %tp = getelementptr inbounds i8, ptr %tagb, i64 %kz
  %gtag8 = load i8, ptr %tp, align 1
  %gtag = zext i8 %gtag8 to i32
  %w2 = add i32 %wr6, 2
  %wtag = call i32 @ld(ptr @ex_rows, i32 %w2)
  %gd = call i32 @ld(ptr %depthb, i32 %k)
  %w3 = add i32 %wr6, 3
  %wd = call i32 @ld(ptr @ex_rows, i32 %w3)
  %gs = call i32 @ld(ptr %startb, i32 %k)
  %ks1 = add i32 %k, 1
  %ge = call i32 @ld(ptr %startb, i32 %ks1)
  %gcount = sub i32 %ge, %gs
  %w4 = add i32 %wr6, 4
  %wfirst = call i32 @ld(ptr @ex_rows, i32 %w4)
  %w5 = add i32 %wr6, 5
  %wcount = call i32 @ld(ptr @ex_rows, i32 %w5)
  %o_ok = icmp eq i32 %go, %wo
  br i1 %o_ok, label %rb2, label %r4
r4:
  ret i32 4
rb2:
  %c_ok = icmp eq i32 %gc, %wc
  br i1 %c_ok, label %rb3, label %r5
r5:
  ret i32 5
rb3:
  %t_ok = icmp eq i32 %gtag, %wtag
  br i1 %t_ok, label %rb4, label %r6
r6:
  ret i32 6
rb4:
  %d_ok = icmp eq i32 %gd, %wd
  br i1 %d_ok, label %rb5, label %r7
r7:
  ret i32 7
rb5:
  %s_ok = icmp eq i32 %gs, %wfirst
  br i1 %s_ok, label %rb6, label %r8
r8:
  ret i32 8
rb6:
  %n_ok = icmp eq i32 %gcount, %wcount
  br i1 %n_ok, label %rl_next, label %r9
r9:
  ret i32 9
rl_next:
  %k1 = add i32 %k, 1
  br label %rl
kidscheck:
  %ko = call i32 @ld(ptr @kids_off, i32 %i)
  %kn = call i32 @ld(ptr %startb, i32 %wt)
  br label %kl
kl:
  %j = phi i32 [ 0, %kidscheck ], [ %j1, %kl_next ]
  %jc = icmp ult i32 %j, %kn
  br i1 %jc, label %kb, label %pass
kb:
  %gk = call i32 @ld(ptr %kidb, i32 %j)
  %wj = add i32 %ko, %j
  %wk = call i32 @ld(ptr @ex_kids, i32 %wj)
  %kk_ok = icmp eq i32 %gk, %wk
  br i1 %kk_ok, label %kl_next, label %r10
r10:
  ret i32 10
kl_next:
  %j1 = add i32 %j, 1
  br label %kl
pass:
  ret i32 0
}

define i32 @main() {
entry:
  %n = load i32, ptr @ncases, align 4
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %i1, %next ]
  %bad = phi i32 [ 0, %entry ], [ %bad2, %next ]
  %c = icmp ult i32 %i, %n
  br i1 %c, label %body, label %done
body:
  %m0 = call i32 @check(i32 %i, i32 0)
  %m1 = call i32 @check(i32 %i, i32 1)
  %m2 = call i32 @check(i32 %i, i32 2)
  %m1x = add i32 %m1, 100
  %m2x = add i32 %m2, 200
  %z0 = icmp eq i32 %m0, 0
  %z1 = icmp eq i32 %m1, 0
  %z2 = icmp eq i32 %m2, 0
  %t2 = select i1 %z2, i32 0, i32 %m2x
  %t1 = select i1 %z1, i32 %t2, i32 %m1x
  %r = select i1 %z0, i32 %t1, i32 %m0
  %failed = icmp ne i32 %r, 0
  br i1 %failed, label %fail, label %next
fail:
  %few = icmp ult i32 %bad, 20
  br i1 %few, label %say, label %count
say:
  call void @report(i32 %i, i32 %r)
  br label %count
count:
  %bad1 = add i32 %bad, 1
  br label %next
next:
  %bad2 = phi i32 [ %bad, %body ], [ %bad1, %count ]
  %i1 = add i32 %i, 1
  br label %loop
done:
  %ok = icmp eq i32 %bad, 0
  %rc = select i1 %ok, i32 0, i32 1
  ret i32 %rc
}
