clc;
clear;

addpath('npy-matlab');

debug_dir = 'debug';

mat_input = readNPY(fullfile(debug_dir, 'matlab_input_q.npy'));
tfl_input = readNPY(fullfile(debug_dir, 'tflite_input_q.npy'));
mat_c1 = readNPY(fullfile(debug_dir, 'matlab_conv1_relu.npy'));
tfl_c1 = readNPY(fullfile(debug_dir, 'tflite_conv1_relu.npy'));
mat_c2 = readNPY(fullfile(debug_dir, 'matlab_conv2_relu.npy'));
tfl_c2 = readNPY(fullfile(debug_dir, 'tflite_conv2_relu.npy'));
mat_c3 = readNPY(fullfile(debug_dir, 'matlab_conv3_relu.npy'));
tfl_c3 = readNPY(fullfile(debug_dir, 'tflite_conv3_relu.npy'));

report_diff('input_q', mat_input, tfl_input);
report_diff('conv1_relu', mat_c1, tfl_c1);
report_diff('conv2_relu', mat_c2, tfl_c2);
report_diff('conv3_relu', mat_c3, tfl_c3);

mat_dense = fullfile(debug_dir, 'matlab_dense_i8.npy');
tfl_dense = fullfile(debug_dir, 'tflite_dense_i8.npy');
if exist(mat_dense, 'file') && exist(tfl_dense, 'file')
    report_diff('dense_i8', readNPY(mat_dense), readNPY(tfl_dense));
else
    fprintf('\n[DENSE_I8]\nskip: missing file(s)\n');
end

function report_diff(tag, mat_arr, ref_arr)
    mat_i16 = int16(mat_arr);
    ref_i16 = int16(ref_arr);

    if isvector(mat_i16) && isvector(ref_i16)
        mat_i16 = mat_i16(:);
        ref_i16 = ref_i16(:);
    end

    assert(isequal(size(mat_i16), size(ref_i16)), ...
        '%s shape mismatch: mat=%s ref=%s', ...
        tag, mat2str(size(mat_i16)), mat2str(size(ref_i16)));

    d = mat_i16 - ref_i16;
    total = numel(d);
    num_diff = nnz(d ~= 0);
    max_abs_diff = max(abs(d(:)));

    fprintf('\n[%s]\n', upper(tag));
    fprintf('shape        : %s\n', mat2str(size(mat_i16)));
    fprintf('num_diff     : %d / %d (%.4f%%)\n', num_diff, total, 100 * num_diff / total);
    fprintf('max_abs_diff : %d\n', max_abs_diff);

    if num_diff > 0
        [~, idx] = max(abs(d(:)));
        subs = cell(1, ndims(d));
        [subs{:}] = ind2sub(size(d), idx);
        sub_str = sprintf('%d,', cell2mat(subs));
        sub_str = sub_str(1:end-1);
        fprintf('worst        : pos=(%s), mat=%d, ref=%d, diff=%d\n', ...
            sub_str, mat_i16(idx), ref_i16(idx), d(idx));
    end
end
