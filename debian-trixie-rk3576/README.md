# Debian 13 (Trixie) Build Kit for RK3576-EVB1-V10

This directory provides a reproducible build specification and automation scripts for a custom Debian 13 (Trixie) arm64 image with A/B rootfs redundancy on RK3576-EVB1-V10 (16 GiB eMMC).

It includes:
- Rockchip vendor Linux 6.1 kernel build script (Image + DTB + modules).
- Debian 13 rootfs generator using debootstrap with package and post-install injection.
- U-Boot A/B boot logic (`boot.cmd` -> `boot.scr`) with watchdog-aware fallback.
- 16 GiB eMMC image assembly script with Rockchip raw bootloader offsets.
- Shared persistent `config` and `logs` partitions and matching `/etc/fstab` template.

## Directory Layout

- `scripts/build-kernel.sh`: cross-compiles Rockchip vendor kernel 6.1 for RK3576.
- `scripts/build-rootfs.sh`: creates Debian 13 arm64 rootfs via debootstrap.
- `scripts/mk-boot-scr.sh`: compiles `uboot/boot.cmd` into `boot.scr`.
- `scripts/create-emmc-image.sh`: creates a flashable 16 GiB eMMC image.
- `scripts/switch-active-slot.sh`: userspace command to toggle/select A/B slot.
- `scripts/mark-boot-success.sh`: clears update-pending state after healthy boot.
- `config/debootstrap-trixie-arm64.env`: rootfs build knobs.
- `config/packages-trixie-base.list`: default package set (editable).
- `config/fstab.shared`: persistent mount config for `config`, `logs`, `data`.
- `config/rauc-system.conf`: RAUC A/B slot config.
- `config/fw_env.config`: `fw_printenv/fw_setenv` mapping for U-Boot env.
- `config/u-boot-ab.fragment`: U-Boot config fragment for bootcount + env.
- `uboot/boot.cmd`: U-Boot script source implementing A/B selection/fallback.
- `rootfs-post-install.d/*.sh`: default post-install hooks for rootfs customization.

## Host Requirements

Install on the build host (or use the provided Dockerfile):

- `debootstrap`, `qemu-user-static`, `binfmt-support`
- `gcc-aarch64-linux-gnu`, `bc`, `bison`, `flex`, `libssl-dev`, `libncurses-dev`
- `u-boot-tools`, `gdisk`, `e2fsprogs`, `dosfstools`, `parted`, `rsync`

## 16 GiB eMMC Layout

Rockchip raw bootloader areas are outside GPT:
- `idbloader.img` at LBA `64` (32 KiB)
- `u-boot.itb` at LBA `16384` (8 MiB)
- `trust.img` at LBA `24576` (12 MiB, optional per platform)

GPT starts at 16 MiB:

1. `uboot_env` 16 MiB (raw, non-filesystem, redundant env blobs)
2. `boot` 256 MiB (ext4: `Image`, `rk3576-evb1-v10.dtb`, `boot.scr`)
3. `rootfs_a` 5632 MiB (ext4)
4. `rootfs_b` 5632 MiB (ext4)
5. `config` 1024 MiB (ext4, persistent)
6. `logs` 1024 MiB (ext4, persistent)
7. `data` remaining capacity (ext4, persistent)

This satisfies the requested shared 1 GiB `config` and 1 GiB `logs` partitions and keeps A/B rootfs symmetric.

## U-Boot A/B and Fallback Logic

`uboot/boot.cmd` uses these variables:
- `active_slot`: `A` or `B`
- `upgrade_available`: set to `1` before first boot of a newly updated slot
- `bootcount`: incremented by U-Boot bootcount framework
- `bootcount_limit`: max failed boots before fallback (default `3`)

Flow:
1. If `upgrade_available=1` and `bootcount >= bootcount_limit`, U-Boot switches `active_slot` to the alternate slot, clears `upgrade_available`, resets `bootcount`, and saves env.
2. U-Boot boots kernel/DTB from `boot` partition and sets root to `PARTLABEL=rootfs_a` or `rootfs_b` based on `active_slot`.
3. On successful boot, userspace runs `mark-boot-success` (systemd oneshot) to clear `upgrade_available` and reset `bootcount`.

To support this, enable the options in `config/u-boot-ab.fragment` in your RK3576 U-Boot build.

## OTA Recommendation (RAUC)

RAUC is included as the OTA mechanism for atomic A/B rootfs updates:
- `config/rauc-system.conf` defines slot mapping to `rootfs_a` and `rootfs_b`.
- `activate-installed=false` keeps slot activation explicit and controlled by your A/B policy script.
- `statusfile` is placed on persistent `/config`.
- The active slot switch for next boot is controlled through U-Boot env (`switch-active-slot`).

Typical update flow:
1. Install RAUC bundle to inactive slot (`rauc install <bundle>`).
2. Set next boot slot and arm rollback (`switch-active-slot A|B|toggle`).
3. Reboot.
4. `mark-boot-success` runs after stable boot and confirms slot.

## Watchdog Integration

`rootfs-post-install.d/20-install-ab-watchdog.sh` installs:
- `/etc/systemd/system.conf.d/watchdog.conf` with `RuntimeWatchdogSec=30s`
- `ab-mark-good.service` to confirm healthy boot after 20s uptime

If userspace hangs and stops servicing watchdog, hardware reset occurs. Subsequent failed boots increase `bootcount`; U-Boot fallback logic switches slot at threshold.

## Quick Start

1) Build kernel and RK3576 DTB:

```bash
./debian-trixie-rk3576/scripts/build-kernel.sh \
  --board-dts ./rk3576-evb1-v10.dts
```

2) Build U-Boot boot script:

```bash
./debian-trixie-rk3576/scripts/mk-boot-scr.sh
```

3) Create Debian 13 rootfs (supports custom package and hook injection):

```bash
sudo ./debian-trixie-rk3576/scripts/build-rootfs.sh \
  --package-list ./debian-trixie-rk3576/config/packages-trixie-base.list \
  --post-install-dir ./debian-trixie-rk3576/rootfs-post-install.d
```

4) Assemble 16 GiB eMMC image:

```bash
sudo ./debian-trixie-rk3576/scripts/create-emmc-image.sh \
  --idbloader /path/to/idbloader.img \
  --uboot-itb /path/to/u-boot.itb \
  --trust /path/to/trust.img
```

Output image defaults to `debian-trixie-rk3576/out/rk3576-trixie-16g.img`.

## Notes

- `config/fw_env.config` assumes U-Boot env resides in GPT partition `uboot_env` with two 16 KiB redundant copies.
- Replace `/etc/rauc/keyring.pem` with your production signing keyring.
- If your Rockchip vendor trees use different branch or defconfig names, override options in the scripts via CLI flags.
