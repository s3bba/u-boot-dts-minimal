#!/usr/bin/env bash
set -euo pipefail

ROOTFS_DIR="${1:?Usage: $0 <rootfs-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

install -d -m 0755 \
    "${ROOTFS_DIR}/usr/local/sbin" \
    "${ROOTFS_DIR}/etc/systemd/system" \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants" \
    "${ROOTFS_DIR}/etc/systemd/system.conf.d"

install -m 0755 "${PROJECT_DIR}/scripts/switch-active-slot.sh" \
    "${ROOTFS_DIR}/usr/local/sbin/switch-active-slot"
install -m 0755 "${PROJECT_DIR}/scripts/mark-boot-success.sh" \
    "${ROOTFS_DIR}/usr/local/sbin/mark-boot-success"

install -m 0644 "${PROJECT_DIR}/config/fw_env.config" "${ROOTFS_DIR}/etc/fw_env.config"
install -m 0644 "${PROJECT_DIR}/config/systemd-watchdog.conf" \
    "${ROOTFS_DIR}/etc/systemd/system.conf.d/watchdog.conf"
install -m 0644 "${PROJECT_DIR}/config/ab-mark-good.service" \
    "${ROOTFS_DIR}/etc/systemd/system/ab-mark-good.service"

ln -sf ../ab-mark-good.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ab-mark-good.service"
