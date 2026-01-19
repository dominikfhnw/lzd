; Baseline, with everything turned off except SINGLELIT: 18 bytes
%define OFFSET16	0 ; use 16bit match offset instead of 8bit. code +3b
%define VAROFFSET16	0 ; use 8/16bit match offset instead of 8bit. code +8/9b
%define MATCHLEN16	0 ; use 16bit match length instead of 8bit. code +1b
%define MINMATCHLEN	0 ; minimal match length to allow. code +2b if >0
			  ; values: 0 -> no min, 1 -> auto matchlen, >1 -> custom matchlen
%define LIT16		0 ; use 16bit literal lengths instead of 8bit. code +1b
%define ALLOWZEROLIT	0 ; allow litlen==0. code +1b
%define CLEARECX	0 ; clear ECX register on start of every loop. Not needed if ecx==0 on start
%define SINGLELIT	1 ; lits are always 1 byte. A.k.a. LZ77.  MINMATCHLEN has to be 0 too. code +2b if turned off
%define NEGOFFSET	0 ; offset is stored as two's complement, so you can add instead of sub it. code -1b
			  ; TODO: needs sign extension or 32b offsets...

; VERSION: Fixed lit/match sequence. 8 bit litlen, exit if lit==0. 8 bit matchlen, 7/15 bit matchoffset. 30 byte
; VAROFFSET16 && !SINGLELIT: two EOF checks, fix

%if MINMATCHLEN == 1
	%assign MINMATCHLEN 3
	%if OFFSET16
		%assign MINMATCHLEN MINMATCHLEN + 1
	%endif
	%if LIT16
		%assign MINMATCHLEN MINMATCHLEN + 1
	%endif
%endif

_LZD:
	rdump

	%if SINGLELIT
		set	eax, 0
		set	ecx, 0
	%endif

	%if !CLEARECX
		rset	ecx, 0
	%endif

.loop:
%if !SINGLELIT
	%if LIT16
		lodsw
.litlen:
		%if CLEARECX
			movzx	ecx, ax
		%else
			mov	ecx, eax
		%endif
	%else
		lodsb
.litlen:
		%if CLEARECX
			movzx	ecx, al
		%else
			xchg	eax, ecx
		%endif
	%endif

	%if !VAROFFSET16
		jecxz .done	
		%if ALLOWZEROLIT
			dec	ecx
		%endif
	%endif
	;reg
	rep	movsb
	rset	ecx,0
%else
	movsb
%endif

.matchlen:
	%if MATCHLEN16
		lodsw
		taint16	eax
	%else
		lodsb
		taint8	eax
	%endif

	%if MINMATCHLEN
		lea	ecx, [eax+MINMATCHLEN]
	%elif VAROFFSET16 ; or just not SINGLELIT?
		ychg	eax, ecx
		;mov	cl, al
		;movzx	ecx, al
	%else
		mov	cl, al
	%endif

	%if SINGLELIT && !VAROFFSET16
		jecxz	.done	
		dec	ecx
	%endif
.matchoff:
	%if VAROFFSET16
		lodsb

		%if 1
			test	al, al
			jz	.done	
			jns	.next
			not	al

			mov	ah, al
			lodsb
			.next:
		%else
			shr	al, 1
			jz	.done	
			jnc	.next
			mov	ah, al
			lodsb
			.next:
		%endif

	%elif OFFSET16
		lodsw
	%else
		lodsb
	%endif

	;reg
	push	esi
	mov	esi, edi
	sub	esi, eax

	rep	movsb
	rset	ecx,0
	pop	esi
	%if VAROFFSET16 || OFFSET16
		;mov	ah,0
		xor	eax,eax
	%endif

	;reg
jmp	short .loop


.done:
%if LIT16 || OFFSET16
	rset	eax, -3
%else
	rset	eax, -2
%endif

