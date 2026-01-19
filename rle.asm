; VERSION: RLE compression. Also RLE==4 is actually LZSS with 7bit litlen/matchlen and 8bit matchoff. 9-21 bytes
_RLE:

%assign RLE	0
%assign VARINT	1

%assign POP	0
rset	ecx, 0

%macro lods_varint 0
	lodsb
	taint8	eax
	%if VARINT
		shr	al, 1
		jnc	%%next
		xchg	ah, al
		lodsb
		taint16	eax
		%%next:
	%endif

%endmacro

.loop:
%if RLE == 0
	; (len,char) encoding. 9 byte
	lodsb
	xchg	eax, ecx
	jecxz	.done
	lodsb
	rep	stosb
	jmp	.loop

%elif RLE == 1
	; Fixed lit/rep sequences. 13 byte
	; Hardcoded lit/rep blocks
	; lit: (len) + literal bytes
	; rep: (len,char)
	lodsb
	xchg	eax, ecx
	jecxz	.done
	lodsb
	rep	stosb

.lit:
	lodsb
	xchg	eax, ecx
	rep	movsb
	jmp	.loop

%elif RLE == 2
	; Fixed lit/rep sequences. 14 byte
	; Uses carry flag/cmc to flip between lit/rep
	; lit: (len) + literal bytes
	; rep: (len,char)

	lodsb
	xchg	eax, ecx
	cmc
	jc	.lit

.rep:
	jecxz	.done
	lodsb
	rep	stosb
	;jmp	.loop
	; ecx==0, rep movsb willl fall through

.lit:
	rep	movsb
	jmp	.loop

%elif RLE == 3
	; LSB encodes lit or repeat. 15 byte
	; lit: (len) + literal bytes
	; rep: (len,char)

	lodsb
	shr	al,1
	xchg	eax, ecx
	jc	.lit

.rep:
	jecxz	.done
	lodsb
	rep	stosb
	;jmp	.loop
	; ecx==0, rep movsb willl fall through

.lit:
	rep	movsb
	jmp	.loop

%elif RLE == 4
	; LSB encodes lit or repeat. 21 byte
	; Reuses rep movsb block by doing RLE like in LZ.
	; Supports multibyte RLE. And is also an LZ decompressor now...
	; check similarity to lzd2b.asm
	; lit: (len) + literal bytes
	; rep: (len,offset)

	lods_varint

	shr	eax,1
	xchg	eax, ecx
	jc	.lit

.rep:
	jecxz	.done
	lodsb
	push	esi
	mov	esi, edi
	sub	esi, eax
	;lea	esi,[edi-1]
	;jmp	.loop
	; ecx==0, rep movsb willl fall through

.lit:
	rep	movsb
	jc	.loop
	pop	esi
	jmp	.loop

%elif RLE == 5
	; LSB encodes lit or repeat. 33 byte
	; Reuses rep movsb block by doing RLE like in LZ.
	; Supports multibyte RLE. And is also an LZ decompressor now...
	; check similarity to lzd2b.asm
	; lit: (len) + literal bytes
	; rep: (len,offset)

	lods_varint

	shr	eax,1
	;xchg	eax, ecx
	jnc	.lit

.rep:
	push	esi
	mov	esi, edi
	sub	esi, eax

	%if VARINT
		xor eax, eax
	%endif

; XXX NOT WORKING, ESI SAVED
	lodsb
	xchg	eax, ecx
	jecxz	.done

	rep	movsb
	pop	esi
	jmp	.loop

.lit:
	xchg	eax, ecx
	rep	movsb
	jmp	.loop

%elif RLE == 6
	; LSB encodes lit or repeat. XXX
	; Reuses rep movsb block by doing RLE like in LZ.
	; Supports multibyte RLE. And is also an LZ decompressor now...
	; check similarity to lzd2b.asm
	; lit: (len) + literal bytes
	; rep: (len,offset)

	lods_varint

	shr	eax,1
	;xchg	eax, ecx
	jnc	.lit

.rep:
	mov	cl, [esi]
	inc	esi
	jecxz	.done

	push	esi
	mov	esi, edi
	sub	esi, eax

	rep	movsb
	pop	esi
	jmp	.loop

.lit:
	rep	movsb
	jmp	.loop

%elif RLE == 7
	; LSB encodes lit or repeat. XXX
	; Reuses rep movsb block by doing RLE like in LZ.
	; Supports multibyte RLE. And is also an LZ decompressor now...
	; check similarity to lzd2b.asm
	; lit: (len) + literal bytes
	; rep: (len,offset)



	;%assign POP 1

	lods_varint
	;reg

	xchg	eax, ecx
	shr	ecx,1
	jc	.lit
.rep:
	lodsb
	xchg	eax, ecx
	jecxz	.done

	push	esi
	mov	esi, edi
	sub	esi, eax

	xor	eax, eax
.lit:
; either varint has to be in ECX (for lit),
; or the last lodsb val has to be in ECX (for match)
	rep	movsb
	jc	.loop

	pop	esi
	jmp	.loop


%else
	%fatal unknown rle variant RLE


%endif

.done:
%if POP
	pop	esi
%endif
rset	ecx, 0
rset	eax, -2



