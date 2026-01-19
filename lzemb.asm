%if 0
DUMP="-Mintel --no-addresses"
. ./newbuild.sh || exit
%endif

%define PRINT 1
%define	FIXED 0


%ifndef ZX0
%define ZX0 0
%endif

%define LZD 0

%include "main.mac"
%define zero_seg 0
%define REG_ASSERT 0

%if PRINT
	elf 0x68439000
	%if ELF_CUSTOM
		rset	ebx, 1
	%else
		;push	4
	%endif

	lea	edi,[esp+4]
	;mov	edi, esp

	mov	esi, EMBEDDED
	taint	esi
	ELF_PHDR 1
%elif FIXED
	elf 0x3dc0b000
	%if ELF_CUSTOM
		rset	eax, 0xc0
	%else
		;push	4
	%endif
	mov	esi, EMBEDDED
	set	ecx, 0xffff
	set	edx, PROT_WRITE|PROT_READ
	taint	esi
	ELF_PHDR 1, 0xbb
	;mmap	0xffff, 0xffff, PROT_WRITE|PROT_READ, MAP_ANONYMOUS|MAP_PRIVATE, x, x
	edi := mmap x, 0xffff, PROT_WRITE|PROT_READ, MAP_ANONYMOUS|MAP_PRIVATE, x, x

%else
	elf; 0x3d909000
	alloca	0xffff +0
	mov	esi, EMBEDDED
	taint	esi
	ELF_PHDR 1
	mov	edi, esp


%endif

%if 0
set	eax, 0xff
varint:
test	al, al
;test	al, 0xC0
jns	.next
;reg
;shr	al,6
;neg	al
;mov	ah, al
xchg	eax, edx
lodsb
imul	dl
;test	al, 0xC0
rset	eax,0
.next:
exit
%endif

z_ALG_BEGIN:
%if LZD
	%if 1
		%include "lzd.asm"
	%else
		%include "rle.asm"
	%endif

%elif !ZX0
	%include "lz4.asm"
%else
	;zero	eax, ebx, ecx, edx, ebp
	;reg
	;call	unzx
	;jmp	unzx_end

	unzx:
	%include "unzx0.asm"
	unzx_end:
	;pop	ebp
	;reg
	taint8	eax
	taint16	ecx
	;rset	eax, -2
	;rset	ecx, -3
	;taint	eax, ecx
	taint	edx, esi, edi
	taint	ebp
%endif

z_ALG_END:

;reg
rdump

%if PRINT
	_print:

	pop	eax
	rset	eax, 4
	set	ecx, esp
	mov	edx, edi
	sub	edx, ecx
	taint	edx
	;reg

	;%define PRINTF_FD 0
	puts	x, x
	rset	eax, -3


	_exit:
	%if 1
		;rtaint
		;ebx := getpid
		;kill x,2
		;xchg	eax, esp	; sigbus
		;aam	0		; sigfpe
		;int3			; sigtrap
		;ud2			; sigill
		;hlt			; sigsegv

		;cdq
		;idiv	dl
		;exit	0
		;zero	eax, ebx, ecx, edx
		exit	0
		;ud2
	%else
		jmp $
	%endif
%else
	jmp	[esp]
%endif

EMBEDDED:
db ""
%ifdef INC
incbin INC
%endif

%include "regdump2.mac"

%assign SIZE z_ALG_END - z_ALG_BEGIN
%warning *************** ALGSIZE: SIZE

