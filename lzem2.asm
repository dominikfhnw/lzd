%if 0
#DUMP="-Mintel --no-addresses"
START="0x3dac001a"


printf '\2AB\21\2\0\1\n' > test.lzd
#printf '\11ABCDEFGH\n\6\10\0\1\n' > test2.lzd
printf '\11ABCDEFGH\n\6\10' > test2.lzd
. ./newbuild.sh || exit
%endif
;CPU 386

%define BLOCKLEN	0 ; use blocklen to signal eof? else lit special value signals eof
			  ; code +5b,data +2b
%define OFFSET16	0 ; use 16bit match offset instead of 8bit. code +1b
%define MINMATCHLEN	0 ; minimal match length to allow. code +1b if >0
			  ; values: 0 -> no min, 1 -> auto matchlen, >1 -> custom matchlen
%define LIT16		0 ; use 16bit literal lengths instead of 8bit. code +1b
%define ALLOWZEROLIT	0 ; allow litlen==0 if BLOCKLEN==0. code +1b
%define CLEARECX	0 ; clear ECX register on start of every loop. Not needed if ecx==0 on start
%define COUNTEDX	0 ; count total nr of output bytes in edx. TODO: remove?

%if MINMATCHLEN == 1
	%assign MINMATCHLEN 3
	%if OFFSET16
		%assign MINMATCHLEN MINMATCHLEN + 1
	%endif
	%if LIT16
		%assign MINMATCHLEN MINMATCHLEN + 1
	%endif
%endif



%define LZD 1

%define START _start2
;%define LINCOM 1
%include "main.mac"
%define zero_seg 0
%define REG_ASSERT 0

elf 0x3dac0000
%if ELF_CUSTOM
	;rset	eax, 3
%endif



z_ALG_BEGIN:


_LZD:
	rdump
	%if !CLEARECX
		rset	ecx, 0
	%endif
.loop:
	%if LIT16
		lodsw
.litlen:
		%if CLEARECX
			movzx	ecx, ax
		%else
			mov	ecx, eax
		%endif
	%else
		;lodsb
.litlen:
		%if CLEARECX
			movzx	ecx, al
		%else
			mov	cl, al
		%endif
	%endif
	%if !BLOCKLEN
		jecxz .done	
		%if ALLOWZEROLIT
			dec	ecx
		%endif
	%endif
	reg
	%if COUNTEDX
		add	edx, ecx
	%endif
	rep	movsb
	rset	ecx,0
.matchlen:
	lodsb
	%if MINMATCHLEN
		lea	ecx, [eax+MINMATCHLEN]
	%else
		mov	cl, al
	%endif

ELF_PHDR 1
.matchoff:
	%if OFFSET16
		lodsw
	%else
		lodsb
	%endif

	push	esi
	%if 1
		mov	esi, edi
		sub	esi, eax
	%else
		; sign extend: +1 byte
		movsx	esi, al
		add	esi, edi
	%endif
	;lea	esi, [edx+eax]
	%if COUNTEDX
		add	edx, ecx
	%endif
	rep	movsb
	rset	ecx,0
	pop	esi

	reg
.is_end:
%if BLOCKLEN
	cmp	esi, ebx
	jb	.loop
%else
	jmp	short .loop
%endif


.done:
%if LIT16 || OFFSET16
	rset	eax, -3
%else
	rset	eax, -2
%endif


z_ALG_END:

%if 0
	_print:

	pop	ecx
	taint	ecx
	mov	edx, edi
	sub	edx, ecx
	taint	edx
	;reg

	puts	x, x
	rset	eax, -3


	_exit:
	%if 0
		exit	0
	%else
		jmp $
	%endif
%else
	jmp	[esp]
%endif


_start2:
set	edi, esp
;push	edi
;set	ebx, STDOUT
mov	esi, EMBEDDED
taint	esi
jmp	_start+1

%include "regdump2.mac"


%assign SIZE z_ALG_END - z_ALG_BEGIN
%warning *************** ALGSIZE: SIZE

EMBEDDED:
