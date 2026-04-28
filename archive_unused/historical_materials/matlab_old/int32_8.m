% int32 -> int8 requant 示例（单值）
acc32   = int32(12345);     % 卷积累加结果
s_in    = 0.0085711749;     % 输入激活 scale
s_w     = 0.0040910519;     % 某输出通道权重 scale
s_out   = 0.0085711749;     % 输出激活 scale
zp_out  = int32(-128);      % 输出 zero_point

M = (s_in * s_w) / s_out;   % 实数重标定系数

q_out_i32 = int32(round(double(acc32) * M)) + zp_out;
q_out_i32_clip = max(int32(-128), min(int32(127), q_out_i32));
q_out_i8 = int8(q_out_i32_clip);

fprintf('M = %.10f\n', M);
fprintf('acc32 = %d\n', acc32);
fprintf('q_out_i32(before clip) = %d\n', q_out_i32);
fprintf('q_out_i32(after clip)  = %d\n', q_out_i32_clip);
fprintf('q_out_i8 = %d\n', q_out_i8);
