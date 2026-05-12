function out = maxpool2x2_int8(x)
% MAXPOOL2X2_INT8  Pure 2x2 stride-2 max pooling (no ReLU fold).
%
%   out = maxpool2x2_int8(x)
%
%   x   : int8 [H, W, C]
%   out : int8 [floor(H/2), floor(W/2), C]
%
%   Hardware alignment:
%     * The accelerator's pool stage is plain max over a 2x2 window.
%     * ReLU is implicit in the upstream Quantization stage when out_zp = -128
%       (clamp(.., -128, 127) == max(.., zp_neg)). We do NOT clamp again here.
%
%   Use this in the hardware-aligned forward pass instead of
%   `relu_maxpool2x2_int8` (which fuses an explicit ReLU into the window).

    assert(isa(x, 'int8'), 'maxpool2x2_int8: input must be int8');
    [H, W, C] = size(x);
    Ho = floor(H / 2);
    Wo = floor(W / 2);
    out = zeros(Ho, Wo, C, 'int8');

    for c = 1:C
        for r = 1:Ho
            for cc = 1:Wo
                window = x(2*r-1:2*r, 2*cc-1:2*cc, c);
                out(r, cc, c) = max(window(:));
            end
        end
    end
end
