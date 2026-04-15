function params = load_tflite_params_mat(mat_path)
% Load exported TFLite int8 parameters from .mat into a MATLAB struct array.
% Usage:
%   params = load_tflite_params_mat('models/v2.int8.params.mat');

if nargin < 1
    mat_path = 'models/v2.int8.params.mat';
end

S = load(mat_path);
n = double(S.num_params);

params = repmat(struct( ...
    'name', "", ...
    'tensor_index', int32(0), ...
    'dtype', "", ...
    'shape', [], ...
    'shape_signature', [], ...
    'quantized_dimension', int32(0), ...
    'values', [], ...
    'scales', [], ...
    'zero_points', []), n, 1);

for i = 1:n
    params(i).name = string(S.names{i});
    params(i).tensor_index = S.tensor_indices(i);
    params(i).dtype = string(S.dtypes{i});
    params(i).shape = S.shapes{i};
    params(i).shape_signature = S.shape_signatures{i};
    params(i).quantized_dimension = S.quantized_dimensions(i);
    params(i).values = S.values{i};
    params(i).scales = S.scales{i};
    params(i).zero_points = S.zero_points{i};
end

end
