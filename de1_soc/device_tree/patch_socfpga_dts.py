#!/usr/bin/env python3
"""Patch a SocFPGA DTS to expose cnn_mmio_interface on the lw bridge.

This is a practical fallback for bring-up when sopc2dts is unavailable.
The current de1_soc Platform Designer system maps cnn_mmio_interface_0 at:

  lightweight HPS-to-FPGA bridge base: 0xff200000
  child offset within bridge:          0x00000000
  span:                                0x00200000

The script patches two things:

1. Insert the MMIO child node under the simple-bus bridge window that maps
   `axi_h2f_lw` into the HPS address space.
2. Add bridge reset wiring to the `fpgabridge@*` helper nodes if the base DTS
   does not already describe them.

It is idempotent and will not add the same properties twice.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

LW_BRIDGE_COMPAT = "altr,socfpga-lwhps2fpga-bridge"
BRIDGE_BUS_COMPAT = 'compatible = "altr,bridge-21.1", "simple-bus";'
BRIDGE_BUS_REG_NAMES = 'reg-names = "axi_h2f", "axi_h2f_lw";'
BRIDGE_BUS_RANGES = "ranges = <0x1 0x0 0xff200000 0x8>;"
NODE_NAME = "cnn_mmio_interface@0x100000000"
OLD_NODE_NAME = "vga@0x100000000"
OLD_NODE_COMPAT = 'compatible = "csee4840,vga_ball-1.0";'
RSTMGR_NODE_NAME = "rstmgr@0xffd05000"
RSTMGR_PHANDLE = 0x29
MIN_BASE_DTS_BYTES = 4096

FPGA_BRIDGE_RESETS = (
    ("fpgabridge@0", "hps2fpga", 0x60),
    ("fpgabridge@1", "lwhps2fpga", 0x61),
    ("fpgabridge@2", "fpga2hps", 0x62),
)


def find_matching_brace(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    escape = False
    i = open_index
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise ValueError("unmatched brace while scanning DTS")


def find_enclosing_node_open(text: str, inner_index: int) -> int:
    open_index = text.rfind("{", 0, inner_index)
    if open_index == -1:
        raise ValueError("could not find enclosing node opening brace")
    return open_index


def find_node_block_containing(text: str, required_fragments: tuple[str, ...]) -> tuple[int, int]:
    start = text.find(required_fragments[0])
    while start != -1:
        open_index = find_enclosing_node_open(text, start)
        close_index = find_matching_brace(text, open_index)
        block = text[open_index:close_index]
        if all(fragment in block for fragment in required_fragments):
            return open_index, close_index
        start = text.find(required_fragments[0], start + 1)
    joined = ", ".join(required_fragments)
    raise ValueError(f"could not find node containing: {joined}")


def find_named_node_block(text: str, node_name: str) -> tuple[int, int]:
    node_pos = text.find(node_name)
    if node_pos == -1:
        raise ValueError(f"could not find node named {node_name}")
    open_index = text.find("{", node_pos)
    if open_index == -1:
        raise ValueError(f"could not find opening brace for {node_name}")
    close_index = find_matching_brace(text, open_index)
    return open_index, close_index


def remove_named_child(block: str, node_name: str, compat_text: str) -> str:
    node_pos = block.find(node_name)
    if node_pos == -1:
        return block
    compat_pos = block.find(compat_text, node_pos)
    if compat_pos == -1:
        return block
    open_index = block.find("{", node_pos)
    if open_index == -1:
        raise ValueError(f"could not find opening brace for {node_name}")
    close_index = find_matching_brace(block, open_index)

    line_start = block.rfind("\n", 0, open_index)
    line_start = 0 if line_start == -1 else line_start + 1

    line_end = close_index + 1
    if line_end < len(block) and block[line_end] == ";":
        line_end += 1
    while line_end < len(block) and block[line_end] in "\r\n\t ":
        if block[line_end] == "\n":
            line_end += 1
            break
        line_end += 1
    return block[:line_start] + block[line_end:]


def node_text(indent: str) -> str:
    return (
        f"{indent}{NODE_NAME} {{\n"
        f'{indent}\tcompatible = "csee4840,cnn-mmio-interface";\n'
        f"{indent}\treg = <0x1 0x0 0x00200000>;\n"
        f'{indent}\tlabel = "cnn_mmio_interface";\n'
        f'{indent}\tstatus = "okay";\n'
        f"{indent}}};\n"
    )


def bridge_reset_text(indent: str, name: str, reset_id: int) -> str:
    return (
        f'{indent}reset-names = "{name}";\n'
        f"{indent}resets = <0x{RSTMGR_PHANDLE:x} 0x{reset_id:x}>;\n"
    )


def patch_bridge_bus(text: str) -> str:
    open_index, close_index = find_node_block_containing(
        text,
        (BRIDGE_BUS_COMPAT, BRIDGE_BUS_REG_NAMES, BRIDGE_BUS_RANGES),
    )
    block = text[open_index:close_index]
    block = remove_named_child(block, OLD_NODE_NAME, OLD_NODE_COMPAT)
    if NODE_NAME not in block:
        block = block.rstrip() + "\n\n" + node_text("\t\t\t")
    return text[:open_index] + block + text[close_index:]


def patch_rstmgr_phandle(text: str) -> str:
    open_index, close_index = find_named_node_block(text, RSTMGR_NODE_NAME)
    block = text[open_index:close_index]
    if "phandle =" in block:
        return text
    addition = (
        f"\t\t\tlinux,phandle = <0x{RSTMGR_PHANDLE:x}>;\n"
        f"\t\t\tphandle = <0x{RSTMGR_PHANDLE:x}>;\n"
    )
    block = block.rstrip() + "\n\n" + addition + "\t\t"
    return text[:open_index] + block + text[close_index:]


def patch_fpga_bridge_resets(text: str) -> str:
    updated = text
    for node_name, reset_name, reset_id in FPGA_BRIDGE_RESETS:
        open_index, close_index = find_named_node_block(updated, node_name)
        block = updated[open_index:close_index]
        if "resets =" in block:
            continue
        block = block.rstrip() + "\n\n" + bridge_reset_text("\t\t\t", reset_name, reset_id) + "\t\t"
        updated = updated[:open_index] + block + updated[close_index:]
    return updated


def validate_base_dts(text: str, source: Path) -> None:
    problems = []
    if len(text) < MIN_BASE_DTS_BYTES:
        problems.append(
            f"input DTS is only {len(text)} bytes; this is too small to be a full boot DTS"
        )
    if "/dts-v1/" not in text:
        problems.append('missing "/dts-v1/" header')
    if "sopc@0" not in text:
        problems.append('missing "sopc@0" node')
    if LW_BRIDGE_COMPAT not in text:
        problems.append(f'missing bridge compatible "{LW_BRIDGE_COMPAT}"')
    if BRIDGE_BUS_REG_NAMES not in text:
        problems.append('missing simple-bus bridge node with "axi_h2f_lw" reg-names')
    if "model" not in text or "compatible" not in text:
        problems.append("missing normal root model/compatible properties")

    if problems:
        joined = "\n- ".join(problems)
        raise ValueError(
            f"{source} does not look like a complete bootable SocFPGA DTS:\n- {joined}"
        )


def patch_text(text: str) -> str:
    updated = patch_bridge_bus(text)
    updated = patch_rstmgr_phandle(updated)
    updated = patch_fpga_bridge_resets(updated)
    return updated


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch a SocFPGA DTS for the de1_soc cnn_mmio_interface"
    )
    parser.add_argument("input", type=Path, help="base input DTS")
    parser.add_argument("output", type=Path, help="patched output DTS")
    args = parser.parse_args()

    src = args.input.read_text(encoding="utf-8")
    validate_base_dts(src, args.input)
    patched = patch_text(src)
    args.output.write_text(patched, encoding="utf-8", newline="\n")

    if patched == src:
        print("No change needed; node already present.")
    else:
        print(f"Patched {args.output} with {NODE_NAME}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
