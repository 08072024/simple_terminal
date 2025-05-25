[bits 16]

mov ax, 0
call clear_screen
jmp start

;
; Data
;
loaded_msg:                 db 'Welcome to the simple_terminal OS mov station', 0
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

buffer: times 4 db 0  ; room for 3 chars + null

;
; Code
;
start:
    mov si, loaded_msg
    call print

.ask:
    mov ax, 1
    call clear_screen

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
    mov [buffer + bx], al
    mov ah, 0x0E
    int 10h
    inc bx
    jmp .read_loop

.flush_key:
    jmp .read_loop

.done:
    call newline
    call match_command
    call clear_buffer    
    jmp .ask

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
  jmp start.read_loop
.fuckoff:
  inc dl
  mov ah, 0x02 
  int 0x10
  jmp start.read_loop

;
; Match command
;
match_command:
    xor si, si          ; index in commands
    xor cx, cx          ; command index
.next_cmd:
    push si
    mov di, 0
.match_chars:
    mov al, [commands + si]
    mov bl, [buffer + di]
    cmp al, bl
    jne .not_match
    inc si
    inc di
    cmp di, 3
    je .found_match
    jmp .match_chars

.not_match:
    pop si
    add si, 3
    inc cx
    cmp cx, 6
    je .unknown
    jmp .next_cmd

.found_match:
    pop si
    mov si, loading_response
    call print

    ; Index into commands_file_bin (cx * 11)
    mov ax, cx
    mov bx, 11
    mul bx
    mov bx, ax
    mov si, commands_file_bin
    add si, bx
    mov byte [si + 11], 0  ; Ensure null-terminated
    call print
    call newline
    ret

.unknown:
    mov si, buffer
    call print
    mov si, unknown_location_response
    call print
    call newline
    ret

clear_screen:
    cmp ax, 0
    je .complete_clear
    cmp ax, 1
    je .clear
    ret
.complete_clear:
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

    mov ax, 2
    jmp clear_screen
.clear:
    mov ah, 06h       ; BIOS scroll up
    mov al, 0         ; Scroll 0 lines = clear area
    mov bh, 07h       ; Attribute for blank lines (grey on black)
    mov cx, 0100h     ; Top-left corner: row 1 (02h), col 0 (00h)
    mov dx, 034Fh     ; Bottom-right: row 3 (0Eh), col 79 (4Fh)
    int 10h           ; Do it!

    ; Move cursor to start of partial area
    mov ah, 02h
    mov bh, 0
    mov dh, 4        ; Row 10
    mov dl, 0         ; Col 0
    int 10h

    mov ax, 2
    jmp clear_screen

clear_buffer:
    mov cx, 4        ; 4 bytes to clear
    mov di, buffer   ; point DI to the buffer label
    xor ax, ax       ; set AL = 0 for stosb
.clear_loop:
    stosb            ; store AL (0) at [DI], increment DI
    loop .clear_loop
    ret