clc;
clear;
close all;

matlab_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(matlab_dir);

params_path = fullfile(repo_root, 'models', 'v1.int8.params.mat');
image_path = fullfile(matlab_dir, 'digit_3_test.png');
class_names = string(0:9);
show_layer_outputs = true;

if ~exist(params_path, 'file')
    error("Parameter file not found: %s\nExport it first with pytorch/export_tflite_params_mat.py.", params_path);
end
if ~exist(image_path, 'file')
    error("Image file not found: %s", image_path);
end

S = load(params_path);

img_uint8 = imread(image_path);
if ndims(img_uint8) == 3
    img_uint8 = rgb2gray(img_uint8);
end
if size(img_uint8, 1) ~= 64 || size(img_uint8, 2) ~= 64
    img_uint8 = imresize(img_uint8, [64, 64]);
end

s_in = single(S.input_scales{1}(1));
in_zp = int32(S.input_zero_points{1}(1));
img_float = single(img_uint8) / 255.0;
img_q_i32 = int32(round(img_float / s_in)) + in_zp;
img_q_i32 = max(min(img_q_i32, int32(127)), int32(-128));
img_int8 = int8(img_q_i32);

if show_layer_outputs
    figure('Name', 'MATLAB INT8 input');
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    imshow(img_uint8, []);
    title('input uint8');
    nexttile;
    imshow(img_int8, []);
    title('input int8 quantized');
end

% TFLite exports Conv2D weights as OHWI. MATLAB kernels below use HWIO.
% Parameter order for models/v1.int8.params.mat:
%   values{11}/{10}: conv1 weight/bias
%   values{9}/{8}  : conv2 weight/bias
%   values{7}/{6}  : conv3 weight/bias
%   values{5}/{4}  : fc weight/bias, shape [10,288] / [10]
W1 = S.values{11};
W1_hwio = permute(W1, [2 3 4 1]);
b1 = int32(S.values{10}(:));

W2 = S.values{9};
W2_hwio = permute(W2, [2 3 4 1]);
b2 = int32(S.values{8}(:));

W3 = S.values{7};
W3_hwio = permute(W3, [2 3 4 1]);
b3 = int32(S.values{6}(:));

w_fc = S.values{5};
b_fc = int32(S.values{4}(:));

z_conv1_out = int32(S.activation_zero_points{1}(1));
z_conv2_out = int32(S.activation_zero_points{3}(1));
z_conv3_out = int32(S.activation_zero_points{5}(1));
z_fc_in = int32(S.activation_zero_points{10}(1));
z_fc_out = int32(S.activation_zero_points{11}(1));

sw1 = S.scales{11};
sw2 = S.scales{9};
sw3 = S.scales{7};
sw_fc = S.scales{5};

s_conv1_out = S.activation_scales{1};
s_conv2_out = S.activation_scales{3};
s_conv3_out = S.activation_scales{5};
s_fc_in = S.activation_scales{10};
s_fc_out = S.activation_scales{11};

[~, qm1, shift1] = tflite_quantize_multiplier(s_in, sw1, s_conv1_out);
[~, qm2, shift2] = tflite_quantize_multiplier(s_conv1_out, sw2, s_conv2_out);
[~, qm3, shift3] = tflite_quantize_multiplier(s_conv2_out, sw3, s_conv3_out);
[~, qm_fc, shift_fc] = tflite_quantize_multiplier(s_fc_in, sw_fc, s_fc_out);

conv1_i32 = conv2D_int8(img_int8, W1_hwio, b1, 1, 'valid', in_zp, int32(0));
conv1_i8 = requant_int32_to_int8(conv1_i32, qm1, shift1, z_conv1_out);
relu1_i8 = relu(conv1_i8, int8(z_conv1_out));
pool1_i8 = relu_maxpool2x2_int8(relu1_i8, int8(z_conv1_out));

if show_layer_outputs
    show_feature_maps(relu1_i8, 'conv1 relu output');
    show_feature_maps(pool1_i8, 'pool1 output');
end

conv2_i32 = conv2D_int8(pool1_i8, W2_hwio, b2, 1, 'valid', z_conv1_out, int32(0));
conv2_i8 = requant_int32_to_int8(conv2_i32, qm2, shift2, z_conv2_out);
relu2_i8 = relu(conv2_i8, int8(z_conv2_out));
pool2_i8 = relu_maxpool2x2_int8(relu2_i8, int8(z_conv2_out));

if show_layer_outputs
    show_feature_maps(relu2_i8, 'conv2 relu output');
    show_feature_maps(pool2_i8, 'pool2 output');
end

conv3_i32 = conv2D_int8(pool2_i8, W3_hwio, b3, 1, 'valid', z_conv2_out, int32(0));
conv3_i8 = requant_int32_to_int8(conv3_i32, qm3, shift3, z_conv3_out);
relu3_i8 = relu(conv3_i8, int8(z_conv3_out));
pool3_i8 = relu_maxpool2x2_int8(relu3_i8, int8(z_conv3_out));

if show_layer_outputs
    show_feature_maps(relu3_i8, 'conv3 relu output');
    show_feature_maps(pool3_i8, 'pool3 output');
end

x_fc = flatten_nhwc_int8(pool3_i8);
assert(size(w_fc, 1) == numel(class_names), 'FC output classes must be 10');
assert(size(w_fc, 2) == numel(x_fc), 'FC weight input length must match flattened tensor');
assert(numel(b_fc) == size(w_fc, 1), 'FC bias length must match output classes');

[fc_i32, fc_i8] = fully_connected_int8( ...
    x_fc, w_fc, b_fc, z_fc_in, int32(0), qm_fc, shift_fc, z_fc_out);

[~, pred_idx] = max(double(fc_i8));
pred_label = class_names(pred_idx);

if show_layer_outputs
    figure('Name', 'FC output');
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    bar(double(fc_i32(:)));
    title('fc int32 accumulator');
    xlabel('class');
    ylabel('acc');
    xticks(1:numel(class_names));
    xticklabels(class_names);

    nexttile;
    bar(double(fc_i8(:)));
    title('fc int8 requantized');
    xlabel('class');
    ylabel('int8');
    xticks(1:numel(class_names));
    xticklabels(class_names);
end

fprintf('image      : %s\n', image_path);
fprintf('conv1_i8   : %s\n', mat2str(size(conv1_i8)));
fprintf('pool1_i8   : %s\n', mat2str(size(pool1_i8)));
fprintf('conv2_i8   : %s\n', mat2str(size(conv2_i8)));
fprintf('pool2_i8   : %s\n', mat2str(size(pool2_i8)));
fprintf('conv3_i8   : %s\n', mat2str(size(conv3_i8)));
fprintf('pool3_i8   : %s\n', mat2str(size(pool3_i8)));
fprintf('fc_i32     : %s\n', mat2str(fc_i32(:).'));
fprintf('fc_i8      : %s\n', mat2str(fc_i8(:).'));
fprintf('pred idx   : %d (MATLAB 1-based)\n', pred_idx);
fprintf('pred label : %s\n', pred_label);

function show_feature_maps(x, fig_name)
    x = squeeze(x);
    if ndims(x) == 2
        x = reshape(x, size(x, 1), size(x, 2), 1);
    end

    num_channels = size(x, 3);
    num_cols = ceil(sqrt(num_channels));
    num_rows = ceil(num_channels / num_cols);

    figure('Name', fig_name);
    tiledlayout(num_rows, num_cols, 'TileSpacing', 'compact', 'Padding', 'compact');
    for c = 1:num_channels
        nexttile;
        imshow(x(:, :, c), []);
        title(sprintf('ch %d', c));
    end
end
