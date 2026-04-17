# File Index

你现在应该在主工程目录：

`/homes/user/stud/fall25/lw3227/CNN_ACC`

下面这些是这轮新增/整理过的关键文件路径。

## RTL / 仿真

- [input/RTL/interface/cnn_mmio_interface.v](/homes/user/stud/fall25/lw3227/CNN_ACC/input/RTL/interface/cnn_mmio_interface.v)
- [input/TB/tb_cnn_mmio_interface.v](/homes/user/stud/fall25/lw3227/CNN_ACC/input/TB/tb_cnn_mmio_interface.v)
- [vf/scripts/runtb_cnn_mmio_interface.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/vf/scripts/runtb_cnn_mmio_interface.tcl)
- [input/SDC/system_top.sdc](/homes/user/stud/fall25/lw3227/CNN_ACC/input/SDC/system_top.sdc)

## HPS / MMIO 共享头文件

- [include/cnn_mmio_regs.h](/homes/user/stud/fall25/lw3227/CNN_ACC/include/cnn_mmio_regs.h)
- [include/cnn_mmio_host.h](/homes/user/stud/fall25/lw3227/CNN_ACC/include/cnn_mmio_host.h)

## HPS tools

- [tools/cnn_mmio_host.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/cnn_mmio_host.c)
- [tools/hps_mmio_infer.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_infer.c)
- [tools/hps_mmio_load_model.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_load_model.c)
- [tools/hps_mmio_run_case.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_run_case.c)
- [tools/hps_mmio_status.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_status.c)
- [tools/run_mmio_inference.py](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/run_mmio_inference.py)
- [tools/Makefile](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/Makefile)

## Python runtime

- [gesture_runtime/network.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/network.py)
- [gesture_runtime/quantization.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/quantization.py)
- [gesture_runtime/preprocess.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/preprocess.py)
- [gesture_runtime/mmio_runtime.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/mmio_runtime.py)
- [gesture_runtime/mmio_driver.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/mmio_driver.py)
- [gesture_runtime/export_mmio_image.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/export_mmio_image.py)
- [gesture_runtime/tests/test_runtime.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/tests/test_runtime.py)
- [gesture_runtime/tests/test_mmio_driver.py](/homes/user/stud/fall25/lw3227/CNN_ACC/gesture_runtime/tests/test_mmio_driver.py)

## DE1-SoC / Platform Designer

- [platform_designer/cnn_mmio_interface_hw.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/platform_designer/cnn_mmio_interface_hw.tcl)
- [de1_soc/README.md](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/README.md)
- [de1_soc/soc_system_template.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/soc_system_template.tcl)
- [de1_soc/soc_system_project.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/soc_system_project.tcl)
- [de1_soc/generate_soc_project.sh](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/generate_soc_project.sh)
- [de1_soc/CNN_ACC_mmio.qsf.template](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/CNN_ACC_mmio.qsf.template)
- [de1_soc/cnn_mmio_demo_top.v](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/cnn_mmio_demo_top.v)
- [de1_soc/cnn_mmio_demo_top.qsf.template](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/cnn_mmio_demo_top.qsf.template)

## 怎么快速找

```bash
cd /homes/user/stud/fall25/lw3227/CNN_ACC
find de1_soc gesture_runtime include tools input/RTL/interface input/TB vf/scripts -maxdepth 2 | sort
```
