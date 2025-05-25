.PHONY: all floppy_image bootloader clean

all: floppy_image

#
# Floppy image
#
floppy_image: main_floppy.img

main_floppy.img: bootloader program
	dd if=/dev/zero of=build/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "TROS" build/main_floppy.img
	dd if=build/boot.bin of=build/main_floppy.img conv=notrunc
	mcopy -i build/main_floppy.img build/main.bin "::main.bin"
	mcopy -i build/main_floppy.img build/mov.bin "::mov.bin"

#
# Bootloader
#
bootloader: boot main

boot: build/boot.bin

main: build/main.bin

run:
	qemu-system-i386 -fda build/main_floppy.img

make:
	nasm -f bin bootloader/boot.asm -o build/boot.bin
	nasm -f bin program/hub/main.asm -o build/main.bin

	nasm -f bin program/stations/mov.asm -o build/mov.bin

clean:
	rm -rf build/*