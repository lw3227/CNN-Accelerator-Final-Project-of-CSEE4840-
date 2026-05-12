function P = load_params(params_mat_path)
% LOAD_PARAMS  Load TFLite-exported INT8 model into hw_forward-ready struct.
%
%   P = load_params(params_mat_path)
%
%   Reads .mat produced by pytorch/export_tflite_params_mat.py with the
%   conventions documented in matlab/main/rps_conv2.m:
%
%     values{11}/{10} : conv1 weight / bias  (weight TFLite OHWI -> we permute to OIHW)
%     values{9}/{8}   : conv2 weight / bias
%     values{7}/{6}   : conv3 weight / bias
%     values{5}/{4}   : fc weight / bias  (already [Cout, K])
%
%   Output struct P:
%     P.W1, P.W2, P.W3   int8 weights in OIHW [Cout, Cin, H, W]
%     P.b1, P.b2, P.b3   int32 raw biases
%     P.W_fc             int8 [Cout=10, K=288]
%     P.b_fc             int32 [10]
%     P.in_zp                                 int32 input zero point
%     P.z_conv1_out / P.z_conv2_out / P.z_conv3_out  int32 quant zps
%     P.z_fc_in                               int32
%     P.qm1 / P.shift1                        int32 (per-channel from TFLite multiplier)
%     P.qm2 / P.shift2
%     P.qm3 / P.shift3
%     P.s_in                                   single (input scale, used for image quant)
%
%   FC quantization (qm_fc / shift_fc / z_fc_out) is intentionally OMITTED:
%   the hardware FC path has no requantization stage, argmax runs on the raw
%   INT32 accumulator. See matlab/main/hw_forward.m header for the rule.

    if ~exist(params_mat_path, 'file')
        error('load_params:missing', 'params .mat not found: %s', params_mat_path);
    end
    S = load(params_mat_path);

    % --- Conv weights: TFLite OHWI -> OIHW [Cout, Cin, H, W] -------------
    P.W1 = int8(permute(S.values{11}, [1, 4, 2, 3]));   % OHWI -> OIHW
    P.W2 = int8(permute(S.values{9},  [1, 4, 2, 3]));
    P.W3 = int8(permute(S.values{7},  [1, 4, 2, 3]));

    P.b1 = int32(S.values{10}(:));
    P.b2 = int32(S.values{8}(:));
    P.b3 = int32(S.values{6}(:));

    % --- FC weight / bias ------------------------------------------------
    P.W_fc = int8(S.values{5});      % [Cout, K]
    P.b_fc = int32(S.values{4}(:));

    % --- Zero points / scales --------------------------------------------
    P.in_zp        = int32(S.input_zero_points{1}(1));
    P.s_in         = single(S.input_scales{1}(1));
    P.z_conv1_out  = int32(S.activation_zero_points{1}(1));
    P.z_conv2_out  = int32(S.activation_zero_points{3}(1));
    P.z_conv3_out  = int32(S.activation_zero_points{5}(1));
    P.z_fc_in      = int32(S.activation_zero_points{10}(1));

    s_conv1_out = S.activation_scales{1};
    s_conv2_out = S.activation_scales{3};
    s_conv3_out = S.activation_scales{5};

    sw1 = S.scales{11};
    sw2 = S.scales{9};
    sw3 = S.scales{7};

    % Per-channel multiplier/shift via TFLite formula.
    [~, qm1, sh1] = tflite_quantize_multiplier(P.s_in,        sw1, s_conv1_out);
    [~, qm2, sh2] = tflite_quantize_multiplier(s_conv1_out,   sw2, s_conv2_out);
    [~, qm3, sh3] = tflite_quantize_multiplier(s_conv2_out,   sw3, s_conv3_out);

    P.qm1    = int32(qm1(:));    P.shift1 = int32(sh1(:));
    P.qm2    = int32(qm2(:));    P.shift2 = int32(sh2(:));
    P.qm3    = int32(qm3(:));    P.shift3 = int32(sh3(:));
end
