%if 0
DUMP="-Mintel --no-addresses"
. ./newbuild.sh || exit
%endif
CPU 386

%include "main.mac"
;%define	REG_OPT 0
;%define REG_SEARCH 0

rinit
ELF
BASE 0x3d03b000
rset	eax, 3

%if 0
	enter	0xffff, 0
	;mov	edi, esp

	enter	0xffff, 0
	ELF_PHDR 1
	mov	esi, esp
	mov	edi, ebp
	read	0, esi, 0xffff
	lodsw
	lodsw
%elif 1
	set	edx, 0xffff
	sub	esp, edx
	mov	edi, esp
	mov	ebp, edi
	ELF_PHDR 1
	sub	esp, edx
	mov	esi, esp
	;mov	ecx, esi
	lea	ecx, [esi-4]	; chop off file header
	read	0, x, 0xffff
%else
	set	edx, 0xffff0000
	lea	edi, [esp+edx]
	mov	ebp, edi
	ELF_PHDR 1
	lea	esi, [edi+edx]
	neg	edx
	read	0, esi, x
	lodsw
	lodsw
%endif



;rtaint
;zero eax, ebx, ecx, edx

;---------------------------------------------------------------
; function lz4_decompress_small(inb,outb:pointer):word; assembler;
;
; Same as LZ4_Decompress but optimized for size, not speed. Still pretty fast,
; although roughly 30% slower than lz4_decompress and RLE sequences are not
; optimally handled.  Same Input, Output, and Trashes as lz4_decompress.
; Minus the Turbo Pascal preamble/postamble, assembles to 78 bytes.
;---------------------------------------------------------------

lz4:
;PROC    lz4_decompress_small    NEAR
;ARG     inb:DWORD, outb:DWORD
;        push    ds              ;preserve compiler assumptions
;        les     edi,[outb]       ;load target buffer
;        lds     si,[inb]        ;load source buffer

        ;cld                     ;make strings copy forward
	;add	esi, 4
        ;lodsw
        ;lodsw                   ;skip magic number, smaller than "add esi,4"
%if 0
        lodsw                   ;load chunk esize low 16-bit word
        xchg    ebx,eax           ;BX = esize of compressed chunk
        add     ebx,esi           ;BX = threshold to stop decompresesion
        lodsw                   ;load chunk esize high 16-bit word
        or      eax,eax           ;is high word non-zero?
        jnz     @@done          ;If so, chunk too big or malformed, abort
%else
	lodsd                   ;load chunk esize low 16-bit word
        xchg    ebx,eax           ;BX = esize of compressed chunk
        add     ebx,esi           ;BX = threshold to stop decompresesion
%endif
@@parsetoken:                   ;CX=0 here because of REP at end of loop
        lodsb                   ;grab token to AL
        mov     edx,eax           ;preserve packed token in DX
@@copyliterals:
	push	4
	pop	ecx		 ;set full CX reg to ensure CH is 0
        shr     al,cl           ;unpack upper 4 bits
        call    buildfullcount  ;build full literal count if necessary
@@doliteralcopy:                  ;src and dst might overlap so do this by bytes
        rep     movsb           ;if ecx=0 nothing happens

;At this point, we might be done; all LZ4 data ends with five literals and the
;offset token is ignored.  If we're at the end of our compressed chunk, stop.

        cmp     esi,ebx           ;are we at the end of our compressed chunk?
        jae     @@done          ;if so, jump to exit; otherwise, process match
@@copymatches:
        lodsw                   ;AX = match offset
        xchg    edx,eax           ;AX = packed token, DX = match offset
        and     al,0Fh          ;unpack match length token
        call    buildfullcount  ;build full match count if necessary
@@domatchcopy:
        push    esi              ;ds:esi saved, xchg with eax would destroy ah
        mov     esi,edi
        sub     esi,edx
%if 1
        add     ecx,4            ;minmatch = 4
                                ;Can't use MOVSWx2 because [es:edi+1] is unknown
%else
	movsd
%endif
        rep     movsb           ;copy match run if any left
        pop     esi
        jmp     @@parsetoken

buildfullcount:
                                ;CH has to be 0 here to ensure AH remains 0
        cmp     al,0Fh          ;test if unpacked literal length token is 15?
        xchg    ecx,eax           ;CX = unpacked literal length token; flags unchanged
        jne     builddone       ;if AL was not 15, we have nothing to build
buildloop:
        lodsb                   ;load a byte
        add     ecx,eax           ;add it to the full count
        cmp     al,0FFh         ;was it FF?
        je      buildloop       ;if so, keep going
builddone:
        retn

@@done:
        ;xchg    edi, edx           ;AX = decompressed esize
	mov	edx, edi
        sub     edx, ebp;subtract original offset from where we are now
        ;ret

_print:
reg
;call lz4
rtaint
rset	eax, -3
rset	ecx, 0
rset	edx, -3
puts ebp, x
_exit:
exit
;ENDP    lz4_decompress_small
;
;ENDS    CODE
;
;        END

%include "regdump2.mac"
