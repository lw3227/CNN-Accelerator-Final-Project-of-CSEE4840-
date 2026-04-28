#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../include/cnn_mmio_host.h"

static double cycles_to_us(uint32_t cycles, double fabric_mhz) {
  if (fabric_mhz <= 0.0)
    return 0.0;
  return (double)cycles / fabric_mhz;
}

int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  uintptr_t csr_base;
  double fabric_mhz = CNN_MMIO_DEFAULT_FABRIC_MHZ;
  struct cnn_mmio_device dev;
  struct cnn_mmio_profile profile;

  if (argc < 2 || argc > 4) {
    fprintf(stderr,
            "usage: %s <csr_base_hex> [fabric_mhz] [devmem_path]\n",
            argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  if (argc >= 3)
    fabric_mhz = strtod(argv[2], NULL);
  if (argc >= 4)
    devmem_path = argv[3];

  if (cnn_mmio_open(&dev, csr_base, devmem_path) != 0)
    return 1;

  cnn_mmio_read_profile(dev.mmio_base, &profile);

  printf("fabric_mhz=%.3f\n", fabric_mhz);
  printf("l1_cycles=%u\n", profile.l1_cycles);
  printf("l2_p0_cycles=%u\n", profile.l2_p0_cycles);
  printf("l2_p1_cycles=%u\n", profile.l2_p1_cycles);
  printf("l3_p0_cycles=%u\n", profile.l3_p0_cycles);
  printf("l3_p1_cycles=%u\n", profile.l3_p1_cycles);
  printf("fc_cycles=%u\n", profile.fc_cycles);
  printf("argmax_cycles=%u\n", profile.argmax_cycles);
  printf("total_cycles=%u\n", profile.total_cycles);
  printf("l1_us=%.3f\n", cycles_to_us(profile.l1_cycles, fabric_mhz));
  printf("l2_p0_us=%.3f\n", cycles_to_us(profile.l2_p0_cycles, fabric_mhz));
  printf("l2_p1_us=%.3f\n", cycles_to_us(profile.l2_p1_cycles, fabric_mhz));
  printf("l3_p0_us=%.3f\n", cycles_to_us(profile.l3_p0_cycles, fabric_mhz));
  printf("l3_p1_us=%.3f\n", cycles_to_us(profile.l3_p1_cycles, fabric_mhz));
  printf("fc_us=%.3f\n", cycles_to_us(profile.fc_cycles, fabric_mhz));
  printf("argmax_us=%.3f\n", cycles_to_us(profile.argmax_cycles, fabric_mhz));
  printf("total_us=%.3f\n", cycles_to_us(profile.total_cycles, fabric_mhz));

  cnn_mmio_close(&dev);
  return 0;
}
