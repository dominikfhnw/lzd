%if 0
NOEXIT=1
#DUMP="-Mintel --no-addresses"
. ./newbuild.sh || exit

#cat lz4/SAMPLES/TEXT.LZ4 >> $OUT
dd if=lz4/SAMPLES/TEXT.LZ4 bs=4 skip=1 >> $OUT

strace -rni ./$OUT

exit
%endif

%include "main.mac"
rinit
%define ELF_OFFSET -4
elf
BASE 0x10000

%define zero_seg 0
_setup_buffers:
	;enter	0xffff,0
	set	edx, 0xffff
	sub	esp, edx

	;sub	esp, 0xffff
	mov	edi, esp
	ELF_PHDR 1, 0xbe
	add	esi, _data - 0x10020

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
        lodsw                   ;load chunk size low 16-bit word
        xchg    ebx,eax         ;BX = size of compressed chunk
        add     ebx,esi         ;BX = threshold to stop decompression
        lodsw                   ;load chunk size high 16-bit word
        or      eax,eax         ;is high word non-zero?
        jnz     @@done          ;If so, chunk too big or malformed, abort
%elif 1
	lodsd                   ;load chunk size low 16-bit word
        xchg    ebx,eax         ;BX = size of compressed chunk
        add     ebx,esi         ;BX = threshold to stop decompression
%else
	lodsd                   ;load chunk size low 16-bit word
	lea	ebx, [eax+esi]
	xor	eax, eax
%endif
@@parsetoken:                   ;CX=0 here because of REP at end of loop
        lodsb                   ;grab token to AL
        mov     edx,eax         ;preserve packed token in DX
@@copyliterals:
        push    4               ;set full CX reg to ensure CH is 0
	pop	ecx
        shr     al,cl           ;unpack upper 4 bits
        call    buildfullcount  ;build full literal count if necessary
@@doliteralcopy:                  ;src and dst might overlap so do this by bytes
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
        retn

@@done:
        sub     edi, esp        ;subtract original offset from where we are now
        ;mov     edx, edi        ;DX = decompressed size
        ;pop     ds              ;restore compiler assumptions
        ;ret

_print:
reg
rtaint
rset	eax, -2
rset	ecx, 0
rset	edx, -2
puts	esp, edi
_exit:
exit

%include "regdump2.mac"

_data:
