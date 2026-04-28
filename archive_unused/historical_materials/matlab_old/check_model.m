clc;
clear;

S = load('v2.int8.params.mat');

% whos S;
% fieldnames(S);
%% extract_scales_from_S.m
% 用法：
%   load('xxx.mat');   % 得到 S
%   % 直接运行本脚本
%
% 输出：
%   T           table: index/name/dtype/shape/qdim/scale_len/is_per_channel
%   scales_map  containers.Map(name -> scales)
%   hit         struct: 找到的某个关键字的第一条

% ====== basic checks ======
assert(isstruct(S), "S must be a struct loaded from .mat");

n = numel(S.names);
assert(numel(S.scales) == n, "S.scales length mismatch with S.names");

% ====== build summary table ======
idx = (1:n).';
name = string(S.names(:));
dtype = string(S.dtypes(:));

shape_str = strings(n,1);
qdim = zeros(n,1,'int32');
scale_len = zeros(n,1);
is_per_channel = false(n,1);

for i = 1:n
    sh = S.shapes{i};
    if isempty(sh)
        shape_str(i) = "[]";
    else
        shape_str(i) = "[" + strjoin(string(sh(:).'), " ") + "]";
    end

    qd = S.quantized_dimensions(i);
    if isempty(qd)
        qdim(i) = int32(-1);
    else
        qdim(i) = int32(qd);
    end

    sc = S.scales{i};
    if isempty(sc)
        scale_len(i) = 0;
        is_per_channel(i) = false;
    else
        scale_len(i) = numel(sc);
        is_per_channel(i) = (numel(sc) > 1);
    end
end

T = table(idx, name, dtype, shape_str, qdim, scale_len, is_per_channel);

% ====== build map: name -> scales ======
scales_map = containers.Map('KeyType','char','ValueType','any');
for i = 1:n
    key = char(name(i));
    scales_map(key) = S.scales{i};
end

% ====== quick filter example ======
keyword = "conv2d";  % 你可以改成 "dense" / "BiasAdd" / "Conv2D" 等
mask = contains(name, keyword);
disp("=== Summary (first 20 rows) ===");
disp(T(1:min(20,height(T)), :));

disp("=== Hits for keyword: " + keyword + " ===");
disp(T(mask, :));

% ====== pick first hit info ======
hit = struct();
hit.keyword = keyword;
hit.first_index = find(mask, 1, 'first');
if isempty(hit.first_index)
    disp("No hit found.");
else
    i = hit.first_index;
    hit.name = S.names{i};
    hit.scale = S.scales{i};
    hit.zero_point = S.zero_points{i};
    hit.dtype = S.dtypes{i};
    hit.shape = S.shapes{i};
    hit.qdim = S.quantized_dimensions(i);

    disp("=== First hit detail ===");
    disp(hit);
end