ENTRY(start)

SECTIONS {
    . = 0x1000;

    .text : {
        *(.text)       /* All .text sections */
    }

    .rodata : {
        *(.rodata)     /* Read-only data */
    }

    .data : {
        *(.data)       /* Initialized data */
    }

    .bss : {
        *(.bss COMMON) /* Uninitialized data */
    }
}