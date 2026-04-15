function [out_i32, out_i8] = fully_connected_int8(x_int8, W_oi, bias_i32, x_zp, w_zp, qm, shift, z_out)
%FULLY_CONNECTED_INT8 INT8 fully-connected with optional int8 requant.
%   Inputs:
%     x_int8   : int8 [1,N] or [N,1]
%     W_oi     : int8 [O,N] (rows are output channels)
%     bias_i32 : int32 [O] (or [] -> treated as zero)
%     x_zp     : int32 scalar input zero-point
%     w_zp     : int32 scalar or int32 [O] weight zero-point(s)
%     qm       : optional int32 scalar or [O], quantized multiplier(s)
%     shift    : optional int32 scalar or [O], shift(s)
%     z_out    : optional int32 scalar output zero-point
%
%   Outputs:
%     out_i32  : int32 [O,1] raw accumulator output
%     out_i8   : int8  [O,1] requantized output (empty if qm/shift/z_out omitted)

    if nargin < 4 || isempty(x_zp), x_zp = int32(0); end
    if nargin < 5 || isempty(w_zp), w_zp = int32(0); end

    assert(isa(x_int8, 'int8'), 'x_int8 must be int8');
    assert(isa(W_oi, 'int8'), 'W_oi must be int8');

    x = x_int8(:).';  % 1xN
    [O, N] = size(W_oi);
    assert(numel(x) == N, 'Input length (%d) must match W second dim (%d)', numel(x), N);

    if nargin < 3 || isempty(bias_i32)
        bias_i32 = zeros(O, 1, 'int32');
    else
        bias_i32 = int32(bias_i32(:));
        assert(numel(bias_i32) == O, 'bias length (%d) must match O (%d)', numel(bias_i32), O);
    end

    w_zp_v = int32(w_zp(:));
    if numel(w_zp_v) == 1
        w_zp_v = repmat(w_zp_v, O, 1);
    end
    assert(numel(w_zp_v) == O, 'w_zp must be scalar or length O');

    x_i32 = int32(x) - int32(x_zp);
    out_i32 = zeros(O, 1, 'int32');

    for o = 1:O
        w_i32 = int32(W_oi(o, :)) - int32(w_zp_v(o));
        acc64 = int64(bias_i32(o)) + sum(int64(x_i32) .* int64(w_i32), 2);
        out_i32(o) = int32(acc64);
    end

    out_i8 = [];
    if nargin >= 8 && ~isempty(qm) && ~isempty(shift) && ~isempty(z_out)
        out_i8 = requant_vec_int32_to_int8(out_i32, qm, shift, int32(z_out));
    end
end

function y = requant_vec_int32_to_int8(x_i32, qm, shift, z_out)
    O = numel(x_i32);
    qm = int64(qm(:));
    shift = int64(shift(:));
    z_out = int64(z_out);

    if numel(qm) == 1, qm = repmat(qm, O, 1); end
    if numel(shift) == 1, shift = repmat(shift, O, 1); end
    assert(numel(qm) == O, 'qm must be scalar or length O');
    assert(numel(shift) == O, 'shift must be scalar or length O');

    y = zeros(O, 1, 'int8');
    for i = 1:O
        prod = int64(x_i32(i)) * qm(i);
        total_shift = 31 - shift(i);

        if total_shift > 0
            round_term = bitshift(int64(1), total_shift - 1);
            prod_adj = prod + round_term - int64(prod < 0);
            scaled = bitshift(prod_adj, -total_shift);
        elseif total_shift == 0
            scaled = prod;
        else
            scaled = bitshift(prod, -total_shift);
        end

        scaled = scaled + z_out;
        if scaled > 127, scaled = 127; end
        if scaled < -128, scaled = -128; end
        y(i) = int8(scaled);
    end
end
