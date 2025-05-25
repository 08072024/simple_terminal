[bits 16]

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
  db 'mov', 0
  db 'crt', 0
  db 'del', 0
  db 'ent', 0
  db 'sve', 0
  db 'mod', 0

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
  mov bx, 12               ; Each command entry in `commands_file_bin` is 11 bytes
  mul bx                   ; AX = AX * BX → AX = command offset
  mov bx, ax               ; BX = offset
  mov si, commands_file_bin ; SI = pointer to begin of command files
  add si, bx               ; SI = pointer to correct file entry string

  call clear_screen

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