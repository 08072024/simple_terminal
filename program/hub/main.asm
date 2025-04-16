[bits 16]

print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0e
  int 0x10
  jmp print
.done:
  ret

start:
  ; Just to check that we entered the hub alright
  mov si, loaded_msg
  call print

  mov ax, 0
  mov es, ax
  mov ds, ax
  
  mov ss, ax
  mov sp, 0


read_input:
  mov ah, 0h  ; Listen for keys function
  int 16h     ; Interrupt to set the function into action

  ; Enter key
  mov si, enter_key
  cmp al, 0dh
  je keys

  ; Backspace key
  mov si, backspace_key
  cmp al, 08h
  je keys

  ; Regular keys
  mov ah, 0eh
  int 10h

newline:
  add dh, 1
  mov dl, 2
  mov bh, 0
  mov ah, 2
  int 10h

loaded_msg: db 'Welcome to the simple_terminal OS hub', 0
hub_question: db 'What would you like to do (Enter qui for options)?:', 0

;
; Keys
;
enter_key: db 'Enter', 0

;
; Commands
;
ent: db 'ent', 0