% RUN_ALL  Multi-case golden + SRAM preload generator.
%
%   Loads the model once, then for every PNG matching `image_glob` runs:
%     export_case  -> debug/txt_cases/<case>/
%     gen_sram_preload -> debug/sram_preload/<case>/
%
%   Edit `params_path` and `image_glob` below to point at the model and
%   the digit sample images you want to process.

clc; clear; close all;

matlab_dir = fileparts(mfilename('fullpath'));

% ----------------------------- USER CONFIG -------------------------------
% .mat lives next to this script for now (was originally planned at <repo>/models/).
params_path = fullfile(matlab_dir, 'v1.int8.params.mat');

% Glob all `digit_<n>_*.png` images in matlab/main/. Adjust as you add cases.
image_glob  = fullfile(matlab_dir, 'digit_*.png');
% -------------------------------------------------------------------------

if ~exist(params_path, 'file')
    error('run_all: params .mat not found: %s', params_path);
end

P = load_params(params_path);
imgs = dir(image_glob);
if isempty(imgs)
    error('run_all: no images match %s', image_glob);
end

fprintf('Loaded params from %s\n', params_path);
fprintf('Processing %d image(s) matching %s\n', numel(imgs), image_glob);

for i = 1:numel(imgs)
    img_path = fullfile(imgs(i).folder, imgs(i).name);
    [~, base, ~] = fileparts(imgs(i).name);
    case_name = sanitize_case_name(base);

    R = export_case(img_path, P, case_name);
    gen_sram_preload(case_name, R, P);
end

fprintf('run_all: done.\n');


function s = sanitize_case_name(s)
% Make a filesystem-safe case tag from the image basename.
    s = lower(s);
    s = regexprep(s, '[^a-z0-9_]+', '_');
    s = regexprep(s, '^_+|_+$', '');
end
