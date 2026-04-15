function out = relu_maxpool2x2_int8(in, zp)
% in : H x W x C (int8)
% out: floor(H/2) x floor(W/2) x C

    [H, W, C] = size(in);

    outH = floor(H/2);
    outW = floor(W/2);

    out = zeros(outH, outW, C, 'int8');

    for c = 1:C
        for oh = 1:outH
            ih = 2*oh - 1;
            for ow = 1:outW
                iw = 2*ow - 1;

                a = in(ih,   iw,   c);
                b = in(ih,   iw+1, c);
                d = in(ih+1, iw,   c);
                e = in(ih+1, iw+1, c);

                % ReLU（量化域阈值=zp）
                a = max(a, zp);
                b = max(b, zp);
                d = max(d, zp);
                e = max(e, zp);

                out(oh,ow,c) = max(max(a,b), max(d,e));
            end
        end
    end
end
