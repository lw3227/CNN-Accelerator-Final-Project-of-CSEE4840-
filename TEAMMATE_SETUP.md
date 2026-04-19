# Teammate Setup

## Access the folder

```bash
echo "umask 002" >> ~/.bashrc && source ~/.bashrc   # 一次性
cd /homes/user/stud/fall25/lw3227/CNN_ACC
```

需要你在 `ee4321-all` 组里，`id | grep ee4321-all` 验一下。

## Open Quartus

```bash
# 一次性加到 PATH（~/.bashrc）
echo 'export PATH=/tools/intel/intelFPGA/21.1/quartus/bin:$PATH' >> ~/.bashrc && source ~/.bashrc

cd /homes/user/stud/fall25/lw3227/CNN_ACC
quartus CNN_ACC.qpf &
```

Top entity: `system_top`  ·  Device: Cyclone V `5CSEMA5F31C6`

##111 Run RTL sim

```bash
NO_VCD=1 ./vf/work/run_vsim_system_e2e_behav.tcsh     # 期望 PASS 10/10
```

## Regenerate MATLAB golden（只在改模型/脚本后）

```bash
cd Golden-Module/matlab/hardware_aligned && matlab -batch "run_all"
```
