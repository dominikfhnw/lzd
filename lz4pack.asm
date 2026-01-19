%if 0
: ${INLINE:=0}

DISAS=0
INPUT="/bin/true"
#INPUT="hellocom2"


IN=lz4.inc
lz4 -c -v -l -12 "$INPUT" > "$IN"


SIZE_ORIG=$(wc -c "$INPUT" | awk '{print$1}' )
SIZE=$(od -An -j 4 -N 4 -t u4 "$IN" | awk '{print$1}' )
echo "DEBUG: size $SIZE_ORIG $SIZE"
EXTRA="-DSIZE=$SIZE -DINLINE=$INLINE"

NOEXIT=1
LDFLAGS="-Ttext-segment=0x20000"
#DUMP="-Mintel --no-addresses"
. ./newbuild.sh

cp $OUT $OUT-o

DD="dd if=$IN bs=8 skip=1"
if [ ${INLINE:-} -ne 1 ]; then
	$DD >> $OUT
else
	$DD of=lz4.tmp
fi

#strace -e raw=write -rni ./$OUT >/dev/null
strace -b execve -rni ./$OUT >/dev/null

ls -l $OUT $OUT-o

exit
%endif

%if INLINE
%define DYN	1
%else
%define DYN	0
%endif

%define MACHINE	6
%include "main.mac"

; USER SETTINGS

%define MEMFD		1
%define ARGENV		0 ; pass arg/env to binary. +4 bytes
%define MEMFD_NAME	0 ; put ARGV[0] in the memfd name, instead of just
			  ; the empty string. This is also going to be used
			  ; as the "comm" value of the new process.
			  ; Setting it makes e.g. pgrep work as expected
			  ; +4 bytes
%define BIGBUFFER	0 ; 16Mb decompression buffer, instead of 64k. +1 byte
%define ONSTACK		1

; END SETTINGS



%define zero_seg	0
rinit
%if BIGBUFFER
	%define BUFFER_SIZE 0x1000000
%else
	%define BUFFER_SIZE 0xffff
%endif


section .text align=1
_setup_buffers:
%if MEMFD
	ELF
	_memfd_create:
	%if ELF_CUSTOM
		BASE	0x3d509000
	%else
		push0
	%endif
	%if MEMFD_NAME
		mov		ebx, [esp+8]
		taint		ebx
		set		eax, SYS_memfd_create
		push0
		ELF_PHDR	1
		syscall		SYS_memfd_create, x, 0
	%else
		syscall		SYS_memfd_create, esp, 0
	%endif
	rset		sc_ret, -2
	_ftruncate:
	ychg		sc_ret, sc_arg1
	ELF_PHDR	1
	ftruncate	x, BUFFER_SIZE
	rset		eax, 0
	_mmap:
	ychg		sc_arg1, sc_arg5
	mmap		x, BUFFER_SIZE, 3, MAP_SHARED, x, 0
	pop		ecx
	ychg		eax, edi
	push		eax

%elif ONSTACK
	%define ELF_OFFSET -4
	BASE 0x10000
	ELF
	;enter	0xFFFF, 0
	%define foo ebx
	set	foo, 0xFFFF
	sub	esp, foo
%else
	%if ELF_CUSTOM
		ELF
		BASE 0x3dc0b000
		rset	eax, 0xc0
	%endif

	pusha
	;set	sc_arg1, 0x80000000
	set	sc_arg2, BUFFER_SIZE
	set	sc_arg3, 7
	set	sc_arg4, MAP_PRIVATE|MAP_ANONYMOUS

	%if !BIGBUFFER
		push0
	%endif

	%if ELF_CUSTOM
		ELF_PHDR 1, 0xbb
		rset	sc_arg1, 0x10020
	%else
		set	sc_arg1, 0xffff
	%endif

	%if BIGBUFFER
		push0
	%endif

	mmap	x,x,x,x,x,x

	ychg	eax, edi
	pop	ecx
%endif


%if !INLINE
	mov	ebx, _data + SIZE
	%if !MEMFD && ONSTACK
		ELF_PHDR 1, 0xbe
		mov	edi, esp
		;add	esi, byte _data - 0x10020
		lea	esi, [byte esi + _data - 0x10020]
	%else
		mov	esi, _data
	%endif

%else
	call	begin
	compressed:
	incbin	"lz4.tmp"
	begin:
	pop	esi
	lea	ebx, dword [dword esi + SIZE]
%endif
taint	ebx, esi
reg

lz4:
;---------------------------------------------------------------
; function lz4_decompress_small(inb,outb:pointer):word; assembler;
;
; Same as LZ4_Decompress but optimized for size, not speed. Still pretty fast,
; although roughly 30% slower than lz4_decompress and RLE sequences are not
; optimally handled.  Same Input, Output, and Trashes as lz4_decompress.
; Minus the Turbo Pascal preamble/postamble, assembles to 78 bytes.
;---------------------------------------------------------------

;PROC    lz4_decompress_small    NEAR
;ARG     inb:DWORD, outb:DWORD
;        push    ds              ;preserve compiler assumptions
;        les     di,[outb]       ;load target buffer
;        lds     si,[inb]        ;load source buffer
;        cld                     ;make strings copy forward
;        lodsw
;        lodsw                   ;skip magic number, smaller than "add si,4"


%if 0
	lodsd                   ;load chunk size low 16-bit word
        xchg    ebx,eax         ;BX = size of compressed chunk
        add     ebx,esi         ;BX = threshold to stop decompression
%else
	;set	ebx, 0x10cee
	;lea	ebx, [esi+SIZE]
%endif

@@parsetoken:                   ;CX=0 here because of REP at end of loop
        lodsb                   ;grab token to AL
        mov     edx,eax         ;preserve packed token in DX
@@copyliterals:
        shr     al,4            ;unpack upper 4 bits
        call    buildfullcount  ;build full literal count if necessary
@@doliteralcopy:                ;src and dst might overlap so do this by bytes
        rep     movsb           ;if cx=0 nothing happens

;At this point, we might be done; all LZ4 data ends with five literals and the
;offset token is ignored.  If we're at the end of our compressed chunk, stop.

        cmp     esi,ebx         ;are we at the end of our compressed chunk?
        jae     @@done          ;if so, jump to exit; otherwise, process match
@@copymatches:
        lodsw                   ;AX = match offset
        xchg    edx,eax         ;AX = packed token, DX = match offset
        and     al,0Fh          ;unpack match length token
        call    buildfullcount  ;build full match count if necessary
@@domatchcopy:
        ;push    ds
        push    esi             ;ds:si saved, xchg with ax would destroy ah
        mov     esi,edi
        sub     esi,edx
        ;push    es
        ;pop     ds              ;ds:si points at match; es:di points at dest
        add     ecx,4           ;minmatch = 4
                                ;Can't use MOVSWx2 because [es:di+1] is unknown
        rep     movsb           ;copy match run if any left
        pop     esi
        ;pop     ds              ;ds:si restored
        jmp     @@parsetoken

buildfullcount:
                                ;CH has to be 0 here to ensure AH remains 0
        cmp     al,0Fh          ;test if unpacked literal length token is 15?
        xchg    ecx,eax         ;CX = unpacked literal length token; flags unchanged
        jne     builddone       ;if AL was not 15, we have nothing to build
buildloop:
        lodsb                   ;load a byte
        add     ecx,eax         ;add it to the full count
        cmp     al,0FFh         ;was it FF?
        je      buildloop       ;if so, keep going
builddone:
        ret

@@done:
;reg
	rtaint
	rset	eax, -2
	rset	ecx, 0
	rset	edx, -2

	;reg

%if MEMFD
memfd:
	set     eax, 358
	pop	ebx
	rset	ebx, -2

	%if MEMFD_NAME
		pop	ebp
	%endif
	%if ARGENV
		;reg
		pop	ebp

		set	edx, esp
		lea     esi, [esp+4*ebp+4]
		taint	edx

	%else
		set	edx, 0
		set	esi, 0
	%endif
	set     edi, 0x1000
	push0
	mov     ecx, esp
	int     0x80
	;pause
%elif ONSTACK
	rtaint
	reg
	jmp	esp
%else
	popa
	;reg
	rinit
	;jmp	0x23:0x10000
	jmp	0x10000
%endif

%include "regdump2.mac"

_data:
