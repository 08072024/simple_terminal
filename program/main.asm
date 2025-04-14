[bits 16]

;
; EXTERNAL SHIT
;
extern find_file

main:
    mov si, loaded_msg
    call print

    mov ax, go_to_address
    push ax
    call find_file

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

loaded_msg: db 'Hello World from the program motherfuckers!', 0
go_to_address: db 'MAIN    BIN'
return_to_address: db 'MAIN    BIN'