% RUN_ALL  Multi-case golden TXT generator.
%
%   Loads the model once, then for every PNG matching `image_glob` runs:
%     export_case  -> hardware_aligned/debug/txt_cases/<case>/
%
%   By default this folder is code-only. It reads the model from
%   <repo>/models/v1.int8.params.mat and images from <repo>/matlab/digit_*.png.

clc; clear; close all;

hw_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(hw_dir);
repo_root = fileparts(matlab_dir);
addpath(hw_dir);

% ----------------------------- USER CONFIG -------------------------------
params_candidates = {
    fullfile(repo_root, 'models', 'v1.int8.params.mat')
    fullfile(matlab_dir, 'main', 'v1.int8.params.mat')
    fullfile(hw_dir, 'v1.int8.params.mat')
};

% Glob all `digit_<n>_*.png` images in matlab/. Adjust as you add cases.
image_glob       = fullfile(matlab_dir, 'digit_*.png');
out_root         = fullfile(hw_dir, 'debug', 'txt_cases');
sram_out_root    = fullfile(hw_dir, 'debug', 'sram_preload');
% -------------------------------------------------------------------------

params_path = "";
for k = 1:numel(params_candidates)
    if exist(params_candidates{k}, 'file')
        params_path = string(params_candidates{k});
        break;
    end
end

if ~exist(params_path, 'file')
    error('run_all: params .mat not found. Tried repo models/, matlab/main/, and hardware_aligned/.');
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

    R = export_case(img_path, P, case_name, out_root);
    gen_sram_preload(case_name, R, P, sram_out_root);
end

fprintf('run_all: done.\n');


function s = sanitize_case_name(s)
% Make a filesystem-safe case tag from the image basename.
    s = lower(s);
    s = regexprep(s, '[^a-z0-9_]+', '_');
    s = regexprep(s, '^_+|_+$', '');
end
