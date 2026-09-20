/* CPU1 application region.  CPU0 uses the normal low-DDR linker script. */

_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x4000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x2000;
_ABORT_STACK_SIZE = 1024;
_SUPERVISOR_STACK_SIZE = 2048;
_IRQ_STACK_SIZE = 1024;
_FIQ_STACK_SIZE = 1024;
_UNDEF_STACK_SIZE = 1024;

MEMORY
{
    cpu1_ddr : ORIGIN = 0x18000000, LENGTH = 0x01000000
}

ENTRY(_vector_table)

SECTIONS
{
    .text : {
        . = ALIGN(2048);
        KEEP (*(.vectors))
        *(.boot)
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
        *(.plt)
        *(.gnu_warning)
        *(.gcc_execpt_table)
        *(.glue_7)
        *(.glue_7t)
        *(.vfp11_veneer)
        *(.ARM.extab)
        *(.gnu.linkonce.armextab.*)
    } > cpu1_ddr

    .init : { KEEP (*(.init)) } > cpu1_ddr
    .fini : { KEEP (*(.fini)) } > cpu1_ddr

    .rodata : {
        __rodata_start = .;
        *(.rodata)
        *(.rodata.*)
        *(.gnu.linkonce.r.*)
        __rodata_end = .;
    } > cpu1_ddr

    .rodata1 : {
        *(.rodata1)
        *(.rodata1.*)
    } > cpu1_ddr

    .sdata2 : {
        __sdata2_start = .;
        *(.sdata2)
        *(.sdata2.*)
        *(.gnu.linkonce.s2.*)
    } > cpu1_ddr

    .sbss2 (NOLOAD) : {
        *(.sbss2)
        *(.sbss2.*)
        *(.gnu.linkonce.sb2.*)
        __sbss2_end = .;
    } > cpu1_ddr

    .data : {
        __data_start = .;
        *(.data)
        *(.data.*)
        *(.gnu.linkonce.d.*)
        *(.jcr)
        *(.got)
        *(.got.plt)
        __data_end = .;
    } > cpu1_ddr

    .data1 : {
        *(.data1)
        *(.data1.*)
    } > cpu1_ddr

    .note.gnu.build-id : {
        KEEP (*(.note.gnu.build-id))
    } > cpu1_ddr

    .ctors : {
        KEEP (*crtbegin.o(.ctors))
        KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
        KEEP (*(SORT(.ctors.*)))
        KEEP (*(.ctors))
    } > cpu1_ddr

    .dtors : {
        KEEP (*crtbegin.o(.dtors))
        KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
    } > cpu1_ddr

    .fixup : {
        *(.fixup)
        *(.eh_frame)
        *(.eh_framehdr)
        *(.gcc_except_table)
    } > cpu1_ddr

    .mmu_tbl (ALIGN(16384)) : {
        __mmu_tbl_start = .;
        *(.mmu_tbl)
        __mmu_tbl_end = .;
    } > cpu1_ddr

    .ARM.exidx : {
        __exidx_start = .;
        *(.ARM.exidx*)
        *(.gnu.linkonce.armexidix.*.*)
        __exidx_end = .;
    } > cpu1_ddr

    .preinit_array : {
        __preinit_array_start = .;
        KEEP (*(SORT(.preinit_array.*)))
        KEEP (*(.preinit_array))
        __preinit_array_end = .;
    } > cpu1_ddr

    .init_array : {
        __init_array_start = .;
        KEEP (*(SORT(.init_array.*)))
        KEEP (*(.init_array))
        __init_array_end = .;
    } > cpu1_ddr

    .fini_array : {
        __fini_array_start = .;
        KEEP (*(SORT(.fini_array.*)))
        KEEP (*(.fini_array))
        __fini_array_end = .;
    } > cpu1_ddr

    .ARM.attributes : {
        *(.ARM.attributes)
    } > cpu1_ddr

    .sdata : {
        __sdata_start = .;
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
    } > cpu1_ddr

    .sbss (NOLOAD) : {
        __sbss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.gnu.linkonce.sb.*)
        __sbss_end = .;
    } > cpu1_ddr

    .tdata : {
        *(.tdata)
        *(.tdata.*)
        *(.gnu.linkonce.td.*)
    } > cpu1_ddr

    .tbss (NOLOAD) : {
        *(.tbss)
        *(.tbss.*)
        *(.gnu.linkonce.tb.*)
    } > cpu1_ddr

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)
        __bss_end = .;
    } > cpu1_ddr

    _SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2);
    _SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2);

    .heap (NOLOAD) : {
        . = ALIGN(16);
        _heap = .;
        HeapBase = .;
        . += _HEAP_SIZE;
        _heap_end = .;
        HeapLimit = .;
    } > cpu1_ddr

    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_end = .;
        . += _STACK_SIZE;
        . = ALIGN(16);
        _stack = .;
        __stack = _stack;
        _irq_stack_end = .;
        . += _IRQ_STACK_SIZE;
        . = ALIGN(16);
        __irq_stack = .;
        _supervisor_stack_end = .;
        . += _SUPERVISOR_STACK_SIZE;
        . = ALIGN(16);
        __supervisor_stack = .;
        _abort_stack_end = .;
        . += _ABORT_STACK_SIZE;
        . = ALIGN(16);
        __abort_stack = .;
        _fiq_stack_end = .;
        . += _FIQ_STACK_SIZE;
        . = ALIGN(16);
        __fiq_stack = .;
        _undef_stack_end = .;
        . += _UNDEF_STACK_SIZE;
        . = ALIGN(16);
        __undef_stack = .;
    } > cpu1_ddr

    _end = .;
}
