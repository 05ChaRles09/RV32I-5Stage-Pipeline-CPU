// wrap/arch_test.h  包裝官方 riscv-test-env/arch_test.h，只修一個工具鏈相容性問題：
// GNU as 13 拒絕 `la x0, sym`（jalr-01 以 rd = x0 測試 jalr）。`la x0, sym` 本來就不會改變任何架構狀態，
// 所以在目的暫存器是 x0 時，改用同樣 8 位元組的 `auipc x0,0 ; addi x0,x0,0`（版面不變）。其餘巨集完全沿用官方版本。
#include_next "arch_test.h"

.macro LAX rd, sym
  .ifc \rd, x0
    auipc x0, 0
    addi  x0, x0, 0
  .else
    la \rd, \sym
  .endif
.endm

#undef LA
#define LA(reg,val);\
    .option push;\
    .option norvc;\
    LAX reg,val;\
    .option pop;
