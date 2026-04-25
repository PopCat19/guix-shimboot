# Guix-Shimboot Context

UNTESTED PROOF-OF-CONCEPT

Proof-of-concept for running Guix System on ChromeOS hardware.

## Structure

- `boards/` — Hardware database per Chromebook model
- `config/` — Guix operating-system and service definitions
- `bootloader/bin/` — Guix generation detection functions
- `tools/build/` — Image assembly script
- `tools/lib/` — Shared shell libraries (logging, fallback)
- `shimboot-core/` — Shared nixos-shimboot components (submodule)

## Vocabulary

- **Board** — ChromeOS hardware identifier (dedede, octopus, zork, etc.)
- **Vendor Partition** — Separate partition holding harvested drivers/firmware
- **Generation** — Immutable system configuration snapshot
- **SHIM** — ChromeOS recovery image used for kernel extraction