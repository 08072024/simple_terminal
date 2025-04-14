.PHONY: all floppy_image bootloader clean

all: floppy_image

#
# Floppy image
#
floppy_image: main_floppy.img

main_floppy.img: bootloader
	dd if=/dev/zero of=build/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "TROS" build/main_floppy.img
	dd if=build/boot.bin of=build/main_floppy.img conv=notrunc
	mcopy -i build/main_floppy.img build/main.bin "::main.bin"

#
# Bootloader
#
bootloader: boot main

boot: build/boot.bin

main: build/main.bin