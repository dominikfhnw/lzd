%if 0
INLINE=0
DISAS=0

INPUT="/bin/true"
INPUT="memfd"
#INPUT="sol"


COMPRESSED=lz4.compressed
TRUNC=lz4.trunc
lz4 -c -l -12 "$INPUT" > "$COMPRESSED"


SIZE=$(od -An -j 4 -N 4 -t u4 "$COMPRESSED" | awk '{print$1}' )
echo "DEBUG: size $SIZE"
EXTRA="-DSIZE=$SIZE -DINLINE=$INLINE"
dd if=$COMPRESSED bs=8 skip=1 status=none > "$TRUNC"

ls -l "$INPUT" "$TRUNC"
#VERBOSE=0
NOEXIT=1
LDFLAGS="-Ttext-segment=0x10000 --noinhibit-exec"
#DUMP="-Mintel --no-addresses"
. ./newbuild.sh

EXTRA+=" -DHEADER_ONLY"
OUT+="-o" build "$@" >/dev/null

setarch -R strace -b execve -rni ./$OUT >/dev/null

ls -l $OUT $OUT-o

exit
%endif

%define INC	"lz4.trunc"
%define DYN	0
%define MACHINE	6
%define TRACE	0
%include "main.mac"

; USER SETTINGS

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

%if ELF_CUSTOM
	%define ELF_OFFSET -4
	BASE 0x10000
	ELF
%else
	_start:
%endif

;enter	0xFFFF, 0
%define foo ebp
set	foo, 0xFFFF
sub	esp, foo

%define SMALL 1

%if !INLINE
	mov	ebx, _data + SIZE
	%if ELF_CUSTOM
		ELF_PHDR 1, 0xbe
		rset esi, 0x10020
	%endif
	reg
	;%define REG_ASSERT	1

	%if SMALL && ELF_CUSTOM
		lea	esi, [byte ebp + _data - 0xFFFF]
		lea	ebp, [byte esi + buildfullcount - _data]
	%else
		mov	ebp, buildfullcount
		mov	esi, _data
	%endif

	mov	edi, esp
	taint	ebx, esi, edi, ebp

%else
	mov	ebp, buildfullcount
	ELF_PHDR 1
	call	begin
	compressed:
	incbin	INC
	begin:
	pop	esi
	lea	ebx, dword [dword esi + SIZE]
	mov	edi, esp
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

@@parsetoken:                   ;CX=0 here because of REP at end of loop
        lodsb                   ;grab token to AL
        mov     edx,eax         ;preserve packed token in DX
@@copyliterals:
        shr     al,4            ;unpack upper 4 bits
        call    ebp             ;build full literal count if necessary
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
        call    ebp             ;build full match count if necessary
@@domatchcopy:
        push    esi             ;ds:si saved, xchg with ax would destroy ah
        mov     esi,edi
        sub     esi,edx
        ;add     ecx,4           ;minmatch = 4
        lea     ecx,[ecx+4]     ;minmatch = 4
                                ;Can't use MOVSWx2 because [es:di+1] is unknown
        rep     movsb           ;copy match run if any left
        pop     esi
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

	rtaint
	rset	eax, -2
	rset	ecx, 0
	rset	edx, -2
	;rset	ebp, buildfullcount
	rdump

	rassert

	reg
	jmp	esp

_data:
%define NOTPREPROC __?PASS?__ != 3
%if NOTPREPROC
	%warning **********************************************
	%warning ************ HEADER_SIZE: %eval(_data-_setup_buffers)
	%warning **********************************************
%endif

%ifndef HEADER_ONLY
%if !INLINE
incbin	INC
%endif
%endif

%include "regdump2.mac"

