/* ===================================================================== */
/* NoVa OS - Linker Script                                               */
/* ===================================================================== */

ENTRY(_start)
OUTPUT_FORMAT(elf32-i386)

SECTIONS
{
    /* GRUB loads kernels at the 1 Megabyte mark */
    . = 1M;

    /* Put the multiboot header absolutely first, followed by code */
    .text BLOCK(4K) : ALIGN(4K)
    {
        *(.multiboot)
        *(.text)
    }

    /* Read-only data (our strings and font arrays) */
    .rodata BLOCK(4K) : ALIGN(4K)
    {
        *(.rodata)
    }

    /* Read-write data (initialized variables and color palettes) */
    .data BLOCK(4K) : ALIGN(4K)
    {
        *(.data)
    }

    /* Read-write data (uninitialized) and stack */
    .bss BLOCK(4K) : ALIGN(4K)
    {
        bss_start = .;
        *(COMMON)
        *(.bss)
        bss_end = .;
    }
}