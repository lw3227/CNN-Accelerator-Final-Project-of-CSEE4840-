% Export L2/L3 quantization parameters and post-processing goldens for RTL.
%
% Generates per-case:
%   tb_conv2_quant_bias_eff_i32_8.txt / _M_ / _sh_
%   tb_conv2_requant_i8_29x29x8.txt
%   tb_conv2_pool_i8_14x14x8.txt
%   tb_conv3_quant_bias_eff_i32_8.txt / _M_ / _sh_
%   tb_conv3_requant_i8_12x12x8.txt
%   tb_conv3_pool_i8_6x6x8.txt
%
% Self-check: L2 pool output must match existing tb_conv3_in_i8_14x14x8.txt
%
% Run from the matlab/ directory:
%   >> export_conv23_quant_params

sample_specs = get_sample_specs();
output_root = fullfile('debug', 'txt_cases');

if ~exist(output_root, 'dir')
    error('Output root "%s" does not exist. Run from matlab/ directory.', output_root);
end

S = load('v2.int8.params.mat');

% --- L1 params (needed to compute L2 input = L1 pool output) ---
in_zp       = int32(S.input_zero_points{1}(1));
z_conv1_out = int32(S.activation_zero_points{1}(1));
W1_hwio     = permute(S.values{9}, [2 3 4 1]);   % [3 3 1 4]
b1          = int32(S.values{8}(:));
s_in        = S.input_scales{1};
sw1         = S.scales{9};
s_conv1_out = S.activation_scales{1};
[~, qm1, shift1] = tflite_quantize_multiplier(s_in, sw1, s_conv1_out);

% --- L2 params ---
z_conv2_out = int32(S.activation_zero_points{3}(1));
W2_hwio     = permute(S.values{7}, [2 3 4 1]);   % [3 3 4 8]
b2          = int32(S.values{6}(:));
sw2         = S.scales{7};
s_conv2_out = S.activation_scales{3};
[~, qm2, shift2] = tflite_quantize_multiplier(s_conv1_out, sw2, s_conv2_out);

% Conv-only RTL goldens use raw MAC with x_zp = 0 and bias = 0.
% Quant therefore needs an effective bias that folds in both the learned
% bias and the input zero-point correction:
%   eff_bias_L2(c) = b2(c) - z_in * sum(W2(:,:,:,c))
% where z_in = z_conv1_out (the input zero point for L2 = L1 output zp)
eff_bias2 = zeros(8, 1, 'int32');
for c = 1:8
    eff_bias2(c) = b2(c) - int32(z_conv1_out) * sum(int32(W2_hwio(:, :, :, c)), 'all');
end
qm2 = int32(qm2(:));
total_shift2 = int32(31) - int32(shift2(:));

% --- L3 params ---
z_conv3_out = int32(S.activation_zero_points{5}(1));
W3_hwio     = permute(S.values{5}, [2 3 4 1]);   % [3 3 8 8]
b3          = int32(S.values{4}(:));
sw3         = S.scales{5};
s_conv3_out = S.activation_scales{5};
[~, qm3, shift3] = tflite_quantize_multiplier(s_conv2_out, sw3, s_conv3_out);

eff_bias3 = zeros(8, 1, 'int32');
for c = 1:8
    eff_bias3(c) = b3(c) - int32(z_conv2_out) * sum(int32(W3_hwio(:, :, :, c)), 'all');
end
qm3 = int32(qm3(:));
total_shift3 = int32(31) - int32(shift3(:));

verify_msgs = {};

for idx = 1:numel(sample_specs)
    spec = sample_specs{idx};
    case_dir = fullfile(output_root, spec.tag);
    if ~exist(case_dir, 'dir')
        error('Case directory "%s" does not exist.', case_dir);
    end

    fprintf('INFO: processing case %s\n', spec.tag);

    % Recompute L1 pipeline to get pool1 (L2 input)
    img_int8 = load_and_quantize_image(spec.image_file, in_zp);
    conv1_full_i32 = conv2D_int8(img_int8, W1_hwio, b1, 1, 'valid', in_zp, int32(0));
    conv1_i8 = requant_int32_to_int8(conv1_full_i32, qm1, shift1, z_conv1_out);
    pool1 = relu_maxpool2x2_int8(relu(conv1_i8, int8(z_conv1_out)), int8(z_conv1_out));

    % === L2: Conv -> Requant -> ReLU -> Pool ===
    conv2_full_i32 = conv2D_int8(pool1, W2_hwio, b2, 1, 'valid', z_conv1_out, int32(0));
    conv2_i8 = requant_int32_to_int8(conv2_full_i32, qm2, shift2, z_conv2_out);
    relu2 = relu(conv2_i8, int8(z_conv2_out));
    pool2 = relu_maxpool2x2_int8(relu2, int8(z_conv2_out));

    % Self-check: L2 pool output vs existing tb_conv3_in
    conv3_in_ref = read_tensor_txt(fullfile(case_dir, 'tb_conv3_in_i8_14x14x8.txt'), [14, 14, 8], 'int8');
    [mc2, ex2] = compare_tensors(pool2, conv3_in_ref, 5);
    if mc2 ~= 0
        fprintf('FAIL: %s L2 pool vs tb_conv3_in mismatch count = %d\n', spec.tag, mc2);
        print_mismatch_examples(ex2);
        error('L2 pool mismatch for case %s.', spec.tag);
    end

    % Cross-check: eff_bias against conv-only raw-MAC golden.
    % The conv-only golden stores raw MAC with x_zp=0, bias=0.
    % RTL quant path computes: requant(raw_MAC + eff_bias, M, sh, z_out).
    % This must equal our requant golden.
    conv2_raw_mac = read_tensor_txt(fullfile(case_dir, 'tb_conv2_out_i32_29x29x8.txt'), [29, 29, 8], 'int32');
    conv2_biased = int32(conv2_raw_mac);
    for c = 1:8
        conv2_biased(:,:,c) = conv2_biased(:,:,c) + eff_bias2(c);
    end
    conv2_xcheck = requant_int32_to_int8(conv2_biased, qm2, shift2, z_conv2_out);
    [mc_xc2, ex_xc2] = compare_tensors(conv2_xcheck, conv2_i8, 5);
    if mc_xc2 ~= 0
        fprintf('FAIL: %s L2 eff_bias cross-check mismatch count = %d\n', spec.tag, mc_xc2);
        print_mismatch_examples(ex_xc2);
        error('L2 eff_bias cross-check failed for case %s.', spec.tag);
    end

    % Write L2 goldens
    write_tensor_txt(eff_bias2, fullfile(case_dir, 'tb_conv2_quant_bias_eff_i32_8.txt'));
    write_tensor_txt(qm2, fullfile(case_dir, 'tb_conv2_quant_M_i32_8.txt'));
    write_tensor_txt(total_shift2, fullfile(case_dir, 'tb_conv2_quant_sh_i32_8.txt'));
    write_tensor_txt(conv2_i8, fullfile(case_dir, 'tb_conv2_requant_i8_29x29x8.txt'));
    write_tensor_txt(pool2, fullfile(case_dir, 'tb_conv2_pool_i8_14x14x8.txt'));

    % === L3: Conv -> Requant -> ReLU -> Pool ===
    conv3_full_i32 = conv2D_int8(pool2, W3_hwio, b3, 1, 'valid', z_conv2_out, int32(0));
    conv3_i8 = requant_int32_to_int8(conv3_full_i32, qm3, shift3, z_conv3_out);
    relu3 = relu(conv3_i8, int8(z_conv3_out));
    pool3 = relu_maxpool2x2_int8(relu3, int8(z_conv3_out));

    % Cross-check L3 eff_bias against conv-only raw-MAC golden.
    conv3_raw_mac = read_tensor_txt(fullfile(case_dir, 'tb_conv3_out_i32_12x12x8.txt'), [12, 12, 8], 'int32');
    conv3_biased = int32(conv3_raw_mac);
    for c = 1:8
        conv3_biased(:,:,c) = conv3_biased(:,:,c) + eff_bias3(c);
    end
    conv3_xcheck = requant_int32_to_int8(conv3_biased, qm3, shift3, z_conv3_out);
    [mc_xc3, ex_xc3] = compare_tensors(conv3_xcheck, conv3_i8, 5);
    if mc_xc3 ~= 0
        fprintf('FAIL: %s L3 eff_bias cross-check mismatch count = %d\n', spec.tag, mc_xc3);
        print_mismatch_examples(ex_xc3);
        error('L3 eff_bias cross-check failed for case %s.', spec.tag);
    end

    % Write L3 goldens
    write_tensor_txt(eff_bias3, fullfile(case_dir, 'tb_conv3_quant_bias_eff_i32_8.txt'));
    write_tensor_txt(qm3, fullfile(case_dir, 'tb_conv3_quant_M_i32_8.txt'));
    write_tensor_txt(total_shift3, fullfile(case_dir, 'tb_conv3_quant_sh_i32_8.txt'));
    write_tensor_txt(conv3_i8, fullfile(case_dir, 'tb_conv3_requant_i8_12x12x8.txt'));
    write_tensor_txt(pool3, fullfile(case_dir, 'tb_conv3_pool_i8_6x6x8.txt'));

    verify_msgs{end+1} = sprintf('%-9s L2 pool vs tb_conv3_in - 0 mismatches %s', ...
                                 [spec.tag ':'], char(10003)); %#ok<AGROW>
end

fprintf('\n=== L2 Quant Params (shared across all cases) ===\n');
fprintf('eff_bias = [%s]\n', join_int_list(eff_bias2));
fprintf('qm       = [%s]\n', join_int_list(qm2));
fprintf('sh       = [%s]\n', join_int_list(total_shift2));
fprintf('z_in     = %d\n', z_conv1_out);
fprintf('z_out    = %d\n', z_conv2_out);

fprintf('\n=== L3 Quant Params (shared across all cases) ===\n');
fprintf('eff_bias = [%s]\n', join_int_list(eff_bias3));
fprintf('qm       = [%s]\n', join_int_list(qm3));
fprintf('sh       = [%s]\n', join_int_list(total_shift3));
fprintf('z_in     = %d\n', z_conv2_out);
fprintf('z_out    = %d\n', z_conv3_out);

fprintf('\n=== Per-case verification ===\n');
for idx = 1:numel(verify_msgs)
    fprintf('%s\n', verify_msgs{idx});
end

fprintf('\nDone. Files written to %s/{paper,rock,scissors}/\n', output_root);

% =========================================================================
% Helper functions
% =========================================================================

function img_int8 = load_and_quantize_image(image_file, in_zp)
    img_uint8 = imread(image_file);
    if ndims(img_uint8) == 3
        img_uint8 = rgb2gray(img_uint8);
    end
    if ~isequal(size(img_uint8, 1), 64) || ~isequal(size(img_uint8, 2), 64)
        img_uint8 = imresize(img_uint8, [64, 64]);
    end
    img_q_i32 = int32(img_uint8) + in_zp;
    img_q_i32 = max(min(img_q_i32, int32(127)), int32(-128));
    img_int8 = int8(img_q_i32);
end

function tensor = read_tensor_txt(path_name, dims, dtype)
    fid = fopen(path_name, 'r');
    if fid < 0
        error('Cannot open %s for reading.', path_name);
    end
    cleaner = onCleanup(@() fclose(fid));
    vals = fscanf(fid, '%d');
    clear cleaner;
    expected = prod(dims);
    if numel(vals) ~= expected
        error('File %s has %d values, expected %d.', path_name, numel(vals), expected);
    end
    switch dtype
        case 'int8',  tensor = reshape(int8(vals), dims);
        case 'int32', tensor = reshape(int32(vals), dims);
        otherwise,    error('Unsupported dtype %s.', dtype);
    end
end

function write_tensor_txt(tensor, path_name)
    fid = fopen(path_name, 'w');
    if fid < 0
        error('Cannot open %s for writing.', path_name);
    end
    cleaner = onCleanup(@() fclose(fid));
    for i = 1:numel(tensor)
        fprintf(fid, '%d\n', int32(tensor(i)));
    end
    clear cleaner;
end

function [mismatch_cnt, examples] = compare_tensors(a, b, max_examples)
    a32 = int32(a); b32 = int32(b);
    diff_mask = (a32 ~= b32);
    mismatch_cnt = nnz(diff_mask);
    examples = {};
    if mismatch_cnt == 0, return; end
    idxs = find(diff_mask);
    show_n = min(max_examples, numel(idxs));
    examples = cell(show_n, 1);
    dims = size(a32);
    for i = 1:show_n
        idx = idxs(i);
        [y, x, c] = ind2sub(dims, idx);
        examples{i} = struct('y', y, 'x', x, 'c', c, 'exp', b32(idx), 'act', a32(idx));
    end
end

function print_mismatch_examples(examples)
    for i = 1:numel(examples)
        ex = examples{i};
        fprintf('  mismatch[%d]: (y=%d, x=%d, c=%d) exp=%d act=%d\n', ...
                i, ex.y, ex.x, ex.c, ex.exp, ex.act);
    end
end

function out = join_int_list(vals)
    vals = int32(vals(:));
    parts = arrayfun(@(v) sprintf('%d', v), vals, 'UniformOutput', false);
    out = strjoin(parts, ', ');
end

function specs = get_sample_specs()
    specs = {
        struct('tag', 'paper',    'image_file', 'paper_200_v2_test_723.png')
        struct('tag', 'rock',     'image_file', 'rock_200_v1_test_1484.png')
        struct('tag', 'scissors', 'image_file', 'scissors_200_v1_test_1644.png')
    };
end
