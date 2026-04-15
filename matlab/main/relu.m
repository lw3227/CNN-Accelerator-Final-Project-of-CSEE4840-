function out = relu(x, zp)
    if nargin < 2 || isempty(zp)
        zp = int8(-128);
    end
    out = max(x, zp);
end
