#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../include/cnn_mmio_host.h"

int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  const char *preload_root;
  uintptr_t csr_base;
  uint16_t status = 0;
  struct cnn_mmio_device dev;
  struct cnn_mmio_preload_bundle preload;

  if (argc < 3 || argc > 4) {
    fprintf(stderr,
            "usage: %s <csr_base_hex> <preload_root> [devmem_path]\n",
            argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  preload_root = argv[2];
  if (argc > 3)
    devmem_path = argv[3];

  if (cnn_mmio_load_preload_bundle(preload_root, &preload) != 0)
    return 1;
  if (cnn_mmio_open(&dev, csr_base, devmem_path) != 0)
    return 1;

  cnn_mmio_program_default_registers(dev.mmio_base);
  cnn_mmio_write_preload_bundle(dev.mmio_base, &preload);
  cnn_mmio_clear_status(dev.mmio_base);
  cnn_mmio_start_model_load(dev.mmio_base);

  if (cnn_mmio_wait_for_status_bit(
          dev.mmio_base,
          CNN_MMIO_STATUS_MODEL_LOADED_SHIFT,
          1,
          CNN_MMIO_DEFAULT_TIMEOUT_MS,
          &status) != 0) {
    fprintf(stderr, "timeout waiting for model_loaded, status=0x%04x\n", status);
    cnn_mmio_close(&dev);
    return 1;
  }

  printf("status=0x%04x\n", status);
  printf("model_loaded=%u\n", (unsigned)((status >> CNN_MMIO_STATUS_MODEL_LOADED_SHIFT) & 0x1));
  cnn_mmio_close(&dev);
  return 0;
}
