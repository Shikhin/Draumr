 ; Contains functions related to the ISO9660 filesystem.
 ;
 ; Copyright (c) 2012, Shikhin Sethi
 ; All rights reserved.
 ;
 ; Redistribution and use in source and binary forms, with or without
 ; modification, are permitted provided that the following conditions are met:
 ;     * Redistributions of source code must retain the above copyright
 ;       notice, this list of conditions and the following disclaimer.
 ;     * Redistributions in binary form must reproduce the above copyright
 ;       notice, this list of conditions and the following disclaimer in the
 ;       documentation and/or other materials provided with the distribution.
 ;     * Neither the name of Draumr nor the
 ;       names of its contributors may be used to endorse or promote products
 ;       derived from this software without specific prior written permission.
 ;
 ; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 ; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 ; DISCLAIMED. IN NO EVENT SHALL SHIKHIN SETHI BE LIABLE FOR ANY
 ; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 ; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 ; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 ; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 ; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

SECTION .data

; Some error strings.
FilesNotFoundMsg:
    db "Required files (DBAL, BIOS, KL, Kernel, Modules) not present on disk.", EL, 0

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

KL:
    .LBA          dd 0                ; The LBA of the KL file.
    .Size         dd 0                ; The Size of the KL file in bytes.

Kernelx86:
    .LBA		  dd 0				  ; The LBA of the x86 kernel.
    .Size		  dd 0                ; The Size of the x86 kernel in bytes.

KernelAMD64:
    .LBA		  dd 0                ; The LBA of the AMD64 kernel.
    .Size		  dd 0                ; The Size of the AMD64 kernel in bytes.

Background:
    .LBA          dd 0                ; The LBA of the Background file.
    .Size         dd 0                ; The size of the Background file in bytes.

FILE:
    .Code   db -1                     ; The "code" of the file opened. If -1, no file opened.
    .LBA    dd 0                      ; The LBA of the sector we are going to "read next".
    .Size   dd 0                      ; The size of the file left to read (as reported by the file system).
    .Extra  dd 0                      ; The number of "extra" bytes read in the last "transaction".
                                      ; And I'll just explain it over here. In cases of BIOS and DBAL file,
                                      ; we need to read exact on spot. Thus, if we read anything extra in 
                                      ; the last transaction, we carry that much over.
    
SECTION .text

 ; Is responsible for finding boot files.
 ;
 ; Returns: 
 ;     Boot -> aborted if ANY error occurs.
BootFilesFind:
    pushad    

    mov eax, [0x9000 + 156 + 10]      ; Get the size of the PVD root directory into EAX.
    mov ebx, [0x9000 + 156 + 2]       ; Get the LBA of the PVD root directory into EBX.

    ; Save the values.
    mov [Root.LBA], ebx
    mov [Root.Size], eax

    mov ecx, 1                        ; Only load 1 sector at a time.

.LoadSectorRD:
    mov edi, 0x9000 | 0x80000000      ; Enable advanced error checking.
    call DiskReadSector

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
    jnz .LoadSectorRD                 ; If EAX isn't zero, load next sector and continue.

.FoundBoot:
    mov eax, [di + 10]
    mov ebx, [di + 2]

    ; Save some values we probably'd need later on.
    mov [Boot.LBA], ebx
    mov [Boot.Size], eax
    
    mov ebp, 6                        ; Number of files to load.

.LoadSectorBD:
    mov edi, 0x9000 | 0x80000000      ; Enable advanced error checking.
    call DiskReadSector

.CheckRecordBD:
    cmp byte [di], 0                  ; If zero, we have finished this sector. Move on to next sector.
    je .NextSectorBD

    cmp byte [di + 32], 7             ; If size of directory identifier isn't 4, then try for KL.
    jne .CheckKL

    cmp dword [di + 33], "BIOS"       ; If directory identifier doesn't match, next record.
    je .FoundBIOS

    cmp dword [di + 33], "DBAL"       ; Sigh, how many 4 byte entries do we have?
    je .FoundDBAL

    ; If not matched with anything, go on to next record.
    jmp .NextRecordBD

.CheckKL:
    cmp byte [di + 32], 5             ; If size of directory isn't 2, then try for x86 kernel.
    jne .CheckKernelx86

    cmp word [di + 33], "KL"          ; If directory identifier doesn't match, next record.
    jne .NextRecordBD

    ; So we found the KL here.

    ; We don't use edx and esi in the loop/anywhere, so use them to move around
    ; and store the LBA and Size.
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [KL.LBA], esi
    mov [KL.Size], edx

    jmp .CheckForAllDone

.CheckKernelx86:
    cmp byte [di + 32], 8             ; Check the size of the directory identifier. If not match, try for AMD64.
    jne .CheckKernelAMD64

    ; Try to match the name.
    cmp dword [di + 33],  "KEX8"
    jne .NextRecordBD

    cmp byte [di + 37], '6'
    jne .NextRecordBD

    ; So we found the Kernelx86 here.

    ; We don't use edx and esi in the loop/anywhere, so use them to move around
    ; and store the LBA and Size.
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [Kernelx86.LBA], esi
    mov [Kernelx86.Size], edx

    jmp .CheckForAllDone

.CheckKernelAMD64:
    cmp byte [di + 32], 10            ; If doesn't match, go to the background image.
    jne .NextRecordBD

    ; Try to match the name.
    cmp dword [di + 33],  "KEAM"
    jne .NextRecordBD

    cmp word [di + 37], "D6"
    jne .NextRecordBD

    cmp byte [di + 39], '4'
    jne .NextRecordBD

    ; So we found the KernelAMD64 here.

    ; We don't use edx and esi in the loop/anywhere, so use them to move around
    ; and store the LBA and Size.
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [KernelAMD64.LBA], esi
    mov [KernelAMD64.Size], edx

    jmp .CheckForAllDone

.CheckBGImage:
    cmp byte [di + 32], 14            ; If doesn't match, go to the background image.
    jne .NextRecordBD

    cmp dword [di + 33], "BACK"       ; Check the file name.
    jne .NextRecordBD

    cmp dword [di + 37], "GROU"       ; And the rest of the file name.
    jne .NextRecordBD
    
    cmp dword [di + 41], ".SIF"       ; And the rest. Woof.
    jne .NextRecordBD

    ; So we found the background image here. 
    
    ; We don't use edx and esi in the loop/anywhere, so use them to move around
    ; and store the LBA and Size.
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [Background.LBA], esi
    mov [Background.Size], edx

.CheckForAllDone:
    dec ebp
    ; If found all files, return.
    jz .Return

.NextRecordBD:
    movzx edx, byte [di]              ; Save the size of the directory record into EDX.
    add di, dx                        ; Move to the next directory record.
    
    cmp di, 0x9800                    ; If we aren't below than 0x9000 + 2048, then we need to load the next sector.
    jb .CheckRecordBD 

.NextSectorBD:
    inc ebx                           ; Increase the LBA.
    
    sub eax, 0x800                    ; Decrease number of bytes left.
    jnz .LoadSectorBD                 ; If EAX isn't zero, load next sector and continue.

    jmp .NotFound                     ; If we reached here, we haven't found all the files. Abort.

.FoundBIOS:   
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [BIOS.LBA], esi
    mov [BIOS.Size], edx

    jmp .CheckForAllDone

.FoundDBAL: 
    mov edx, [di + 10]
    mov esi, [di + 2]

    mov [DBAL.LBA], esi
    mov [DBAL.Size], edx
   
    jmp .CheckForAllDone
  
; Not found - abort boot.
.NotFound:
    ; If the only thing we haven't found yet is the background image, then, can continue.
    cmp ebp, 1
    jg .Abort

    ; So 1 file hasn't been found. Is it the image?
    cmp dword [Background.LBA], 0
    je .Return                        ; Yes, return.

.Abort:
    ; Else, abort.
    mov si, FilesNotFoundMsg
    jmp AbortBoot

.Return:
    popad
    ret

 ; Opens a file to be read from.
 ;     AL   -> contains the code number of the file to open.
 ;      0   -> common BIOS File.
 ;      1   -> DBAL.
 ;      2   -> background image.
 ;      3   -> KL.
 ;      4   -> Kernel x86.
 ;      5   -> Kernel AMD64.
 ;
 ; Returns: 
 ;    ECX   -> the size of the file you want to open.
 ;    Carry -> set if any error occured.
FileOpen:
    ; Save some variables.
    push eax
    push ebx

    ; Check if any file is already opened. If yes, return with carry set.
    cmp byte [FILE.Code], -1
    jne .Error

    mov [FILE.Code], al
    
    cmp al, 0
    je .BIOS                          ; 0 indicates the common BIOS file.

    cmp al, 1                         ; 1 indicates the DBAL file.
    je .DBAL

    cmp al, 2                         ; 2 indicates the Background image.
    je .Background

    cmp al, 3                         ; 3 indicates the KL.
    je .KL

    cmp al, 4                         ; 4 indicates the Kernel x86.
    je .Kernelx86

    cmp al, 5                         ; 5 indicates the Kernel AMD64.
    je .KernelAMD64

    jmp .Error
   
; Store the required thingies.
.BIOS:
    mov eax, [BIOS.LBA]
    mov [FILE.LBA], eax

    mov eax, [BIOS.Size]
    mov [FILE.Size], eax
   
    jmp .Return

.DBAL:
    mov eax, [DBAL.LBA]
    mov [FILE.LBA], eax

    mov eax, [DBAL.Size]
    mov [FILE.Size], eax

    jmp .Return

.Background:
    ; If the background file isn't present, return with carry set.
    mov eax, [Background.LBA]
    test eax, eax
    jz .Error
    mov [FILE.LBA], eax

    mov eax, [Background.Size]
    mov [FILE.Size], eax

    jmp .Return

.KL:
    mov eax, [KL.LBA]
    mov [FILE.LBA], eax

    mov eax, [KL.Size]
    mov [FILE.Size], eax

    jmp .Return
    
.Kernelx86:
    mov eax, [Kernelx86.LBA]
    mov [FILE.LBA], eax

    mov eax, [Kernelx86.Size]
    mov [FILE.Size], eax

    jmp .Return

.KernelAMD64:
    mov eax, [KernelAMD64.LBA]
    mov [FILE.LBA], eax

    mov eax, [KernelAMD64.Size]
    mov [FILE.Size], eax

    jmp .Return

.Error:
    mov byte [FILE.Code], -1
    mov dword [FILE.Extra], 0
    stc 
    
.Return:
    ; Restore registers.
    pop ebx
    pop eax
    
    mov ecx, [FILE.Size] 
    ret

 ; Reads the 'next LBA' of the file currently opened.
 ;     EDI  -> the destination address of where to read the file to.
 ;     ECX  -> the number of bytes to read.
 ;
 ; Returns:
 ;     Boot -> aborted if any error occured.
FileRead:
    pushad

    mov edx, ecx                      ; Get the original number of bytes in EDX.
    add ecx, 0x7FF
    and ecx, ~0x7FF                   ; Get it to the highest rounded 0x800 byte thingy.

    mov eax, ecx                      ; Get the new number of bytes in EAX.
    sub eax, edx                      ; And now, get the extra in EAX.
    push eax                          ; Push it.

    ; Get the LBA in EBX.
    mov ebx, [FILE.LBA]

    cmp ecx, [FILE.Size]              ; If size we want to read <= size we can read continue;
    jbe .Cont
  
    mov ecx, [FILE.Size]              ; Else, we read only [FILE.Size] bytes.
    
    ; If which is zero, we return.
    test ecx, ecx
    jz .Return

.Cont:
    sub [FILE.Size], ecx              ; Subtract bytes read from bytes we can read.

.Read:
    ; Add the extra bytes.
    add edi, [FILE.Extra]
    
    add ecx, 0x7FF
    shr ecx, 11                       ; And the number of sectors to read in ECX.

    mov edx, ecx                      ; Keep that for internal count.

; Here we have the number of sectors to read in ECX, the LBA in EAX and the destination buffer in EDI. Let's shoot!
.Loop:
    call DiskReadSectorM              ; Do the CALL!
    
    add ebx, ecx                      ; Advance the LBA by read sectors count.
   
    sub edx, ecx                      ; EDX more sectors left to do.
    jz .Return                        ; Read all sectors, return.
  
    ; Now need to advance EDI.
    mov ebp, ecx
    shl ebp, 12
    add edi, ebp
    
    mov ecx, edx                      ; If not, read EDX (sectors left to do) sectors next time.
    jmp .Loop

.Return:
    mov [FILE.LBA], ebx
    
    pop eax
    mov [FILE.Extra], eax
    
    popad
    ret

 ; Closes the file currently opened.
FileClose:
    mov byte [FILE.Code], -1
    mov dword [FILE.Extra], 0
    mov dword [FILE.Size], 0
    mov dword [FILE.LBA], 0
    ret
