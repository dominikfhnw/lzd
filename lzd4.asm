; VERSION: 6/14 bit litlen. Exit if matchlen==0. 8 bit matchlen. 6/14 bit matchoffset. 31 byte.

; decompressors:
;	NAME	FLAG	LIT	MOFF	MLEN	SIZE
;	lzd4	y	6-31	6-31	8	31
;	lzd4	y	7	7	8	22
;	lzd3e	y	6/14	8	6/14	28
;	lzd3e	y	7	8	7	21
;	lzd	n	0	8	8	18
;	lzd	n	8	8	8	20
;	lzd	n	8	7/15	8	30
;	lzd2	y	7	6/14	8	32

; by size:
;	NAME	FLAG	LIT	MOFF	MLEN	SIZE
;	lzd4	y	6-31	6-31	8	31
;	lzd3e	y	7	8	7	21
;	lzd	n	0	8	8	18
;	rle3	y	7	0	7	15
;	rle1	n	8	0	8	13
;	rle0	n	0	0	8	9

; stoopid ones:
;	lzd2	y	7	6/14	8	32
;	lzd	n	8	7/15	8	30
;	lzd3e	y	6/14	8	6/14	28
;	lzd4	y	7	7	8	22
;	lzd	n	8	8	8	20

_LZD4:

%assign VARINT	2

rset	ecx, 0

; startup conditions:
; esi has to point to source
; edi has to point to dest
; eax & 0x00ffffff == 0
; ecx & 0xffffff00 == 0
; working stack. stack is cleaned up on exit

%macro lods_varint 1
	%if VARINT == 1
		lodsb
		taint8	eax
		shr	al, 1
		jnc	%%next
		mov	ah, al
		lodsb
		taint16	eax
		%%next:
		ychg	eax, %1
	%elif VARINT == 2

		%%varloop:
		shl	eax, 8
		lodsb
		shr	eax, 1
		jc	%%varloop

		%%next:
		taint	eax
		ychg	eax, %1

	%elif VARINT == 3
		%ifidn %1,eax
			%fatal eax not allowed
		%endif

		%%varloop:
		shl	%1, 7
		lodsb
		shr	al, 1
		lea	%1,[%1+eax]
		jc	%%varloop

		%%next:
		taint	%1
	%endif

%endmacro

.loop:
	; ecx is zero
	; eax is nonzero if last codeword was match
	;  ah is nonzero if last codeword was match with 15b varint
	; ...except we have a xor
	lods_varint ecx
	;reg
	;exit 0

.type:
	shr	ecx,1
	jc	.lit
.match:
	lodsb
	xchg	eax, ecx
	jecxz	.done

	push	esi

	; start calc...
	; keep ecx
	mov	esi, edi
	sub	esi, eax
	%if VARINT
		xor	eax, eax
	%endif
	; esi = edi - eax
	; eax = 0, or
	;  ah = 0  at least
.lit:
; either varint has to be in ECX (for lit),
; or the last lodsb val has to be in ECX (for match)
	rep	movsb
	jc	.loop

	pop	esi
	jmp	.loop

.done:
rset	ecx, 0
rset	eax, -3



