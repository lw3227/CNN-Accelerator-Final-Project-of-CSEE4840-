c=1;
acc_min = min(conv1_img(:,:,c),[],'all');
acc_max = max(conv1_img(:,:,c),[],'all');
disp([acc_min acc_max])

% 看 scaled（不加 z_out 的）
x = int64(conv1_img(:,:,c));
qmc = int64(qm1(c));
shc = int64(shift1(c));
total_shift = 31 - shc;
round_term = bitshift(int64(1), total_shift-1);
scaled0 = bitshift(x.*qmc + round_term, -total_shift);

disp([min(scaled0,[],'all') max(scaled0,[],'all')])