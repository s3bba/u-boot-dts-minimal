#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${PROJECT_DIR}/config/debootstrap-trixie-arm64.env"
APT_SOURCES="${PROJECT_DIR}/config/apt-sources-trixie.list"
PACKAGE_LIST="${PROJECT_DIR}/config/packages-trixie-base.list"
POST_INSTALL_DIR="${PROJECT_DIR}/rootfs-post-install.d"
ROOTFS_DIR="${PROJECT_DIR}/out/rootfs"
ROOTFS_TARBALL="${PROJECT_DIR}/out/rootfs.tar"
FORCE=0
MAKE_TARBALL=1

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --config <file>            debootstrap env config
  --apt-sources <file>       apt sources.list template
  --package-list <file>      package list (one package per line)
  --post-install-dir <dir>   hook directory (*.sh)
  --rootfs-dir <dir>         rootfs output directory
  --rootfs-tarball <file>    rootfs tarball output path
  --no-tarball               skip generating tarball
  --force                    remove existing rootfs before build
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --apt-sources)
            APT_SOURCES="$2"
            shift 2
            ;;
        --package-list)
            PACKAGE_LIST="$2"
            shift 2
            ;;
        --post-install-dir)
            POST_INSTALL_DIR="$2"
            shift 2
            ;;
        --rootfs-dir)
            ROOTFS_DIR="$2"
            shift 2
            ;;
        --rootfs-tarball)
            ROOTFS_TARBALL="$2"
            shift 2
            ;;
        --no-tarball)
            MAKE_TARBALL=0
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Config file not found: ${CONFIG_FILE}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
DEBIAN_ARCH="${DEBIAN_ARCH:-arm64}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_COMPONENTS="${DEBIAN_COMPONENTS:-main,contrib,non-free-firmware}"
DEBOOTSTRAP_VARIANT="${DEBOOTSTRAP_VARIANT:-minbase}"
HOSTNAME="${HOSTNAME:-rk3576}"

for tool in debootstrap chroot install; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Missing required tool: ${tool}" >&2
        exit 1
    fi
done

if [[ "${EUID}" -eq 0 ]]; then
    AS_ROOT=()
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "This script needs root privileges (run as root or install sudo)." >&2
        exit 1
    fi
    AS_ROOT=(sudo)
fi

run_root() {
    "${AS_ROOT[@]}" "$@"
}

if [[ -e "${ROOTFS_DIR}" ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
        run_root rm -rf "${ROOTFS_DIR}"
    else
        echo "Rootfs directory already exists: ${ROOTFS_DIR}" >&2
        echo "Use --force to remove it." >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "${ROOTFS_DIR}")" "$(dirname "${ROOTFS_TARBALL}")"

run_root debootstrap \
    --arch="${DEBIAN_ARCH}" \
    --foreign \
    --components="${DEBIAN_COMPONENTS}" \
    --variant="${DEBOOTSTRAP_VARIANT}" \
    "${DEBIAN_SUITE}" "${ROOTFS_DIR}" "${DEBIAN_MIRROR}"

USE_QEMU=0
if [[ "${DEBIAN_ARCH}" = "arm64" && "$(uname -m)" != "aarch64" ]]; then
    if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
        echo "Need qemu-aarch64-static for foreign-arm64 second stage." >&2
        exit 1
    fi
    run_root install -m 0755 "$(command -v qemu-aarch64-static)" \
        "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"
    USE_QEMU=1
fi

chroot_run() {
    if [[ "${USE_QEMU}" -eq 1 ]]; then
        run_root chroot "${ROOTFS_DIR}" /usr/bin/qemu-aarch64-static "$@"
    else
        run_root chroot "${ROOTFS_DIR}" "$@"
    fi
}

if [[ "${USE_QEMU}" -eq 1 ]]; then
    # /debootstrap/debootstrap is a shell script, so run it via /bin/sh under qemu.
    chroot_run /bin/sh /debootstrap/debootstrap --second-stage
else
    chroot_run /debootstrap/debootstrap --second-stage
fi

if [[ ! -f "${APT_SOURCES}" ]]; then
    echo "APT sources file not found: ${APT_SOURCES}" >&2
    exit 1
fi

if [[ ! -f "${PACKAGE_LIST}" ]]; then
    echo "Package list not found: ${PACKAGE_LIST}" >&2
    exit 1
fi

run_root install -m 0644 "${APT_SOURCES}" "${ROOTFS_DIR}/etc/apt/sources.list"

TMP_HOSTNAME="$(mktemp)"
printf '%s\n' "${HOSTNAME}" > "${TMP_HOSTNAME}"
run_root install -m 0644 "${TMP_HOSTNAME}" "${ROOTFS_DIR}/etc/hostname"
rm -f "${TMP_HOSTNAME}"

if [[ -f /etc/resolv.conf ]]; then
    run_root install -m 0644 /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
fi

declare -a PACKAGES=()
while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line%${line##*[![:space:]]}}"
    line="${line#${line%%[![:space:]]*}}"
    if [[ -n "${line}" ]]; then
        PACKAGES+=("${line}")
    fi
done < "${PACKAGE_LIST}"

chroot_run /usr/bin/apt-get update

if [[ "${#PACKAGES[@]}" -gt 0 ]]; then
    chroot_run /usr/bin/env DEBIAN_FRONTEND=noninteractive \
        /usr/bin/apt-get install -y --no-install-recommends "${PACKAGES[@]}"
fi

if [[ -d "${POST_INSTALL_DIR}" ]]; then
    shopt -s nullglob
    for hook in "${POST_INSTALL_DIR}"/*.sh; do
        echo "Running post-install hook: ${hook}"
        run_root env ROOTFS_DIR="${ROOTFS_DIR}" bash "${hook}" "${ROOTFS_DIR}"
    done
    shopt -u nullglob
fi

chroot_run /usr/bin/apt-get clean
run_root rm -rf "${ROOTFS_DIR}/var/lib/apt/lists"/*

if [[ "${USE_QEMU}" -eq 1 ]]; then
    run_root rm -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"
fi

if [[ "${MAKE_TARBALL}" -eq 1 ]]; then
    run_root tar -C "${ROOTFS_DIR}" --xattrs --acls -cpf "${ROOTFS_TARBALL}" .
    echo "Created rootfs tarball: ${ROOTFS_TARBALL}"
fi

echo "Rootfs ready at: ${ROOTFS_DIR}"
