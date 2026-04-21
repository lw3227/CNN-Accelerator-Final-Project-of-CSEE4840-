# Teammate Setup

This document is the teammate-facing setup guide for the current
`DE1-SoC + HPS + MMIO + web demo` mainline.

Use it to answer:

- which host OS is practical for which task
- what must be installed locally
- which commands are shared across systems
- what changes when you move from Windows to Linux or macOS

## Support Matrix

| Task | Windows | Linux | macOS |
| --- | --- | --- | --- |
| Read docs / inspect repo | Yes | Yes | Yes |
| Python preprocessing / local model checks | Yes | Yes | Yes |
| Run Flask web demo over SSH to board | Yes | Yes | Yes |
| Run host-side helper scripts | Yes | Yes | Yes |
| Serial bring-up helpers | Yes | Yes | Yes |
| Quartus full FPGA rebuild | Yes | Usually yes if Intel tools are installed | Not the validated lane |
| JTAG program `.sof` with `quartus_pgm` | Yes | Usually yes if programmer is installed | Not the validated lane |

## Practical Summary

- Use **Windows** for the full validated board lane:
  Quartus, JTAG, USB-Blaster, serial bring-up, SSH, and web demo.
- Use **Linux** for host-side runtime work and, if your Intel tool setup is
  already good, possibly for rebuild / programming too.
- Use **macOS** for host-side runtime work:
  Python, SSH, web demo, and optional serial access.

## Shared Assumptions

All commands assume you start at the repository root:

```text
<repo>/
```

Current validated board-side constants:

- board repo path:
  `/root/cnn_acc_hps`
- board IP:
  `169.254.217.241`
- host bind IP on the direct-link NIC:
  `169.254.217.240`
- MMIO base:
  `0xff200000`
- local demo URL:
  `http://127.0.0.1:5000`

## Common Host Requirements

Install these on any OS:

- Python 3.10+ recommended
- `pip`
- Git

For the web / runtime lane you also need:

- dependencies from `web_demo/requirements.txt`
- one TFLite runtime path:
  `tflite-runtime` or `tensorflow`

Install the repo Python packages with:

```bash
python -m pip install -r web_demo/requirements.txt
```

If your machine uses `python3` as the main command, replace `python` with
`python3` in the rest of this document.

## Common First Checks

These are the best first commands on any OS:

1. Confirm Python:
   ```bash
   python --version
   ```
2. Probe the repo tooling:
   ```bash
   python de1_soc/build_soc_system.py --check
   ```
3. Install runtime dependencies:
   ```bash
   python -m pip install -r web_demo/requirements.txt
   ```
4. Build the host-side C helpers:
   ```bash
   make -C tools
   ```

Useful cross-platform runtime commands:

```bash
python web_demo/check_board.py
python web_demo/check_board.py --build-tools
python web_demo/app.py
python test_data/run_case.py digit_0_test
```

## Windows Walkthrough

This is the fully validated lane for the current repo.

### What Windows Covers

Windows is the practical choice if you need:

- Quartus GUI
- `quartus_pgm`
- USB-Blaster / JTAG programming
- COM-port serial bring-up
- SSH and web demo

### Windows-Specific Tools

For the full board lane, make sure your machine has:

- Intel Quartus / Quartus Lite 21.1
- `quartus_sh`
- `qsys-generate`
- `quartus_cpf`
- `quartus_pgm`
- a serial port such as `COM3`

### Windows Quickstart

1. Check the toolchain:
   ```powershell
   python de1_soc\build_soc_system.py --check
   ```
2. Build if needed:
   ```powershell
   python de1_soc\build_soc_system.py
   ```
3. Bring the board all the way up:
   ```powershell
   python tools\prepare_web_demo.py --program-sof --build-tools
   ```
4. Optional serial MMIO sanity check:
   ```powershell
   python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000"
   ```
5. Start the web demo:
   ```powershell
   python web_demo\app.py
   ```

## Linux Walkthrough

Use Linux when you want concrete host-side runtime steps.

### What Linux Covers Well

Linux is practical for:

- Python preprocessing and local model checks
- board SSH access
- the Flask web demo
- runtime code edits
- serial bring-up if you know the UART device path

Quartus and `quartus_pgm` may also work on Linux, but that is not the current
validated teammate lane in this repo.

### Linux Packages

On Debian / Ubuntu style systems:

```bash
sudo apt update
sudo apt install -y python3 python3-pip make gcc openssh-client
```

On Fedora:

```bash
sudo dnf install -y python3 python3-pip make gcc openssh-clients
```

Then install the repo Python packages:

```bash
python3 -m pip install -r web_demo/requirements.txt
```

### Linux Quickstart

If the board is already programmed and networked, this is usually enough:

1. Check Python and the repo:
   ```bash
   python3 --version
   python3 de1_soc/build_soc_system.py --check
   ```
2. Install runtime dependencies:
   ```bash
   python3 -m pip install -r web_demo/requirements.txt
   ```
3. Verify board SSH:
   ```bash
   python3 web_demo/check_board.py --build-tools
   ```
4. Start the web app:
   ```bash
   python3 web_demo/app.py
   ```

### Linux Serial Discovery

Typical UART device names:

- `/dev/ttyUSB0`
- `/dev/ttyACM0`

Find candidates with:

```bash
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

Example serial probe:

```bash
python3 tools/hps_serial_exec.py --port /dev/ttyUSB0 "cd /root/cnn_acc_hps && pwd"
```

If permission is denied, check whether your user needs access to a serial
group such as `dialout`.

### Linux Network Check

If you are directly cabled to the board, inspect interfaces with:

```bash
ip addr
```

Look for the host-side address:

```text
169.254.217.240
```

### Linux Limits

- Do not assume Quartus is installed just because Python and SSH work.
- `python tools/prepare_web_demo.py --program-sof --build-tools` only makes
  sense on Linux if:
  - Quartus programmer is installed and in PATH
  - serial access is also working

## macOS Walkthrough

Use macOS for the supported host-side runtime path.

### What macOS Covers Well

macOS is practical for:

- reading and editing the repo
- Python preprocessing and local model checks
- the Flask web demo
- SSH access to the board
- serial bring-up if you know the `/dev/cu.*` device path

macOS is not the validated lane for Quartus rebuilds or JTAG programming.

### macOS Setup

Typical minimum setup:

```bash
xcode-select --install
python3 --version
python3 -m pip install -r web_demo/requirements.txt
```

If you use Homebrew and need Python 3:

```bash
brew install python
```

### macOS Quickstart

1. Check Python and the repo:
   ```bash
   python3 --version
   python3 de1_soc/build_soc_system.py --check
   ```
2. Verify board SSH:
   ```bash
   python3 web_demo/check_board.py --build-tools
   ```
3. Start the web app:
   ```bash
   python3 web_demo/app.py
   ```

### macOS Serial Discovery

Typical UART device names:

- `/dev/cu.usbserial-0001`
- `/dev/cu.usbmodem*`

Find candidates with:

```bash
ls /dev/cu.usb* /dev/cu.usbmodem* 2>/dev/null
```

Example serial probe:

```bash
python3 tools/hps_serial_exec.py --port /dev/cu.usbserial-0001 "cd /root/cnn_acc_hps && pwd"
```

### macOS Network Check

Inspect interfaces with:

```bash
ifconfig
```

Look for the host-side address:

```text
169.254.217.240
```

### macOS Limits

- Do not plan around Quartus GUI or `quartus_pgm` on macOS for this repo.
- Treat macOS as a host-side runtime / SSH / web-demo environment unless you
  already maintain your own FPGA tooling separately.

## If You Switch Host OS

When you move the same repo and board workflow to another OS, the main things
that usually change are:

- `python` vs `python3`
- serial port name:
  `COM3` vs `/dev/ttyUSB0` vs `/dev/cu.usbserial-*`
- whether Quartus tools are installed and on PATH
- whether the host NIC still owns `169.254.217.240`
- SSH key paths if you use key-based auth

Minimum recheck after switching:

1. Confirm Python
2. Reinstall `web_demo/requirements.txt` if needed
3. Verify `web_demo/check_board.py --build-tools`
4. Rediscover the serial device name before using `hps_serial_exec.py`
5. Recheck `quartus_pgm` if you also expect JTAG programming on the new host

## Read Next

- [README.md](README.md)
- [DOCS_INDEX.md](DOCS_INDEX.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
