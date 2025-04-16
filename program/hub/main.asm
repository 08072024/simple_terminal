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



loaded_msg: db 'Welcome to the simple_terminal OS hub', 0
hub_question: db 'What would you like to do (Enter qui for options)?:'