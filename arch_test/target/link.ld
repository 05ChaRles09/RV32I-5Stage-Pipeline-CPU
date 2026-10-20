/* link.ld  riscv-arch-test 用：指令記憶體與資料記憶體是分開的（Harvard），各 2 MB（模擬用，IMEM/DMEM_ADDR_WIDTH = 21；jal-01 的程式約 1.77 MB）。
   .data 放在 0x200000；DMEM 以 addr[20:2] 索引，所以 0x200000 對應 DMEM 字索引 0。 */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 2M
  DMEM (rw) : ORIGIN = 0x00200000, LENGTH = 2M
}

SECTIONS
{
  .text.init : { *(.text.init) } > IMEM
  .text      : { *(.text) *(.text.*) } > IMEM
  .data      : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > DMEM
  .bss       : { *(.bss) *(.sbss) *(COMMON) } > DMEM
  /DISCARD/  : { *(.riscv.attributes) *(.comment) *(.note*) }
}
