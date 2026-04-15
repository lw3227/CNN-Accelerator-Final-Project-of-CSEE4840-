function export_cnn_rtl_txt_dataset(varargin)
% Export txt-driven RTL golden files for paper / rock / scissors cases.
%
% This exporter keeps the current Conv1 txt format for backward-compatible
% testbenches, and additionally emits L2/L3 conv-only golden files using:
% - layer input tensors taken from the previous layer's full post-processed
%   output (requant + ReLU + Pooling)
% - zero bias
% - x_zp = 0 and w_zp = 0 during the current layer's MAC accumulation

    p = inputParser;
    addParameter(p, 'sample_tags', {'paper', 'rock', 'scissors'});
    addParameter(p, 'output_root', fullfile('debug', 'txt_cases'));
    addParameter(p, 'write_legacy_conv1_alias', true);
    addParameter(p, 'legacy_sample_tag', 'scissors');
    parse(p, varargin{:});

    sample_specs = get_sample_specs();
    selected_specs = select_sample_specs(sample_specs, p.Results.sample_tags);
    output_root = p.Results.output_root;

    if ~exist(output_root, 'dir')
        mkdir(output_root);
    end

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

    W1_hwio = permute(S.values{9}, [2 3 4 1]);  % [3 3 1 4]
    b1 = int32(S.values{8}(:));
    W2_hwio = permute(S.values{7}, [2 3 4 1]);  % [3 3 4 8]
    b2 = int32(S.values{6}(:));
    W3_hwio = permute(S.values{5}, [2 3 4 1]);  % [3 3 8 8]
    b3 = int32(S.values{4}(:));

    s_in = S.input_scales{1};
    sw1 = S.scales{9};
    sw2 = S.scales{7};
    sw3 = S.scales{5};

    s_conv1_out = S.activation_scales{1};
    s_conv2_out = S.activation_scales{3};
    s_conv3_out = S.activation_scales{5};

    [~, qm1, shift1] = tflite_quantize_multiplier(s_in,        sw1, s_conv1_out);
    [~, qm2, shift2] = tflite_quantize_multiplier(s_conv1_out, sw2, s_conv2_out);
    [~, qm3, shift3] = tflite_quantize_multiplier(s_conv2_out, sw3, s_conv3_out);

    % FC parameters
    w_fc  = S.values{3};             % [3, 288] int8
    b_fc  = int32(S.values{2}(:));   % [3] int32
    x_zp_fc = int32(S.activation_zero_points{7}(1));

    % Precompute effective bias: eff_bias = bias - x_zp * sum(w)
    fc_eff_bias = zeros(3, 1, 'int32');
    for o = 1:3
        fc_eff_bias(o) = b_fc(o) - x_zp_fc * int32(sum(int32(w_fc(o,:))));
    end

    for idx = 1:numel(selected_specs)
        spec = selected_specs{idx};
        fprintf('INFO: exporting RTL txt case %s from %s\n', spec.tag, spec.image_file);

        img_int8 = load_and_quantize_image(spec.image_file, in_zp);

        conv1_mac_i32 = conv2D_int8(img_int8, W1_hwio, zeros(size(b1), 'int32'), ...
                                    1, 'valid', int32(0), int32(0));
        conv1_full_i32 = conv2D_int8(img_int8, W1_hwio, b1, ...
                                     1, 'valid', in_zp, int32(0));
        conv1_i8 = requant_int32_to_int8(conv1_full_i32, qm1, shift1, z_conv1_out);
        relu1 = relu(conv1_i8, int8(z_conv1_out));
        pool1 = relu_maxpool2x2_int8(relu1, int8(z_conv1_out));

        conv2_mac_i32 = conv2D_int8(pool1, W2_hwio, zeros(size(b2), 'int32'), ...
                                    1, 'valid', int32(0), int32(0));
        conv2_full_i32 = conv2D_int8(pool1, W2_hwio, b2, ...
                                     1, 'valid', z_conv1_out, int32(0));
        conv2_i8 = requant_int32_to_int8(conv2_full_i32, qm2, shift2, z_conv2_out);
        relu2 = relu(conv2_i8, int8(z_conv2_out));
        pool2 = relu_maxpool2x2_int8(relu2, int8(z_conv2_out));

        conv3_mac_i32 = conv2D_int8(pool2, W3_hwio, zeros(size(b3), 'int32'), ...
                                    1, 'valid', int32(0), int32(0));
        conv3_full_i32 = conv2D_int8(pool2, W3_hwio, b3, ...
                                     1, 'valid', z_conv2_out, int32(0));
        conv3_i8 = requant_int32_to_int8(conv3_full_i32, qm3, shift3, z_conv3_out);
        relu3 = relu(conv3_i8, int8(z_conv3_out));
        pool3 = relu_maxpool2x2_int8(relu3, int8(z_conv3_out));

        case_dir = fullfile(output_root, spec.tag);
        if ~exist(case_dir, 'dir')
            mkdir(case_dir);
        end

        write_tensor_txt(img_int8, fullfile(case_dir, 'tb_conv1_in_i8_64x64x1.txt'));
        write_tensor_txt(squeeze(W1_hwio(:, :, 1, :)), ...
                         fullfile(case_dir, 'tb_conv1_w_i8_3x3x4.txt'));
        write_tensor_txt(int32(conv1_mac_i32), ...
                         fullfile(case_dir, 'tb_conv1_out_i32_62x62x4.txt'));

        write_tensor_txt(pool1, fullfile(case_dir, 'tb_conv2_in_i8_31x31x4.txt'));
        write_tensor_txt(W2_hwio, fullfile(case_dir, 'tb_conv2_w_i8_3x3x4x8.txt'));
        write_tensor_txt(int32(conv2_mac_i32), ...
                         fullfile(case_dir, 'tb_conv2_out_i32_29x29x8.txt'));

        write_tensor_txt(pool2, fullfile(case_dir, 'tb_conv3_in_i8_14x14x8.txt'));
        write_tensor_txt(W3_hwio, fullfile(case_dir, 'tb_conv3_w_i8_3x3x8x8.txt'));
        write_tensor_txt(int32(conv3_mac_i32), ...
                         fullfile(case_dir, 'tb_conv3_out_i32_12x12x8.txt'));

        % FC golden: acc = eff_bias + sum(x * w), no zp subtraction at runtime
        x_fc = flatten_nhwc_int8(pool3);
        fc_out_i32 = zeros(3, 1, 'int32');
        for o = 1:3
            fc_out_i32(o) = fc_eff_bias(o) + int32(sum(int32(x_fc) .* int32(w_fc(o,:))));
        end

        write_tensor_txt(x_fc, fullfile(case_dir, 'tb_fc_in_i8_288.txt'));
        write_tensor_txt(w_fc, fullfile(case_dir, 'tb_fc_w_i8_3x288.txt'));
        write_tensor_txt(fc_eff_bias, fullfile(case_dir, 'tb_fc_bias_eff_i32_3.txt'));
        write_tensor_txt(fc_out_i32, fullfile(case_dir, 'tb_fc_out_i32_3.txt'));

        write_case_manifest(case_dir, spec, in_zp, z_conv1_out, z_conv2_out, z_conv3_out, ...
                            img_int8, pool1, pool2, conv1_mac_i32, conv2_mac_i32, conv3_mac_i32, ...
                            fc_out_i32);
    end

    if p.Results.write_legacy_conv1_alias
        legacy_case_dir = fullfile(output_root, p.Results.legacy_sample_tag);
        if ~exist(legacy_case_dir, 'dir')
            error('Legacy sample tag "%s" was not exported.', p.Results.legacy_sample_tag);
        end
        copyfile(fullfile(legacy_case_dir, 'tb_conv1_in_i8_64x64x1.txt'), ...
                 fullfile('debug', 'tb_conv1_in_i8_64x64x1.txt'));
        copyfile(fullfile(legacy_case_dir, 'tb_conv1_w_i8_3x3x4.txt'), ...
                 fullfile('debug', 'tb_conv1_w_i8_3x3x4.txt'));
        copyfile(fullfile(legacy_case_dir, 'tb_conv1_out_i32_62x62x4.txt'), ...
                 fullfile('debug', 'tb_conv1_out_i32_62x62x4.txt'));
        fprintf('INFO: refreshed legacy Conv1 txt aliases from sample %s\n', p.Results.legacy_sample_tag);
    end
end

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

function write_case_manifest(case_dir, spec, in_zp, z_conv1_out, z_conv2_out, z_conv3_out, ...
                             img_int8, pool1, pool2, conv1_mac_i32, conv2_mac_i32, conv3_mac_i32, ...
                             fc_out_i32)
    manifest_path = fullfile(case_dir, 'manifest.txt');
    fid = fopen(manifest_path, 'w');
    if fid < 0
        error('Cannot open %s for writing.', manifest_path);
    end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'case=%s\n', spec.tag);
    fprintf(fid, 'image_file=%s\n', spec.image_file);
    fprintf(fid, 'conv1_input=tb_conv1_in_i8_64x64x1.txt\n');
    fprintf(fid, 'conv1_weight=tb_conv1_w_i8_3x3x4.txt\n');
    fprintf(fid, 'conv1_output=tb_conv1_out_i32_62x62x4.txt\n');
    fprintf(fid, 'conv2_input=tb_conv2_in_i8_31x31x4.txt\n');
    fprintf(fid, 'conv2_weight=tb_conv2_w_i8_3x3x4x8.txt\n');
    fprintf(fid, 'conv2_output=tb_conv2_out_i32_29x29x8.txt\n');
    fprintf(fid, 'conv3_input=tb_conv3_in_i8_14x14x8.txt\n');
    fprintf(fid, 'conv3_weight=tb_conv3_w_i8_3x3x8x8.txt\n');
    fprintf(fid, 'conv3_output=tb_conv3_out_i32_12x12x8.txt\n');
    fprintf(fid, 'input_zero_point=%d\n', in_zp);
    fprintf(fid, 'conv1_output_zero_point=%d\n', z_conv1_out);
    fprintf(fid, 'conv2_output_zero_point=%d\n', z_conv2_out);
    fprintf(fid, 'conv3_output_zero_point=%d\n', z_conv3_out);
    fprintf(fid, 'conv_rule=layer input keeps full upstream tensor values; current-layer conv MAC uses x_zp=0,w_zp=0,bias=0\n');
    fprintf(fid, 'conv1_input_shape=%s\n', shape_string(img_int8));
    fprintf(fid, 'conv2_input_shape=%s\n', shape_string(pool1));
    fprintf(fid, 'conv3_input_shape=%s\n', shape_string(pool2));
    fprintf(fid, 'conv1_output_shape=%s\n', shape_string(conv1_mac_i32));
    fprintf(fid, 'conv2_output_shape=%s\n', shape_string(conv2_mac_i32));
    fprintf(fid, 'conv3_output_shape=%s\n', shape_string(conv3_mac_i32));
    fprintf(fid, 'conv1_output_range=[%d,%d]\n', min(conv1_mac_i32, [], 'all'), max(conv1_mac_i32, [], 'all'));
    fprintf(fid, 'conv2_output_range=[%d,%d]\n', min(conv2_mac_i32, [], 'all'), max(conv2_mac_i32, [], 'all'));
    fprintf(fid, 'conv3_output_range=[%d,%d]\n', min(conv3_mac_i32, [], 'all'), max(conv3_mac_i32, [], 'all'));
    fprintf(fid, 'fc_input=tb_fc_in_i8_288.txt\n');
    fprintf(fid, 'fc_weight=tb_fc_w_i8_3x288.txt\n');
    fprintf(fid, 'fc_bias_eff=tb_fc_bias_eff_i32_3.txt\n');
    fprintf(fid, 'fc_output=tb_fc_out_i32_3.txt\n');
    fprintf(fid, 'fc_output_range=[%d,%d]\n', min(fc_out_i32), max(fc_out_i32));
    fprintf(fid, 'fc_rule=acc = eff_bias + sum(x*w); eff_bias = bias - x_zp*sum(w); no runtime zp subtraction\n');
    clear cleaner;
end

function out = shape_string(tensor)
    dims = size(tensor);
    out = sprintf('%dx', dims);
    out(end) = [];
end

function selected_specs = select_sample_specs(sample_specs, sample_tags)
    if ischar(sample_tags)
        sample_tags = {sample_tags};
    end

    selected_specs = cell(1, numel(sample_tags));
    for idx = 1:numel(sample_tags)
        tag = sample_tags{idx};
        match = [];
        for s = 1:numel(sample_specs)
            if strcmp(sample_specs{s}.tag, tag)
                match = sample_specs{s};
                break;
            end
        end
        if isempty(match)
            error('Unknown sample tag "%s".', tag);
        end
        selected_specs{idx} = match;
    end
end

function specs = get_sample_specs()
    specs = {
        struct('tag', 'paper',    'image_file', 'paper_200_v2_test_723.png')
        struct('tag', 'rock',     'image_file', 'rock_200_v1_test_1484.png')
        struct('tag', 'scissors', 'image_file', 'scissors_200_v1_test_1644.png')
    };
end
