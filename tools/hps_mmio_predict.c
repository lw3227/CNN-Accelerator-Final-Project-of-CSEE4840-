#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "../include/cnn_mmio_host.h"

static double monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  const char *case_root;
  uintptr_t csr_base;
  uint16_t status = 0;
  uint16_t error_reg = 0;
  struct cnn_mmio_device dev;
  struct cnn_mmio_inference_case tc;
  struct cnn_mmio_profile profile;
  double total_started_ms;
  double case_load_started_ms;
  double case_load_ended_ms;
  double mmio_program_started_ms;
  double mmio_program_ended_ms;
  double infer_started_ms;
  double infer_ended_ms;

  if (argc < 3 || argc > 4) {
    fprintf(stderr, "usage: %s <csr_base_hex> <case_root> [devmem_path]\n", argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  case_root = argv[2];
  if (argc > 3)
    devmem_path = argv[3];

  total_started_ms = monotonic_ms();
  case_load_started_ms = monotonic_ms();
  if (cnn_mmio_load_inference_case(case_root, &tc) != 0)
    return 1;
  case_load_ended_ms = monotonic_ms();
  if (cnn_mmio_open(&dev, csr_base, devmem_path) != 0)
    return 1;

  mmio_program_started_ms = monotonic_ms();
  cnn_mmio_program_default_registers(dev.mmio_base);
  cnn_mmio_write_inference_case(dev.mmio_base, &tc);
  mmio_program_ended_ms = monotonic_ms();

  infer_started_ms = monotonic_ms();
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
  infer_ended_ms = monotonic_ms();

  error_reg = cnn_mmio_read_error(dev.mmio_base);
  cnn_mmio_read_profile(dev.mmio_base, &profile);
  printf("predict_class=%u\n", (unsigned)cnn_mmio_pack_status_predict(status));
  printf("status=0x%04x\n", status);
  printf("error=0x%04x\n", error_reg);
  printf("l1_cycles=%u\n", profile.l1_cycles);
  printf("l2_p0_cycles=%u\n", profile.l2_p0_cycles);
  printf("l2_p1_cycles=%u\n", profile.l2_p1_cycles);
  printf("l3_p0_cycles=%u\n", profile.l3_p0_cycles);
  printf("l3_p1_cycles=%u\n", profile.l3_p1_cycles);
  printf("fc_cycles=%u\n", profile.fc_cycles);
  printf("argmax_cycles=%u\n", profile.argmax_cycles);
  printf("total_cycles=%u\n", profile.total_cycles);
  printf("board_case_load_ms=%.3f\n", case_load_ended_ms - case_load_started_ms);
  printf("board_program_ms=%.3f\n", mmio_program_ended_ms - mmio_program_started_ms);
  printf("board_infer_wait_ms=%.3f\n", infer_ended_ms - infer_started_ms);
  printf("board_total_ms=%.3f\n", infer_ended_ms - total_started_ms);

  cnn_mmio_close(&dev);
  return (error_reg == 0) ? 0 : 1;
}
