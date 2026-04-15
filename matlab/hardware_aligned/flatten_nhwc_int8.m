function y = flatten_nhwc_int8(x)
%FLATTEN_NHWC_INT8 Flatten HxWxC int8 tensor with NHWC logical order.
%   x: int8 [H, W, C]
%   y: int8 [1, H*W*C]
%
% TFLite Flatten on [1,H,W,C] follows NHWC contiguous order:
%   h major, then w, and c is the fastest-changing index.

    assert(isa(x, 'int8'), 'x must be int8');
    assert(ndims(x) == 3, 'x must be HxWxC');

    [H, W, C] = size(x);
    y = zeros(1, H * W * C, 'int8');

    k = 1;
    for h = 1:H
        for w = 1:W
            for c = 1:C
                y(k) = x(h, w, c);
                k = k + 1;
            end
        end
    end
end
