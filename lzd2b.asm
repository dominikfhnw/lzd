%define VARINT 0

; VERSION: 7 bit litlen, exit if lit==0, 7bit matchlen, 7/15bit matchoffset. 35 bytes

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


_LZD2b:
	rset	ecx, 0

.loop:
	lodsb
	test	al,al
	jz	.done
	xchg	eax, ecx
	jns	.lit	; if MSB set, it is a match operator

.match:
.matchlen:
	neg	cl

.matchoff:
	lodsb
%if VARINT
	test    al, al
	jns     .next
	not     al

	mov     ah, al
	lodsb
.next:
%endif

	push	esi
	mov	esi, edi
	sub	esi, eax
	;lodsb	; XXX - we already have ecx loaded??
	;mov	cl, al
	rep	movsb
	pop	esi


.lit:
	;jecxz	.done	; XXX where to check if EOF?
	rep	movsb
	rset	ecx,0

jmp	short .loop


.done:
%if VARINT
rset	eax, -3
%else
rset	eax, -2
%endif

