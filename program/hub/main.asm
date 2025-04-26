[bits 16]

start:
  mov si, loaded_msg
  call print

  mov ah, 0x03
  mov bh, 0
  int 0x10

  ; Move to next line
  inc dh
  mov dl, 0

  ; Set new cursor position
  mov ah, 0x02
  int 0x10

  mov si, hub_question
  call print

  ; Set the bytes counter
  xor bx, bx

  ; Go to the place that reads the input of the keyboard
  jmp read_input

print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0e
  int 0x10
  jmp print
.done:
  ret

read_input:
  mov ah, 0h  ; Listen for keys function
  int 16h     ; Interrupt to set the function into action

  ; Enter key
  cmp al, 0dh
  je newline

  ; Backspace key
  cmp al, 08h
  je backspace

  ; Regular keys
  mov ah, 0eh
  int 10h

  ; Save the character into the buffer
  mov [buffer + bx], al

  ; Increase the bytes counter register by 1
  inc bx

  jmp read_input

newline:
  ; Get current cursor position first
  mov ah, 0x03
  mov bh, 0
  int 0x10

  ; Move to next line
  inc dh
  mov dl, 0

  ; Set new cursor position
  mov ah, 0x02
  int 0x10

  mov di, 7 ; Number of iterations of the outer loop which is also the amount of commands + 1 incase it can't find the command and then we can just check if cx is 0!
  jmp evaluate_command_line

backspace:
  ; Save backspace to buffer
  mov byte [buffer + bx], 0
  
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

  ; Save backspace to buffer
  xor cx, cx
  mov [buffer + bx], cx

  ; Return to read_input
  jmp read_input
.fuckoff:
  inc dl
  mov ah, 0x02 
  int 0x10
  jmp read_input

;
; FORMAT
;   - first 3 bytes are the command
; 
;   For the station! Really important that I remember my new way of doing this!
;   - Next 128 bytes are the initial destination
;   - Last 128 bytes are the ending destination, only the move command needs this so that means that it can just be ignored by all the other functions

;
; Variables
;   - di = The counter for the amount of times the outer loop must be looped through to check every possible command
;   - bx = The counter for the letters to be checked in each command
;

evaluate_command_line:
  xor bx, bx ; Reset the counter for the letters to be checked in each command
  test di, di ; Check if di is equal to zero yet
  jz unknown_command ; Error if no command is found from the list
  dec di ; Sub 1
.inner_loop:
  cmp bx, 4 ; Check if bx has gone through every letter
  je found_command ; Jmp to found_command if a command has been identified
  mov al, [buffer + bx] ; Move the last letter from the buffer to al
  add bx, di ; Add the index of the commands checked to bx to get the correct offset for the next letter to check in the commands list
  mov ah, [commands + bx] ; Get the 3rd last unchecked letter from the commands list
  sub bx, di ; Put bx back to the correct index for the user input buffer

  cmp al, ah ; Compare the letter from the user input buffer to the letter from the commands list
  jne evaluate_command_line ; If the letters are not the same then jmp to the outer loop to check the next command
  
  inc bx ; Add 1 to bx for the next unchecked letter
  jmp .inner_loop ; Jump to the beginning of the loop so that the next command and letter can be checked

found_command:
  mov si, di
  mov al, [commands + si] ; Load the byte at commands + si into AL
  mov [command_file_bin], al ; Store AL into command_file_bin
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

  ; Search for main.bin
  xor bx, bx
  mov di, buffer ; di is being set to the start of the buffer, where the root directory is now sitting
.search_station:
  mov si, command_file_bin
  mov cx, 11                      ; Compare up to 11 characters
  push di                         ; Save di
  repe cmpsb                      ; cmpsb = Compare String Bytes: This happens at memory addresses ds:si and es:di    and   repe = Repeat while Equal: Repeats until either cx = 0 or zero flag = 1
  pop di                          ; Return di to its original value
  je .found_station

  add di, 32
  inc bx
  cmp bx, [bdb_dir_entries_count]
  jl .search_station

  jmp unknown_command

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

  ; Read station and process FAT chain
  mov bx, STATION_LOAD_SEGMENT
  mov es, bx
  mov bx, STATION_LOAD_OFFSET

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
  ; Jump to our station
  mov dl, [ebr_drive_number]        ; Boot device in dl

  mov ax, STATION_LOAD_SEGMENT       ; Set segment registers
  mov ds, ax
  mov es, ax

  jmp STATION_LOAD_SEGMENT:STATION_LOAD_OFFSET

  
  jmp wait_key_and_reboot

  cli
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
  

;
; Error handling
;
unknown_command:
  mov si, [buffer + bx]               ; Get the first letter out of the buffer
  call print                          ; Print it to the screen
  inc bx                              ; Increment bx by 1
  cmp bx, 4                           ; Compare bx to 4
  jne unknown_command                 ; If bx != 4 jmp to the beginning of the label
  mov si, unknown_location_response   ; mov the error message to si
  call print                          ; Print the error message on to the screen

  jmp start                      ; Go back to read_input

read_error:
  mov si, read_failed_msg
  call print

  jmp start

reset_error:
  mov si, reset_failed_msg
  call print

  jmp start

wait_key_and_reboot:
  mov ah, 0
  int 016h                           ; Wait for keypress
  jmp 0ffffh:0                       ; Jump to the beginning of the BIOS, should reboot

.halt:
  cli                                ; Disables interrupts, this way the CPU can't get out of the halt state
  hlt

;
; Messages + Questions
;
loaded_msg:                 db 'Welcome to the simple_terminal OS hub', 0
hub_question:               db 'What would you like to do (Enter qui for options)?:', 0
loading_response:           db 'Loading into ', 0
unknown_location_response:  db ' is not a known station of this OS.', 0
read_failed_msg:            db 'Failed to read', 0
reset_failed_msg:           db 'Failure to reset', 0
stage2_not_found_msg:       db 'Stage 2 was not found', 0

;
; Keys
;
enter_key: db 'Enter', 0

;
; Commands
;
ent: db 'ent', 0

;
;  Storage for shit
;
buffer:             times 5 db 0 ; Fills buffer with 256 bytes of 0's

;
; Variables
;
commands:
  ; Move command
  db 'm' ; 1
  db 'o' ; 2
  db 'v' ; 3
  ; Create command:
  db 'c' ; 4
  db 'r' ; 5
  db 't' ; 6
  ; Delete command
  db 'd' ; 7
  db 'e' ; 8
  db 'l' ; 9
  ; Enter command
  db 'e' ; 10
  db 'n' ; 11
  db 't' ; 12
  ; Save command
  db 's' ; 13
  db 'v' ; 14
  db 'e' ; 15
  ; Modify command
  db 'm' ; 16
  db 'o' ; 17
  db 'd' ; 18

commands_file_bin:
  db 'MOV     BIN',0  ; 1
  db 'CRT     BIN',0  ; 2
  db 'DEL     BIN',0  ; 3
  db 'ENT     BIN',0  ; 4
  db 'SVE     BIN',0  ; 5
  db 'MOD     BIN',0  ; 6

bdb_oem:                    db 'MSWIN4.1'             ; Oem identifier
bdb_bytes_per_sector:       dw 512                    ; 512 bytes/sector
bdb_sectors_per_cluster:    db 1                      ; 1 sector/cluster
bdb_reserved_sectors:       dw 1                      ; 1 reserved sector
bdb_fat_count:              db 2                      ; 2 fats
bdb_dir_entries_count:      dw 0e0h                   ; Directory entry point
bdb_total_sectors:          dw 2880                   ; 2880 sectors * 512 bytes = 1.44MB
bdb_media_descriptor_type:  db 0f0h                   ; f0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                      ; 9 sectors/fat
bdb_sectors_per_track:      dw 18                     ; 18 sectors/track
bdb_heads:                  dw 2                      ; 2 disk heads
bdb_hidden_sectors:         dd 0                      ; No hidden sectors
bdb_large_sector_count:     dd 0                      ; No large sectors

; Extended boot record
ebr_drive_number:           db 0                      ; 0X00 = floppy, 0x80 = hdd
                            db 0                      ; Reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h     ; Serial numbers, value doesn't matter
ebr_volume_label:           db 'TERRY OS   '          ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '             ; 8 bytes, also padded with spaces

command_file_bin:           db 0

station_cluster:            dw 0

STATION_LOAD_SEGMENT        equ 0x4000
STATION_LOAD_OFFSET         equ 0