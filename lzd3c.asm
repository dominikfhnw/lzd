%ifndef VARINT
%define VARINT	1
%endif

%ifndef OFF16
%define OFF16	0
%endif

; VERSION: 6/14 bit litlen. Exit if litlen or matchlen==0. 8 bit matchlen. 6/14 bit matchoffset. 33 byte.

; 3 distinct values:
; - literal length
; - match offset
; - match length
;
; match offset must often be >255 to achieve reasonable compression
; match offset is >MINLEN if RLE is not active
; matchlen sometimes >255, but not that big of an impact
; litlen often less than 255
;
; idea: matchoff and litlen with varint encoding, then check flag only after decoding


_LZD3c:
	rset	ecx, 0

.loop:
%if VARINT
%if 1
	lodsb
	shr	al, 1
	jnc	.next
	mov	ah, al
	lodsb
%else
	mov	al,[esi]
	inc	esi
	shr	al, 1
	jnc	.next
	mov	ah, al
	mov	al,[esi]
	inc	esi

%endif
%elif OFF16
	lodsw
%else
	lodsb
%endif
.next:

; ja	Jump near if above (CF=0 and ZF=0).
; jg	Jump short if greater (ZF=0 and SF=OF).
; jng	Jump short if not greater (ZF=1 or SF≠ OF).
;

;check if match or lit
	shr	eax,1	; LSB contains flag
	;reg
	jc	.litlen	; if LSB set, it is a literal operator

.match:
.matchoff:
	;xchg	eax, ecx
	;jecxz	.done
	;lodsb
	mov	cl, [esi]
	jecxz	.done
	inc	esi
	push	esi
	mov	esi, edi
	; this should and must not set the carry flag
	sub	esi, eax
	xchg	eax, ecx

.matchlen:

.litlen:
	xchg	eax, ecx
	;reg
	;jecxz	.done
	rep	movsb
	rset	ecx,0
	reg
	jc 	.loop
	pop	esi

	;reg
	xor	eax,eax
	jmp	short .loop


.done:
%if OFF16
rset	eax, -3
%else
rset	eax, -3
%endif

