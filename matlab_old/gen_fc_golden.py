#!/usr/bin/env python3
"""Generate FC golden txt files for RTL verification.

Reads the existing MATLAB-generated pool3 golden (tb_conv3_pool_i8_6x6x8.txt)
and computes FC with effective bias (x_zp folded in).
"""
import os
import numpy as np
import scipy.io


def load_txt_i8(path, n):
    with open(path) as f:
        vals = [int(line.strip()) for line in f]
    assert len(vals) == n, '%s: expected %d values, got %d' % (path, n, len(vals))
    return np.array(vals, dtype=np.int8)


def flatten_nhwc(x):
    """Flatten HxWxC in NHWC order (h major, w, c fastest) — matches MATLAB."""
    H, W, C = x.shape
    out = np.zeros(H * W * C, dtype=np.int8)
    k = 0
    for h in range(H):
        for w in range(W):
            for c in range(C):
                out[k] = x[h, w, c]
                k += 1
    return out


def write_txt(arr, path):
    with open(path, 'w') as f:
        for v in arr.flat:
            f.write('%d\n' % int(v))


def main():
    S = scipy.io.loadmat('v2.int8.params.mat')

    w_fc = S['values'][2, 0].astype(np.int8)              # [3, 288]
    b_fc = S['values'][1, 0].flatten().astype(np.int32)    # [3]
    x_zp_fc = int(S['activation_zero_points'][6, 0].flatten()[0])

    # Effective bias: eff_bias = bias - x_zp * sum(w)
    eff_bias = np.zeros(3, dtype=np.int32)
    for o in range(3):
        eff_bias[o] = int(b_fc[o]) - x_zp_fc * int(np.sum(w_fc[o, :].astype(np.int32)))
    print('eff_bias:', eff_bias)
    print('x_zp_fc:', x_zp_fc)

    txt_root = os.path.join('debug', 'txt_cases')
    labels = ['paper', 'rock', 'scissors']

    for tag in labels:
        print('\n=== %s ===' % tag)
        case_dir = os.path.join(txt_root, tag)

        # Read existing MATLAB-generated pool3 golden
        pool3_path = os.path.join(case_dir, 'tb_conv3_pool_i8_6x6x8.txt')
        pool3_flat = load_txt_i8(pool3_path, 6 * 6 * 8)
        # The txt is written by MATLAB write_tensor_txt which iterates numel(tensor)
        # For a 6x6x8 MATLAB array stored column-major, the iteration order is
        # (1,1,1),(2,1,1),...,(6,1,1),(1,2,1),...  (h varies fastest in MATLAB)
        # But flatten_nhwc expects NHWC: (1,1,1),(1,1,2),...,(1,1,8),(1,2,1),...
        # So we need to reshape respecting MATLAB column-major order first.
        pool3_matlab = pool3_flat.reshape((6, 6, 8), order='F')
        print('  pool3 shape:', pool3_matlab.shape)
        print('  pool3 range: [%d, %d]' % (pool3_matlab.min(), pool3_matlab.max()))

        # Flatten in NHWC order (matching TFLite / MATLAB flatten_nhwc_int8)
        x_fc = flatten_nhwc(pool3_matlab)
        print('  x_fc len:', len(x_fc))

        # FC: acc = eff_bias + sum(x * w)
        fc_out = np.zeros(3, dtype=np.int32)
        for o in range(3):
            fc_out[o] = int(eff_bias[o]) + int(
                np.sum(x_fc.astype(np.int32) * w_fc[o, :].astype(np.int32)))

        pred = labels[np.argmax(fc_out)]
        print('  fc_out:', fc_out, '-> prediction:', pred)

        # Write
        write_txt(x_fc,     os.path.join(case_dir, 'tb_fc_in_i8_288.txt'))
        write_txt(w_fc,     os.path.join(case_dir, 'tb_fc_w_i8_3x288.txt'))
        write_txt(eff_bias, os.path.join(case_dir, 'tb_fc_bias_eff_i32_3.txt'))
        write_txt(fc_out,   os.path.join(case_dir, 'tb_fc_out_i32_3.txt'))
        print('  wrote 4 FC golden files')

    print('\nDone.')


if __name__ == '__main__':
    main()
