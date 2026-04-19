#define _POSIX_C_SOURCE 200809L

#include "../include/cnn_mmio_regs.h"

#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#define CNN_MMIO_MAP_SPAN_BYTES (4 * 1024 * 1024)

static void usage(const char *argv0) {
  fprintf(stderr,
          "usage: %s <csr_base_hex> read <halfword_addr_hex> [devmem_path]\n"
          "       %s <csr_base_hex> write <halfword_addr_hex> <value_hex> [devmem_path]\n",
          argv0, argv0);
}

int main(int argc, char **argv) {
  const char *devmem_path = "/dev/mem";
  const char *op;
  uintptr_t csr_base;
  uint32_t halfword_addr;
  uint16_t value = 0;
  int fd;
  void *map_base;
  volatile uint16_t *mmio_base;

  if (argc < 4) {
    usage(argv[0]);
    return 1;
  }

  csr_base = (uintptr_t)strtoull(argv[1], NULL, 0);
  op = argv[2];
  halfword_addr = (uint32_t)strtoul(argv[3], NULL, 0);

  if (halfword_addr >= (CNN_MMIO_MAP_SPAN_BYTES / 2u)) {
    fprintf(stderr, "halfword address 0x%08" PRIx32 " is out of range\n", halfword_addr);
    return 1;
  }

  if (op[0] == 'w') {
    if (argc < 5 || argc > 6) {
      usage(argv[0]);
      return 1;
    }
    value = (uint16_t)strtoul(argv[4], NULL, 0);
    if (argc == 6)
      devmem_path = argv[5];
  } else if (op[0] == 'r') {
    if (argc > 5) {
      usage(argv[0]);
      return 1;
    }
    if (argc == 5)
      devmem_path = argv[4];
  } else {
    usage(argv[0]);
    return 1;
  }

  fd = open(devmem_path, O_RDWR | O_SYNC);
  if (fd < 0) {
    perror(devmem_path);
    return 1;
  }

  map_base = mmap(NULL, CNN_MMIO_MAP_SPAN_BYTES, PROT_READ | PROT_WRITE,
                  MAP_SHARED, fd, csr_base);
  if (map_base == MAP_FAILED) {
    perror("mmap");
    close(fd);
    return 1;
  }

  mmio_base = (volatile uint16_t *)map_base;

  if (op[0] == 'w') {
    mmio_base[halfword_addr] = value;
    printf("write[0x%08" PRIx32 "] = 0x%04x\n", halfword_addr, value);
  } else {
    value = mmio_base[halfword_addr];
    printf("read[0x%08" PRIx32 "] = 0x%04x\n", halfword_addr, value);
  }

  munmap(map_base, CNN_MMIO_MAP_SPAN_BYTES);
  close(fd);
  return 0;
}
