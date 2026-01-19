%if 0
OUT=$(basename "$0" .asm)
nasm "$0" -o "$OUT"
chmod +x "$OUT"
ndisasm -b 32 "$OUT"
objdump -Mintel -b binary -m i386 -D "$OUT"
ls -l "$OUT"
exit
%endif

;  unzx0_8088.S - ZX0 decompressor for 8088 - 81 bytes - NASM
;
;  inputs:
;  * ds:si: start of compressed data
;  * es:di: start of decompression buffer
;
;  Copyright (C) 2021 Emmanuel Marty
;  ZX0 compression (c) 2021 Einar Saukas, https://github.com/einar-saukas/ZX0
;
;  This software is provided 'as-is', without any express or implied
;  warranty.  In no event will the authors be held liable for any damages
;  arising from the use of this software.
;
;  Permission is granted to anyone to use this software for any purpose,
;  including commercial applications, and to alter it and redistribute it
;  freely, subject to the following restrictions:
;
;  1. The origin of this software must not be misrepresented; you must not
;     claim that you wrote the original software. If you use this software
;     in a product, an acknowledgment in the product documentation would be
;     appreciated but is not required.
;  2. Altered source versions must be plainly marked as such, and must not be
;     misrepresented as being the original software.
;  3. This notice may not be removed or altered from any source distribution.

        segment .text
;        bits 16
BITS	32
;CPU 8086


zx0_decompress:
%if 1
	%define GET_ELIAS ebp
	mov	ebp, .get_elias
%else
	%define GET_ELIAS .get_elias
%endif

        ;cld                     ; make string operations go forward
        mov     al,0x80         ; initialize empty bit queue
                                ; plus bit to roll into carry
        ;xor     dx,dx           ; initialize rep-offset to 1
        ;dec     dx
	or	edx, -1

.literals:
        call    GET_ELIAS       ; read number of literals to copy
        rep     movsb           ; copy literal bytes

        add     al,al           ; shift bit queue, and high bit into carry
        jc      .get_offset     ; if 1: read offset, if 0: rep-match

        call    GET_ELIAS       ; read rep-match length (starts at 1)

.copy_match:
        ;push    ds              ; save ds:si (current pointer to compressed data)
        push    esi

        ;mov     esi,edi           ; point to destination in es:di + offset in dx
        ;add     esi,edx
	lea	esi, [edi+edx]
        rep     movsb           ; copy matched bytes

        pop     esi              ; restore ds:si

        add     al,al           ; read 'literal or match' bit
        jnc     .literals       ; if 0: go copy literals

.get_offset:
        mov     cl,0xfe         ; initialize value to FEh
        call    .elias_loop     ; read high byte of match offset
        inc     cl              ; obtain negative offset high byte
        je      .done           ; exit if EOD marker
        
        mov     dh,cl           ; transfer negative high byte into dh
	push	1
	pop	ecx
        ;mov     ecx,1            ; initialize match length value to 1

        mov     dl,[esi]         ; read low byte of offset + 1 bit of len
        inc     esi
	;lodsb
	;xchg	al, dl

        stc                     ; set high bit that is shifted into bit 15
	; XXX - rcr edx or rcr dx??
        rcr     edx,1            ; shift len bit into carry/offset in place
        jc      .got_offs       ; if len bit is set, no need for more
        call    .elias_bt       ; read rest of elias-encoded match length
.got_offs:
        inc     ecx              ; fix match length
        jmp     short .copy_match ; go copy match

.get_elias:
	push	1
	pop	ecx
        ;mov     cx,1            ; initialize value to 1
.elias_loop:
        add     al,al           ; shift bit queue, and high bit into carry
        jnz     .got_bit        ; queue not empty, bits remain
        lodsb                   ; read 8 new bits
        adc     al,al           ; shift bit queue, and high bit into carry
.got_bit:
        jc      .got_elias      ; done if control bit is 1
.elias_bt:
        add     al,al           ; read data bit
        adc     ecx,ecx           ; shift into cx
        jmp     short .elias_loop ; keep reading
.got_elias:
	ret
.done:

