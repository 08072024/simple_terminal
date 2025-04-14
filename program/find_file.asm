[bits 16]

global find_file

;
; FAT12 header
; If you want to know what the fuck any of this means I have documented it pretty good if you ask me but I'd go to Nanobyte's YouTube channel and watch part 3, where he explains it all very well!
;
jmp find_file
nop

bdb_oem:                    db 'MSWIN4.1'   ; Oem identifier
bdb_bytes_per_sector:       dw 512          ; 512 bytes/sector
bdb_sectors_per_cluster:    db 1            ; 1 sector/cluster
bdb_reserved_sectors:       dw 1            ; 1 reserved sector
bdb_fat_count:              db 2            ; 2 fats
bdb_dir_entries_count:      dw 0e0h         ; Directory entry point
bdb_total_sectors:          dw 2880         ; 2880 sectors * 512 bytes = 1.44MB
bdb_media_descriptor_type:  db 0f0h         ; f0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9            ; 9 sectors/fat
bdb_sectors_per_track:      dw 18           ; 18 sectors/track
bdb_heads:                  dw 2            ; 2 disk heads
bdb_hidden_sectors:         dd 0            ; No hidden sectors
bdb_large_sector_count:     dd 0            ; No large sectors

; Extended boot record
ebr_drive_number: db 0                      ; 0X00 = floppy, 0x80 = hdd
                  db 0                      ; Reserved
ebr_signature:    db 29h
ebr_volume_id:    db 12h, 34h, 56h, 78h     ; Serial numbers, value doesn't matter
ebr_volume_label: db 'TERRY OS   '          ; 11 bytes, padded with spaces
ebr_system_id:    db 'FAT12   '             ; 8 bytes, also padded with spaces

;
; Code goes here
;

print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0e
  int 0x10
  jmp print
.done:
  ret

find_file:
  ; Setup data segments
  mov ax, 0
  mov ds, ax
  mov es, ax

  ; Setup stack
  mov ss, ax
  mov sp, 0x7c00

  ; Some BIOSes might start us at 07c0:0000 instead of 0000:7c00
  ; Expected location
  push es
  push word .after
.after:
  ; Read something from floppy disk
  ; BIOS should set dl to drive number
  mov [ebr_drive_number], dl

  ; Print hello world message
  mov si, msg
  call print

  ; Read drive parameters (Sectors per track and head count),
  ; instead of relying on data on formatted disks
  push es
  mov ah, 08h
  int 13h
  jc read_error
  pop es

  and cl, 03fh
  xor ch, ch
  mov [bdb_sectors_per_track], cx ; Sector count

  inc dh
  mov [bdb_heads], dh             ; Head count

  ; Read FAT root directory
  ; Note: this section can be hardcoded
  mov ax, [bdb_sectors_per_fat]   ; LBA of root directory = reserved + fats * sectors per fat: ax = sectors per fat
  mov bl, [bdb_fat_count]         ; bl = fats
  xor bh, bh                      ; bh = 0
  mul bx                          ; ax * bl or in other words: fats * sectors per fat
  add ax, [bdb_reserved_sectors]  ; reserved then gets added on to ax: So ax is now the LBA!
  push ax                         ; Save ax's value

  ; Compute size of root directory = (32 * number of entries) / bytes per sector
  mov ax, [bdb_dir_entries_count]
  shl ax, 5                       ; ax *= 32
  xor dx, dx                      ; dx = 0
  div word [bdb_bytes_per_sector] ; Number of sectors we need to read

  test dx, dx                     ; If dx != 0, add 1
  jz .root_dir_after
  inc ax                          ; Division remainder != 0, add 1; That means we have a sector only partially filled with entries
.root_dir_after:
  ; Read root directory
  mov cl, al                      ; cl = number of sectors = size of root directory
  pop ax                          ; ax = LBA of root directory
  mov dl, [ebr_drive_number]      ; dl = drive number
  mov bx, buffer
  call read_disk

  ; Search for return.bin
  xor bx, bx
  mov di, buffer ; di is being set to the start of the buffer, where the root directory is now sitting
.search_return:
  pop si;mov si, file_return_bin
  mov cx, 11                      ; Compare up to 11 characters
  push di                         ; Save di
  repe cmpsb                      ; cmpsb = Compare String Bytes: This happens at memory addresses ds:si and es:di    and   repe = Repeat while Equal: Repeats until either cx = 0 or zero flag = 1
  pop di                          ; Return di to its original value
  je .found_return

  add di, 32
  inc bx
  cmp bx, [bdb_dir_entries_count]
  jl .search_return

  jmp return_not_found_error

.found_return:
  ; di should have the address to the entry
  mov ax, [di + 26]               ; First logical cluster field (Offset of 26): save cluster address to ax
  mov [return_cluster], ax        ; Assign return_cluster the address of the return's cluster
  
  ; Load FAT from disk into memory
  mov ax, [bdb_reserved_sectors]
  mov bx, buffer
  mov cl, [bdb_sectors_per_fat]
  mov dl, [ebr_drive_number]
  call read_disk

  ; Read return and process FAT chain
  mov bx, RETURN_LOAD_SEGMENT
  mov es, bx
  mov bx, RETURN_LOAD_OFFSET

.load_return_loop:
  ; Read next cluster
  mov ax, [return_cluster]
  add ax, 31 ; FIX ME!
  mov cl, 1
  mov dl, [ebr_drive_number]
  call read_disk

  add bx, [bdb_bytes_per_sector]

  ; Compute location of the next cluster
  mov ax, [return_cluster]
  mov cx, 3
  mul cx
  mov cx, 2
  div cx                            ; ax =index of entry in FAT, dx = cluster mod 2

  mov si, buffer
  add si, ax
  mov ax, [ds:si]                   ; Read entry from FAT table at index ax

  or dx, dx
  jz .even

.odd:
  shr ax, 4
  jmp .next_cluster_after

.even:
  and ax, 0x0fff

.next_cluster_after:
  cmp ax, 0x0ff8
  jae .read_finish

  mov [return_cluster], ax
  jmp .load_return_loop

.read_finish:
  ; Jump to our return
  mov dl, [ebr_drive_number]        ; Boot device in dl

  mov ax, RETURN_LOAD_SEGMENT       ; Set segment registers
  mov ds, ax
  mov es, ax

  jmp RETURN_LOAD_SEGMENT:RETURN_LOAD_OFFSET

  
  jmp wait_key_and_reboot

  cli
  hlt

;
; Error handlers
;

read_error:
  mov si, read_failed_msg
  call print
  hlt

reset_error:
  mov si, reset_failed_msg
  call print
  hlt

return_not_found_error:
  mov si, return_not_found_msg
  call print
  hlt

wait_key_and_reboot:
  mov ah, 0
  int 016h                           ; Wait for keypress
  jmp 0ffffh:0                       ; Jump to the beginning of the BIOS, should reboot

.halt:
  cli                                ; Disables interrupts, this way the CPU can't get out of the halt state
  hlt

;
; Disk routines
;

;
; Converts an LBA address to a CHS address
; Parameters:
;   - ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head
;

lba_to_chs:
  push ax
  push dx

  xor dx, dx  ; dx = 0
  div word [bdb_sectors_per_track]  ; ax = LBA / SectorsPerTrack
                                    ; dx = LBA % SectorsPerTrack
  inc dx                            ; dx = (LBA % SectorsPerTrack) + 1
  mov cx, dx                        ; cx = sector

  xor dx, dx
  div word [bdb_heads]              ; ax = (LBA / SectorsPerTrack) / Heads
                                    ; dx = (LBA / SectorsPerTrack) % Heads
  mov dh, dl                        ; dl = head
  mov ch, al                        ; ch = cylinder (Lower 8 bits)
  shl ah, 6
  or cl ,ah                         ; Put upper 2 bits of cylinder in cl

  pop ax
  mov dl, al                      ; Restor dl
  pop ax
  ret

;
; Reads sectors from the disk
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors to read
;   - dl: drive number
;   - es:bx: memory address where to store read data
;   
read_disk:

  push ax                           ; Save the registers that will be modified
  push bx
  push cx
  push dx
  push di

  push cx                           ; Temporarily save cx
  call lba_to_chs                   ; Compute CHS
  pop ax                            ; al = number of sectors to read

  mov ah, 02h
  mov di, 3                         ; Amount of times we want to retry because floppy disk are unreliable :(
.retry:
  pusha                             ; Save all registers, we don't know what the BIOS will modify
  stc                               ; Set carry flag, some BIOS'es don't set them
  int 13h                           ; Carry flag cleared = success
  jnc .done

  ; Read failed
  popa
  call disk_reset

  dec di
  test di, di
  jnz .retry
.fail:
  ; All attempts failed
  jmp read_error
.done:
  popa

  pop di
  pop dx
  pop cx
  pop bx
  pop ax
  ret
  
;
; Reset disk controller
; Parameters:
;   - dl: drive number
;
disk_reset:
  pusha
  mov ah, 0
  stc
  int 13h
  jc reset_error
  popa
  ret

msg:                  db 'Loading...', 0
read_failed_msg:      db 'Failed to read', 0
reset_failed_msg:     db 'Failure to reset', 0
return_not_found_msg: db 'return file was not found', 0

;file_return_bin:      db 0
return_cluster:       dw 0

RETURN_LOAD_SEGMENT   equ 0x2000
RETURN_LOAD_OFFSET    equ 0

buffer: