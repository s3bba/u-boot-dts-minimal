#!/usr/bin/env bash
set -euo pipefail

ROOTFS_DIR="${1:?Usage: $0 <rootfs-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

install -d -m 0755 "${ROOTFS_DIR}/etc/rauc" "${ROOTFS_DIR}/config/rauc"
install -m 0644 "${PROJECT_DIR}/config/rauc-system.conf" "${ROOTFS_DIR}/etc/rauc/system.conf"
