% Export L1 quantization parameters and post-processing goldens for RTL.
%
% Run this script from the matlab/ directory:
%   >> export_conv1_quant_params

sample_specs = get_sample_specs();
output_root = fullfile('debug', 'txt_cases');

if ~exist(output_root, 'dir')
    error('Output root "%s" does not exist. Run from matlab/ directory.', output_root);
end

S = load('v2.int8.params.mat');

in_zp       = int32(S.input_zero_points{1}(1));
z_conv1_out = int32(S.activation_zero_points{1}(1));
W1_hwio     = permute(S.values{9}, [2 3 4 1]);   % [3 3 1 4] int8
b1          = int32(S.values{8}(:));             % [4x1] int32
s_in        = S.input_scales{1};
sw1         = S.scales{9};
s_conv1_out = S.activation_scales{1};
[~, qm1, shift1] = tflite_quantize_multiplier(s_in, sw1, s_conv1_out);

eff_bias = zeros(4, 1, 'int32');
for c = 1:4
    eff_bias(c) = b1(c) + int32(128) * sum(int32(W1_hwio(:, :, 1, c)), 'all');
end

qm1 = int32(qm1(:));
total_shift = int32(31) - int32(shift1(:));

verify_msgs = cell(numel(sample_specs), 1);

for idx = 1:numel(sample_specs)
    spec = sample_specs{idx};
    case_dir = fullfile(output_root, spec.tag);
    if ~exist(case_dir, 'dir')
        error('Case directory "%s" does not exist.', case_dir);
    end

    fprintf('INFO: processing case %s from %s\n', spec.tag, spec.image_file);

    img_int8 = load_and_quantize_image_local(spec.image_file, in_zp);
    conv1_full_i32 = conv2D_int8(img_int8, W1_hwio, b1, 1, 'valid', in_zp, int32(0));
    conv1_i8 = requant_int32_to_int8(conv1_full_i32, qm1, shift1, z_conv1_out);
    pool1 = relu_maxpool2x2_int8(relu(conv1_i8, int8(z_conv1_out)), int8(z_conv1_out));

    pool1_ref = read_tensor_txt(fullfile(case_dir, 'tb_conv2_in_i8_31x31x4.txt'), [31, 31, 4], 'int8');
    [mismatch_cnt, mismatch_examples] = compare_tensors(pool1, pool1_ref, 5);
    if mismatch_cnt ~= 0
        fprintf('FAIL: %s pool1 mismatch count = %d\n', spec.tag, mismatch_cnt);
        print_mismatch_examples(mismatch_examples);
        error('pool1 mismatch detected for case %s.', spec.tag);
    end

    write_tensor_txt(eff_bias, fullfile(case_dir, 'tb_conv1_quant_bias_eff_i32_4.txt'));
    write_tensor_txt(qm1, fullfile(case_dir, 'tb_conv1_quant_M_i32_4.txt'));
    write_tensor_txt(total_shift, fullfile(case_dir, 'tb_conv1_quant_sh_i32_4.txt'));
    write_tensor_txt(conv1_i8, fullfile(case_dir, 'tb_conv1_requant_i8_62x62x4.txt'));
    write_tensor_txt(pool1, fullfile(case_dir, 'tb_conv1_pool_i8_31x31x4.txt'));

    verify_msgs{idx} = sprintf('%-9s pool1 vs existing tb_conv2_in - 0 mismatches %s', ...
                               [spec.tag ':'], char(10003));
end

fprintf('\n=== L1 Quant Params (shared across all cases) ===\n');
fprintf('eff_bias = [%s]\n', join_int_list(eff_bias));
fprintf('qm       = [%s]\n', join_int_list(qm1));
fprintf('sh       = [%s]\n', join_int_list(total_shift));
fprintf('in_zp    = %d\n', in_zp);
fprintf('z_out    = %d\n', z_conv1_out);

fprintf('\n=== Per-case verification ===\n');
for idx = 1:numel(verify_msgs)
    fprintf('%s\n', verify_msgs{idx});
end

function img_int8 = load_and_quantize_image_local(image_file, in_zp)
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
        case 'int8'
            tensor = reshape(int8(vals), dims);
        case 'int32'
            tensor = reshape(int32(vals), dims);
        otherwise
            error('Unsupported dtype %s.', dtype);
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
    a32 = int32(a);
    b32 = int32(b);
    diff_mask = (a32 ~= b32);
    mismatch_cnt = nnz(diff_mask);
    examples = {};

    if mismatch_cnt == 0
        return;
    end

    idxs = find(diff_mask);
    show_n = min(max_examples, numel(idxs));
    examples = cell(show_n, 1);
    dims = size(a32);

    for i = 1:show_n
        idx = idxs(i);
        [y, x, c] = ind2sub(dims, idx);
        examples{i} = struct( ...
            'y', y, ...
            'x', x, ...
            'c', c, ...
            'exp', b32(idx), ...
            'act', a32(idx));
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
