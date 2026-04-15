% --- helper: int8 zero padding for HxWxC ---
function y = pad_int8_hw(x, p)
    % x: int8 [H,W,C], p: integer padding
    y = zeros(size(x,1)+2*p, size(x,2)+2*p, size(x,3), 'like', x);
    y(p+1:p+size(x,1), p+1:p+size(x,2), :) = x;
end