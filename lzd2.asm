; Baseline, with everything turned off except SINGLELIT: 18 bytes
%define OFFSET16	0 ; use 16bit match offset instead of 8bit. code +3b
%define MATCHLEN16	0 ; use 16bit match length instead of 8bit. code +1b
%define MINMATCHLEN	0 ; minimal match length to allow. code +2b if >0
			  ; values: 0 -> no min, 1 -> auto matchlen, >1 -> custom matchlen
%define LIT16		0 ; use 16bit literal lengths instead of 8bit. code +1b
%define ALLOWZEROLIT	0 ; allow litlen==0. code +1b
%define CLEARECX	0 ; clear ECX register on start of every loop. Not needed if ecx==0 on start

; VERSION: 7 bit litlen, exit if lit==0, 8bit matchlen, 6/14bit matchoffset. 32 byte

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


_LZD2:
	rset	ecx, 0

.loop:
	lodsb
	shr	al,1	; LSB contains flag
	jc	.match	; if LSB set, it is a match operator
.litlen:
	xchg	eax, ecx

	jecxz	.done	; XXX where to check if EOF?
	rep	movsb
	rset	ecx,0
	jmp	short .loop

.match:
.matchoff:
	shr	al,1
	;test	al, 0x40
	jc	.m2
	mov	ah, al
	lodsb
.m2:

	push	esi
	mov	esi, edi
	sub	esi, eax

.matchlen:
	lodsb
	ychg	eax, ecx
	rep	movsb
	rset	ecx,0
	pop	esi

	; xchg instead of xor?
	xor	eax,eax

jmp	short .loop


.done:
rset	eax, -3

