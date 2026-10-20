/* link_qemu.ld  參考模型用（QEMU virt，RAM 從 0x80000000 開始，指令與資料共用）。
   只用來產生 Zbb 測試的「參考簽章」（3.9.1 版測試沒有附 reference_output）；不是被測對象。 */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }
  . = ALIGN(0x1000);
  .data      : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) }
  .bss       : { *(.bss) *(.sbss) *(COMMON) }
  /DISCARD/  : { *(.riscv.attributes) *(.comment) *(.note*) }
}
