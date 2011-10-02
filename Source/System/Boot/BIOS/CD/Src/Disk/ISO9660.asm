; Contains functions related to the ISO9660 filesystem.
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



SECTION .text


; Finds the Primary Volume Descriptor, puts its LBA in PVDLBA and loads it at 0x9000.
;     @rc
;                 Aborts boot if any error occurs.
FindPVD:
    pushad
    xor si, si                        ; If any error occurs, basic boot.
    mov ecx, 1                        ; Only read one sector (2KiB).
    mov ebx, 0x0F                     ; We should start from the 16th Sector.
    mov edi, 0x9000 | 0x80000000      ; Read the sector at 0x9000 WITH advanced disk checking.

.LoopThroughSectors:
    inc ebx
    call ReadFromDisk                 ; Read the disk.
    jc AbortBoot                      ; The read from the disk failed for some reason.

    cmp byte [di], 0x1                ; If the Type field contains 0x1 we just stumbled upon the Primary Volume Descriptor.
    jne .Next 

    cmp dword [di + 1], 'CD00'        ; Check if valid Volume Descriptor.
    jne .Next                         ; No, move on to next.

    cmp byte [di + 4], '1'            ; Check if valid Volume Descriptor.
    jne .Next                         ; No, move on to next. 

.Next:
    cmp byte [di], 255                ; This is the Volume Descriptor Set Terminator. No more Volume Descriptors.
    je AbortBoot                      ; The PVD isn't present! :-(

    jmp .LoopThroughSectors

.Found:
    popad
    mov [BootInfo.PVD], ebx
    ret


SECTION .data

; Some error strings.
FilesNotFound     db "ERROR: Important boot files are not present.", nl, 0

; Save all LBA/sizes here.
Root:
    .LBA          dd 0                ; The LBA of the root directory.
    .Size         dd 0                ; The size of the root directory in bytes.

Boot:
    .LBA          dd 0                ; The LBA of the boot directory.
    .Size         dd 0                ; The size of the boot directory in bytes.

BIOS:
    .LBA          dd 0                ; The LBA of the BIOS file.
    .Size         dd 0                ; The Size of the BIOS file in bytes.

DBAL:
    .LBA          dd 0                ; The LBA of the DBAL file.
    .Size         dd 0                ; The Size of the DBAL file in bytes.

; Is responsible for finding boot files.
;     @rc
;                 Aborts boot if ANY error occurs.
FindBootFiles:
    pushad    

    mov eax, [0x9000 + 156 + 10]      ; Get the size of the PVD root directory into EAX.
    mov ebx, [0x9000 + 156 + 2]       ; Get the LBA of the PVD root directory into EBX.

    ; Save the values.
    mov [Root.LBA], ebx
    mov [Root.Size], eax

    mov ecx, 1                        ; Only load 1 sector at a time.

.LoadSectorRD:
    mov edi, 0x9000 | 0x80000000      ; Enable advanced error checking.
    call ReadFromDisk

.CheckRecordRD:
    cmp byte [di], 0                  ; If zero, we have finished this sector. Move on to next sector.
    je .NextSectorRD

    cmp byte [di + 32], 4             ; If size of directory identifier isn't 0, next record.
    jne .NextRecordRD

    cmp dword [di + 33], "BOOT"       ; If directory identifier doesn't match, next record.
    je .FoundBoot

.NextRecordRD:
    movzx edx, byte [di]              ; Save the size of the directory record into EDX.
    add di, dx                        ; Move to the next directory record.
    
    cmp di, 0x9800                    ; If we aren't below than 0x9000 + 2048, then we need to load the next sector.
    jb .CheckRecordRD 

.NextSectorRD:
    inc ebx                           ; Increase the LBA.
    sub eax, 0x800                    ; Decrease number of bytes left.
    test eax, eax
    jnz .LoadSectorRD                 ; If EAX isn't zero, load next sector and continue.

.FoundBoot:
    mov eax, [di + 10]
    mov ebx, [di + 2]

    ; Save some values we probably'd need later on.
    mov [Boot.LBA], ebx
    mov [Boot.Size], eax
    
    mov edx, "BIOS"
    mov ebp, 2                        ; Number of files to load.

.LoadSectorBD:
    mov edi, 0x9000 | 0x80000000      ; Enable advanced error checking.
    call ReadFromDisk

.CheckRecordBD:
    cmp byte [di], 0                  ; If zero, we have finished this sector. Move on to next sector.
    je .NextSectorBD

    cmp byte [di + 32], 7             ; If size of directory identifier isn't 0, next record.
    jne .NextRecordBD

    cmp dword [di + 33], "BIOS"       ; If directory identifier doesn't match, next record.
    je .FoundBIOS

    cmp dword [di + 33], "DBAL"       ; Sigh, how many 4 byte entries do we have?
    je .FoundDBAL

.NextRecordBD:
    movzx edx, byte [di]              ; Save the size of the directory record into EDX.
    add di, dx                        ; Move to the next directory record.
    
    cmp di, 0x9800                    ; If we aren't below than 0x9000 + 2048, then we need to load the next sector.
    jb .CheckRecordBD 

.NextSectorBD:
    inc ebx                           ; Increase the LBA.
    sub eax, 0x800                    ; Decrease number of bytes left.
    test eax, eax
    jnz .LoadSectorBD                 ; If EAX isn't zero, load next sector and continue.

    jmp .NotFound                     ; If we reached here, we haven't found all the files. Abort.

.FoundBIOS:
    push eax
    push ebx
 
    mov eax, [di + 10]
    mov ebx, [di + 2]

    mov [BIOS.LBA], ebx
    mov [BIOS.Size], eax

    pop ebx
    pop eax

    dec ebp

    jmp .MoveOn

.FoundDBAL:
    push eax
    push ebx
 
    mov eax, [di + 10]
    mov ebx, [di + 2]

    mov [DBAL.LBA], ebx
    mov [DBAL.Size], eax
   
    pop ebx
    pop eax

    dec ebp

.MoveOn:
    test ebp, ebp
    jnz .NextRecordBD

    jmp .Return
  
; Not found - abort boot.
.NotFound:
    mov si, FilesNotFound
    mov ax, 0
    call AbortBoot

.Return:
    popad
    ret

SECTION .data

Open:
    .IsOpen db 0                      ; Set to 1 is a file is open.
    .LBA    dd 0                      ; The LBA of the sector we are going to "read next".
    .Size   dd 0                      ; The size of the file left to read (as reported by the file system).

SECTION .text

; Opens a file to be read from.
; @al             Contains the code number of the file to open.
;                 0 -> Common BIOS File.
;     @rc 
;                 Returns with carry set if ANY error occured (technically, no error should be happening, but still).
;                 @ecx    The size of the file you want to open.
OpenFile:
    pushad
    
    mov bl, [Open]
    test bl, bl
    jnz .Error

    mov byte [Open], 1

    cmp al, 0
    je .BIOS                          ; 0 indicates the common BIOS file.

    cmp al, 1                         ; 1 indicates the DBAL file.
    je .DBAL

    jmp .Error
   
.BIOS:
    mov eax, [BIOS.LBA]
    mov [Open.LBA], eax

    mov eax, [BIOS.Size]
    mov [Open.Size], eax
   
    jmp .Return

.DBAL:
    mov eax, [DBAL.LBA]
    mov [Open.LBA], eax

    mov eax, [DBAL.Size]
    mov [Open.Size], eax

.Return:
    popad
    mov ecx, [Open.Size] 
    ret

.Error:
    stc 
    popad
    ret


; Reads the 'next LBA' of the file currently opened.
; @edi            The destination address of where to read the file to.
; @ecx            The number of bytes to read.
;     @rc
;                 Aborts boot if any error occured (during read, that is).
ReadFile:
    pushad

    add ecx, 0x7FF
    and ecx, ~0x7FF                   ; Get it to the nearest rounded 0x800 byte thingy.

    cmp ecx, [Open.Size]              ; If size we want to read <= size we can read continue;

    jbe .Cont
  
    mov ecx, [Open.Size]              ; Else, we read only [Open.Size] bytes.
    mov ebx, [Open.LBA]               ; If we jbe .Return, then we need the LBA in EBX.
    cmp ecx, 0
    jbe .Return

.Cont:
    sub [Open.Size], ecx              ; Subtract bytes read from bytes we can read.

.Read:
    mov ebx, [Open.LBA]               ; Get the LBA to read in EBX.
    add ecx, 0x7FF
    shr ecx, 11                       ; And the number of sectors to read in ECX.

    mov edx, ecx                      ; Keep that for internal count.

; Here we have the number of sectors to read in ECX, the LBA in EAX and the destination buffer in EDI. Let's shoot!
.Loop:
    call ReadFromDiskM                ; Do the CALL!

    add ebx, ecx                      ; Advance the LBA by read sectors count.
   
    sub edx, ecx                      ; EDX more sectors left to do.
    test edx, edx
    jz .Return                        ; Read all sectors, return.
  
    ; Now need to advance EDI.
    push eax                          ; Save EAX - and restore it later.
    push edx

    mov eax, ecx                      ; Get the sectors read count in ECX.
    mov edx, 2048
    mul edx                           ; And multiply it by 2048, and advance EDI by it.

    add edi, eax

    pop edx
    pop eax
    
    mov ecx, edx                      ; If not, read EDX (sectors left to do) sectors next time.
    jmp .Loop

.Return:
    mov [Open.LBA], ebx               ; Store the new LBA.

    popad
    ret

; Closes the file currently opened.
CloseFile:
    mov byte [Open], 0
    ret
