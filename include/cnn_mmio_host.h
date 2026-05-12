#ifndef CNN_MMIO_HOST_H
#define CNN_MMIO_HOST_H

#include <stdint.h>

#include "cnn_mmio_regs.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The HPS maps one small page-aligned lightweight-bridge window. The RTL uses
 * 16 KiB of scratchpad, and the highest 32-bit config/status register ends at
 * byte offset 0x407F. A 20 KiB span is the smallest 4 KiB page-aligned mapping
 * that covers the implemented scratchpad and register window.
 */
#define CNN_MMIO_MAP_SPAN_BYTES (20 * 1024)
#define CNN_MMIO_DEFAULT_TIMEOUT_MS 1000
#define CNN_MMIO_DEFAULT_FABRIC_MHZ 50.0

/* Model parameters loaded once before inference requests. */
struct cnn_mmio_preload_bundle {
  int32_t conv_cfg[CNN_MMIO_DEFAULT_CONV_CFG_WORDS];
  uint32_t conv_wt[CNN_MMIO_DEFAULT_CONV_WT_WORDS];
  int32_t fc_bias[CNN_MMIO_DEFAULT_FC_BIAS_WORDS];
  int32_t fcw[CNN_MMIO_DEFAULT_FCW_WORDS];
};

/* One uploaded/test image case in the packed 32-bit word format. */
struct cnn_mmio_inference_case {
  uint32_t image[CNN_MMIO_DEFAULT_IMAGE_WORDS];
  int expected_class;
};

/* Userspace view of the /dev/mem mapping for the FPGA MMIO window. */
struct cnn_mmio_device {
  int fd;
  void *map_base;
  volatile uint32_t *mmio_base;
  uintptr_t csr_base;
};

/* Snapshot of RTL cycle counters exposed through profile registers. */
struct cnn_mmio_profile {
  uint32_t l1_cycles;
  uint32_t l2_p0_cycles;
  uint32_t l2_p1_cycles;
  uint32_t l3_p0_cycles;
  uint32_t l3_p1_cycles;
  uint32_t fc_cycles;
  uint32_t argmax_cycles;
  uint32_t total_cycles;
};

/* File loaders translate text fixtures into packed in-memory C buffers. */
int cnn_mmio_load_preload_bundle(const char *preload_root, struct cnn_mmio_preload_bundle *bundle);
int cnn_mmio_load_inference_case(const char *case_root, struct cnn_mmio_inference_case *tc);

/* Open/close the physical FPGA control window through /dev/mem. */
int cnn_mmio_open(struct cnn_mmio_device *dev, uintptr_t csr_base, const char *devmem_path);
void cnn_mmio_close(struct cnn_mmio_device *dev);

/* Program the scratchpad layout and copy data into the FPGA-visible memory. */
void cnn_mmio_program_default_registers(volatile uint32_t *mmio_base);
void cnn_mmio_write_preload_bundle(volatile uint32_t *mmio_base, const struct cnn_mmio_preload_bundle *bundle);
void cnn_mmio_write_inference_case(volatile uint32_t *mmio_base, const struct cnn_mmio_inference_case *tc);

/* Read software-visible result, error, and profiling registers. */
uint16_t cnn_mmio_read_status(volatile uint32_t *mmio_base);
uint16_t cnn_mmio_read_error(volatile uint32_t *mmio_base);
uint16_t cnn_mmio_read_predict(volatile uint32_t *mmio_base);
void cnn_mmio_read_profile(volatile uint32_t *mmio_base, struct cnn_mmio_profile *profile);

/* Pulse control bits consumed by the RTL wrapper. */
void cnn_mmio_clear_status(volatile uint32_t *mmio_base);
void cnn_mmio_start_model_load(volatile uint32_t *mmio_base);
void cnn_mmio_start_infer(volatile uint32_t *mmio_base);

int cnn_mmio_wait_for_status_bit(
    volatile uint32_t *mmio_base,
    unsigned bit_idx,
    unsigned expected_value,
    int timeout_ms,
    uint16_t *last_status);

#ifdef __cplusplus
}
#endif

#endif
