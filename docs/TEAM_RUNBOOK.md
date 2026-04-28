# Team Runbook

This document is the practical end-to-end runbook for the current DE1-SoC
project lane.

It is written for teammates who need to:

- rebuild the FPGA project
- program the board
- run board-side validation
- run the web demo
- understand the direct host-to-board network setup
- recover the system after unplugging cables or power

The goal is not only to list commands, but also to explain why each step
exists so the flow is easier to debug and maintain.

## Which Docs To Pair With This Runbook

Use this runbook together with:

- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
  for cross-platform host-role guidance
- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
  for "which file owns what" across RTL, Quartus, host tools, and web runtime
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
  for the detailed browser -> host -> board -> FPGA runtime path
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
  for the shared register map, scratchpad layout, and host helper API
- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
  for current model size, fit summary, and timing report locations
- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)
  for the RTL changes that moved the validated build back to direct 50 MHz

This file stays focused on staged bring-up, recovery, and practical commands.

## What This Project Is Doing

The current working lane is:

`host machine -> HPS Linux userspace -> MMIO -> FPGA accelerator`

The pieces are:

- FPGA RTL core:
  `input/RTL/system_top.v`
- MMIO wrapper:
  `input/RTL/interface/cnn_mmio_interface.v`
- DE1-SoC board integration:
  `de1_soc/`
- HPS-side C tools:
  `tools/`
- Host-side web demo:
  `web_demo/`

The current validated board path is not DMA-based and not PYNQ-based.
It is MMIO over the lightweight HPS-to-FPGA bridge at `0xff200000`.

## Current Known-Good Baseline

At the time this runbook was written, the following are true:

- the Quartus project builds through:
  `python de1_soc/build_soc_system.py`
- the generated bitstream can be programmed successfully
- the board-side `digit_0_test` through `digit_9_test` suite passes
- the hardware-aligned case set was repaired so the suite now reports
  `10/10 PASS`
- the web demo works using:
  - Flask on the host machine
  - SSH from host to board
  - board-side CPU baseline
  - board-side FPGA inference

## Repository Working Directories

This matters because most earlier path errors were just caused by running
commands from the wrong directory.

Recommended default: open your terminal at the repository root:

```text
<repo>/
```

Examples in this document assume that default unless stated otherwise.

If you are inside `de1_soc/`, remember that `tools/` is one level up.

## Part 1: Build The FPGA Project

### Recommended Command

From the repository root:

```bash
python de1_soc/build_soc_system.py --check
python de1_soc/build_soc_system.py
```

On Windows you may also use:

```cmd
de1_soc\build_soc_system.cmd
```

### Why Use The Script

Use the build script instead of manually clicking through Quartus because it:

- finds `qsys-generate`
- finds `quartus_sh`
- finds `quartus_cpf`
- regenerates Platform Designer HDL
- compiles the Quartus project
- converts `sof` to `rbf`

This makes the flow more reproducible across teammates and machines.

### Outputs

Successful build artifacts:

- `de1_soc/output_files/soc_system.sof`
- `de1_soc/output_files/soc_system.rbf`

### About The Platform Designer Red Errors

On some Windows machines, `qsys-generate` may show red errors related to HPS
SDRAM sequencer generation.

Important:

- this is usually not a signal-wire connection problem
- it is typically an Intel toolchain environment problem in the generated HPS
  SDRAM helper stage
- on the currently validated machine, the build script can recover and still
  produce a usable Quartus build

So if GUI `Generate HDL...` shows red text, do not assume the design is broken.
First try the scripted build.

## Part 2: Program The FPGA

### What To Program

For quick testing after a rebuild, program the volatile JTAG bitstream:

- `de1_soc/output_files/soc_system.sof`

This is the fastest way to update the FPGA fabric.

### Why SOF Vs RBF Matters

- `SOF` is used for immediate JTAG programming
- `RBF` is used for boot-time or longer-lived deployment flows

If you only JTAG-program a `sof`, the FPGA changes immediately, but the change
is lost when the board powers off.

If you need the board to come back after a power cycle without reprogramming
the FPGA manually, then you need the correct boot-time `rbf` path as well.

### Typical Programmer Flow

You can use Quartus Programmer GUI, or CLI via `quartus_pgm`.

The important result to look for is:

```text
Configuration succeeded -- 1 device(s) configured
```

### Current Windows CLI Command

On the currently validated Windows machine, the Quartus Programmer executable
was found at:

```text
F:\intelFPGA_lite\21.1\quartus\bin64\quartus_pgm.exe
```

The DE1-SoC JTAG chain on this board shows two devices:

1. `SOCVHPS`
2. `5CSEMA5...` FPGA

That means the FPGA is **device index 2**, not device index 1.
So the working manual CLI command is:

```powershell
& "F:\intelFPGA_lite\21.1\quartus\bin64\quartus_pgm.exe" `
  -c "DE-SoC [USB-1]" `
  -m jtag `
  -o "p;C:\path\to\repo\de1_soc\output_files\soc_system.sof@2"
```

If you forget the `@2`, Quartus may try to program the HPS entry in the JTAG
chain first and fail with an ID-code mismatch.

### Preferred One-Command Programmer Flow

Use the repository helper when possible:

```powershell
python tools\prepare_web_demo.py --program-sof --skip-serial-network --skip-ssh-check
```

This helper:

- finds `quartus_pgm`
- finds the first available programming cable
- uses JTAG device index `2` by default for DE1-SoC
- programs the current `de1_soc/output_files/soc_system.sof`

### Which Design Used To Drive The Board LEDs

There are two different board-visible debug paths in this repository:

1. `de1_soc/cnn_mmio_demo_top.v`
   FPGA-only bring-up shell that directly mirrors:
   - `model_loaded`
   - `predict_done`
   - `predict_class_latched`
   onto `LEDR`
2. `de1_soc/soc_system_top.sv`
   The real HPS + MMIO + FPGA top-level used for the current board and web-demo
   mainline

If you remember the board LEDs showing the predicted class directly, you were
most likely running the older FPGA-only LED debug shell or an earlier variant
of the board top that still drove board display outputs directly.

## Part 3: Bring The Board Up

### Current Board-Side Repo Path

The currently validated board-side repository root is:

```text
/root/cnn_acc_hps
```

Do not assume older paths such as lab-machine home directories.

### HPS Tools Used On The Board

These are the main board-side tools:

- `./tools/hps_mmio_status`
- `./tools/hps_mmio_load_model`
- `./tools/hps_mmio_run_case`
- `./tools/hps_mmio_infer`
- `./tools/hps_cpu_reference`
- `./tools/hps_mmio_predict`

## Part 4: How To Test The Board Manually

### 4.1 First Check The Board Is Alive

If you are using the serial path:

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && pwd"
```

Expected result:

```text
/root/cnn_acc_hps
```

### Why This Step Exists

This confirms three things at once:

- the board is powered and Linux is up
- the serial port is correct
- the repo exists at the expected board path

### 4.2 Check MMIO Status

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000"
```

A good idle response looks like:

```text
status=0x0000
model_loaded=0
predict_done=0
predict_class=0
error=0x0000
```

### Why This Step Exists

This tells you whether:

- the HPS-to-FPGA bridge is responding
- the MMIO base address is correct
- the bitstream is at least partially alive

If this is already wrong, do not trust later inference steps.

### 4.3 Load One Model

Example:

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_load_model 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_7_test"
```

### Why This Step Exists

The current flow is intentionally split into stages:

1. model load
2. image/case run

This makes failures easier to localize.

### 4.4 Run One Case

Example:

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_run_case 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_7_test"
```

You should see:

```text
expected_class=7
predict_class=7
status=0x007c
error=0x0000
```

### How To Judge Success

The important lines are:

- `expected_class=...`
- `predict_class=...`
- `error=0x0000`

If `predict_class == expected_class` and `error=0x0000`, that case passed.

## Part 5: Run The Full Board Suite

From the repository root:

```powershell
python tools\run_hps_digit_suite.py --port COM3 --skip-upload --skip-build
```

### Why These Flags

- `--skip-upload`
  means the board already has the case directories
- `--skip-build`
  means the HPS tools are already compiled on the board

If either assumption is false, remove those flags.

### Current Expected Result

The current repaired suite should print `PASS` for all ten cases.

## Part 6: What Was Repaired In The Case Set

Two hardware-aligned test cases were previously inconsistent:

- `digit_4_test`
- `digit_9_test`

The issue was not that the FPGA was miscomputing. The issue was that the case
directories contained inputs and labels that did not match the intended PNGs.

This has now been repaired so that the suite is self-consistent and passes.

Supporting tools:

- `tools/run_hps_digit_suite.py`
  now warns if directory naming and case labels diverge
- `tools/sync_case_from_png.py`
  can regenerate a case input and manifest label from a PNG using the current
  Python preprocessing/model path

## Part 7: How The Web Demo Works

The web demo is not running on the board.

The architecture is:

```text
PC browser -> Flask app on host -> SSH to board -> HPS tools -> FPGA
```

### Detailed Flow

1. The browser uploads an image or captures one from the browser webcam.
2. The Flask backend on the host preprocesses the image.
3. The host sends a preprocessed input to the board.
4. The board runs:
   - a CPU reference path on the HPS ARM CPU
   - the FPGA accelerator path
5. The host receives both results and renders them in the web UI.

For the file-by-file version of that path, see
[WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md).

### Why The Webcam Is On The Host

The webcam is intentionally the browser/PC camera, not a board-attached camera,
because:

- it is easier for demos
- it is cross-platform
- it avoids adding another hardware path before the main host/board flow is stable

### Where The Web App Lives

- backend:
  `web_demo/app.py`
- config:
  `web_demo/config.py`
- frontend:
  `web_demo/templates/index.html`
  and `web_demo/static/*`

### Launch

```bash
python web_demo/app.py
```

Open:

```text
http://127.0.0.1:5000
```

### What The Timing Means

The current UI compares same-platform board CPU vs FPGA:

- `Board CPU Time`
  software reference inference time on the HPS ARM CPU
- `FPGA Wait Time`
  time from `INFER` to `predict_done`
- `Remote request`
  host-side SSH and transfer overhead; shown for transparency, but not the main
  speedup metric

This is more meaningful than comparing host x86 CPU time against FPGA time.

For the exact MMIO register contract under this flow, see
[MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md).

## Part 8: Network / IP / LAN Explanation

### Do We Need A LAN

Not necessarily a full routed LAN.

The current validated setup works with a direct Ethernet connection between:

- the host machine
- the DE1-SoC board

### Current Working Addresses

Current direct-link values:

- host bind address:
  `169.254.217.240`
- board address:
  `169.254.217.241`

These are link-local style addresses used over the direct Ethernet cable.

### What This Means

This is still IP networking.

It is not “magic local connection”; it is simply a direct Ethernet link with IP
addresses assigned to each side.

So the web demo and SSH path work because:

- the host can reach the board over Ethernet
- the board runs SSH
- the Flask app uses SSH to trigger board-side tools

### Do You Need To Rebuild The Network Every Time

No, but after unplugging everything you may need to re-establish:

- Ethernet physical link
- the host IP on the Ethernet adapter
- the board IP and SSH reachability

### Current Practical Board-Side Network Finding

During current bring-up validation, the host-side direct-link adapter already
held:

- host bind address: `169.254.217.240`

but the board-side Ethernet interface initially came up as:

- `eth0 state DOWN`
- no board IPv4 address configured

In that state:

- serial still works
- MMIO validation can still work
- SSH and the web demo will fail because the board never answers on
  `169.254.217.241:22`

So board SSH failure does **not** automatically mean the FPGA or Linux bring-up
is broken; it can simply mean the board network path was never reconfigured
after reboot or cable changes.

### Preferred One-Command SSH / Web Bring-Up

If the FPGA is already programmed and Linux is up, use:

```powershell
python tools\prepare_web_demo.py --build-tools
```

If you want the helper to program the `sof` first and then prepare the web
path:

```powershell
python tools\prepare_web_demo.py --program-sof --build-tools
```

This helper currently does all of the following:

- optionally programs `de1_soc/output_files/soc_system.sof`
- logs into the board over serial
- confirms `/root/cnn_acc_hps`
- brings up `eth0`
- assigns board IP `169.254.217.241/16`
- starts `ssh` / `sshd` / `dropbear` if present
- pings the board from the host
- verifies SSH from the host
- optionally runs `make` in the board `tools/` directory

### Manual Board Network Recovery

If you want to do the board network part by hand over serial, the current
direct-link setup is:

```bash
ip link set eth0 up
ip addr flush dev eth0
ip addr add 169.254.217.241/16 dev eth0
```

Then start SSH if needed with one of:

```bash
service ssh start
service sshd start
service dropbear start
```

or:

```bash
/etc/init.d/ssh start
/etc/init.d/sshd start
/etc/init.d/dropbear start
```

Then from the host:

```powershell
python web_demo\check_board.py
```

## Part 9: If Everything Gets Unplugged, How Do I Start Again

This is the recovery checklist.

### 9.1 Physically Reconnect

Reconnect:

- USB-Blaster / JTAG cable
- USB-UART / serial cable
- Ethernet cable between host and board
- board power

### 9.2 Power The Board

Power on the DE1-SoC board and wait for Linux to boot.

### 9.3 Reprogram The FPGA If Needed

If you only previously used `sof` over JTAG, then after power loss you must
program the FPGA again.

In practice:

1. rebuild if needed:
   ```bash
   python de1_soc/build_soc_system.py
   ```
2. program the new `sof`

### Why This Is Necessary

`SOF` programming is volatile. Power cycling clears the FPGA configuration.

### 9.4 Reconfirm Serial

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && pwd"
```

### 9.5 Reconfirm Board Networking

If using the web demo or SSH path, verify:

- Ethernet link is up
- the host adapter still has the expected direct-link IP
- the board is reachable by its configured IP

The shortest current recovery command is:

```powershell
python tools\prepare_web_demo.py --build-tools
```

### 9.6 Reconfirm MMIO

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000"
```

### 9.7 Reconfirm Board Suite

```powershell
python tools\run_hps_digit_suite.py --port COM3 --skip-upload --skip-build
```

### 9.8 Reconfirm Web Demo

Start the Flask app:

```bash
python web_demo/app.py
```

Then open:

```text
http://127.0.0.1:5000
```

## Part 10: Common Failure Modes

### Quartus JTAG ID Mismatch During SOF Programming

If you see something like:

```text
Expected JTAG ID code 0x02D120DD ... but found 0x4BA00477
```

then Quartus tried to program device index 1 in the JTAG chain instead of the
actual FPGA device.

Cause:

- DE1-SoC exposes both `SOCVHPS` and the FPGA in the JTAG chain
- the FPGA is device index `2`

Fix:

- use the helper:
  `python tools\prepare_web_demo.py --program-sof --skip-serial-network --skip-ssh-check`
- or manually add `@2` to the `.sof` operation string

### Serial Port Errors

If you see:

```text
could not open port 'COM3'
```

Likely causes:

- wrong port name
- another program already owns the serial port

Fix:

- close other serial tools
- confirm the correct COM port

On the current machine, `COM3` is the validated board UART.

### Serial Command Output Looks Polluted Or Duplicated

Current serial helper output may include shell prompt lines, echoed commands,
wrapped arguments, or terminal control-sequence artifacts such as:

- `root@de1-soc:~/cnn_acc_hps#`
- partial command re-echo
- broken long arguments like `0xff` on one line and `200000` on the next

This does **not** necessarily mean the board command failed.

When judging success, trust the key-value lines printed by the board tools,
for example:

```text
status=0x0004
model_loaded=1
```

or:

```text
expected_class=0
predict_class=0
error=0x0000
```

### SSH Timeout Even Though Serial And MMIO Work

If `python web_demo\check_board.py` times out on SSH, but serial and MMIO
still work, do not jump to RTL or bridge debugging first.

The confirmed current failure mode is:

- host adapter still has `169.254.217.240`
- board `eth0` is down or unconfigured
- board SSH service is not started

Fix:

- use `python tools\prepare_web_demo.py --build-tools`
- or bring up `eth0` and start SSH manually over serial

### Web Demo Works But The Board No Longer Shows The Predicted Class

This can happen even when FPGA inference is correct.

Cause:

- the old FPGA-only LED debug shell and the current HPS/MMIO mainline are not
  the same top-level
- previous board runs may have used `de1_soc/cnn_mmio_demo_top.v`
- the current project top is `de1_soc/soc_system_top.sv`

Current repository behavior:

- the old LED-only path still exists for bring-up reference
- the current mainline top now exposes prediction/debug information again
  through the board HEX displays by directly reading:
  - `predict_class_latched`
  - `predict_done`
  - `model_loaded`
  - `interface_error`
  from the instantiated MMIO wrapper inside `soc_system`

Current display convention in `soc_system_top.sv`:

- `HEX0` shows predicted class after `predict_done`
- `HEX1` shows the two debug bits `{model_loaded, predict_done}`
- `HEX2` shows low nibble of `interface_error` when non-zero
- `HEX5` shows `E` when an interface error is latched

If the board still does not show the result after rebuilding, confirm that the
newly rebuilt `de1_soc/output_files/soc_system.sof` was actually programmed
after the display logic change.

### Ping Can Be Misleading On The Direct Link

On the current Windows host, `ping 169.254.217.241` may print
`Destination host unreachable` style lines even while SSH succeeds
immediately afterwards.

For this setup, treat the following as the authoritative web-demo checks:

- `python tools\prepare_web_demo.py --build-tools`
- `python web_demo\check_board.py`

### No Such File Or Directory

This is often just a current-directory mistake.

If you are in `de1_soc/`, then:

- `python build_soc_system.py`
  is correct
- `python tools/...`
  is wrong from there because `tools/` lives at the repo root

### Web Demo Can Reach The Board Poorly

Check:

- Ethernet link lights
- host adapter IP
- board IP
- SSH service on the board
- whether board `eth0` was reconfigured after reboot
- whether the direct-link board IP is still `169.254.217.241`

### FPGA Seems Wrong But MMIO Looks Fine

Check timing and the currently programmed bitstream.

This project previously had timing concerns at 50 MHz. The current validated
`submission` build is back on direct `CLOCK_50` without the earlier
`clk_div2` workaround. If timing now looks suspicious, confirm that you are
programming the current bitstream and compare against:

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)

## Part 11: Recommended Daily Workflow

For a teammate resuming the project, this is the shortest safe path:

1. Open terminal at repo root
2. Build if needed:
   ```bash
   python de1_soc/build_soc_system.py --check
   python de1_soc/build_soc_system.py
   ```
3. Run the one-command recovery helper:
   ```powershell
   python tools\prepare_web_demo.py --program-sof --build-tools
   ```
4. If you want the staged manual confirmation path, continue with:
   ```powershell
   python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && pwd"
   ```
5. Confirm MMIO:
   ```powershell
   python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000"
   ```
6. Run the board suite:
   ```powershell
   python tools\run_hps_digit_suite.py --port COM3 --skip-upload --skip-build
   ```
7. If needed, launch the web demo:
   ```bash
   python web_demo/app.py
   ```

## Part 12: Files To Keep In Mind

Team members should know these first:

- `de1_soc/build_soc_system.py`
- `tools/run_hps_digit_suite.py`
- `tools/sync_case_from_png.py`
- `tools/hps_serial_exec.py`
- `tools/prepare_web_demo.py`
- `web_demo/app.py`
- `de1_soc/DEVELOPMENT_MAINLINE.md`
- `de1_soc/BOARD_TEST_PLAN.md`

## Final Practical Note

If the board is unplugged and you later want to run again, the most important
thing to remember is:

- reconnect cables
- power the board
- reprogram the FPGA with the current `sof`
- rerun `python tools\prepare_web_demo.py --program-sof --build-tools`
- recheck serial and MMIO if deeper validation is needed
- then rerun the suite

That is the minimum reliable recovery path.
