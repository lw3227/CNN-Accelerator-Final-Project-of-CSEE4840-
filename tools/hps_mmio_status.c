#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../include/cnn_mmio_host.h"

/*
 * Web service 请求前使用的轻量状态探针。
 *
 * 它不会修改 FPGA 状态，只 mmap MMIO window，读取 status/prediction/error
 * 寄存器，然后打印 Python 端容易解析的 key=value 文本。
 */
int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  uintptr_t csr_base;
  struct cnn_mmio_device dev;
  uint16_t status;
  uint16_t predict;
  uint16_t error_reg;

  if (argc < 2 || argc > 3) {
    fprintf(stderr, "usage: %s <csr_base_hex> [devmem_path]\n", argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  if (argc > 2)
    devmem_path = argv[2];

  /* csr_base 是 Platform Designer slave window 的物理地址。 */
  if (cnn_mmio_open(&dev, csr_base, devmem_path) != 0)
    return 1;

  status = cnn_mmio_read_status(dev.mmio_base);
  predict = cnn_mmio_read_predict(dev.mmio_base);
  error_reg = cnn_mmio_read_error(dev.mmio_base);

  printf("status=0x%04x\n", status);
  printf("model_loaded=%u\n", (unsigned)cnn_mmio_status_model_loaded(status));
  printf("predict_done=%u\n", (unsigned)cnn_mmio_status_predict_done(status));
  printf("predict_class=%u\n", (unsigned)(predict & 0xF));
  printf("error=0x%04x\n", error_reg);

  cnn_mmio_close(&dev);
  return 0;
}
