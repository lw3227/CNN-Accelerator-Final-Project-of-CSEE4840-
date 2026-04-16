function gen_sram_preload(case_name, R, P, out_root)
% GEN_SRAM_PRELOAD  Produce the four host preload streams the TB drives in.
%
%   gen_sram_preload(case_name, R, P, out_root)
%
%   case_name : tag (e.g. 'digit_0')
%   R         : forward result struct from hw_forward / export_case
%   P         : params struct from load_params
%   out_root  : root output dir (default: matlab/main/debug/sram_preload/)
%
%   Writes to <out_root>/<case_name>/:
%     preload_conv_cfg_<NCFG>w.txt     conv L1/L2/L3 cfg (45 host words to SRAM_A@0x000)
%     preload_conv_wt_225w_bytes.txt   conv L1/L2/L3 weights (900 INT8 bytes = 225 packed words)
%     preload_fc_bias_10w.txt          FC bias eff (10 host words to SRAM_A@0x111 via LAYER_FC+SEL_CFG)
%     preload_fcw_864w.txt             FC weight host stream (864 words -> packer -> 288 x 80b)
%
%   Each host word is one INT32 line (signed decimal) -- the TB feeds these
%   directly into load_data[31:0] one per beat. Host words are signed but the
%   bit-pattern is what the wrapper writes to SRAM.
%
%   ---------------------------------------------------------------
%   STATUS NOTE (read before relying on this script):
%
%     * FC bias  (10w)   : FULLY IMPLEMENTED
%     * FC weight (864w) : FULLY IMPLEMENTED -- matches RTL fcw_preload_packer
%                          spec (3 host words -> 80-bit slot, ch0 in LSB)
%     * Conv weight (900B) : IMPLEMENTED via the reorder ported from
%                            matlab_old/gen_sram_preload.py. TB packs this
%                            byte stream into 225 host words.
%     * Conv cfg (45w)   : SCAFFOLD ONLY. Each layer-pass uses 9 cfg words,
%                          but the bit-packing inside each word depends on
%                          how Quantization_Top.v unpacks them. See the TODO
%                          inside conv_cfg_stream() below; consult the per-
%                          layer cfg writer in the standalone TBs to verify.
%   ---------------------------------------------------------------

    if nargin < 4 || isempty(out_root)
        matlab_dir = fileparts(mfilename('fullpath'));
        out_root   = fullfile(matlab_dir, 'debug', 'sram_preload');
    end
    case_dir = fullfile(out_root, case_name);
    if ~exist(case_dir, 'dir'), mkdir(case_dir); end

    % ---------------------------------------------------------------------
    %  conv CFG: 45 words = 9*5 (L1, L2_p0, L2_p1, L3_p0, L3_p1)
    % ---------------------------------------------------------------------
    cfg_stream = [conv_cfg_stream(R.conv1_eff_bias, R.conv1_M, R.conv1_sh, R.zp.conv1_out, 'L1');
                  conv_cfg_stream(R.conv2_eff_bias(1:4), R.conv2_M(1:4), R.conv2_sh(1:4), R.zp.conv2_out, 'L2p0');
                  conv_cfg_stream(R.conv2_eff_bias(5:8), R.conv2_M(5:8), R.conv2_sh(5:8), R.zp.conv2_out, 'L2p1');
                  conv_cfg_stream(R.conv3_eff_bias(1:4), R.conv3_M(1:4), R.conv3_sh(1:4), R.zp.conv3_out, 'L3p0');
                  conv_cfg_stream(R.conv3_eff_bias(5:8), R.conv3_M(5:8), R.conv3_sh(5:8), R.zp.conv3_out, 'L3p1')];
    assert(numel(cfg_stream) == 45, 'conv_cfg stream length %d != 45', numel(cfg_stream));
    dump_txt(fullfile(case_dir, 'preload_conv_cfg_45w.txt'), cfg_stream, 'i32', 'flat');

    % ---------------------------------------------------------------------
    %  conv WT: 900 bytes = 4*(9 + 36*2 + 72*2), later packed to 225 host words
    % ---------------------------------------------------------------------
    wt_stream = [conv_wt_pass(P.W1, 9,  1, 1, 4);   % L1: dot_k=9,  Cin=1, 4 channels (single pass)
                 conv_wt_pass(P.W2, 36, 4, 1, 4);   % L2 pass 0: dot_k=36, Cin=4, ch 1..4
                 conv_wt_pass(P.W2, 36, 4, 5, 4);   % L2 pass 1: ch 5..8
                 conv_wt_pass(P.W3, 72, 8, 1, 4);   % L3 pass 0: dot_k=72, Cin=8, ch 1..4
                 conv_wt_pass(P.W3, 72, 8, 5, 4)];  % L3 pass 1: ch 5..8
    assert(numel(wt_stream) == 4 * (9 + 36*2 + 72*2), 'conv wt stream length %d != 900 bytes', numel(wt_stream));
    % wt_stream is byte-stream (each entry one INT8 byte); host word packs 4 bytes,
    % so the file ends up as 225 host beats only after 4-byte packing in the TB.
    % Until the TB's packer is hooked here, dump byte-by-byte for transparency.
    dump_txt(fullfile(case_dir, 'preload_conv_wt_225w_bytes.txt'), wt_stream, 'i8', 'flat');

    % ---------------------------------------------------------------------
    %  FC bias: 10 INT32 words. Goes to SRAM_A @ 0x111 via LAYER_FC+SEL_CFG.
    % ---------------------------------------------------------------------
    dump_txt(fullfile(case_dir, 'preload_fc_bias_10w.txt'), R.fc_eff_bias, 'i32', 'flat');

    % ---------------------------------------------------------------------
    %  FC weight: 864 host words for fcw_preload_packer (3 host words per
    %  80-bit slot). For each k in 0..287, emit 3 host words:
    %    word0 [31:0] = {k3, k2, k1, k0}     (LSB byte = ch 0)
    %    word1 [31:0] = {k7, k6, k5, k4}
    %    word2 [15:0] = {k9, k8}            (high 16b zero-padded)
    %  This matches input/RTL/SRAM/fcw_preload_packer.v.
    % ---------------------------------------------------------------------
    Cout = size(P.W_fc, 1);
    K    = size(P.W_fc, 2);
    assert(Cout == 10 && K == 288, 'FC weight expected [10,288], got [%d,%d]', Cout, K);
    fcw_stream = zeros(K * 3, 1, 'int32');
    for k = 1:K
        % bytes for 10 channels at this k position
        bytes = int32(P.W_fc(:, k));   % [10, 1]
        bytes = bitand(bytes, int32(255));   % treat as unsigned for bit-packing
        word0 = bitor(bitor(bitor(bytes(1), bitshift(bytes(2), 8)), ...
                            bitshift(bytes(3), 16)), bitshift(bytes(4), 24));
        word1 = bitor(bitor(bitor(bytes(5), bitshift(bytes(6), 8)), ...
                            bitshift(bytes(7), 16)), bitshift(bytes(8), 24));
        word2 = bitor(bytes(9), bitshift(bytes(10), 8));   % upper 16b = 0
        % word0/1/2 are already int32 with the correct bit pattern.
        % Do NOT pass through uint32() — MATLAB saturates negatives to 0.
        fcw_stream(3*(k-1)+1) = word0;
        fcw_stream(3*(k-1)+2) = word1;
        fcw_stream(3*(k-1)+3) = word2;
    end
    assert(numel(fcw_stream) == 864, 'fcw stream length %d != 864', numel(fcw_stream));
    dump_txt(fullfile(case_dir, 'preload_fcw_864w.txt'), fcw_stream, 'i32', 'flat');

    fprintf('gen_sram_preload: wrote 4 streams to %s\n', case_dir);
end


% =========================================================================
%  Helpers
% =========================================================================

function out = conv_cfg_stream(eff_bias, M, sh, zp_out, tag)   %#ok<INUSD>
% Pack 9 host words for one conv pass cfg, matching input/RTL/quant_pool/
% integration/quant_param_loader.v (lines 6-8 header comment):
%
%   word 0..3 : bias0..3 (per-channel eff_bias, one INT32 per word)
%   word 4..7 : M0..3    (per-channel TFLite multiplier, one INT32 per word)
%   word 8    : sh_packed = {sh1[31:24], sh2[23:16], sh3[15:8], sh4[7:0]}
%               i.e. ch1 is MSB, ch4 is LSB (Verilog concat order).
%
% Verified against Quantization_Top.v:32-53 which slices sh_in[31:24]->PE1,
% [23:16]->PE2, [15:8]->PE3, [7:0]->PE4.
    assert(numel(eff_bias) == 4 && numel(M) == 4 && numel(sh) == 4, ...
           'conv_cfg_stream: expected 4 channels per pass, got [%d,%d,%d] (%s)', ...
           numel(eff_bias), numel(M), numel(sh), tag);

    sh8 = bitand(int32(sh(:)), int32(255));   % truncate each shift to 8 bits
    sh_packed = bitor(bitor(bitor( ...
        bitshift(sh8(1), 24), ...
        bitshift(sh8(2), 16)), ...
        bitshift(sh8(3),  8)), ...
                     sh8(4));

    out       = int32(zeros(9, 1));
    out(1:4)  = int32(eff_bias(:));
    out(5:8)  = int32(M(:));
    out(9)    = int32(sh_packed);
end


function bytes = conv_wt_pass(W_oihw, dot_k, Cin, ch_start, cols)
% Reorder + interleave one pass worth of weights for the systolic array.
% Ported from matlab_old/gen_sram_preload.py (reorder_weights + interleave_for_sram).
%
% W_oihw : int8 [Cout_total, Cin, 3, 3]
% dot_k  : 9 (L1) / 36 (L2) / 72 (L3) -- inner MAC sequence length
% Cin    : 1 / 4 / 8
% ch_start, cols : take ch_start..ch_start+cols-1 output channels for this pass
%
% Returns INT8 column vector of length cols*dot_k, byte-interleaved as the
% SRAM stores them: for each k position, emit col0_k, col1_k, ..., col(cols-1)_k.

    assert(size(W_oihw, 2) == Cin, 'conv_wt_pass: W Cin %d != expected %d', size(W_oihw,2), Cin);

    % Build w_tap[ch][rd_col_idx] in the SA traversal order.
    w_tap = zeros(cols, dot_k, 'int8');
    for ch = 0:cols-1
        oc = ch_start + ch;        % 1-based oc index
        for rd_col_idx = 0:dot_k-1
            c_in_i = mod(rd_col_idx, Cin);
            kw     = mod(floor(rd_col_idx / Cin), 3);
            kh     = 2 - floor(rd_col_idx / (3 * Cin));
            % MATLAB indices are 1-based and stored as OIHW.
            w_tap(ch+1, rd_col_idx+1) = W_oihw(oc, c_in_i+1, kh+1, kw+1);
        end
    end

    % Interleave: for each k, emit cols bytes (col0..col_{cols-1}).
    bytes = zeros(cols * dot_k, 1, 'int8');
    idx = 1;
    for k = 1:dot_k
        for ch = 1:cols
            bytes(idx) = w_tap(ch, k);
            idx = idx + 1;
        end
    end
end
