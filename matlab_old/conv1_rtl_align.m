clc;

if ~exist('sample_tag', 'var')
    sample_tag = 'scissors';
end
if ~exist('write_legacy_conv1_alias', 'var')
    write_legacy_conv1_alias = true;
end

fprintf('INFO: conv1_rtl_align exports Conv1 txt for sample %s\n', sample_tag);
fprintf('INFO: for paper/rock/scissors + L2/L3 exports, run export_cnn_rtl_txt_dataset instead.\n');

export_cnn_rtl_txt_dataset( ...
    'sample_tags', {sample_tag}, ...
    'write_legacy_conv1_alias', write_legacy_conv1_alias, ...
    'legacy_sample_tag', sample_tag);
