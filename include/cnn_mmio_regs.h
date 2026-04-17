#ifndef CNN_MMIO_REGS_H
#define CNN_MMIO_REGS_H

#include <stdint.h>

/*
 * Shared register/memory map for cnn_mmio_interface.
 *
 * The RTL uses address[19] to split the space:
 *   0x00000..0x7FFFF : 16-bit scratchpad memory space
 *   0x80000..0x8001F : 16-bit config/status register space
 *
 * Userspace/HPS code should address halfwords, not bytes.
 */

#define CNN_MMIO_MEM_SPACE_BIT   (0u << 19)
#define CNN_MMIO_CFG_SPACE_BIT   (1u << 19)

#define CNN_MMIO_REG_CONTROL       0u
#define CNN_MMIO_REG_STATUS        1u
#define CNN_MMIO_REG_CONV_CFG_BASE 2u
#define CNN_MMIO_REG_CONV_CFG_LEN  3u
#define CNN_MMIO_REG_CONV_WT_BASE  4u
#define CNN_MMIO_REG_CONV_WT_LEN   5u
#define CNN_MMIO_REG_FC_BIAS_BASE  6u
#define CNN_MMIO_REG_FC_BIAS_LEN   7u
#define CNN_MMIO_REG_FCW_BASE      8u
#define CNN_MMIO_REG_FCW_LEN       9u
#define CNN_MMIO_REG_IMAGE_BASE    10u
#define CNN_MMIO_REG_IMAGE_LEN     11u
#define CNN_MMIO_REG_PREDICT       12u
#define CNN_MMIO_REG_IF_ERROR      13u

#define CNN_MMIO_CTRL_MODEL_LOAD   0x0001u
#define CNN_MMIO_CTRL_INFER        0x0002u
#define CNN_MMIO_CTRL_CLEAR_STATUS 0x0004u

#define CNN_MMIO_STATUS_BUSY_SHIFT         1u
#define CNN_MMIO_STATUS_MODEL_LOADED_SHIFT 2u
#define CNN_MMIO_STATUS_PREDICT_DONE_SHIFT 3u
#define CNN_MMIO_STATUS_PREDICT_SHIFT      4u

#define CNN_MMIO_DEFAULT_CONV_CFG_BASE_HW 0u
#define CNN_MMIO_DEFAULT_CONV_CFG_WORDS   45u
#define CNN_MMIO_DEFAULT_CONV_WT_BASE_HW  90u
#define CNN_MMIO_DEFAULT_CONV_WT_WORDS    225u
#define CNN_MMIO_DEFAULT_FC_BIAS_BASE_HW  540u
#define CNN_MMIO_DEFAULT_FC_BIAS_WORDS    10u
#define CNN_MMIO_DEFAULT_FCW_BASE_HW      560u
#define CNN_MMIO_DEFAULT_FCW_WORDS        864u
#define CNN_MMIO_DEFAULT_IMAGE_BASE_HW    2288u
#define CNN_MMIO_DEFAULT_IMAGE_WORDS      1024u

static inline uint32_t cnn_mmio_cfg_addr(uint32_t reg_idx) {
  return CNN_MMIO_CFG_SPACE_BIT | (reg_idx & 0x1Fu);
}

static inline uint32_t cnn_mmio_mem_addr(uint32_t halfword_addr) {
  return CNN_MMIO_MEM_SPACE_BIT | (halfword_addr & 0x7FFFFu);
}

static inline uint32_t cnn_mmio_pack_status_predict(uint16_t status_word) {
  return (status_word >> CNN_MMIO_STATUS_PREDICT_SHIFT) & 0xFu;
}

#endif
