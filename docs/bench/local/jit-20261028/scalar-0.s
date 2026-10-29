	.build_version macos, 15, 0
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_scalar                         ; -- Begin function scalar
	.p2align	2
_scalar:                                ; @scalar
; %bb.0:
	mov	w8, #3                          ; =0x3
	add	x9, x0, x0, lsl #1
	smulh	x8, x0, x8
	asr	x10, x9, #63
	subs	x9, x9, #1
	asr	x11, x9, #63
	sbc	x12, x10, xzr
	adds	x9, x9, #7
	cinc	x13, x11, hs
	str	x9, [x1]
	cmp	x8, x10
	eor	x8, x13, x9, asr #63
	ccmp	x12, x11, #0, eq
	ccmp	x8, #0, #0, eq
	cset	w0, ne
	ret
                                        ; -- End function
	.globl	__mlir_scalar                   ; -- Begin function _mlir_scalar
	.p2align	2
__mlir_scalar:                          ; @_mlir_scalar
; %bb.0:
	ldp	x9, x10, [x0]
	mov	w8, #3                          ; =0x3
	ldr	x9, [x9]
	ldr	x10, [x10]
	add	x11, x9, x9, lsl #1
	smulh	x8, x9, x8
	asr	x9, x11, #63
	subs	x11, x11, #1
	asr	x12, x11, #63
	sbc	x13, x9, xzr
	adds	x11, x11, #7
	cinc	x14, x12, hs
	cmp	x8, x9
	str	x11, [x10]
	eor	x8, x14, x11, asr #63
	ccmp	x13, x12, #0, eq
	ccmp	x8, #0, #0, eq
	ldr	x8, [x0, #16]
	cset	w9, ne
	str	x9, [x8]
	ret
                                        ; -- End function
.subsections_via_symbols
