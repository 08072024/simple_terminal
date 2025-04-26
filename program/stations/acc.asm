[bits 16]

start:
  mov si, loaded_msg
  call print
  cli
  hlt

print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0e
  int 0x10
  jmp print
.done:
  ret

loaded_msg: db 'You have just loaded into a station', 0