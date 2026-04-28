function out_int8 = requant_int32_to_int8(conv1_img, qm, shift, z_out)
% conv1_img : H x W x C (int32)
% qm        : scalar or 1 x C (int32)
% shift     : scalar or 1 x C (int32)
% z_out     : scalar int32 (output zero point)
%
% output    : H x W x C (int8)

    [H, W, C] = size(conv1_img);
    qm = int64(qm(:).');
    shift = int64(shift(:).');
    z_out = int64(z_out);

    if numel(qm) == 1
        qm = repmat(qm, 1, C);
    end
    if numel(shift) == 1
        shift = repmat(shift, 1, C);
    end
    assert(numel(qm) == C, "qm length (%d) must be 1 or C (%d)", numel(qm), C);
    assert(numel(shift) == C, "shift length (%d) must be 1 or C (%d)", numel(shift), C);

    out_int8 = zeros(H, W, C, 'int8');

    for c = 1:C
        x = int64(conv1_img(:,:,c));      % promote to int64
        qmc = qm(c);
        shc = shift(c);

        % === TFLite single-rounding logic ===
        total_shift = 31 - shc;
        prod = x .* qmc;

        if total_shift > 0
            % Signed rounding before arithmetic right shift.
            round_term = bitshift(int64(1), total_shift - 1);
            prod_adj = prod + round_term - int64(prod < 0);
            scaled = bitshift(prod_adj, -total_shift);
        elseif total_shift == 0
            scaled = prod;
        else
            % Equivalent to multiplying by 2^(-total_shift).
            scaled = bitshift(prod, -total_shift);
        end

        % add output zero point
        scaled = scaled + z_out;

        % clamp to int8 range
        % scaled(scaled > 127)  = 127;
        % scaled(scaled < -128) = -128;

        out_int8(:,:,c) = int8(scaled);
    end
end
