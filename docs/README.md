# Documentation Index

This directory is the cleaned-up teammate documentation set for the current
`submission` branch.

The goal is:

- keep repo root cleaner
- put the high-level explanations in one place
- separate "how to run it" from "why it is built this way"

## Chinese Companion Docs

Core teammate-facing docs also have Chinese companion versions under:

- [zh/README.md](zh/README.md)

The Chinese set also includes a short teammate-forwardable timing summary:

- [zh/FMAX_TEAMMATE_BRIEF.md](zh/FMAX_TEAMMATE_BRIEF.md)

Use the Chinese set for onboarding and design explanation. Use the English
files as the canonical command/reference set if you need to cross-check wording.

## Read In This Order

1. [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
   Cross-platform setup, host-role expectations, and first checks
2. [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
   Practical rebuild / program / recover / validate steps
3. [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
   Which directories and files own which part of the flow
4. [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
   Detailed runtime path from browser upload to FPGA inference and back
5. [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
   32-bit MMIO map, register meanings, scratchpad layout, and transfer rules

## If You Need A Specific Topic

### "I just need to get it running"

- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [../web_demo/README.md](../web_demo/README.md)
- [../de1_soc/README.md](../de1_soc/README.md)

### "I need to understand which file does what"

- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)

### "I need the exact software-to-hardware data path"

- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)

### "I need the MMIO map / address construction / register map"

- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)

### "I need build artifacts, model size, resources, and timing numbers"

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)

### "I need to know what RTL changes were made to improve Fmax"

- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)

### "I need model/task semantics or current model diagnostics"

- [DATASET_GUIDE.md](DATASET_GUIDE.md)
- [MODEL_DIAGNOSTICS.md](MODEL_DIAGNOSTICS.md)
- [PROJECT_STATUS_AND_PLAN.md](PROJECT_STATUS_AND_PLAN.md)

## Board-Specific Supporting Docs

- [../de1_soc/README.md](../de1_soc/README.md)
- [../de1_soc/DEVELOPMENT_MAINLINE.md](../de1_soc/DEVELOPMENT_MAINLINE.md)
- [../de1_soc/BOARD_TEST_PLAN.md](../de1_soc/BOARD_TEST_PLAN.md)
- [../de1_soc/FILE_INDEX.md](../de1_soc/FILE_INDEX.md)
- [../de1_soc/device_tree/README.md](../de1_soc/device_tree/README.md)

## Data / Model / Demo Supporting Docs

- [../Golden-Module/README.md](../Golden-Module/README.md)
- [../web_demo/README.md](../web_demo/README.md)
- [../test_data/README.md](../test_data/README.md)

## Legacy Material

Legacy materials are still in the repository for reference, but they are no
longer part of the main navigation path. Most of them were moved under:

- `archive_unused/`

Treat them as historical reference, not as the main submission flow.
