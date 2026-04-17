#define _POSIX_C_SOURCE 200809L

#include "../include/cnn_mmio_host.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static int read_i32_lines(const char *path, int32_t *dst, size_t count) {
  FILE *fp = fopen(path, "r");
  size_t i;
  if (!fp) {
    perror(path);
    return -1;
  }
  for (i = 0; i < count; ++i) {
    if (fscanf(fp, "%" SCNd32, &dst[i]) != 1) {
      fprintf(stderr, "short read in %s at index %zu\n", path, i);
      fclose(fp);
      return -1;
    }
  }
  fclose(fp);
  return 0;
}

static int read_packed_i8_words(const char *path, uint32_t *dst, size_t word_count) {
  FILE *fp = fopen(path, "r");
  size_t i;
  if (!fp) {
    perror(path);
    return -1;
  }
  for (i = 0; i < word_count; ++i) {
    int32_t b0, b1, b2, b3;
    if (fscanf(fp, "%" SCNd32, &b0) != 1 ||
        fscanf(fp, "%" SCNd32, &b1) != 1 ||
        fscanf(fp, "%" SCNd32, &b2) != 1 ||
        fscanf(fp, "%" SCNd32, &b3) != 1) {
      fprintf(stderr, "short packed read in %s at word %zu\n", path, i);
      fclose(fp);
      return -1;
    }
    dst[i] = ((uint32_t)(b0 & 0xFF)) |
             ((uint32_t)(b1 & 0xFF) << 8) |
             ((uint32_t)(b2 & 0xFF) << 16) |
             ((uint32_t)(b3 & 0xFF) << 24);
  }
  fclose(fp);
  return 0;
}

static int load_manifest_expected_class(const char *path, int *expected_class) {
  FILE *fp = fopen(path, "r");
  char line[256];
  if (!fp) {
    perror(path);
    return -1;
  }
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, "predict_class=", 14) == 0) {
      *expected_class = atoi(line + 14);
      fclose(fp);
      return 0;
    }
  }
  fclose(fp);
  fprintf(stderr, "predict_class not found in %s\n", path);
  return -1;
}

static void build_path(char *dst, size_t dst_len, const char *root, const char *leaf) {
  snprintf(dst, dst_len, "%s/%s", root, leaf);
}

static void mmio_write16(volatile uint16_t *base, uint32_t halfword_addr, uint16_t value) {
  base[halfword_addr] = value;
}

static uint16_t mmio_read16(volatile uint16_t *base, uint32_t halfword_addr) {
  return base[halfword_addr];
}

static void write_word_image(volatile uint16_t *base, uint32_t start_halfword,
                             const uint32_t *words, size_t word_count) {
  size_t i;
  for (i = 0; i < word_count; ++i) {
    uint32_t word = words[i];
    mmio_write16(base, cnn_mmio_mem_addr(start_halfword + (uint32_t)(i * 2)), (uint16_t)(word & 0xFFFFu));
    mmio_write16(base, cnn_mmio_mem_addr(start_halfword + (uint32_t)(i * 2 + 1)), (uint16_t)((word >> 16) & 0xFFFFu));
  }
}

int cnn_mmio_load_preload_bundle(const char *preload_root, struct cnn_mmio_preload_bundle *bundle) {
  char path[1024];
  build_path(path, sizeof(path), preload_root, "conv_cfg_words.txt");
  if (read_i32_lines(path, bundle->conv_cfg, CNN_MMIO_DEFAULT_CONV_CFG_WORDS) != 0)
    return -1;

  build_path(path, sizeof(path), preload_root, "conv_wt_words.txt");
  if (read_packed_i8_words(path, bundle->conv_wt, CNN_MMIO_DEFAULT_CONV_WT_WORDS) != 0)
    return -1;

  build_path(path, sizeof(path), preload_root, "fc_bias_words.txt");
  if (read_i32_lines(path, bundle->fc_bias, CNN_MMIO_DEFAULT_FC_BIAS_WORDS) != 0)
    return -1;

  build_path(path, sizeof(path), preload_root, "fcw_words.txt");
  if (read_i32_lines(path, (int32_t *)bundle->fcw, CNN_MMIO_DEFAULT_FCW_WORDS) != 0)
    return -1;

  return 0;
}

int cnn_mmio_load_inference_case(const char *case_root, struct cnn_mmio_inference_case *tc) {
  char path[1024];
  build_path(path, sizeof(path), case_root, "image_words.txt");
  if (read_packed_i8_words(path, tc->image, CNN_MMIO_DEFAULT_IMAGE_WORDS) != 0)
    return -1;

  build_path(path, sizeof(path), case_root, "manifest.txt");
  if (load_manifest_expected_class(path, &tc->expected_class) != 0)
    return -1;

  return 0;
}

int cnn_mmio_open(struct cnn_mmio_device *dev, uintptr_t csr_base, const char *devmem_path) {
  memset(dev, 0, sizeof(*dev));
  dev->fd = open(devmem_path, O_RDWR | O_SYNC);
  if (dev->fd < 0) {
    perror(devmem_path);
    return -1;
  }

  dev->map_base = mmap(NULL, CNN_MMIO_MAP_SPAN_BYTES, PROT_READ | PROT_WRITE,
                       MAP_SHARED, dev->fd, csr_base);
  if (dev->map_base == MAP_FAILED) {
    perror("mmap");
    close(dev->fd);
    dev->fd = -1;
    return -1;
  }

  dev->mmio_base = (volatile uint16_t *)dev->map_base;
  dev->csr_base = csr_base;
  return 0;
}

void cnn_mmio_close(struct cnn_mmio_device *dev) {
  if (dev->map_base && dev->map_base != MAP_FAILED) {
    munmap(dev->map_base, CNN_MMIO_MAP_SPAN_BYTES);
  }
  if (dev->fd >= 0) {
    close(dev->fd);
  }
  dev->fd = -1;
  dev->map_base = NULL;
  dev->mmio_base = NULL;
  dev->csr_base = 0;
}

void cnn_mmio_program_default_registers(volatile uint16_t *mmio_base) {
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONV_CFG_BASE), CNN_MMIO_DEFAULT_CONV_CFG_BASE_HW);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONV_CFG_LEN), CNN_MMIO_DEFAULT_CONV_CFG_WORDS);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONV_WT_BASE), CNN_MMIO_DEFAULT_CONV_WT_BASE_HW);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONV_WT_LEN), CNN_MMIO_DEFAULT_CONV_WT_WORDS);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_FC_BIAS_BASE), CNN_MMIO_DEFAULT_FC_BIAS_BASE_HW);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_FC_BIAS_LEN), CNN_MMIO_DEFAULT_FC_BIAS_WORDS);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_FCW_BASE), CNN_MMIO_DEFAULT_FCW_BASE_HW);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_FCW_LEN), CNN_MMIO_DEFAULT_FCW_WORDS);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_IMAGE_BASE), CNN_MMIO_DEFAULT_IMAGE_BASE_HW);
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_IMAGE_LEN), CNN_MMIO_DEFAULT_IMAGE_WORDS);
}

void cnn_mmio_write_preload_bundle(volatile uint16_t *mmio_base, const struct cnn_mmio_preload_bundle *bundle) {
  write_word_image(mmio_base, CNN_MMIO_DEFAULT_CONV_CFG_BASE_HW, (const uint32_t *)bundle->conv_cfg,
                   CNN_MMIO_DEFAULT_CONV_CFG_WORDS);
  write_word_image(mmio_base, CNN_MMIO_DEFAULT_CONV_WT_BASE_HW, bundle->conv_wt,
                   CNN_MMIO_DEFAULT_CONV_WT_WORDS);
  write_word_image(mmio_base, CNN_MMIO_DEFAULT_FC_BIAS_BASE_HW, (const uint32_t *)bundle->fc_bias,
                   CNN_MMIO_DEFAULT_FC_BIAS_WORDS);
  write_word_image(mmio_base, CNN_MMIO_DEFAULT_FCW_BASE_HW, (const uint32_t *)bundle->fcw,
                   CNN_MMIO_DEFAULT_FCW_WORDS);
}

void cnn_mmio_write_inference_case(volatile uint16_t *mmio_base, const struct cnn_mmio_inference_case *tc) {
  write_word_image(mmio_base, CNN_MMIO_DEFAULT_IMAGE_BASE_HW, tc->image,
                   CNN_MMIO_DEFAULT_IMAGE_WORDS);
}

uint16_t cnn_mmio_read_status(volatile uint16_t *mmio_base) {
  return mmio_read16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_STATUS));
}

uint16_t cnn_mmio_read_error(volatile uint16_t *mmio_base) {
  return mmio_read16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_IF_ERROR));
}

uint16_t cnn_mmio_read_predict(volatile uint16_t *mmio_base) {
  return mmio_read16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_PREDICT));
}

void cnn_mmio_clear_status(volatile uint16_t *mmio_base) {
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONTROL), CNN_MMIO_CTRL_CLEAR_STATUS);
}

void cnn_mmio_start_model_load(volatile uint16_t *mmio_base) {
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONTROL), CNN_MMIO_CTRL_MODEL_LOAD);
}

void cnn_mmio_start_infer(volatile uint16_t *mmio_base) {
  mmio_write16(mmio_base, cnn_mmio_cfg_addr(CNN_MMIO_REG_CONTROL), CNN_MMIO_CTRL_INFER);
}

int cnn_mmio_wait_for_status_bit(
    volatile uint16_t *mmio_base,
    unsigned bit_idx,
    unsigned expected_value,
    int timeout_ms,
    uint16_t *last_status) {
  struct timespec req;
  int elapsed_ms = 0;
  if (bit_idx >= 16)
    return -1;

  req.tv_sec = 0;
  req.tv_nsec = 1000000L;

  while (elapsed_ms < timeout_ms) {
    uint16_t status = cnn_mmio_read_status(mmio_base);
    if (last_status)
      *last_status = status;
    if (((status >> bit_idx) & 0x1u) == (expected_value & 0x1u))
      return 0;
    nanosleep(&req, NULL);
    elapsed_ms += 1;
  }

  return -1;
}
