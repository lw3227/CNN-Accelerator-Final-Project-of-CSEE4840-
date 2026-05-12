#!/usr/bin/env python3
"""Cross-platform build wrapper for the DE1-SoC Quartus project.

Usage:
    python de1_soc/build_soc_system.py
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
PROJECT_NAME = "soc_system"
QSYS_FILE = PROJECT_DIR / f"{PROJECT_NAME}.qsys"
SOF_FILE = PROJECT_DIR / "output_files" / f"{PROJECT_NAME}.sof"
RBF_FILE = PROJECT_DIR / "output_files" / f"{PROJECT_NAME}.rbf"
GENERATED_SOC_SYSTEM_V = PROJECT_DIR / "soc_system" / "synthesis" / "soc_system.v"


def candidate_roots() -> list[Path]:
    env_root = os.environ.get("QUARTUS_ROOTDIR")
    roots: list[Path] = []
    if env_root:
        roots.append(Path(env_root))

    system = platform.system()
    if system == "Windows":
        roots.extend(
            [
                Path(r"C:\intelFPGA_lite"),
                Path(r"C:\intelFPGA"),
                Path(r"C:\Program Files\intelFPGA_lite"),
                Path(r"C:\Program Files\intelFPGA"),
            ]
        )
    elif system == "Darwin":
        roots.extend(
            [
                Path("/Applications/intelFPGA_lite"),
                Path("/Applications/intelFPGA"),
                Path.home() / "intelFPGA_lite",
                Path.home() / "intelFPGA",
            ]
        )
    else:
        roots.extend(
            [
                Path("/opt/intelFPGA_lite"),
                Path("/opt/intelFPGA"),
                Path.home() / "intelFPGA_lite",
                Path.home() / "intelFPGA",
            ]
        )
    return roots


def tool_names(base: str) -> list[str]:
    system = platform.system()
    if system == "Windows":
        return [f"{base}.exe", base]
    return [base]


def env_var_name(base: str) -> str:
    return base.replace("-", "_").upper()


def find_tool(base: str, verbose: bool = False) -> tuple[str | None, list[str]]:
    searched: list[str] = []
    override_var = env_var_name(base)
    override = os.environ.get(override_var)
    if override:
        searched.append(f"{override_var}={override}")
        if Path(override).exists():
            return override, searched

    for name in tool_names(base):
        searched.append(f"PATH:{name}")
        found = shutil.which(name)
        if found:
            return found, searched

    for root in candidate_roots():
        searched.append(f"ROOT:{root}")
        if not root.exists():
            continue

        if root.name == "quartus":
            search_bins = [
                root / "bin64",
                root / "bin",
                root / "sopc_builder" / "bin",
            ]
        else:
            search_bins = []
            for version_dir in sorted(root.glob("*")):
                if not version_dir.is_dir():
                    continue
                quartus_dir = version_dir / "quartus"
                if quartus_dir.exists():
                    search_bins.extend(
                        [
                            quartus_dir / "bin64",
                            quartus_dir / "bin",
                            quartus_dir / "sopc_builder" / "bin",
                        ]
                    )

        for bin_dir in search_bins:
            for name in tool_names(base):
                candidate = bin_dir / name
                searched.append(str(candidate))
                if candidate.exists():
                    return str(candidate), searched

    if verbose:
        for item in searched:
            print(f"  searched {item}")

    return None, searched


def build_env_for_subprocesses(quartus_sh: str | None) -> dict[str, str]:
    env = os.environ.copy()

    if platform.system() != "Windows" or not quartus_sh:
        return env

    quartus_path = Path(quartus_sh).resolve()
    acds_root = quartus_path.parent.parent.parent
    nios_gnu_bin = acds_root / "nios2eds" / "bin" / "gnu" / "H-x86_64-mingw32" / "bin"

    if nios_gnu_bin.exists():
        env["PATH"] = str(nios_gnu_bin) + os.pathsep + env.get("PATH", "")

    return env


def run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(f'"{part}"' if " " in part else part for part in cmd))
    subprocess.run(cmd, cwd=str(cwd), env=env, check=True)


def run_capture(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(f'"{part}"' if " " in part else part for part in cmd))
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def is_recoverable_windows_qsys_failure(output: str) -> bool:
    markers = [
        "generate_hps_sdram.tcl",
        "Nios II Command Shell.bat",
        "child process exited abnormally",
        "Error: border: Error during execution of script generate_hps_sdram.tcl: seq:",
    ]
    return platform.system() == "Windows" and all(marker in output for marker in markers)


def generated_hdl_looks_usable() -> bool:
    required = [
        PROJECT_DIR / "soc_system" / "synthesis" / "soc_system.v",
        PROJECT_DIR / "soc_system" / "synthesis" / "submodules" / "hps_sdram.v",
        PROJECT_DIR / "soc_system" / "synthesis" / "submodules" / "hps_sdram_p0.sv",
    ]
    return all(path.exists() for path in required)


def patch_generated_soc_system_debug_ports() -> None:
    if not GENERATED_SOC_SYSTEM_V.exists():
        raise FileNotFoundError(f"generated top not found: {GENERATED_SOC_SYSTEM_V}")

    text = GENERATED_SOC_SYSTEM_V.read_text(encoding="utf-8")

    if "cnn_debug_predict_class" in text:
        return

    module_old = "module soc_system (\n\t\tinput  wire        clk_clk,"
    module_new = (
        "module soc_system (\n"
        "\t\tinput  wire        clk_clk,\n"
        "\t\toutput wire        cnn_debug_model_loaded,\n"
        "\t\toutput wire        cnn_debug_predict_done,\n"
        "\t\toutput wire [3:0]  cnn_debug_predict_class,\n"
        "\t\toutput wire [15:0] cnn_debug_interface_error,"
    )

    inst_old = (
        "\t\t.address    (mm_interconnect_0_cnn_mmio_interface_0_avalon_slave_0_address),    //               .address\n"
        "\t\t.readdata   (mm_interconnect_0_cnn_mmio_interface_0_avalon_slave_0_readdata)    //               .readdata\n"
        "\t);"
    )
    inst_new = (
        "\t\t.address    (mm_interconnect_0_cnn_mmio_interface_0_avalon_slave_0_address),    //               .address\n"
        "\t\t.readdata   (mm_interconnect_0_cnn_mmio_interface_0_avalon_slave_0_readdata),   //               .readdata\n"
        "\t\t.debug_model_loaded   (cnn_debug_model_loaded),                                   //               .debug_model_loaded\n"
        "\t\t.debug_predict_done   (cnn_debug_predict_done),                                   //               .debug_predict_done\n"
        "\t\t.debug_predict_class  (cnn_debug_predict_class),                                  //               .debug_predict_class\n"
        "\t\t.debug_interface_error(cnn_debug_interface_error)                                 //               .debug_interface_error\n"
        "\t);"
    )

    if module_old not in text:
        raise RuntimeError("could not find soc_system module header to patch debug ports")
    if inst_old not in text:
        raise RuntimeError("could not find cnn_mmio_interface instantiation to patch debug ports")

    text = text.replace(module_old, module_new, 1)
    text = text.replace(inst_old, inst_new, 1)
    GENERATED_SOC_SYSTEM_V.write_text(text, encoding="utf-8")


def check_windows_qsys_prereqs(quartus_sh: str | None) -> tuple[bool, list[str]]:
    if platform.system() != "Windows" or not quartus_sh:
        return True, []

    messages: list[str] = []
    quartus_path = Path(quartus_sh).resolve()
    quartus_root = quartus_path.parent.parent
    nios2_shell = quartus_root.parent / "nios2eds" / "Nios II Command Shell.bat"
    mingw_bin = quartus_root.parent / "nios2eds" / "bin" / "gnu" / "H-x86_64-mingw32" / "bin"

    ok = True
    if not nios2_shell.exists():
        messages.append(f"missing Nios II Command Shell: {nios2_shell}")
        ok = False
    if not mingw_bin.exists():
        messages.append(f"missing Nios II GCC toolchain directory: {mingw_bin}")
        ok = False

    try:
        subprocess.run(
            ["wsl.exe", "bash", "-lc", "command -v dos2unix"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    except subprocess.CalledProcessError:
        messages.append("WSL is missing dos2unix (install with: wsl -u root bash -lc \"apt-get install -y dos2unix\")")
        ok = False
    except FileNotFoundError:
        messages.append("WSL is not available on this machine")
        ok = False

    return ok, messages


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the DE1-SoC Quartus project.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Only check tool discovery and print what would be used.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print searched locations while resolving Quartus tools.",
    )
    parser.add_argument(
        "--skip-qsys",
        action="store_true",
        help="Skip qsys-generate and compile using the committed generated HDL.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    qsys_generate, qsys_search = find_tool("qsys-generate", verbose=args.verbose)
    quartus_sh, quartus_sh_search = find_tool("quartus_sh", verbose=args.verbose)
    quartus_cpf, quartus_cpf_search = find_tool("quartus_cpf", verbose=args.verbose)

    missing = []
    if not qsys_generate and not args.skip_qsys:
        missing.append("qsys-generate")
    if not quartus_sh:
        missing.append("quartus_sh")

    if missing:
        print("Required Quartus tools were not found:", ", ".join(missing), file=sys.stderr)
        print(
            "Tried PATH, tool-specific env vars, QUARTUS_ROOTDIR, and common install folders.",
            file=sys.stderr,
        )
        print("Optional overrides:", file=sys.stderr)
        print("  QSYS_GENERATE=/path/to/qsys-generate", file=sys.stderr)
        print("  QUARTUS_SH=/path/to/quartus_sh", file=sys.stderr)
        print("  QUARTUS_CPF=/path/to/quartus_cpf", file=sys.stderr)
        return 1

    prereq_ok, prereq_messages = check_windows_qsys_prereqs(quartus_sh)
    build_env = build_env_for_subprocesses(quartus_sh)
    if args.check:
        print("Quartus tool check passed.")
        if args.skip_qsys:
            print("  qsys-generate: skipped by request")
        else:
            print(f"  qsys-generate: {qsys_generate}")
        print(f"  quartus_sh:    {quartus_sh}")
        if quartus_cpf:
            print(f"  quartus_cpf:   {quartus_cpf}")
        else:
            print("  quartus_cpf:   not found (RBF conversion will be skipped)")
        if platform.system() == "Windows":
            if prereq_ok:
                print("  windows qsys prereqs: OK")
                quartus_path = Path(quartus_sh).resolve()
                acds_root = quartus_path.parent.parent.parent
                mingw_bin = acds_root / "nios2eds" / "bin" / "gnu" / "H-x86_64-mingw32" / "bin"
                print(f"  injected Nios GCC path: {mingw_bin}")
            else:
                print("  windows qsys prereqs: MISSING")
                for message in prereq_messages:
                    print(f"    - {message}")
                return 1
        return 0

    if not prereq_ok:
        print("Windows Qsys prerequisites are incomplete:", file=sys.stderr)
        for message in prereq_messages:
            print(f"  - {message}", file=sys.stderr)
        return 1

    try:
        if args.skip_qsys:
            print("[1/3] Skipping Qsys generation and using committed generated HDL...")
        else:
            print("[1/3] Generating Qsys HDL...")
            qsys_result = run_capture(
                [qsys_generate, str(QSYS_FILE), "--synthesis=VERILOG"],
                cwd=PROJECT_DIR,
                env=build_env,
            )
            sys.stdout.write(qsys_result.stdout)
            if qsys_result.returncode != 0:
                if is_recoverable_windows_qsys_failure(qsys_result.stdout) and generated_hdl_looks_usable():
                    print()
                    print(
                        "Warning: qsys-generate hit the known Windows/WSL HPS SDRAM "
                        "sequencer-build failure, but the HDL outputs were still emitted."
                    )
                    print("Continuing to Quartus compile with the freshly generated HDL.")
                else:
                    print(f"Build failed with exit code {qsys_result.returncode}.", file=sys.stderr)
                    return qsys_result.returncode

        patch_generated_soc_system_debug_ports()

        print("[2/3] Compiling Quartus project...")
        run([quartus_sh, "--flow", "compile", PROJECT_NAME], cwd=PROJECT_DIR, env=build_env)

        if not SOF_FILE.exists():
            print(f"Expected SOF not found: {SOF_FILE}", file=sys.stderr)
            return 1

        if quartus_cpf:
            print("[3/3] Converting SOF to RBF...")
            run([quartus_cpf, "-c", str(SOF_FILE), str(RBF_FILE)], cwd=PROJECT_DIR, env=build_env)
        else:
            print("[3/3] quartus_cpf not found, skipping RBF conversion.")
    except subprocess.CalledProcessError as exc:
        print(f"Build failed with exit code {exc.returncode}.", file=sys.stderr)
        return exc.returncode

    print()
    print(f"Build complete.")
    print(f"SOF: {SOF_FILE}")
    if RBF_FILE.exists():
        print(f"RBF: {RBF_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
