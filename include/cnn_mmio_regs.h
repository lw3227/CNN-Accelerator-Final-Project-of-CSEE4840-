#ifndef CNN_MMIO_REGS_H
#define CNN_MMIO_REGS_H

#include <stdint.h>

/*
 * Shared register/memory map for cnn_mmio_interface.
 *
 * The RTL uses address[18] to split the space:
 *   0x00000..0x3FFFF : 32-bit scratchpad memory space
 *   0x40000..0x4001F : 32-bit config/status register space
 *
 * Userspace/HPS code should address 32-bit words, not bytes.
 */

#define CNN_MMIO_MEM_SPACE_BIT   (0u << 18)
#define CNN_MMIO_CFG_SPACE_BIT   (1u << 18)

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
#define CNN_MMIO_REG_PROFILE_L1_LO     14u
#define CNN_MMIO_REG_PROFILE_L1_HI     15u
#define CNN_MMIO_REG_PROFILE_L2_P0_LO  16u
#define CNN_MMIO_REG_PROFILE_L2_P0_HI  17u
#define CNN_MMIO_REG_PROFILE_L2_P1_LO  18u
#define CNN_MMIO_REG_PROFILE_L2_P1_HI  19u
#define CNN_MMIO_REG_PROFILE_L3_P0_LO  20u
#define CNN_MMIO_REG_PROFILE_L3_P0_HI  21u
#define CNN_MMIO_REG_PROFILE_L3_P1_LO  22u
#define CNN_MMIO_REG_PROFILE_L3_P1_HI  23u
#define CNN_MMIO_REG_PROFILE_FC_LO     24u
#define CNN_MMIO_REG_PROFILE_FC_HI     25u
#define CNN_MMIO_REG_PROFILE_ARGMAX_LO 26u
#define CNN_MMIO_REG_PROFILE_ARGMAX_HI 27u
#define CNN_MMIO_REG_PROFILE_TOTAL_LO  28u
#define CNN_MMIO_REG_PROFILE_TOTAL_HI  29u
/* Optional debug/readback helpers. Not used by the normal host flow. */
#define CNN_MMIO_REG_LAST_WRITE        30u
#define CNN_MMIO_REG_MAGIC            31u

#define CNN_MMIO_CTRL_MODEL_LOAD   0x0001u
#define CNN_MMIO_CTRL_INFER        0x0002u
#define CNN_MMIO_CTRL_CLEAR_STATUS 0x0004u

#define CNN_MMIO_STATUS_BUSY_SHIFT         1u
#define CNN_MMIO_STATUS_MODEL_LOADED_SHIFT 2u
#define CNN_MMIO_STATUS_PREDICT_DONE_SHIFT 3u
#define CNN_MMIO_STATUS_PREDICT_SHIFT      4u

/*
 * Default staged memory layout for the current 64x64x1 -> 10-class model.
 *
 * All *_WORDS values count 32-bit host words. All *_BASE_W values are
 * 32-bit word addresses because the MMIO scratchpad is word-indexed.
 *
 * Model structure behind these constants:
 *   - L1 conv: 3x3x1  -> DOT_K = 9
 *   - L2 conv: 3x3x4  -> DOT_K = 36, split into pass0/pass1
 *   - L3 conv: 3x3x8  -> DOT_K = 72, split into pass0/pass1
 *   - FC: 6x6x8 = 288 inputs -> 10 outputs
 *
 * Derived word counts:
 *   - CONV_CFG_WORDS = 5 passes x 9 cfg words/pass = 45
 *     (L1, L2p0, L2p1, L3p0, L3p1)
 *   - CONV_WT_WORDS  = 9 + 36 + 36 + 72 + 72 = 225
 *   - FC_BIAS_WORDS  = 10 output classes = 10
 *   - FCW_WORDS      = 288 FC positions x 3 host words/position = 864
 *     Each FC position stores 10x8b = 80b of weights, packed from 3x32b.
 *   - IMAGE_WORDS    = 64x64x1 int8 pixels / 4 pixels per 32-bit word = 1024
 *
 * Base addresses are packed contiguously in word units:
 *   conv_cfg @   0
 *   conv_wt  @   0 + 45     = 45
 *   fc_bias  @  45 + 225    = 270
 *   fcw      @ 270 + 10     = 280
 *   image    @ 280 + 864    = 1144
 */
#define CNN_MMIO_DEFAULT_CONV_CFG_BASE_W  0u
#define CNN_MMIO_DEFAULT_CONV_CFG_WORDS   45u
#define CNN_MMIO_DEFAULT_CONV_WT_BASE_W   45u
#define CNN_MMIO_DEFAULT_CONV_WT_WORDS    225u
#define CNN_MMIO_DEFAULT_FC_BIAS_BASE_W   270u
#define CNN_MMIO_DEFAULT_FC_BIAS_WORDS    10u
#define CNN_MMIO_DEFAULT_FCW_BASE_W       280u
#define CNN_MMIO_DEFAULT_FCW_WORDS        864u
#define CNN_MMIO_DEFAULT_IMAGE_BASE_W     1144u
#define CNN_MMIO_DEFAULT_IMAGE_WORDS      1024u

static inline uint32_t cnn_mmio_cfg_addr(uint32_t reg_idx) {
  return CNN_MMIO_CFG_SPACE_BIT | (reg_idx & 0x1Fu);
}

static inline uint32_t cnn_mmio_mem_addr(uint32_t word_addr) {
  return CNN_MMIO_MEM_SPACE_BIT | (word_addr & 0x3FFFFu);
}

static inline uint32_t cnn_mmio_pack_status_predict(uint16_t status_word) {
  return (status_word >> CNN_MMIO_STATUS_PREDICT_SHIFT) & 0xFu;
}

static inline uint32_t cnn_mmio_status_busy(uint16_t status_word) {
  return (status_word >> CNN_MMIO_STATUS_BUSY_SHIFT) & 0x1u;
}

static inline uint32_t cnn_mmio_status_model_loaded(uint16_t status_word) {
  return (status_word >> CNN_MMIO_STATUS_MODEL_LOADED_SHIFT) & 0x1u;
}

static inline uint32_t cnn_mmio_status_predict_done(uint16_t status_word) {
  return (status_word >> CNN_MMIO_STATUS_PREDICT_DONE_SHIFT) & 0x1u;
}

#endif
