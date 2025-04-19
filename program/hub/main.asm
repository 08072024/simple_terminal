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

  mov si, hub_question
  call print

  jmp read_input

backspace:
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
  jmp read_input
.fuckoff:
  inc dl
  mov ah, 0x02
  int 0x10
  jmp read_input

;
; Messages + Questions
;
loaded_msg: db 'Welcome to the simple_terminal OS hub', 0
hub_question: db 'What would you like to do (Enter qui for options)?:', 0

;
; Responses
;
loading_response: db 'Loading into ', 0
unknown_location_response: db 'is not a known function of this OS', 0

;
; Keys
;
enter_key: db 'Enter', 0

;
; Commands
;
ent: db 'ent', 0