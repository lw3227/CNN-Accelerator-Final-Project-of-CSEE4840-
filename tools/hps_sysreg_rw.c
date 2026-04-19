#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#define SYSREG_MAP_SPAN_BYTES 4096u

static void usage(const char *argv0) {
  fprintf(stderr,
          "usage: %s read <addr_hex> [devmem_path]\n"
          "       %s write <addr_hex> <value_hex> [devmem_path]\n",
          argv0, argv0);
}

int main(int argc, char **argv) {
  const char *op;
  const char *devmem_path = "/dev/mem";
  uintptr_t addr;
  uintptr_t page_base;
  size_t page_off;
  uint32_t value = 0;
  int fd;
  void *map_base;
  volatile uint32_t *reg32;

  if (argc < 3) {
    usage(argv[0]);
    return 1;
  }

  op = argv[1];
  addr = (uintptr_t)strtoull(argv[2], NULL, 0);
  page_base = addr & ~(uintptr_t)(SYSREG_MAP_SPAN_BYTES - 1u);
  page_off = (size_t)(addr - page_base);

  if ((page_off & 0x3u) != 0u) {
    fprintf(stderr, "address 0x%08" PRIxPTR " is not 32-bit aligned\n", addr);
    return 1;
  }

  if (op[0] == 'w') {
    if (argc < 4 || argc > 5) {
      usage(argv[0]);
      return 1;
    }
    value = (uint32_t)strtoul(argv[3], NULL, 0);
    if (argc == 5)
      devmem_path = argv[4];
  } else if (op[0] == 'r') {
    if (argc > 4) {
      usage(argv[0]);
      return 1;
    }
    if (argc == 4)
      devmem_path = argv[3];
  } else {
    usage(argv[0]);
    return 1;
  }

  fd = open(devmem_path, O_RDWR | O_SYNC);
  if (fd < 0) {
    perror(devmem_path);
    return 1;
  }

  map_base = mmap(NULL, SYSREG_MAP_SPAN_BYTES, PROT_READ | PROT_WRITE,
                  MAP_SHARED, fd, (off_t)page_base);
  if (map_base == MAP_FAILED) {
    perror("mmap");
    close(fd);
    return 1;
  }

  reg32 = (volatile uint32_t *)((volatile uint8_t *)map_base + page_off);

  if (op[0] == 'w') {
    *reg32 = value;
    printf("write[0x%08" PRIxPTR "] = 0x%08" PRIx32 "\n", addr, value);
  } else {
    value = *reg32;
    printf("read[0x%08" PRIxPTR "] = 0x%08" PRIx32 "\n", addr, value);
  }

  munmap(map_base, SYSREG_MAP_SPAN_BYTES);
  close(fd);
  return 0;
}
