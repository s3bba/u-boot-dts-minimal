#!/usr/bin/env bash
set -euo pipefail

ROOTFS_DIR="${1:?Usage: $0 <rootfs-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

install -d -m 0755 "${ROOTFS_DIR}/config" "${ROOTFS_DIR}/var/log" "${ROOTFS_DIR}/data"
install -m 0644 "${PROJECT_DIR}/config/fstab.shared" "${ROOTFS_DIR}/etc/fstab"
