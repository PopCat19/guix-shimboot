# Guix-Shimboot

**UNTESTED PROOF-OF-CONCEPT — Do not expect this to boot yet.**

Port of [nixos-shimboot](https://github.com/PopCat19/nixos-shimboot) for GNU Guix System on ChromeOS hardware.

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| `modules/boards.scm` | Module loads ✓ | Needs guix-daemon to verify full build |
| `modules/config/*.scm` | Module loads ✓ | Needs guix-daemon to verify full build |
| `bootloader/bin/bootstrap.sh` | Syntax only | shellcheck clean, untested on real paths |
| `shimboot-core.patch` | Untested | Not applied to bootstrap.sh yet |
| End-to-end boot | **Not tested** | Needs hardware |

## Overview (Intended Behavior)

Guix-shimboot is a port of [nixos-shimboot](https://github.com/PopCat19/nixos-shimboot) for GNU Guix. It enables running a full Guix System on ChromeOS devices by:

1. Using the ChromeOS kernel from a SHIM partition
2. Booting via shimboot bootloader (pivot_root approach)
3. Mounting a vendor partition with harvested drivers/firmware
4. Starting Shepherd as PID 1

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     ChromeOS SHIM Kernel                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   bootstrap.sh (p3)                         │
│  • Scan for shimboot_rootfs:* partitions                    │
│  • Select rootfs + vendor partitions                        │
│  • pivot_root to /newroot                                   │
│  • exec /var/guix/profiles/system/init                      │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────────┐
│    p4 VENDOR  │   │  p5 ROOTFS    │   │    Shepherd       │
│               │   │               │   │                   │
│ lib/modules/  │──▶│ /var/guix/    │   │ • vendor-mount    │
│ lib/firmware/ │──▶│ profiles/     │   │ • module-loader   │
│ modprobe.d/   │   │ system        │   │ • network-manager│
└───────────────┘   └───────────────┘   └───────────────────┘
```

## Components

| Directory | Purpose |
|-----------|---------|
| `boards.scm` | Hardware database per Chromebook model |
| `config/` | Guix operating-system and services |
| `bootloader/bin/` | Generation detection for Guix |
| `shimboot-core/` | Shared components (git submodule) |

## Prerequisites

1. ChromeOS device with supported board
2. SHIM image for your board
3. USB drive for initial boot
4. `nonguix` channel for firmware (proprietary WiFi/BT)

## Quick Start

```bash
# Clone with submodule
git clone --recurse-submodules https://github.com/PopCat19/guix-shimboot
cd guix-shimboot

# Add nonguix channel
guix pull -C channels.scm

# Build system config (needs guix-daemon running)
guix system build -L ./modules modules/config/system.scm

# Build image
./tools/build/assemble-guix-image.sh --board dedede
```

## Board Support

| Board | CPU | WiFi | Status |
|-------|-----|------|--------|
| dedede | Intel | AX201/AX210 | Planned |
| octopus | Intel | AX200 | Planned |
| zork | AMD | MT7921E | Planned |
| grunt | AMD | Realtek | Planned |
| jacuzzi | ARM | MediaTek | Planned |

## Differences from NixOS-Shimboot

| Aspect | NixOS | Guix |
|--------|-------|------|
| Init | systemd (needs patch) | Shepherd (no patch) |
| Config | `configuration.nix` | `config.scm` |
| Generations | `/nix/var/nix/profiles/system` | `/var/guix/profiles/system` |
| Firmware | `hardware.enableRedistributableFirmware` | nonguix channel |
| Services | systemd units | Shepherd services |

## License

MIT