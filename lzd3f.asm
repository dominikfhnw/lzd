%ifndef VARINT
%define VARINT	0
%endif

%ifndef OFF16
%define OFF16	0
%endif

; VERSION: 7 bit litlen. Exit if litlen or matchlen==0. 7 bit matchlen. 8 bit matchoffset. 21 byte.

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


_LZD3e:
	rset	ecx, 0

.loop:
%if VARINT
	lodsb
	shr	al, 1
	jnc	.next
	mov	ah, al
	lodsb
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
	test	al, al
	xchg	eax, ecx
	jz	.done
	jns	.litlen
	;shr	eax,1	; LSB contains flag

.match:
.matchoff:
	movsx	edx, cl
	;add	eax, 10
	lodsb
	xchg	eax, ecx
	push	esi
	lea	esi, [edi+edx]

.matchlen:

.litlen:
	rep	movsb
	rset	ecx,0
	jc 	.loop
	pop	esi

	;xor	eax,eax
	jmp	short .loop


.done:
%if OFF16
rset	eax, -3
%else
rset	eax, -3
%endif

