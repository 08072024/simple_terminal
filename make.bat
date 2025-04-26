@echo off
setlocal

echo Creating necessary directories...
mkdir build 2>nul
mkdir bin 2>nul

echo Assembling bootloader...
nasm -f bin bootloader/new_boot.asm -o build\boot.bin

echo Assembling kernel entry...
echo nasm -f bin program/hub/main.asm -o build\main.bin

echo Merging bootloader and stage2...
copy /b build\boot.bin+bin\main.bin build\os.bin > nul

echo Booting QEMU...
qemu-system-i386 -fda build\os.bin

endlocal
