%if 0



#SIZE_ORIG=$(wc -c < "$INPUT")
#echo "DEBUG: size $SIZE_ORIG $SIZE"
#EXTRA="-DSIZE=$SIZE"

NOEXIT=1
LDFLAGS="-Ttext-segment=0x20000"
#DUMP="-Mintel --no-addresses"
. ./newbuild.sh

cp $OUT $OUT-o

IN="lz4.tmp"
INPUT="/bin/cat"
lz4 -c -v -l -12 "$INPUT" >> "$OUT"
#lz4 -c -v -l -12 "$INPUT" > "$IN"

#od -An -j 4 -N 4 -t x4 "$IN"

strace -b execve -rni ./$OUT >/dev/null </dev/null

ls -l $OUT $OUT-o

exit
%endif

; USER SETTINGS

%define ARGENV		1 ; pass arg/env to binary. +4 bytes
%define MEMFD_NAME	0 ; put ARGV[0] in the memfd name, instead of just
			  ; the empty string. This is also going to be used
			  ; as the "comm" value of the new process.
			  ; Setting it makes e.g. pgrep work as expected
			  ; +4 bytes
%define BIGBUFFER	1 ; 16Mb decompression buffer, instead of 64k. +1 byte

; END SETTINGS



%define DYN	0
%define MACHINE	6
%include "main.mac"


%define zero_seg	0
rinit
%if BIGBUFFER
	%define BUFFER_SIZE 0x1000000
%else
	%define BUFFER_SIZE 0xffff
%endif

ELF
%if ELF_CUSTOM
	BASE	0x3d509000
%else
	push0
%endif
_memfd_create:
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
rdump
rset		eax, 0
_mmap:
ychg		sc_arg1, sc_arg5
mmap		x, BUFFER_SIZE, 3, MAP_SHARED, x, 0
pop		ecx
ychg		eax, edi
push		eax



mov	esi, _data
lodsd
lodsd			; size
taint	eax
ychg	eax, ebx
;lea	ebx, [eax+esi]
add	ebx, esi
reg

taint	eax,ebx,esi

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
;        lodsd                   ;load chunk size low 16-bit word
;        xchg    ebx,eax         ;BX = size of compressed chunk
;        add     ebx,esi         ;BX = threshold to stop decompression

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
	rtaint
	rset	eax, -2
	rset	ecx, 0
	rset	edx, -2

memfd:
	set     eax, 358
	pop	ebx
	rset	ebx, -2

	%if MEMFD_NAME
		pop	ebp
	%endif
	%if ARGENV
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
	;reg
	;ause
	int     0x80
	int3

%include "regdump2.mac"
_data:

