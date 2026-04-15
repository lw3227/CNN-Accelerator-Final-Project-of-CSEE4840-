function R = hw_forward(img_int8, P)
% HW_FORWARD  Hardware-aligned forward pass for one 64x64x1 image.
%
%   R = hw_forward(img_int8, P)
%
%   img_int8 : int8 [64, 64] or [64, 64, 1] -- already quantized input
%   P        : params struct (see load_params helper below)
%
%   Returns struct R with all intermediates needed by the testbench.
%
%   ---------------------------------------------------------------
%   Hardware conventions (vs the TFLite reference rps_conv2.m):
%
%     1. **Conv MAC stage**: x_zp = 0, w_zp = 0, bias = 0.
%        Output is raw INT32 MAC (sum(x_q * w_q)) with no zp folding.
%        These goldens go to tb_convN_out_i32_*.txt.
%
%     2. **Quant stage**: receives eff_bias (NOT raw bias):
%           eff_bias = b - x_zp * sum(W_per_oc)
%        Then: y = clamp(((MAC + eff_bias) * M >> sh) + zp_out, -128, 127)
%        These eff_bias / M / shift goldens go to tb_convN_quant_*_C.txt.
%
%     3. **No standalone ReLU**. With out_zp = -128 the Quant clamp itself
%        is the ReLU; we do NOT call relu() before pooling.
%
%     4. **Pool**: pure 2x2 max, no ReLU fold (use maxpool2x2_int8.m).
%
%     5. **FC**: NO requantization. Raw INT32 accumulator with eff_bias is
%        what the hardware feeds straight into argmax. Golden output is
%        tb_fc_out_i32_<OUT_CHANNELS>.txt; predicted class = argmax(fc_acc).
%   ---------------------------------------------------------------
%
%   Returned fields (every tensor matches the format the TB will read):
%     R.input_int8                       int8 [64,64,1]
%     R.conv1_w / R.conv2_w / R.conv3_w  int8 weight tensors (OIHW logical)
%     R.conv1_mac / R.conv2_mac / R.conv3_mac
%                                        int32 raw MAC outputs (no bias, no zp)
%     R.conv1_eff_bias / .._M / .._sh    int32 quant params per channel
%     R.conv1_requant / R.conv2_requant / R.conv3_requant  int8 quantized
%     R.pool1 / R.pool2 / R.pool3        int8 maxpool outputs
%     R.fc_in                            int8 [288] (= flatten of pool3)
%     R.fc_w                             int8 [10, 288]
%     R.fc_eff_bias                      int32 [10]
%     R.fc_acc                           int32 [10]   <-- HW final, argmax-ready
%     R.predict_class                    0..9
%     R.zp                               struct of zero points used

    if ndims(img_int8) == 2
        img_int8 = reshape(img_int8, size(img_int8,1), size(img_int8,2), 1);
    end
    assert(isa(img_int8, 'int8') && isequal(size(img_int8), [64 64 1]), ...
           'hw_forward: img must be int8 [64,64] or [64,64,1]');

    R.input_int8 = img_int8;
    R.conv1_w = P.W1;     % [Cout, Cin, H, W] logical (OIHW)
    R.conv2_w = P.W2;
    R.conv3_w = P.W3;
    R.fc_w    = P.W_fc;   % [Cout, K]

    R.zp = struct( ...
        'in',         P.in_zp, ...
        'conv1_out',  P.z_conv1_out, ...
        'conv2_out',  P.z_conv2_out, ...
        'conv3_out',  P.z_conv3_out, ...
        'fc_in',      P.z_fc_in);

    % --- Layer 1 -----------------------------------------------------------
    R.conv1_mac      = conv2d_mac(img_int8, P.W1);                       % int32 [62,62,4]
    R.conv1_eff_bias = compute_eff_bias(P.b1, P.W1, P.in_zp);            % int32 [4]
    R.conv1_M        = int32(P.qm1);
    R.conv1_sh       = int32(P.shift1);
    R.conv1_requant  = quant_int32_to_int8(R.conv1_mac, R.conv1_eff_bias, ...
                                           R.conv1_M, R.conv1_sh, P.z_conv1_out);
    R.pool1          = maxpool2x2_int8(R.conv1_requant);                 % int8 [31,31,4]

    % --- Layer 2 -----------------------------------------------------------
    R.conv2_mac      = conv2d_mac(R.pool1, P.W2);                        % int32 [29,29,8]
    R.conv2_eff_bias = compute_eff_bias(P.b2, P.W2, P.z_conv1_out);      % int32 [8]
    R.conv2_M        = int32(P.qm2);
    R.conv2_sh       = int32(P.shift2);
    R.conv2_requant  = quant_int32_to_int8(R.conv2_mac, R.conv2_eff_bias, ...
                                           R.conv2_M, R.conv2_sh, P.z_conv2_out);
    R.pool2          = maxpool2x2_int8(R.conv2_requant);                 % int8 [14,14,8]

    % --- Layer 3 -----------------------------------------------------------
    R.conv3_mac      = conv2d_mac(R.pool2, P.W3);                        % int32 [12,12,8]
    R.conv3_eff_bias = compute_eff_bias(P.b3, P.W3, P.z_conv2_out);      % int32 [8]
    R.conv3_M        = int32(P.qm3);
    R.conv3_sh       = int32(P.shift3);
    R.conv3_requant  = quant_int32_to_int8(R.conv3_mac, R.conv3_eff_bias, ...
                                           R.conv3_M, R.conv3_sh, P.z_conv3_out);
    R.pool3          = maxpool2x2_int8(R.conv3_requant);                 % int8 [6,6,8]

    % --- Flatten + FC ------------------------------------------------------
    R.fc_in = flatten_nhwc_int8(R.pool3);   % int8 [288]
    K       = numel(R.fc_in);
    Cout    = size(P.W_fc, 1);
    assert(size(P.W_fc, 2) == K, 'FC weight K (%d) must match flatten (%d)', size(P.W_fc,2), K);
    assert(numel(P.b_fc)   == Cout, 'FC bias must have length %d', Cout);

    R.fc_eff_bias = compute_fc_eff_bias(P.b_fc, P.W_fc, P.z_fc_in);   % int32 [Cout]

    % FC accumulator (hardware path): acc[oc] = eff_bias[oc] + sum(x * w[oc,:])
    % where x is the raw INT8 stored in SRAM_B (zp already baked in).
    x_i32 = int32(R.fc_in);
    acc   = zeros(Cout, 1, 'int32');
    for oc = 1:Cout
        w_i32 = int32(P.W_fc(oc, :)).';
        % Use int64 accumulation internally to avoid intermediate overflow,
        % then saturate to int32. RTL accumulator is 32 bits; saturation here
        % matches what the hardware would silently wrap, so flag any case
        % where it actually exceeds 32-bit range (would indicate a model bug).
        s64 = int64(R.fc_eff_bias(oc)) + sum(int64(x_i32) .* int64(w_i32));
        if s64 > intmax('int32') || s64 < intmin('int32')
            warning('hw_forward:fc_overflow', ...
                    'FC oc=%d accumulator %d out of int32; saturating', oc, s64);
        end
        acc(oc) = int32(max(min(s64, int64(intmax('int32'))), int64(intmin('int32'))));
    end
    R.fc_acc = acc;

    % Argmax: strict-greater so ties go to the lower index (matches RTL ST_ARGMAX).
    best_idx = int32(0);   % 0-based class id (matches predict_class[3:0])
    best_val = R.fc_acc(1);
    for oc = 2:Cout
        if R.fc_acc(oc) > best_val
            best_val = R.fc_acc(oc);
            best_idx = int32(oc - 1);
        end
    end
    R.predict_class = best_idx;
end


% =========================================================================
%  Helpers
% =========================================================================

function mac = conv2d_mac(x_int8, W_oihw)
% Raw MAC convolution: x_zp = 0, w_zp = 0, bias = 0; INT32 output.
% W_oihw: int8 [Cout, Cin, H, W] (OIHW).
% Stride 1, valid padding.

    [Cout, Cin, kH, kW] = size_oihw(W_oihw);
    [Hi, Wi, Ci] = size3(x_int8);
    assert(Cin == Ci, 'conv2d_mac: weight Cin (%d) != input C (%d)', Cin, Ci);

    Ho = Hi - kH + 1;
    Wo = Wi - kW + 1;
    mac = zeros(Ho, Wo, Cout, 'int32');

    x32 = int32(x_int8);
    W32 = int32(W_oihw);

    for oc = 1:Cout
        for r = 1:Ho
            for c = 1:Wo
                s = int64(0);
                for ic = 1:Cin
                    patch = x32(r:r+kH-1, c:c+kW-1, ic);
                    ker   = squeeze(W32(oc, ic, :, :));   % [kH, kW]
                    s     = s + sum(int64(patch(:)) .* int64(ker(:)));
                end
                if s > intmax('int32') || s < intmin('int32')
                    warning('hw_forward:mac_overflow', ...
                            'MAC overflow at oc=%d r=%d c=%d : %d', oc, r, c, s);
                end
                mac(r, c, oc) = int32(s);
            end
        end
    end
end


function eb = compute_eff_bias(bias, W_oihw, x_zp)
% eff_bias[oc] = bias[oc] - x_zp * sum(W[oc, :, :, :])
% W_oihw: int8 [Cout, Cin, H, W]
    Cout = size(W_oihw, 1);
    eb = zeros(Cout, 1, 'int32');
    xz = int64(x_zp);
    for oc = 1:Cout
        sw = sum(int64(W_oihw(oc, :, :, :)), 'all');
        eb(oc) = int32(int64(bias(oc)) - xz * sw);
    end
end


function eb = compute_fc_eff_bias(bias, W_fc, x_zp)
% eff_bias[oc] = bias[oc] - x_zp * sum(W_fc[oc, :])
% W_fc: int8 [Cout, K]
    Cout = size(W_fc, 1);
    eb = zeros(Cout, 1, 'int32');
    xz = int64(x_zp);
    for oc = 1:Cout
        sw = sum(int64(W_fc(oc, :)));
        eb(oc) = int32(int64(bias(oc)) - xz * sw);
    end
end


function out = quant_int32_to_int8(mac_i32, eff_bias_i32, M_i32, sh_i32, zp_out)
% TFLite single-rounding requant, with eff_bias added pre-multiply:
%   acc = mac + eff_bias
%   y   = (acc * M) round-shifted right by (31 - sh)
%   out = clamp(y + zp_out, -128, 127)
%
% mac_i32:      int32 [H, W, C]
% eff_bias_i32: int32 [C]
% M_i32:        int32 [C]
% sh_i32:       int32 [C]
% zp_out:       int32 scalar
    [H, W, C] = size3(mac_i32);
    out = zeros(H, W, C, 'int8');
    for c = 1:C
        acc64 = int64(mac_i32(:, :, c)) + int64(eff_bias_i32(c));
        prod  = acc64 * int64(M_i32(c));
        ts    = 31 - int64(sh_i32(c));
        if ts > 0
            round_term = bitshift(int64(1), ts - 1);
            prod_adj   = prod + round_term - int64(prod < 0);
            scaled     = bitshift(prod_adj, -ts);
        elseif ts == 0
            scaled = prod;
        else
            scaled = bitshift(prod, -ts);
        end
        scaled = scaled + int64(zp_out);
        scaled(scaled >  127) =  127;
        scaled(scaled < -128) = -128;
        out(:, :, c) = int8(scaled);
    end
end


function [Cout, Cin, kH, kW] = size_oihw(W)
    sz = size(W);
    Cout = sz(1); Cin = sz(2); kH = sz(3); kW = sz(4);
end


function [H, W, C] = size3(x)
    if ismatrix(x)
        x = reshape(x, size(x,1), size(x,2), 1);
    end
    sz = size(x);
    H = sz(1); W = sz(2);
    if numel(sz) >= 3, C = sz(3); else, C = 1; end
end
