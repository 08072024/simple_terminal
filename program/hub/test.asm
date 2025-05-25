[bits 16]

jmp short start
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

start:
  ; Setup data segments
  mov ax, 0
  mov ds, ax
  mov es, ax
.after:
  ; Read something from floppy disk
  ; BIOS should set dl to drive number
  mov [ebr_drive_number], dl

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

  ; Search for station.bin
  xor bx, bx
  mov di, buffer ; di is being set to the start of the buffer, where the root directory is now sitting
.search_station:
  mov si, file_station_bin
  mov cx, 11                      ; Compare up to 11 characters
  push di                         ; Save di
  repe cmpsb                      ; cmpsb = Compare String Bytes: This happens at memory addresses ds:si and es:di    and   repe = Repeat while Equal: Repeats until either cx = 0 or zero flag = 1
  pop di                          ; Return di to its original value
  je .found_station

  add di, 32
  inc bx
  cmp bx, [bdb_dir_entries_count]
  jl .search_station

  jmp station_not_found_error

.found_station:
  ; di should have the address to the entry
  mov ax, [di + 26]               ; First logical cluster field (Offset of 26): save cluster address to ax
  mov [station_cluster], ax        ; Assign station_cluster the address of the station's cluster
  
  ; Load FAT from disk into memory
  mov ax, [bdb_reserved_sectors]
  mov bx, buffer
  mov cl, [bdb_sectors_per_fat]
  mov dl, [ebr_drive_number]
  call read_disk

  ; Read station and process FAT chains
  mov bx, station_LOAD_SEGMENT
  mov es, bx
  mov bx, station_LOAD_OFFSET

.load_station_loop:
  ; Read next cluster
  mov ax, [station_cluster]
  add ax, 31 ; FIX ME!
  mov cl, 1
  mov dl, [ebr_drive_number]
  call read_disk

  add bx, [bdb_bytes_per_sector]

  ; Compute location of the next cluster
  mov ax, [station_cluster]
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

  mov [station_cluster], ax
  jmp .load_station_loop

.read_finish:
  mov ax, [loop_count]
  cmp ax, 7
  je begin

  inc ax
  jmp start

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

station_not_found_error:
  mov si, station_not_found_msg
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

read_failed_msg:        db 'Failed to read', 0
reset_failed_msg:       db 'Failure to reset', 0
station_not_found_msg:  db 'Stage 2 was not found', 0

loop_count:             db 0

file_station_bin:       db 'MAIN    BIN'
station_cluster:        dw 0

station_LOAD_SEGMENT    equ 0x2F00
station_LOAD_OFFSET     equ 0x0008

buffer:

call clear_screen
jmp begin

;
; Data
;
loaded_msg:                 db 'Welcome to the simple_terminal OS hub', 0
hub_question:               db 'What would you like to do (Enter qui for options)?:', 0
loading_response:           db 'Loading into ', 0
unknown_location_response:  db ' is not a known station of this OS.', 0

commands: db 'movcrtdelentsvemod'  ; no null terminators between
commands_file_bin:
  db 'MOV     BIN'
  db 'CRT     BIN'
  db 'DEL     BIN'
  db 'ENT     BIN'
  db 'SVE     BIN'
  db 'MOD     BIN'

command: times 4 db 0  ; room for 3 chars + null

;
; Code
;
begin:
  call clear_command
  mov si, loaded_msg
  call print

.ask:
  call newline
  mov si, hub_question
  call print

  ; Read 3 characters
  xor bx, bx
.read_loop:
  mov ah, 0
  int 16h

  cmp al, 0Dh
  je .done

  cmp al, 08h
  je backspace

  cmp bx, 3
  jae .flush_key
  mov [command + bx], al
  mov ah, 0x0E
  int 10h
  inc bx
  jmp .read_loop

.flush_key:
  jmp .read_loop

.done:
  call newline
  call match_command
  jmp begin

;
; Print string at SI
;
print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0E
  int 10h
  jmp print
.done:
  ret

;
; Print newline (next line)
;
newline:
  mov ah, 0x03
  mov bh, 0
  int 10h
  inc dh
  mov dl, 0
  mov ah, 0x02
  int 10h
  ret

backspace:
  ; Save backspace to command
  mov byte [command + bx], 0
  
  ; Save bx
  push bx

  ; Get current cursor position
  mov ah, 0x03
  mov bh, 0
  int 0x10

  cmp dx, 0x0000
  je .done

  ; Move cursor left
  dec dl
  mov ah, 0x02
  int 0x10

  ; Check if the character is a ':'
  mov ah, 0x08
  int 0x10

  cmp al, ':'
  je .fuckoff

  ; Write space at current cursor
  mov ah, 0x0e
  mov al, ' '
  int 0x10

  ; Move cursor back again
  mov ah, 0x03
  mov bh, 0
  int 0x10
  dec dl
  mov ah, 0x02
  int 0x10
.done:
  ; Restore bx
  pop bx

  ; Decrease the bytes_entered variable by 1
  dec bx

  ; Save backspace to command
  xor cx, cx
  mov [command + bx], cx

  ; Return to read_input
  jmp begin.read_loop
.fuckoff:
  inc dl
  mov ah, 0x02 
  int 0x10
  jmp begin.read_loop

;
; Match command — compares user input in `command` to hardcoded commands
;
match_command:
  xor si, si          ; Clear SI (used to index into the `commands` string)
  xor cx, cx          ; Clear CX (counts how many command blocks we've checked — used as command index)

.next_cmd:
  push si             ; Save the current SI value on the stack (so we can restore it if it’s not a match)
  mov di, 0           ; DI will index into `command` (user input, e.g., "mod")

.match_chars:
  mov al, [commands + si] ; Load a character from the current command being tested
  mov bl, [command + di]   ; Load the corresponding character from user input
  cmp al, bl              ; Compare the two characters
  jne .not_match          ; If they don’t match, skip to check the next command
  inc si                  ; Move to the next char in the `commands` list
  inc di                  ; Move to the next char in the command
  cmp di, 3               ; Have we compared 3 characters?
  je .found_match         ; If so, it's a full match!
  jmp .match_chars        ; Otherwise, continue comparing next char

.not_match:
  pop si                  ; Restore SI to the beginning of the last tested command
  add si, 3               ; Move to the next 3-letter command in the list
  inc cx                  ; Increment the command index
  cmp cx, 6               ; Have we checked all 6 commands?
  je .unknown             ; If yes, then it's an unknown command
  jmp .next_cmd           ; Otherwise, try the next command

.found_match:
  pop si                  ; Pop the old SI (safe cleanup, even though we're done matching)
  mov si, loading_response  ; SI = pointer to "Loading into " message
  call print                ; Print it

  mov si, command
  call print               ; Print the full filename string (e.g., "MOD     BIN")
  call newline             ; Print a newline

  ; Calculate index into commands_file_bin (each entry is 11 bytes wide: e.g., "MOD     BIN")
  mov ax, cx               ; AX = command index
  mov bx, 11               ; Each command entry in `commands_file_bin` is 11 bytes
  mul bx                   ; AX = AX * BX → AX = command offset
  mov bx, ax               ; BX = offset
  mov si, commands_file_bin ; SI = pointer to begin of command files
  add si, bx               ; SI = pointer to correct file entry string

  ret

.unknown:
  mov si, command           ; SI = pointer to command (user's invalid command)
  call print               ; Print the unknown command back to the user
  mov si, unknown_location_response ; SI = "is not a known station..." message
  call print               ; Print the error message
  call newline             ; Move to new line
  ret                      ; Return from match_command

clear_screen:
  mov ah, 06h       ; BIOS scroll up
  mov al, 0         ; Scroll 0 lines = clear area
  mov bh, 07h       ; Attribute for blank lines (grey on black)
  mov cx, 0000h     ; Top-left corner: row 10 (0Ah), col 0 (00h)
  mov dx, 0F4Fh     ; Bottom-right: row 14 (0Eh), col 79 (4Fh)
  int 10h           ; Do it!

  ; Move cursor to top-left
  mov ah, 02h
  mov bh, 0
  mov dh, 0         ; Row 0
  mov dl, 0         ; Col 0
  int 10h

  ret

clear_command:
  mov cx, 4        ; 4 bytes to clear
  mov di, command   ; point DI to the command label
  xor ax, ax       ; set AL = 0 for stosb
.clear_loop:
  stosb            ; store AL (0) at [DI], increment DI
  loop .clear_loop
  ret