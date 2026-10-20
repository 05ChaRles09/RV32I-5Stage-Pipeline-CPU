// model_test.h  riscv-arch-test（2.x framework）的 target 定義：RV32I 五級管線 CPU（模擬用，記憶體放大）
// 本核心沒有 CSR / trap / IO；結束用自我跳躍（self_loop），簽章區由 begin_signature / end_signature 界定，
// 由 testbench（sim/tb_archtest.v）在偵測到 self_loop 後從 DMEM 傾印。
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define RVMODEL_DATA_SECTION

// 結束：自我跳躍（jal x0, 0）。tb 以 EX 階段的 PC 偵測。
#define RVMODEL_HALT                                              \
  .global self_loop;                                              \
  self_loop:  j self_loop;

#define RVMODEL_DATA_BEGIN                                              \
  .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                                \
  .align 4; .global end_signature; end_signature:                       \
  RVMODEL_DATA_SECTION

// 沒有需要的開機程式（暫存器由測試自己初始化）
#define RVMODEL_BOOT

// 本核心沒有 IO；斷言巨集留空
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_SP, _STR)
#define RVMODEL_IO_ASSERT_GPR_EQ(_SP, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
