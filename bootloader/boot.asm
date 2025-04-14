[org 0x7c00]
[bits 16]

;
; FAT12 header
; If you want to know what the fuck any of this means I have documented it pretty good if you ask me but I'd go to Nanobyte's YouTube channel and watch part 3, where he explains it all very well!
;

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

start:
  ; Setup data segments
  mov ax, 0
  mov ds, ax
  mov es, ax

  ; Setup stack
  mov ss, ax
  mov sp, 0x7c00

  mov si, go_to_address
  push si
  call find_file

go_to_address: db 'MAIN    BIN'

times 510 - ($ - $$) db 0
dw 0aa55h