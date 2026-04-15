function dump_txt(filepath, tensor, dtype, layout)
% DUMP_TXT  Write a tensor as one decimal int per line (GOLDEN_FORMAT.md).
%
%   dump_txt(filepath, tensor, dtype, layout)
%
%   filepath : output path (will overwrite)
%   tensor   : numeric array (any size)
%   dtype    : 'i8' or 'i32' (validates element range)
%   layout   : (optional) traversal hint:
%       'hwc'   - 3D activation [H, W, C], outer→inner = H, W, C (default for ndims=3)
%       'oihw'  - 4D weight [Cout, Cin, H, W] (default for ndims=4)
%       'ohw'   - 3D weight  [Cout, H, W]    (e.g. conv1 with Cin=1, after squeeze)
%       'flat'  - just iterate column-major (default for vectors / matrices)
%       'fc_oik'- 2D FC weight [Cout, K], outer=Cout, inner=K (default for 2D)
%       'fc_int_kxo' - SRAM-interleaved FC weight: outer=K, inner=Cout
%                      (writes Cout bytes per K position, LSB=ch0)
%
%   The tensor argument is expected to already be in the *logical* layout
%   listed above (e.g. an OIHW tensor must be passed as a [Cout, Cin, H, W]
%   numeric array). The function reorders elements into the file's
%   slow→fast order before writing.
%
%   GOLDEN_FORMAT.md compliance:
%     * one signed decimal integer per line, LF terminator
%     * no header, no comments, no blank lines
%     * file ends with a trailing newline
%     * line count == numel(tensor)

    if nargin < 4 || isempty(layout)
        if ndims(tensor) == 4
            layout = 'oihw';
        elseif ndims(tensor) == 3
            layout = 'hwc';
        elseif ismatrix(tensor) && ~isvector(tensor)
            layout = 'fc_oik';
        else
            layout = 'flat';
        end
    end

    switch lower(dtype)
        case 'i8'
            lo = -128; hi = 127;
        case 'i32'
            lo = -2147483648; hi = 2147483647;
        otherwise
            error('dump_txt:dtype', 'dtype must be ''i8'' or ''i32'', got "%s"', dtype);
    end

    % Reorder into the file emission sequence.
    switch lower(layout)
        case 'hwc'
            assert(ndims(tensor) <= 3, 'hwc layout expects up to 3D tensor');
            % MATLAB stores [H, W, C] in column-major (H fastest, then W, then C).
            % File order is H outer, W middle, C fastest -> permute then linearize.
            t = permute(tensor, [3, 2, 1]);   % now [C, W, H], column-major == file order
            seq = t(:);

        case 'oihw'
            assert(ndims(tensor) == 4, 'oihw layout expects 4D tensor');
            % File order: Cout outer, Cin, H, W fastest.
            t = permute(tensor, [4, 3, 2, 1]); % [W, H, Cin, Cout] in column-major
            seq = t(:);

        case 'ohw'
            assert(ndims(tensor) == 3, 'ohw layout expects 3D tensor');
            % File order: Cout outer, H, W fastest.
            t = permute(tensor, [3, 2, 1]);   % [W, H, Cout] in column-major
            seq = t(:);

        case 'fc_oik'
            assert(ismatrix(tensor), 'fc_oik layout expects 2D [Cout, K] tensor');
            % File order: Cout outer, K fastest.
            t = tensor.';   % [K, Cout]; column-major == [Cout][K] with K fast
            seq = t(:);

        case 'fc_int_kxo'
            assert(ismatrix(tensor), 'fc_int_kxo layout expects 2D [Cout, K] tensor');
            % File order: K outer, Cout fastest. SRAM_FCW has one 80-bit slot
            % per K position; bytes within slot are ch0 (LSB) .. ch9 (MSB).
            % Writing column-major over the original [Cout, K] = ch0,ch1,..,ch9
            % per K position is exactly what we want.
            seq = tensor(:);

        case 'flat'
            seq = tensor(:);

        otherwise
            error('dump_txt:layout', 'unknown layout "%s"', layout);
    end

    % Range check (after cast to a safe wide type).
    seq_i64 = int64(seq);
    if any(seq_i64 < lo) || any(seq_i64 > hi)
        bad_idx = find(seq_i64 < lo | seq_i64 > hi, 1, 'first');
        error('dump_txt:range', ...
              'value %d at element %d out of %s range [%d, %d] (file %s)', ...
              seq_i64(bad_idx), bad_idx, dtype, lo, hi, filepath);
    end

    % Make sure parent directory exists.
    parent = fileparts(filepath);
    if ~isempty(parent) && ~exist(parent, 'dir')
        mkdir(parent);
    end

    % Write: one decimal int per line, LF, trailing newline.
    fid = fopen(filepath, 'w');
    if fid < 0
        error('dump_txt:io', 'cannot open %s for write', filepath);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%d\n', seq_i64);
end
