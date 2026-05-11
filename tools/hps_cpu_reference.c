#define _POSIX_C_SOURCE 200809L

/*
 * 浏览器 demo 使用的 HPS ARM CPU reference。
 *
 * 这个程序在板子的 ARM CPU 上运行同一个量化网络，并且读取和 FPGA 相同的
 * exported case 文件。这样 web UI 可以展示 same-board 软件 baseline，也能让
 * FPGA speedup 数字更容易解释。
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define IMG_H 64
#define IMG_W 64
#define C1_OUT 4
#define C2_OUT 8
#define C3_OUT 8
#define FC_OUT 10

#define C1_H 62
#define C1_W 62
#define P1_H 31
#define P1_W 31
#define C2_H 29
#define C2_W 29
#define P2_H 14
#define P2_W 14
#define C3_H 12
#define C3_W 12
#define P3_H 6
#define P3_W 6
#define FC_IN 288

static double monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static int read_i8_lines(const char *path, int8_t *dst, size_t count) {
  FILE *fp = fopen(path, "r");
  size_t i;
  long v;
  if (!fp) {
    perror(path);
    return -1;
  }
  for (i = 0; i < count; ++i) {
    if (fscanf(fp, "%ld", &v) != 1) {
      fprintf(stderr, "short read in %s at index %zu\n", path, i);
      fclose(fp);
      return -1;
    }
    if (v < -128 || v > 127) {
      fprintf(stderr, "i8 out of range in %s at index %zu: %ld\n", path, i, v);
      fclose(fp);
      return -1;
    }
    dst[i] = (int8_t)v;
  }
  fclose(fp);
  return 0;
}

static int read_i32_lines(const char *path, int32_t *dst, size_t count) {
  FILE *fp = fopen(path, "r");
  size_t i;
  long v;
  if (!fp) {
    perror(path);
    return -1;
  }
  for (i = 0; i < count; ++i) {
    if (fscanf(fp, "%ld", &v) != 1) {
      fprintf(stderr, "short read in %s at index %zu\n", path, i);
      fclose(fp);
      return -1;
    }
    dst[i] = (int32_t)v;
  }
  fclose(fp);
  return 0;
}

static void build_path(char *dst, size_t dst_len, const char *root, const char *leaf) {
  snprintf(dst, dst_len, "%s/%s", root, leaf);
}

static int8_t clamp_int8(int64_t v) {
  if (v > 127)
    return 127;
  if (v < -128)
    return -128;
  return (int8_t)v;
}

static int idx_hwc(int h, int w, int c, int width, int channels) {
  return ((h * width) + w) * channels + c;
}

static int idx_oihw(int oc, int ic, int kh, int kw, int cin, int ksize) {
  return (((oc * cin + ic) * ksize + kh) * ksize + kw);
}

static int idx_ohw(int oc, int kh, int kw, int ksize) {
  return ((oc * ksize + kh) * ksize + kw);
}

static int32_t requantize_single(int32_t mac,
                                 int32_t eff_bias,
                                 int32_t mult,
                                 int32_t shift,
                                 int32_t zp_out) {
  /* 匹配 RTL quantizer 使用的 integer multiplier/shift 流程。 */
  int64_t acc = (int64_t)mac + (int64_t)eff_bias;
  int64_t prod = acc * (int64_t)mult;
  int64_t scaled;

  if (shift > 0) {
    int64_t round_term = (int64_t)1 << (shift - 1);
    int64_t prod_adj = prod + round_term - (prod < 0 ? 1 : 0);
    scaled = prod_adj >> shift;
  } else if (shift == 0) {
    scaled = prod;
  } else {
    scaled = prod << (-shift);
  }

  return (int32_t)scaled + zp_out;
}

static void conv1_forward(const int8_t *input,
                          const int8_t *weights,
                          const int32_t *bias,
                          const int32_t *mult,
                          const int32_t *shift,
                          int8_t *pool_out) {
  /* 第一层只有一个 input channel，所以单独写成更直接的版本。 */
  int8_t requant[C1_H * C1_W * C1_OUT];
  int h, w, oc, kh, kw;

  for (h = 0; h < C1_H; ++h) {
    for (w = 0; w < C1_W; ++w) {
      for (oc = 0; oc < C1_OUT; ++oc) {
        int32_t mac = 0;
        for (kh = 0; kh < 3; ++kh) {
          for (kw = 0; kw < 3; ++kw) {
            int32_t x = input[idx_hwc(h + kh, w + kw, 0, IMG_W, 1)];
            int32_t wt = weights[idx_ohw(oc, kh, kw, 3)];
            mac += x * wt;
          }
        }
        requant[idx_hwc(h, w, oc, C1_W, C1_OUT)] =
            clamp_int8(requantize_single(mac, bias[oc], mult[oc], shift[oc], -128));
      }
    }
  }

  for (h = 0; h < P1_H; ++h) {
    for (w = 0; w < P1_W; ++w) {
      for (oc = 0; oc < C1_OUT; ++oc) {
        int base_h = h * 2;
        int base_w = w * 2;
        int8_t a = requant[idx_hwc(base_h + 0, base_w + 0, oc, C1_W, C1_OUT)];
        int8_t b = requant[idx_hwc(base_h + 0, base_w + 1, oc, C1_W, C1_OUT)];
        int8_t c = requant[idx_hwc(base_h + 1, base_w + 0, oc, C1_W, C1_OUT)];
        int8_t d = requant[idx_hwc(base_h + 1, base_w + 1, oc, C1_W, C1_OUT)];
        int8_t m1 = a > b ? a : b;
        int8_t m2 = c > d ? c : d;
        pool_out[idx_hwc(h, w, oc, P1_W, C1_OUT)] = m1 > m2 ? m1 : m2;
      }
    }
  }
}

static void conv_generic_forward(const int8_t *input,
                                 int in_h,
                                 int in_w,
                                 int in_c,
                                 const int8_t *weights,
                                 int out_c,
                                 const int32_t *bias,
                                 const int32_t *mult,
                                 const int32_t *shift,
                                 int out_h,
                                 int out_w,
                                 int pool_h,
                                 int pool_w,
                                 int8_t *pool_out) {
  /* 第二、三层共用的 convolution + requantization + 2x2 max-pool。 */
  int8_t *requant = (int8_t *)malloc((size_t)out_h * (size_t)out_w * (size_t)out_c);
  int h, w, oc, ic, kh, kw;
  if (!requant) {
    fprintf(stderr, "alloc failed for requant buffer\n");
    exit(1);
  }

  for (h = 0; h < out_h; ++h) {
    for (w = 0; w < out_w; ++w) {
      for (oc = 0; oc < out_c; ++oc) {
        int32_t mac = 0;
        for (ic = 0; ic < in_c; ++ic) {
          for (kh = 0; kh < 3; ++kh) {
            for (kw = 0; kw < 3; ++kw) {
              int32_t x = input[idx_hwc(h + kh, w + kw, ic, in_w, in_c)];
              int32_t wt = weights[idx_oihw(oc, ic, kh, kw, in_c, 3)];
              mac += x * wt;
            }
          }
        }
        requant[idx_hwc(h, w, oc, out_w, out_c)] =
            clamp_int8(requantize_single(mac, bias[oc], mult[oc], shift[oc], -128));
      }
    }
  }

  for (h = 0; h < pool_h; ++h) {
    for (w = 0; w < pool_w; ++w) {
      for (oc = 0; oc < out_c; ++oc) {
        int base_h = h * 2;
        int base_w = w * 2;
        int8_t a = requant[idx_hwc(base_h + 0, base_w + 0, oc, out_w, out_c)];
        int8_t b = requant[idx_hwc(base_h + 0, base_w + 1, oc, out_w, out_c)];
        int8_t c = requant[idx_hwc(base_h + 1, base_w + 0, oc, out_w, out_c)];
        int8_t d = requant[idx_hwc(base_h + 1, base_w + 1, oc, out_w, out_c)];
        int8_t m1 = a > b ? a : b;
        int8_t m2 = c > d ? c : d;
        pool_out[idx_hwc(h, w, oc, pool_w, out_c)] = m1 > m2 ? m1 : m2;
      }
    }
  }

  free(requant);
}

static int fc_argmax(const int8_t *input, const int8_t *weights, const int32_t *bias) {
  /* 最后一层分类器：288 个 INT8 输入分别和 10 行 FC weights 做 dot product。 */
  int oc, k;
  int best_idx = 0;
  int32_t best_val = 0;

  for (oc = 0; oc < FC_OUT; ++oc) {
    int64_t acc = bias[oc];
    for (k = 0; k < FC_IN; ++k) {
      acc += (int64_t)input[k] * (int64_t)weights[oc * FC_IN + k];
    }
    if (oc == 0 || acc > best_val) {
      best_val = (int32_t)acc;
      best_idx = oc;
    }
  }

  return best_idx;
}

int main(int argc, char **argv) {
  char path[1024];
  const char *image_case_root;
  const char *reference_case_root;
  int8_t input[IMG_H * IMG_W];
  int8_t pool1[P1_H * P1_W * C1_OUT];
  int8_t pool2[P2_H * P2_W * C2_OUT];
  int8_t pool3[P3_H * P3_W * C3_OUT];
  int8_t conv1_w[C1_OUT * 3 * 3];
  int8_t conv2_w[C2_OUT * C1_OUT * 3 * 3];
  int8_t conv3_w[C3_OUT * C2_OUT * 3 * 3];
  int8_t fc_w[FC_OUT * FC_IN];
  int32_t conv1_bias[C1_OUT], conv2_bias[C2_OUT], conv3_bias[C3_OUT], fc_bias[FC_OUT];
  int32_t conv1_m[C1_OUT], conv2_m[C2_OUT], conv3_m[C3_OUT];
  int32_t conv1_sh[C1_OUT], conv2_sh[C2_OUT], conv3_sh[C3_OUT];
  int predicted_class;
  double started_ms, ended_ms;

  if (argc != 3) {
    fprintf(stderr, "usage: %s <image_case_root> <reference_case_root>\n", argv[0]);
    return 1;
  }

  image_case_root = argv[1];
  reference_case_root = argv[2];

  /* 上传图片来自临时 case；模型参数来自部署模型对应的 hardware-aligned
   * reference case。
   */
  build_path(path, sizeof(path), image_case_root, "tb_conv1_in_i8_64x64x1.txt");
  if (read_i8_lines(path, input, IMG_H * IMG_W) != 0)
    return 1;

  build_path(path, sizeof(path), reference_case_root, "tb_conv1_w_i8_3x3x4.txt");
  if (read_i8_lines(path, conv1_w, C1_OUT * 3 * 3) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv2_w_i8_3x3x4x8.txt");
  if (read_i8_lines(path, conv2_w, C2_OUT * C1_OUT * 3 * 3) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv3_w_i8_3x3x8x8.txt");
  if (read_i8_lines(path, conv3_w, C3_OUT * C2_OUT * 3 * 3) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_fc_w_i8_10x288.txt");
  if (read_i8_lines(path, fc_w, FC_OUT * FC_IN) != 0)
    return 1;

  build_path(path, sizeof(path), reference_case_root, "tb_conv1_quant_bias_eff_i32_4.txt");
  if (read_i32_lines(path, conv1_bias, C1_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv2_quant_bias_eff_i32_8.txt");
  if (read_i32_lines(path, conv2_bias, C2_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv3_quant_bias_eff_i32_8.txt");
  if (read_i32_lines(path, conv3_bias, C3_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_fc_bias_eff_i32_10.txt");
  if (read_i32_lines(path, fc_bias, FC_OUT) != 0)
    return 1;

  build_path(path, sizeof(path), reference_case_root, "tb_conv1_quant_M_i32_4.txt");
  if (read_i32_lines(path, conv1_m, C1_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv2_quant_M_i32_8.txt");
  if (read_i32_lines(path, conv2_m, C2_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv3_quant_M_i32_8.txt");
  if (read_i32_lines(path, conv3_m, C3_OUT) != 0)
    return 1;

  build_path(path, sizeof(path), reference_case_root, "tb_conv1_quant_sh_i32_4.txt");
  if (read_i32_lines(path, conv1_sh, C1_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv2_quant_sh_i32_8.txt");
  if (read_i32_lines(path, conv2_sh, C2_OUT) != 0)
    return 1;
  build_path(path, sizeof(path), reference_case_root, "tb_conv3_quant_sh_i32_8.txt");
  if (read_i32_lines(path, conv3_sh, C3_OUT) != 0)
    return 1;

  started_ms = monotonic_ms();
  /* 按照和 RTL accelerator 相同的 layer 顺序执行，保证比较公平。 */
  conv1_forward(input, conv1_w, conv1_bias, conv1_m, conv1_sh, pool1);
  conv_generic_forward(pool1, P1_H, P1_W, C1_OUT, conv2_w, C2_OUT, conv2_bias, conv2_m, conv2_sh,
                       C2_H, C2_W, P2_H, P2_W, pool2);
  conv_generic_forward(pool2, P2_H, P2_W, C2_OUT, conv3_w, C3_OUT, conv3_bias, conv3_m, conv3_sh,
                       C3_H, C3_W, P3_H, P3_W, pool3);
  predicted_class = fc_argmax(pool3, fc_w, fc_bias);
  ended_ms = monotonic_ms();

  printf("predict_class=%d\n", predicted_class);
  printf("board_cpu_infer_ms=%.3f\n", ended_ms - started_ms);
  return 0;
}
