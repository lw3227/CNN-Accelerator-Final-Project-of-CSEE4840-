#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p platform_designer/ip_index
ip-make-ipx --source-directory=platform_designer --output=platform_designer/ip_index/components.ipx

qsys-script --search-path="$ROOT_DIR/platform_designer/ip_index,$" --script=de1_soc/soc_system_template.tcl

echo "Generated de1_soc/soc_system.qsys (with current custom-component limitations, see de1_soc/README.md)."
echo "Next step:"
echo "  quartus_sh -t de1_soc/soc_system_project.tcl"
