#!/usr/bin/env python3
"""
Generate SRAM preload weight files with column-interleaved packing.

The Conv RTL weight_buffer expects each 32-bit beat to contain
{col3_k, col2_k, col1_k, col0_k} — the same dot-product position k
for all 4 output channels (columns).

The standalone TBs read column-major weight files and reorder using
a MATLAB-style index mapping (kh, kw, c_in).  The SRAM preload must
apply the same reorder so the Conv sees correct weights.

This script reads the per-layer weight txt files (same ones used by
standalone TBs), applies the reorder, then writes the column-interleaved
byte stream to sram_a_wt_513w.txt.
"""
import argparse
import pathlib
import numpy as np

COLS = 4  # SA columns = output channels per pass

# Layer configs: (dot_k, c_in, out_c, num_passes)
LAYER_CFGS = {
    'L1': {'dot_k': 9,  'c_in': 1, 'out_c': 4, 'passes': 1},
    'L2': {'dot_k': 36, 'c_in': 4, 'out_c': 8, 'passes': 2},
    'L3': {'dot_k': 72, 'c_in': 8, 'out_c': 8, 'passes': 2},
}

def reorder_weights(w_raw, dot_k, c_in, ch_offset, cols=COLS):
    """
    Reorder weights from MATLAB column-major layout to the DOT_K sequence
    that the Conv SA expects, matching the standalone TB reorder logic.

    w_raw: flat list of cols*dot_k int8 values for one pass, in MATLAB order.
           Layout: ch0_all_k, ch1_all_k, ch2_all_k, ch3_all_k
    Returns: list of (cols*dot_k) interleaved values, grouped as
             [col0_k0, col1_k0, col2_k0, col3_k0, col0_k1, ...]
    """
    w_tap = [0] * (cols * dot_k)
    for ch in range(cols):
        for rd_col_idx in range(dot_k):
            c_in_i = rd_col_idx % c_in
            kw     = (rd_col_idx // c_in) % 3
            kh     = 2 - (rd_col_idx // (3 * c_in))
            matlab_idx = kh + 3 * kw + 9 * c_in_i
            w_tap[ch * dot_k + rd_col_idx] = w_raw[ch_offset + ch * dot_k + matlab_idx]
    return w_tap

def interleave_for_sram(w_tap, dot_k, cols=COLS):
    """
    Given reordered w_tap[cols*dot_k] (col-major: ch0 first, ch1, ...),
    produce interleaved byte stream: for each k, emit col0_k, col1_k, col2_k, col3_k.
    This is how the SRAM stores them (4 bytes per word = 1 beat).
    """
    result = []
    for k in range(dot_k):
        for ch in range(cols):
            result.append(w_tap[ch * dot_k + k])
    return result

def discover_cases(txt_root, requested_cases):
    if requested_cases:
        return requested_cases
    return sorted(p.name for p in txt_root.iterdir() if p.is_dir())


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate SRAM preload/golden files for one or more cases."
    )
    parser.add_argument(
        "cases",
        nargs="*",
        help="Case names under matlab/debug/txt_cases/. If omitted, scan all case directories.",
    )
    return parser.parse_args()


def main(requested_cases):
    txt_root = pathlib.Path("matlab/debug/txt_cases")
    sram_root = pathlib.Path("matlab/debug/sram_preload")
    cases = discover_cases(txt_root, requested_cases)

    if not cases:
        print(f"SKIP: no case directories found under {txt_root}")
        return

    for case in cases:
        case_txt = txt_root / case
        case_sram = sram_root / case

        if not case_txt.exists():
            print(f"SKIP: {case_txt} not found")
            continue

        # --- L1 ---
        l1_file = case_txt / 'tb_conv1_w_i8_3x3x4.txt'
        l1_raw = [int(x) for x in l1_file.read_text().strip().split('\n')]
        assert len(l1_raw) == 36, f"L1 weight count mismatch: {len(l1_raw)}"

        cfg = LAYER_CFGS['L1']
        l1_tap = reorder_weights(l1_raw, cfg['dot_k'], cfg['c_in'], 0)
        l1_interleaved = interleave_for_sram(l1_tap, cfg['dot_k'])

        # --- L2 (2 passes, 4 channels per pass from 8 total) ---
        l2_file = case_txt / 'tb_conv2_w_i8_3x3x4x8.txt'
        l2_raw = [int(x) for x in l2_file.read_text().strip().split('\n')]
        assert len(l2_raw) == 288, f"L2 weight count mismatch: {len(l2_raw)}"

        cfg = LAYER_CFGS['L2']
        wt_per_pass = COLS * cfg['dot_k']  # 144
        l2_p0_tap = reorder_weights(l2_raw, cfg['dot_k'], cfg['c_in'], 0)
        l2_p0_interleaved = interleave_for_sram(l2_p0_tap, cfg['dot_k'])
        l2_p1_tap = reorder_weights(l2_raw, cfg['dot_k'], cfg['c_in'], wt_per_pass)
        l2_p1_interleaved = interleave_for_sram(l2_p1_tap, cfg['dot_k'])

        # --- L3 (2 passes, 4 channels per pass from 8 total) ---
        l3_file = case_txt / 'tb_conv3_w_i8_3x3x8x8.txt'
        l3_raw = [int(x) for x in l3_file.read_text().strip().split('\n')]
        assert len(l3_raw) == 576, f"L3 weight count mismatch: {len(l3_raw)}"

        cfg = LAYER_CFGS['L3']
        wt_per_pass = COLS * cfg['dot_k']  # 288
        l3_p0_tap = reorder_weights(l3_raw, cfg['dot_k'], cfg['c_in'], 0)
        l3_p0_interleaved = interleave_for_sram(l3_p0_tap, cfg['dot_k'])
        l3_p1_tap = reorder_weights(l3_raw, cfg['dot_k'], cfg['c_in'], wt_per_pass)
        l3_p1_interleaved = interleave_for_sram(l3_p1_tap, cfg['dot_k'])

        # --- FC (already interleaved in its own file) ---
        fc_file = case_txt / 'tb_fc_w_interleaved_i8_288x4.txt'
        fc_raw = [int(x) for x in fc_file.read_text().strip().split('\n')]
        assert len(fc_raw) == 1152, f"FC weight count mismatch: {len(fc_raw)}"
        fc_interleaved = fc_raw  # already in correct format

        # --- Concatenate all layers ---
        all_bytes = (l1_interleaved + l2_p0_interleaved + l2_p1_interleaved +
                     l3_p0_interleaved + l3_p1_interleaved + fc_interleaved)
        assert len(all_bytes) == 2052, f"Total byte count mismatch: {len(all_bytes)}"

        case_sram.mkdir(parents=True, exist_ok=True)

        # --- Write output ---
        out_file = case_sram / 'sram_a_wt_513w.txt'
        with open(out_file, 'w') as f:
            for v in all_bytes:
                f.write(f"{v}\n")

        print(f"OK: {case} wt -> {out_file} ({len(all_bytes)} bytes = {len(all_bytes)//4} words)")

        # --- Image: column-major to row-major reorder ---
        # MATLAB write_tensor_txt outputs 64x64 image in column-major order:
        #   (0,0),(1,0),(2,0),...,(63,0),(0,1),(1,1),...
        # Conv expects pixels in row-major order (row 0 first, then row 1, ...):
        #   (0,0),(0,1),(0,2),...,(0,63),(1,0),(1,1),...
        # The TB packs 4 consecutive bytes per SRAM word, so row-major means
        # each word contains 4 pixels from the same row.
        img_file = case_txt / 'tb_conv1_in_i8_64x64x1.txt'
        img_raw = [int(x) for x in img_file.read_text().strip().split('\n')]
        assert len(img_raw) == 4096, f"Image size mismatch: {len(img_raw)}"

        # Reshape as MATLAB column-major [64,64], then flatten row-major
        img_mat = np.array(img_raw, dtype=np.int8).reshape(64, 64, order='F')
        img_row_major = img_mat.flatten(order='C').tolist()

        img_out_file = case_sram / 'sram_a_image_1024w.txt'
        with open(img_out_file, 'w') as f:
            for v in img_row_major:
                f.write(f"{int(v)}\n")
        print(f"OK: {case} img -> {img_out_file} (4096 bytes = 1024 words, row-major)")
        print(f"  first 4 pixels (row 0): {img_row_major[:4]}")
        print(f"  (col-major first 4: {img_raw[:4]})")

def reorder_pool_colmaj_to_rowmaj(vals, H, W, C):
    """Reorder MATLAB col-major [H,W,C] tensor to row-major channel-packed bytes."""
    p = np.array(vals, dtype=np.int8).reshape(H, W, C, order='F')
    out = []
    for row in range(H):
        for col in range(W):
            for ch in range(C):
                out.append(int(p[row, col, ch]))
    return out

def gen_pool_golden_rowmajor(requested_cases):
    """Generate row-major pool golden files for system E2E comparison."""
    txt_root = pathlib.Path('matlab/debug/txt_cases')
    sram_root = pathlib.Path('matlab/debug/sram_preload')
    cases = discover_cases(txt_root, requested_cases)

    for case in cases:
        case_txt = txt_root / case
        case_sram = sram_root / case
        if not case_txt.exists():
            continue
        case_sram.mkdir(parents=True, exist_ok=True)

        # L1 pool: [31,31,4]
        src = case_txt / 'tb_conv1_pool_i8_31x31x4.txt'
        vals = [int(x) for x in src.read_text().strip().split('\n')]
        out = reorder_pool_colmaj_to_rowmaj(vals, 31, 31, 4)
        dst = case_sram / 'expected_sram_b_l1_pool_961w.txt'
        with open(dst, 'w') as f:
            for v in out: f.write(f"{v}\n")
        print(f"OK: {case} L1 pool -> {dst} ({len(out)} bytes)")

        # L2 pool: source is [14,14,8] col-major, split into pass0 (ch0-3) + pass1 (ch4-7)
        l2_src = case_txt / 'tb_conv2_pool_i8_14x14x8.txt'
        l2_vals = [int(x) for x in l2_src.read_text().strip().split('\n')]
        l2_p = np.array(l2_vals, dtype=np.int8).reshape(14, 14, 8, order='F')
        l2_p0 = l2_p[:, :, :4].flatten(order='C').tolist()  # pass0 row-major
        l2_p1 = l2_p[:, :, 4:].flatten(order='C').tolist()  # pass1 row-major
        # Interleave pass0 and pass1: p0[0],p1[0],p0[1],p1[1],...
        # Each word = 4 bytes (4 channels). Interleave at word level.
        l2_interleaved = []
        for i in range(196):
            l2_interleaved.extend(l2_p0[i*4:(i+1)*4])  # pass0 word i
            l2_interleaved.extend(l2_p1[i*4:(i+1)*4])  # pass1 word i
        l2_dst = case_sram / 'expected_sram_a_l2_pool_392w.txt'
        with open(l2_dst, 'w') as f:
            for v in l2_interleaved: f.write(f"{int(v)}\n")
        print(f"OK: {case} L2 pool -> {l2_dst} ({len(l2_interleaved)} bytes, interleaved)")

        # L3 pool: source is [6,6,8] col-major, split into pass0 (ch0-3) + pass1 (ch4-7)
        l3_src = case_txt / 'tb_conv3_pool_i8_6x6x8.txt'
        if not l3_src.exists():
            # Fallback: try reading from the existing expected file and reorder
            l3_src = case_sram / 'expected_sram_b_l3_pool_72w.txt'
            l3_vals = [int(x) for x in l3_src.read_text().strip().split('\n')]
            # Original is col-major [6,6,8] = 288 bytes
            if len(l3_vals) == 288:
                l3_p = np.array(l3_vals, dtype=np.int8).reshape(6, 6, 8, order='F')
                l3_p0 = l3_p[:, :, :4].flatten(order='C').tolist()
                l3_p1 = l3_p[:, :, 4:].flatten(order='C').tolist()
            else:
                # Already 2x144 format, just reorder each half
                l3_p0 = reorder_pool_colmaj_to_rowmaj(l3_vals[:144], 6, 6, 4)
                l3_p1 = reorder_pool_colmaj_to_rowmaj(l3_vals[144:], 6, 6, 4)
        else:
            l3_vals = [int(x) for x in l3_src.read_text().strip().split('\n')]
            l3_p = np.array(l3_vals, dtype=np.int8).reshape(6, 6, 8, order='F')
            l3_p0 = l3_p[:, :, :4].flatten(order='C').tolist()
            l3_p1 = l3_p[:, :, 4:].flatten(order='C').tolist()
        l3_dst = case_sram / 'expected_sram_b_l3_pool_72w.txt'
        with open(l3_dst, 'w') as f:
            for v in (l3_p0 + l3_p1): f.write(f"{int(v)}\n")
        print(f"OK: {case} L3 pool -> {l3_dst} ({len(l3_p0)+len(l3_p1)} bytes)")

if __name__ == '__main__':
    args = parse_args()
    main(args.cases)
    gen_pool_golden_rowmajor(args.cases)
