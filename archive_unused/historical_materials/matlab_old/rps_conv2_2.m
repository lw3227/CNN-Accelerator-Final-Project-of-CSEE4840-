clc;
clearvars;

addpath('npy-matlab');

save_debug_npy = true;
debug_dir = 'debug';
if save_debug_npy && ~exist(debug_dir, 'dir')
    mkdir(debug_dir);
end

% Input image
img_uint8 = imread('scissors_200_v1_test_1644.png');
if ndims(img_uint8) == 3
    img_uint8 = rgb2gray(img_uint8);
end
if ~isequal(size(img_uint8, 1), 64) || ~isequal(size(img_uint8, 2), 64)
    img_uint8 = imresize(img_uint8, [64, 64]);
end

% Load quantized model params
S = load('v2.int8.params.mat');

in_zp = int32(S.input_zero_points{1}(1));
if isfield(S, 'activation_zero_points')
    z_conv1_out = int32(S.activation_zero_points{1}(1));
    z_conv2_out = int32(S.activation_zero_points{3}(1));
    z_conv3_out = int32(S.activation_zero_points{5}(1));
else
    z_conv1_out = int32(-128);
    z_conv2_out = int32(-128);
    z_conv3_out = int32(-128);
end

% Input quantization
img_q_i32 = int32(img_uint8) + in_zp;
img_q_i32 = max(min(img_q_i32, int32(127)), int32(-128));
img_int8 = int8(img_q_i32);
if save_debug_npy
    writeNPY(img_int8, fullfile(debug_dir, 'matlab_input_q.npy'));
end

% Weights / bias
W1_hwio = permute(S.values{9}, [2 3 4 1]);  % [3 3 1 4]
b1 = int32(S.values{8}(:));

W2_hwio = permute(S.values{7}, [2 3 4 1]);  % [3 3 4 8]
b2 = int32(S.values{6}(:));

W3_hwio = permute(S.values{5}, [2 3 4 1]);  % [3 3 8 8]
b3 = int32(S.values{4}(:));

% Requant multipliers
s_in = S.input_scales{1};
sw1 = S.scales{9};
sw2 = S.scales{7};
sw3 = S.scales{5};
sw4 = S.scales{3};

s_conv1_out = S.activation_scales{1};
s_conv2_out = S.activation_scales{3};
s_conv3_out = S.activation_scales{5};
s_fc_out = S.activation_scales{8};

[~, qm1, shift1] = tflite_quantize_multiplier(s_in,        sw1, s_conv1_out);
[~, qm2, shift2] = tflite_quantize_multiplier(s_conv1_out, sw2, s_conv2_out);
[~, qm3, shift3] = tflite_quantize_multiplier(s_conv2_out, sw3, s_conv3_out);
[~, qm4, shift4] = tflite_quantize_multiplier(s_conv3_out, sw4, s_fc_out);

% Conv1 -> Requant -> ReLU -> Pool
conv1_img = conv2D_int8(img_int8, W1_hwio, b1, 1, 'valid', in_zp, int32(0));
conv1_img_int8 = requant_int32_to_int8(conv1_img, qm1, shift1, z_conv1_out);
Relu1 = relu(conv1_img_int8, int8(z_conv1_out));
if save_debug_npy
    writeNPY(Relu1, fullfile(debug_dir, 'matlab_conv1_relu.npy'));
end
Pooling1 = relu_maxpool2x2_int8(Relu1, int8(z_conv1_out));

% Conv2 -> Requant -> ReLU -> Pool
conv2_img = conv2D_int8(Pooling1, W2_hwio, b2, 1, 'valid', z_conv1_out, int32(0));
conv2_img_int8 = requant_int32_to_int8(conv2_img, qm2, shift2, z_conv2_out);
Relu2 = relu(conv2_img_int8, int8(z_conv2_out));
if save_debug_npy
    writeNPY(Relu2, fullfile(debug_dir, 'matlab_conv2_relu.npy'));
end
Pooling2 = relu_maxpool2x2_int8(Relu2, int8(z_conv2_out));

% Conv3 -> Requant -> ReLU -> Pool
conv3_img = conv2D_int8(Pooling2, W3_hwio, b3, 1, 'valid', z_conv2_out, int32(0));
conv3_img_int8 = requant_int32_to_int8(conv3_img, qm3, shift3, z_conv3_out);
Relu3 = relu(conv3_img_int8, int8(z_conv3_out));
if save_debug_npy
    writeNPY(Relu3, fullfile(debug_dir, 'matlab_conv3_relu.npy'));
end
Pooling3 = relu_maxpool2x2_int8(Relu3, int8(z_conv3_out));

% FC
x_fc = flatten_nhwc_int8(Pooling3);
w_fc = S.values{3};
b_fc = S.values{2};
x_zp_fc_in = S.activation_zero_points{7};
w_zp_fc = int32(0);
z_out_fc = S.activation_zero_points{8};

[out_fc_i32, out_fc_i8] = fully_connected_int8( ...
    x_fc, w_fc, b_fc, x_zp_fc_in, w_zp_fc, qm4, shift4, z_out_fc);

if save_debug_npy
    writeNPY(int8(x_fc), fullfile(debug_dir, 'matlab_flatten_i8.npy'));
    writeNPY(int8(out_fc_i8), fullfile(debug_dir, 'matlab_dense_i8.npy'));
    writeNPY(int32(out_fc_i32), fullfile(debug_dir, 'matlab_dense_i32.npy'));
end

% Final prediction
[~, idx] = max(double(out_fc_i8));   % MATLAB index is 1-based
class_names = ["paper", "rock", "scissors"];
pred_label = class_names(idx);

fprintf('pred idx (MATLAB 1-based): %d\n', idx);
fprintf('pred label: %s\n', pred_label);
