function R = export_case(image_path, P, case_name, out_root)
% EXPORT_CASE  Run hardware-aligned forward + write all golden TXT for one image.
%
%   R = export_case(image_path, P, case_name, out_root)
%
%   image_path : path to source PNG (any size; converted to 64x64 grayscale)
%   P          : params struct from load_params()
%   case_name  : short tag for the case directory (e.g. 'digit_0')
%   out_root   : root directory; case files go to <out_root>/<case_name>/
%
%   Returns the hw_forward result struct R for further inspection.
%
%   Files written to <out_root>/<case_name>/ follow GOLDEN_FORMAT.md naming
%   `tb_<layer>_<role>_<dtype>_<shape>.txt` plus a `manifest.txt`.

    if nargin < 4 || isempty(out_root)
        matlab_dir = fileparts(mfilename('fullpath'));
        out_root   = fullfile(matlab_dir, 'debug', 'txt_cases');
    end

    case_dir = fullfile(out_root, case_name);
    if ~exist(case_dir, 'dir'), mkdir(case_dir); end

    % ---------------------------------------------------------------------
    %  Load + quantize image to INT8
    % ---------------------------------------------------------------------
    img_uint8 = imread(image_path);
    if ndims(img_uint8) == 3
        img_uint8 = rgb2gray(img_uint8);
    end
    if size(img_uint8, 1) ~= 64 || size(img_uint8, 2) ~= 64
        img_uint8 = imresize(img_uint8, [64, 64]);
    end
    img_float = single(img_uint8) / 255.0;
    img_q     = int32(round(img_float / P.s_in)) + P.in_zp;
    img_q     = max(min(img_q, int32(127)), int32(-128));
    img_int8  = int8(img_q);

    % ---------------------------------------------------------------------
    %  Hardware-aligned forward
    % ---------------------------------------------------------------------
    R = hw_forward(img_int8, P);

    % ---------------------------------------------------------------------
    %  Write all golden TXT files
    % ---------------------------------------------------------------------
    cd_ = @(name) fullfile(case_dir, name);

    % Conv1
    dump_txt(cd_('tb_conv1_in_i8_64x64x1.txt'),         R.input_int8,           'i8',  'hwc');
    dump_txt(cd_('tb_conv1_w_i8_3x3x4.txt'),            squeeze(R.conv1_w),     'i8',  'ohw');   % Cin=1 squeezed
    dump_txt(cd_('tb_conv1_out_i32_62x62x4.txt'),       R.conv1_mac,            'i32', 'hwc');
    dump_txt(cd_('tb_conv1_quant_bias_eff_i32_4.txt'),  R.conv1_eff_bias,       'i32', 'flat');
    dump_txt(cd_('tb_conv1_quant_M_i32_4.txt'),         R.conv1_M,              'i32', 'flat');
    dump_txt(cd_('tb_conv1_quant_sh_i32_4.txt'),        R.conv1_sh,             'i32', 'flat');
    dump_txt(cd_('tb_conv1_requant_i8_62x62x4.txt'),    R.conv1_requant,        'i8',  'hwc');
    dump_txt(cd_('tb_conv1_pool_i8_31x31x4.txt'),       R.pool1,                'i8',  'hwc');

    % Conv2
    dump_txt(cd_('tb_conv2_in_i8_31x31x4.txt'),         R.pool1,                'i8',  'hwc');
    dump_txt(cd_('tb_conv2_w_i8_3x3x4x8.txt'),          R.conv2_w,              'i8',  'oihw');
    dump_txt(cd_('tb_conv2_out_i32_29x29x8.txt'),       R.conv2_mac,            'i32', 'hwc');
    dump_txt(cd_('tb_conv2_quant_bias_eff_i32_8.txt'),  R.conv2_eff_bias,       'i32', 'flat');
    dump_txt(cd_('tb_conv2_quant_M_i32_8.txt'),         R.conv2_M,              'i32', 'flat');
    dump_txt(cd_('tb_conv2_quant_sh_i32_8.txt'),        R.conv2_sh,             'i32', 'flat');
    dump_txt(cd_('tb_conv2_requant_i8_29x29x8.txt'),    R.conv2_requant,        'i8',  'hwc');
    dump_txt(cd_('tb_conv2_pool_i8_14x14x8.txt'),       R.pool2,                'i8',  'hwc');

    % Conv3
    dump_txt(cd_('tb_conv3_in_i8_14x14x8.txt'),         R.pool2,                'i8',  'hwc');
    dump_txt(cd_('tb_conv3_w_i8_3x3x8x8.txt'),          R.conv3_w,              'i8',  'oihw');
    dump_txt(cd_('tb_conv3_out_i32_12x12x8.txt'),       R.conv3_mac,            'i32', 'hwc');
    dump_txt(cd_('tb_conv3_quant_bias_eff_i32_8.txt'),  R.conv3_eff_bias,       'i32', 'flat');
    dump_txt(cd_('tb_conv3_quant_M_i32_8.txt'),         R.conv3_M,              'i32', 'flat');
    dump_txt(cd_('tb_conv3_quant_sh_i32_8.txt'),        R.conv3_sh,             'i32', 'flat');
    dump_txt(cd_('tb_conv3_requant_i8_12x12x8.txt'),    R.conv3_requant,        'i8',  'hwc');
    dump_txt(cd_('tb_conv3_pool_i8_6x6x8.txt'),         R.pool3,                'i8',  'hwc');

    % FC (no quant -- raw INT32 accumulator with eff_bias, argmax-ready)
    dump_txt(cd_('tb_fc_in_i8_288.txt'),                R.fc_in,                'i8',  'flat');
    dump_txt(cd_('tb_fc_w_i8_10x288.txt'),              R.fc_w,                 'i8',  'fc_oik');
    dump_txt(cd_('tb_fc_w_interleaved_i8_288x10.txt'),  R.fc_w,                 'i8',  'fc_int_kxo');
    dump_txt(cd_('tb_fc_bias_eff_i32_10.txt'),          R.fc_eff_bias,          'i32', 'flat');
    dump_txt(cd_('tb_fc_out_i32_10.txt'),               R.fc_acc,               'i32', 'flat');

    % ---------------------------------------------------------------------
    %  Manifest (key=value, GOLDEN_FORMAT.md compliant)
    % ---------------------------------------------------------------------
    manifest_path = fullfile(case_dir, 'manifest.txt');
    fid = fopen(manifest_path, 'w');
    if fid < 0, error('export_case:io', 'cannot open %s', manifest_path); end
    cu = onCleanup(@() fclose(fid));

    [~, img_name, img_ext] = fileparts(image_path);
    fprintf(fid, 'case=%s\n',                         case_name);
    fprintf(fid, 'image_file=%s%s\n',                 img_name, img_ext);

    fprintf(fid, 'conv1_input=tb_conv1_in_i8_64x64x1.txt\n');
    fprintf(fid, 'conv1_weight=tb_conv1_w_i8_3x3x4.txt\n');
    fprintf(fid, 'conv1_output=tb_conv1_out_i32_62x62x4.txt\n');
    fprintf(fid, 'conv1_requant=tb_conv1_requant_i8_62x62x4.txt\n');
    fprintf(fid, 'conv1_pool=tb_conv1_pool_i8_31x31x4.txt\n');
    fprintf(fid, 'conv2_input=tb_conv2_in_i8_31x31x4.txt\n');
    fprintf(fid, 'conv2_weight=tb_conv2_w_i8_3x3x4x8.txt\n');
    fprintf(fid, 'conv2_output=tb_conv2_out_i32_29x29x8.txt\n');
    fprintf(fid, 'conv2_requant=tb_conv2_requant_i8_29x29x8.txt\n');
    fprintf(fid, 'conv2_pool=tb_conv2_pool_i8_14x14x8.txt\n');
    fprintf(fid, 'conv3_input=tb_conv3_in_i8_14x14x8.txt\n');
    fprintf(fid, 'conv3_weight=tb_conv3_w_i8_3x3x8x8.txt\n');
    fprintf(fid, 'conv3_output=tb_conv3_out_i32_12x12x8.txt\n');
    fprintf(fid, 'conv3_requant=tb_conv3_requant_i8_12x12x8.txt\n');
    fprintf(fid, 'conv3_pool=tb_conv3_pool_i8_6x6x8.txt\n');
    fprintf(fid, 'fc_input=tb_fc_in_i8_288.txt\n');
    fprintf(fid, 'fc_weight=tb_fc_w_i8_10x288.txt\n');
    fprintf(fid, 'fc_weight_interleaved=tb_fc_w_interleaved_i8_288x10.txt\n');
    fprintf(fid, 'fc_bias_eff=tb_fc_bias_eff_i32_10.txt\n');
    fprintf(fid, 'fc_output=tb_fc_out_i32_10.txt\n');
    fprintf(fid, 'predict_class=%d\n',                 R.predict_class);

    fprintf(fid, 'input_zero_point=%d\n',              R.zp.in);
    fprintf(fid, 'conv1_output_zero_point=%d\n',       R.zp.conv1_out);
    fprintf(fid, 'conv2_output_zero_point=%d\n',       R.zp.conv2_out);
    fprintf(fid, 'conv3_output_zero_point=%d\n',       R.zp.conv3_out);
    fprintf(fid, 'fc_input_zero_point=%d\n',           R.zp.fc_in);

    fprintf(fid, ['conv_rule=layer input keeps full upstream tensor values; ' ...
                  'current-layer conv MAC uses x_zp=0,w_zp=0,bias=0; ' ...
                  'eff_bias = bias - x_zp*sum(W) added in Quant stage; ' ...
                  'no standalone ReLU (subsumed by Quant clamp when out_zp=-128); ' ...
                  'FC has no requant (argmax on raw INT32 acc)\n']);

    fprintf(fid, 'conv1_input_shape=64x64x1\n');
    fprintf(fid, 'conv2_input_shape=31x31x4\n');
    fprintf(fid, 'conv3_input_shape=14x14x8\n');
    fprintf(fid, 'conv1_output_shape=62x62x4\n');
    fprintf(fid, 'conv2_output_shape=29x29x8\n');
    fprintf(fid, 'conv3_output_shape=12x12x8\n');
    fprintf(fid, 'fc_output_shape=10\n');

    fprintf(fid, 'conv1_output_range=[%d,%d]\n', min(R.conv1_mac(:)), max(R.conv1_mac(:)));
    fprintf(fid, 'conv2_output_range=[%d,%d]\n', min(R.conv2_mac(:)), max(R.conv2_mac(:)));
    fprintf(fid, 'conv3_output_range=[%d,%d]\n', min(R.conv3_mac(:)), max(R.conv3_mac(:)));
    fprintf(fid, 'fc_acc_range=[%d,%d]\n',       min(R.fc_acc),       max(R.fc_acc));

    fprintf('export_case: wrote case=%s -> %s (predict_class=%d)\n', ...
            case_name, case_dir, R.predict_class);
end
