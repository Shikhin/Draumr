; Common definitions to get the Video Mode information list.
;
; Copyright (c) 2011 Shikhin Sethi
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program; if not, write to the Free Software Foundation, Inc.,
; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

SECTION .data

; Reserve space for the palette - where we store it.
Palette:
    times (4 * 256) db 0x00

PaletteLookup3BITS    db 0,  9, 18, 27, 36, 45, 54, 63
PaletteLookup2BITS    db 0, 21, 42, 63

SECTION .text
BITS 16

; Performs a switch to a VGA mode, using the BIOS.
; @ax             The mode to switch to.
SwitchVGA:
    pushad

    int 0x10                          ; Since the mode is in AX, AH should be cleared. So, switch!

.Return:
    popad
    ret


; Set ups the palette for a 8bpp mode, using the BIOS.
SetupPaletteVGA:
    pushad

    ; Clear the counter, and point edi at the output buffer.
    mov edi, Palette
    xor edx, edx

.PaletteLoop:
    ; Move the counter in EAX, EBX, ECX.
    mov eax, edx
    mov ebx, edx
    mov ecx, edx

    ; Get the red, green and blue bits in EAX, EBX, ECX.
    shr al, 5
    shr bl, 2
    and cl, 0x03
    and bl, 0x07

    ; Get the values from the lookup tables.
    mov al, [PaletteLookup3BITS + eax]
    mov ah, [PaletteLookup3BITS + ebx]
    mov bl, [PaletteLookup2BITS + ecx]
    
    ; And store them.
    mov [di], ax
    mov [di + 2], bl
    
    add di, 3
    add dl, 0x01
    jnc .PaletteLoop

    ; Start from register 0, set 256 registers, from the table 'Palette', using AX = 0x1012.
    xor bx, bx
    mov ax, 0x1012
    mov cx, 256
    mov dx, Palette

    int 0x10

.Return:
    popad
    ret


; Checks for VGA, VBE, and if VBE supported, also gets the VBE information.
VideoInit:
    pushad

.VGACheck:
    ; AX=0x1A00, int 0x10 returns the display combination code.
    mov ax, 0x1A00

    ; Quoting Ralf Brown's interrupt list:
    ; Notes: This function is commonly used to check for the presence of a VGA. 
    ; This function is supported on the ATI EGA Wonder with certain undocumented configuration switch settings,
    ; even though the EGA Wonder does not support VGA graphics; 
    ; to distinguish this case, call AX=1C00h with CX nonzero, which the EGA Wonder does not support.

    xor cx, cx
    not cx

    int 0x10

    ; If AL isn't 0x1A, it failed. Go the VBE check.
    cmp al, 0x1A
    jne .VBECheck
    
    ; 0xFF indicated unknown display type.
    cmp bl, 0xFF
    je .VGAPresent

    ; 0x07 indicates VGA w/ monochrome display
    cmp bl, 0x07
    je .VGAPresent
 
    ; 0x08 indicates VGA w/ color analogue display.
    cmp bl, 0x08
    je .VGAPresent

    ; No - no VGA; check for VBE.
    jmp .VBECheck

; So VGA is present - set the right flag.
.VGAPresent:
    or byte [BIT.VideoFlags], VGA_PRESENT

; Check whether VBE is present or not.
.VBECheck:

.Return:
    popad
    ret