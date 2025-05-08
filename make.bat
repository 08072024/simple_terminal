@echo off
setlocal

echo Creating necessary directories...
mkdir build 2>nul

echo Assembling bootloader...
nasm -f bin bootloader/boot.asm -o build/boot.bin

echo Assembling stage 2 loader...
nasm -f bin program/hub/test_main.asm -o build/main.bin

echo Merging bootloader and stage 2 into os.bin...

:: Copy bootloader (should be exactly 512 bytes)
copy /b build\boot.bin + build\main.bin build\os.bin >nul

:: Make sure os.bin is at least 1.44MB for QEMU floppy
fsutil file createnew build\padding.bin 1474560 >nul
copy /b build\os.bin + build\padding.bin build\floppy.img >nul
del build\padding.bin

echo Booting QEMU...
qemu-system-i386 -fda build\floppy.img

endlocal