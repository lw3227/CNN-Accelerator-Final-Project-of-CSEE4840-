function [M, qm, shift] = tflite_quantize_multiplier(S_in, S_w, S_out)
%TFLITE_QUANTIZE_MULTIPLIER  Compute per-channel real multiplier and
%TFLite-style (quantized_multiplier, shift) for int32->int8 requant.
%
%   M[c]  = (S_in * S_w[c]) / S_out[c]
%   M ~= (qm / 2^31) * 2^shift
%
% Inputs:
%   S_in  : single/double scalar
%   S_w   : single/double scalar or vector (per-channel)
%   S_out : single/double scalar or vector (per-channel)
%
% Outputs:
%   M     : double vector of real multipliers
%   qm    : int32 vector (Q0.31 quantized multiplier, non-negative)
%   shift : int32 vector (can be negative/positive)
%
% Notes:
%   - This matches the common TFLite meaning used in MultiplyByQuantizedMultiplier:
%       total_shift = 31 - shift
%       y = (x * qm + round) >> total_shift
%   - For typical conv/FC requant, M is in (0,1), shift usually <= 0,
%     but we support general M >= 0.

    % Make everything double for stable computation
    S_in  = double(S_in);
    S_w   = double(S_w);
    S_out = double(S_out);

    % Broadcast scalars to vector length
    n = max([numel(S_w), numel(S_out), 1]);
    if isscalar(S_w),   S_w   = repmat(S_w,   1, n); end
    if isscalar(S_out), S_out = repmat(S_out, 1, n); end

    % Real multipliers
    M = (S_in .* S_w) ./ S_out;

    qm    = zeros(1, n, 'int32');
    shift = zeros(1, n, 'int32');

    for i = 1:n
        r = M(i);

        if r == 0 || ~isfinite(r) || r < 0
            qm(i) = int32(0);
            shift(i) = int32(0);
            continue;
        end

        % log2 gives: r = significand * 2^exp, significand in [0.5, 1)
        [significand, exp] = log2(r);

        % Convert significand to Q31
        q = round(significand * 2^31);

        % Edge case: rounding to exactly 2^31
        if q == 2^31
            q = q / 2;
            exp = exp + 1;
        end

        % Clamp into [0, 2^31-1] (TFLite expects non-negative here)
        if q < 0, q = 0; end
        if q > (2^31 - 1), q = (2^31 - 1); end

        qm(i) = int32(q);
        shift(i) =  int32(exp);
    end
end