# Teammate Setup

This document is the teammate-facing setup guide for the current
`DE1-SoC + HPS + MMIO + web demo` mainline.

Use this file when a teammate needs to answer:

- which host OS is supported for which task
- what must be installed locally
- which commands are expected to work from the repository root
- what is board-only vs host-only vs cross-platform

## Support Matrix

The current repo supports three practical host roles.

| Task | Windows host | Linux host | macOS host |
| --- | --- | --- | --- |
| Read docs / inspect repo | Yes | Yes | Yes |
| Python preprocessing / local model checks | Yes | Yes | Yes |
| Run Flask web demo over SSH to board | Yes | Yes | Yes |
| Run host-side helper scripts | Yes | Yes | Yes |
| Quartus full FPGA rebuild | Yes | Yes | Depends on external Intel-tool setup; not the validated lane |
| JTAG program `.sof` with `quartus_pgm` | Yes | Usually yes if Quartus programmer is installed | Not the validated lane |
| UART/serial bring-up helper scripts | Yes | Yes | Yes, if serial device path is known |

## Practical Recommendation

For teammates, the most reliable split today is:

- use **Windows** if you need Quartus GUI, `quartus_pgm`, USB-Blaster, and COM-port bring-up
- use **Windows or Linux** if you only need board SSH, web demo, Python preprocessing, or board-side tool validation
- use **macOS** only for host-side Python/web/SSH tasks unless you already maintain your own FPGA-toolchain setup

## Repository Root

All commands in the active docs assume you start at the repository root:

```text
<repo>/
```

That matters because many scripts use repo-relative paths.

## Required Host Tools

### Always Useful

- Python 3.10+ recommended
- `pip`
- Git

### Needed For The Web Demo / Runtime Lane

- Python packages from:
  - `web_demo/requirements.txt`
- one TFLite runtime path:
  - `tflite-runtime`, or
  - `tensorflow`

Install with:

```bash
python -m pip install -r web_demo/requirements.txt
```

### Needed For Quartus / Board Programming Lane

- Intel Quartus / Quartus Lite 21.1 compatible with this repo
- `quartus_sh`
- `qsys-generate`
- `quartus_cpf`
- `quartus_pgm`

### Needed For Serial Bring-Up

- a usable USB-UART path
- on Windows: a `COM` port such as `COM3`
- on Linux/macOS: a serial device such as `/dev/ttyUSB0`, `/dev/ttyACM0`, or `/dev/cu.usbserial-*`

## First Commands To Try

### 1. Confirm The Repo And Python Environment

```bash
python --version
python de1_soc/build_soc_system.py --check
```

The `--check` command is the safest first probe because it checks for the main
Intel tools without starting a full build.

### 2. Install Web / Runtime Dependencies

```bash
python -m pip install -r web_demo/requirements.txt
```

### 3. Build HPS-side Tools Locally

```bash
make -C tools
```

This confirms the host compiler can build the C helpers and that the shared
headers are internally consistent.

## Cross-Platform Commands

These commands are intended to work from any host OS, assuming Python and the
required dependencies are present.

### Run The Web Demo

```bash
python web_demo/app.py
```

Open:

```text
http://127.0.0.1:5000
```

### Check Board SSH

```bash
python web_demo/check_board.py
python web_demo/check_board.py --build-tools
```

### Run A Local Mock Case

```bash
python test_data/run_case.py digit_0_test
```

### Inspect The Active Demo Config

```text
GET /api/health
```

## Windows-Specific Commands

These are the currently validated commands for the main board lane.

### Build Quartus Project

```powershell
python de1_soc\build_soc_system.py --check
python de1_soc\build_soc_system.py
```

### One-Command Board Prep

```powershell
python tools\prepare_web_demo.py --program-sof --build-tools
```

### Serial MMIO Check

```powershell
python tools\hps_serial_exec.py --port COM3 "cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000"
```

## Linux / macOS Notes

If the board has already been programmed and networked, Linux/macOS teammates
can still do the high-value runtime work:

- run the web demo
- inspect preprocessing behavior
- verify SSH access
- compare CPU vs FPGA inference
- iterate on host-side scripts and docs

Typical flow:

```bash
python web_demo/check_board.py
python web_demo/app.py
```

If you want to use serial helpers on Linux/macOS, replace `COM3` with the
correct device path for your machine.

Examples:

```bash
python tools/hps_serial_exec.py --port /dev/ttyUSB0 "cd /root/cnn_acc_hps && pwd"
python tools/hps_serial_exec.py --port /dev/cu.usbserial-0001 "cd /root/cnn_acc_hps && pwd"
```

## Board Assumptions

The board-side validated repository root is:

```text
/root/cnn_acc_hps
```

The current direct-link Ethernet configuration is:

- host bind address: `169.254.217.240`
- board address: `169.254.217.241`

## If You Only Need The Current Working Flow

The shortest safe teammate path is:

1. Open a terminal at the repo root
2. Install Python dependencies
3. If you are on Windows and need a fresh FPGA image:
   ```powershell
   python tools\prepare_web_demo.py --program-sof --build-tools
   ```
4. If the board is already up:
   ```bash
   python web_demo/check_board.py --build-tools
   ```
5. Start the demo:
   ```bash
   python web_demo/app.py
   ```

## Read Next

- [README.md](README.md)
- [DOCS_INDEX.md](DOCS_INDEX.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
