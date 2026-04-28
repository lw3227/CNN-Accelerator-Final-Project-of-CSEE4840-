% compare_conv3_matlab_vs_tflite.m
% 作用：比较 MATLAB 手算的 conv3 int8 输出 与 TFLite dump 的同层输出

%% 1) 读文件
% 你的手算结果（改成你的变量名/文件）
A = load('conv3_out_int8.mat');      % 例如包含变量 conv3_out_int8
mat = A.conv3_out_int8;              % int8, HxWxC 或 1xHxWxC

% TFLite 参考结果（优先 .mat；如果你只有 .npy 就改 readNPY）
R = load('conv3_ref.mat');           % 例如包含变量 conv3_ref
ref = R.conv3_ref;                   % 常见是 1xHxWxC

%% 2) 维度对齐（去掉 batch 维）
if ndims(mat) == 4 && size(mat,1) == 1, mat = squeeze(mat); end
if ndims(ref) == 4 && size(ref,1) == 1, ref = squeeze(ref); end

assert(isequal(size(mat), size(ref)), ...
    'Shape mismatch: mat=%s ref=%s', mat2str(size(mat)), mat2str(size(ref)));

mat = int8(mat);
ref = int8(ref);

%% 3) 整体误差
d = int16(mat) - int16(ref);
max_abs_diff = max(abs(d(:)));
num_diff = nnz(d ~= 0);
total = numel(d);

fprintf('\n[OVERALL]\n');
fprintf('shape: %s\n', mat2str(size(mat)));
fprintf('num_diff: %d / %d (%.4f%%)\n', num_diff, total, 100*num_diff/total);
fprintf('max_abs_diff: %d\n', max_abs_diff);

%% 4) 饱和统计
mat_neg128 = nnz(mat == -128); mat_pos127 = nnz(mat == 127);
ref_neg128 = nnz(ref == -128); ref_pos127 = nnz(ref == 127);

fprintf('\n[SATURATION]\n');
fprintf('MAT: -128=%d (%.2f%%), 127=%d (%.2f%%)\n', ...
    mat_neg128, 100*mat_neg128/total, mat_pos127, 100*mat_pos127/total);
fprintf('REF: -128=%d (%.2f%%), 127=%d (%.2f%%)\n', ...
    ref_neg128, 100*ref_neg128/total, ref_pos127, 100*ref_pos127/total);

%% 5) 通道级统计
C = size(mat,3);
fprintf('\n[PER-CHANNEL] c | mat[min max mean] | ref[min max mean] | diff_nnz\n');
for c = 1:C
    mc = mat(:,:,c); rc = ref(:,:,c); dc = d(:,:,c);
    fprintf('%2d | [%4d %4d %8.3f] | [%4d %4d %8.3f] | %d\n', ...
        c, min(mc(:)), max(mc(:)), mean(double(mc(:))), ...
        min(rc(:)), max(rc(:)), mean(double(rc(:))), ...
        nnz(dc ~= 0));
end

%% 6) 可选：找差异最大的点
if num_diff > 0
    [~, idx] = max(abs(d(:)));
    [i,j,c] = ind2sub(size(d), idx);
    fprintf('\n[WORST]\n');
    fprintf('pos=(%d,%d,%d), mat=%d, ref=%d, diff=%d\n', ...
        i,j,c, mat(i,j,c), ref(i,j,c), d(i,j,c));
end
