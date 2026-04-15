

function output = conv2D_int8(img, filters, bias, stride, padding, x_zp, w_zp)
% INT8 conv with INT32 accumulation (+ INT32 bias)
%
% img:     int8   [H, W] or [H, W, Cin]
% filters: int8   [f, f, Cout] (Cin=1 legacy)
%               or [f, f, Cin, Cout] (recommended)
% bias:    int32  [Cout] or [1,Cout] or [Cout,1] (can pass [] -> treated as 0)
% stride:  scalar
% padding: "same" or "valid"
% x_zp,w_zp: int32 zero points (usually 0; in your case all 0)

    if nargin < 6 || isempty(x_zp), x_zp = int32(0); end
    if nargin < 7 || isempty(w_zp), w_zp = int32(0); end

    % --- normalize img to HxWxCin ---
    if ismatrix(img)
        img = reshape(img, size(img,1), size(img,2), 1);
    end
    assert(isa(img,'int8'), "img must be int8");

    % --- normalize bias ---
    if nargin < 3 || isempty(bias)
        % create later after Cout known
        bias = [];
    else
        assert(isa(bias,'int32') || isa(bias,'int16') || isa(bias,'int64') || isa(bias,'double'), ...
            "bias should be int32 (or convertible)");
        bias = int32(bias(:)); % column
    end

    % --- filter dims ---
    f = size(filters,1);
    assert(size(filters,2) == f, "filters must be square fxf");
    assert(isa(filters,'int8'), "filters must be int8");

    Cin = size(img,3);

    if ndims(filters) == 3
        % [f,f,Cout], assumes Cin=1
        Cout = size(filters,3);
        assert(Cin == 1, "3D filters implies Cin=1, but img Cin=%d", Cin);
    elseif ndims(filters) == 4
        % [f,f,Cin,Cout]
        assert(size(filters,3) == Cin, "filters Cin (%d) != img Cin (%d)", size(filters,3), Cin);
        Cout = size(filters,4);
    else
        error("filters must be 3D or 4D");
    end

    if isempty(bias)
        bias = zeros(Cout,1,'int32');
    else
        assert(numel(bias) == Cout, "bias length (%d) must match Cout (%d)", numel(bias), Cout);
    end

    % --- padding ---
    if strcmp(padding,"same")
        p = (f - 1)/2;
        assert(mod(f,2)==1, "'same' padding here assumes odd f (e.g., 3,5,7)");
        img = pad_int8_hw(img, p); % int8 pad with zeros
    elseif strcmp(padding,"valid")
        % no pad
    else
        error("padding must be ""same"" or ""valid""");
    end

    H = size(img,1);
    W = size(img,2);

    outH = floor((H - f)/stride) + 1;
    outW = floor((W - f)/stride) + 1;
    assert(outH > 0 && outW > 0, "Output size is non-positive; check f/stride/padding.");

    output = zeros(outH, outW, Cout, 'int32');

    % fast path if zero points are both 0
    zp_is_zero = (x_zp == 0) && (w_zp == 0);

    for oc = 1:Cout
        for row = 1:stride:(H - (f-1))
            out_r = (row-1)/stride + 1;
            for col = 1:stride:(W - (f-1))
                out_c = (col-1)/stride + 1;

                acc = bias(oc);

                for ic = 1:Cin
                    local = img(row:row+f-1, col:col+f-1, ic); % int8
                    if ndims(filters) == 3
                        ker = filters(:,:,oc);         % int8
                    else
                        ker = filters(:,:,ic,oc);      % int8
                    end

                    if zp_is_zero
                        acc = acc + sum(int32(local) .* int32(ker), "all");
                    else
                        xv = int32(local) - x_zp;
                        wv = int32(ker)   - w_zp;
                        acc = acc + sum(xv .* wv, "all");
                    end
                end

                output(out_r, out_c, oc) = acc;
            end
        end
    end
end

