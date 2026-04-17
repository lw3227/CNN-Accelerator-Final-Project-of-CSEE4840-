#ifndef CNN_MMIO_HOST_H
#define CNN_MMIO_HOST_H

#include <stdint.h>

#include "cnn_mmio_regs.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CNN_MMIO_MAP_SPAN_BYTES (4 * 1024 * 1024)
#define CNN_MMIO_DEFAULT_TIMEOUT_MS 1000

struct cnn_mmio_preload_bundle {
  int32_t conv_cfg[CNN_MMIO_DEFAULT_CONV_CFG_WORDS];
  uint32_t conv_wt[CNN_MMIO_DEFAULT_CONV_WT_WORDS];
  int32_t fc_bias[CNN_MMIO_DEFAULT_FC_BIAS_WORDS];
  int32_t fcw[CNN_MMIO_DEFAULT_FCW_WORDS];
};

struct cnn_mmio_inference_case {
  uint32_t image[CNN_MMIO_DEFAULT_IMAGE_WORDS];
  int expected_class;
};

struct cnn_mmio_device {
  int fd;
  void *map_base;
  volatile uint16_t *mmio_base;
  uintptr_t csr_base;
};

int cnn_mmio_load_preload_bundle(const char *preload_root, struct cnn_mmio_preload_bundle *bundle);
int cnn_mmio_load_inference_case(const char *case_root, struct cnn_mmio_inference_case *tc);

int cnn_mmio_open(struct cnn_mmio_device *dev, uintptr_t csr_base, const char *devmem_path);
void cnn_mmio_close(struct cnn_mmio_device *dev);

void cnn_mmio_program_default_registers(volatile uint16_t *mmio_base);
void cnn_mmio_write_preload_bundle(volatile uint16_t *mmio_base, const struct cnn_mmio_preload_bundle *bundle);
void cnn_mmio_write_inference_case(volatile uint16_t *mmio_base, const struct cnn_mmio_inference_case *tc);

uint16_t cnn_mmio_read_status(volatile uint16_t *mmio_base);
uint16_t cnn_mmio_read_error(volatile uint16_t *mmio_base);
uint16_t cnn_mmio_read_predict(volatile uint16_t *mmio_base);

void cnn_mmio_clear_status(volatile uint16_t *mmio_base);
void cnn_mmio_start_model_load(volatile uint16_t *mmio_base);
void cnn_mmio_start_infer(volatile uint16_t *mmio_base);

int cnn_mmio_wait_for_status_bit(
    volatile uint16_t *mmio_base,
    unsigned bit_idx,
    unsigned expected_value,
    int timeout_ms,
    uint16_t *last_status);

#ifdef __cplusplus
}
#endif

#endif
