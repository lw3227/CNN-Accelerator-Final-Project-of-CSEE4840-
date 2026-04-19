# Device Tree Patch Path

This directory provides a practical fallback for board bring-up when `sopc2dts`
is not available on the host.

For the current `de1_soc/soc_system.sopcinfo`, the important MMIO facts are:

- bridge: lightweight HPS-to-FPGA bridge
- HPS-visible base: `0xff200000`
- child offset inside bridge: `0x0`
- span: `0x00200000`

The goal is to add a `cnn_mmio_interface@0` node under the DTS node whose
`compatible` is `altr,socfpga-lwhps2fpga-bridge`.

Important:

- This flow must start from a complete bootable SocFPGA base DTB/DTS.
- Do not feed it a tiny hand-written snippet or a partial bridge fragment.
- The helper now refuses very small DTS/DTB outputs because those are not safe
  to flash as boot artifacts.

## Files

- `patch_socfpga_dts.py`: inserts the node into an existing SocFPGA base DTS
- `cnn_mmio_interface_node.dtsi`: the node body being inserted

## Suggested host flow

If you already have a bootable base DTB from the board or SD card:

```bash
wsl.exe bash -lc '
  set -e
  cd /mnt/c/Users/KOUYO/CNN-Accelerator-Final-Project-of-CSEE4840-
  dtc -I dtb -O dts -o /tmp/base_socfpga.dts path/to/base.dtb
  python3 de1_soc/device_tree/patch_socfpga_dts.py \
    /tmp/base_socfpga.dts \
    /tmp/soc_system_patched.dts
  dtc -I dts -O dtb -o /tmp/soc_system.dtb /tmp/soc_system_patched.dts
'
```

Then replace the board boot artifact with the new `soc_system.dtb` together
with the matching `soc_system.rbf`, reboot, and re-run:

```bash
./tools/hps_mmio_status 0xff200000
```

On a Windows host with WSL installed, you can use the helper script instead:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/build_soc_system_dtb.ps1 `
  -BaseDtb path\to\base.dtb
```

Or if you already have a base DTS:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/build_soc_system_dtb.ps1 `
  -BaseDts path\to\base.dts
```

The outputs will be written under `de1_soc/device_tree/build/`:

- `base_from_dtb.dts` when starting from a DTB
- `soc_system_patched.dts`
- `soc_system.dtb`

If the helper throws a "too small to be a full boot DTS/DTB" error, that is a
safety stop. It means the input is not a real boot device tree and must not be
written to the SD boot partition.

## Safe Staging To SD Boot Partition

If the SD boot partition is mounted on the host as a drive letter, stage the
new artifacts with:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/stage_boot_partition.ps1 `
  -BootDriveLetter X
```

That script:

- refuses DTBs smaller than 4096 bytes
- backs up the current `soc_system.dtb` and `soc_system.rbf`
- copies in the new pair

## Recovery

If the board stops booting after a DTB replacement:

1. Mount the SD card boot partition on the host.
2. Restore the last known-good `soc_system.dtb`.
3. Keep the current `soc_system.rbf` only if the board previously booted with
   it; otherwise restore the pair together.
4. Reboot the board and verify serial boot logs return before trying another
   DTB.

If backups are already present on the mounted boot partition, restore them with:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/restore_boot_partition.ps1 `
  -BootDriveLetter X
```

Only resume MMIO bring-up after the board is booting normally again.

## Linux-side smell test

After reboot, the active tree should expose a child node for the MMIO block
under `/proc/device-tree/sopc@0/...` instead of only the old `vga@...` node.
