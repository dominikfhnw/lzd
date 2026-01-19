; Baseline, with everything turned off except SINGLELIT: 18 bytes
%define OFFSET16	1 ; use 16bit match offset instead of 8bit. code +3b
%define MATCHLEN16	0 ; use 16bit match length instead of 8bit. code +1b
%define MINMATCHLEN	0 ; minimal match length to allow. code +2b if >0
			  ; values: 0 -> no min, 1 -> auto matchlen, >1 -> custom matchlen
%define LIT16		0 ; use 16bit literal lengths instead of 8bit. code +1b
%define ALLOWZEROLIT	1 ; allow litlen==0. code +1b
%define CLEARECX	0 ; clear ECX register on start of every loop. Not needed if ecx==0 on start

; VERSION: 6/14 bit litlen. No exit condition. 8 bit matchlen. 6/14 bit matchoffset. 31 byte.

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


_LZD3:
	rset	ecx, 0

.loop:
;decode varint
	lodsb
	test	al, al
	jns	.next
	not	al
	mov	ah, al
	lodsb
.next:

; ja	Jump near if above (CF=0 and ZF=0).
; jg	Jump short if greater (ZF=0 and SF=OF).
; jng	Jump short if not greater (ZF=1 or SF≠ OF).
;

;check if match or lit
; jump if parity??
	shr	eax,1	; LSB contains flag
	jnc	.litlen	; if LSB set, it is a match operator


.match:
	push	esi
	mov	esi, edi
	sub	esi, eax

.matchlen:
	lodsb
	xchg	eax, ecx
	rep	movsb
	rset	ecx,0
	pop	esi

	; xchg instead of xor?
	xor	eax,eax

.litlen:
	xchg	eax, ecx

	rep	movsb


jmp	short .loop


.done:
rset	eax, -3

