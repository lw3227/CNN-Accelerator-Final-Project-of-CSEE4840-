#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../include/cnn_mmio_host.h"

int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  const char *case_root;
  uintptr_t csr_base;
  uint16_t status = 0;
  uint16_t error_reg = 0;
  struct cnn_mmio_device dev;
  struct cnn_mmio_inference_case tc;

  if (argc < 3 || argc > 4) {
    fprintf(stderr,
            "usage: %s <csr_base_hex> <case_root> [devmem_path]\n",
            argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  case_root = argv[2];
  if (argc > 3)
    devmem_path = argv[3];

  if (cnn_mmio_load_inference_case(case_root, &tc) != 0)
    return 1;
  if (cnn_mmio_open(&dev, csr_base, devmem_path) != 0)
    return 1;

  cnn_mmio_program_default_registers(dev.mmio_base);
  cnn_mmio_write_inference_case(dev.mmio_base, &tc);
  cnn_mmio_start_infer(dev.mmio_base);

  if (cnn_mmio_wait_for_status_bit(
          dev.mmio_base,
          CNN_MMIO_STATUS_PREDICT_DONE_SHIFT,
          1,
          CNN_MMIO_DEFAULT_TIMEOUT_MS,
          &status) != 0) {
    fprintf(stderr, "timeout waiting for predict_done, status=0x%04x\n", status);
    cnn_mmio_close(&dev);
    return 1;
  }

  error_reg = cnn_mmio_read_error(dev.mmio_base);
  printf("expected_class=%d\n", tc.expected_class);
  printf("predict_class=%u\n", (unsigned)cnn_mmio_pack_status_predict(status));
  printf("status=0x%04x\n", status);
  printf("error=0x%04x\n", error_reg);

  cnn_mmio_close(&dev);
  return ((int)cnn_mmio_pack_status_predict(status) == tc.expected_class && error_reg == 0)
             ? 0
             : 1;
}
