#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_PATH="${PROJECT_DIR}/out/rk3576-trixie-16g.img"
IMAGE_SIZE="16GiB"
ROOTFS_A_DIR="${PROJECT_DIR}/out/rootfs"
ROOTFS_B_DIR="${ROOTFS_A_DIR}"
BOOT_DIR="${PROJECT_DIR}/out/kernel"
BOOT_SCR="${PROJECT_DIR}/out/boot.scr"
DTB_FILE="rk3576-evb1-v10.dtb"
IDBLOADER_IMG=""
UBOOT_ITB=""
TRUST_IMG=""
FORCE=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --image <file>         Output eMMC image path
  --size <size>          Image size (default: ${IMAGE_SIZE})
  --rootfs-a <dir>       Rootfs content for slot A
  --rootfs-b <dir>       Rootfs content for slot B (default: same as A)
  --boot-dir <dir>       Directory with Image and DTB
  --boot-scr <file>      U-Boot boot.scr path
  --dtb-file <name>      DTB filename under boot dir
  --idbloader <file>     idbloader.img to write at LBA 64
  --uboot-itb <file>     u-boot.itb to write at LBA 16384
  --trust <file>         trust.img to write at LBA 24576 (optional)
  --force                Overwrite existing output image
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)
            IMAGE_PATH="$2"
            shift 2
            ;;
        --size)
            IMAGE_SIZE="$2"
            shift 2
            ;;
        --rootfs-a)
            ROOTFS_A_DIR="$2"
            shift 2
            ;;
        --rootfs-b)
            ROOTFS_B_DIR="$2"
            shift 2
            ;;
        --boot-dir)
            BOOT_DIR="$2"
            shift 2
            ;;
        --boot-scr)
            BOOT_SCR="$2"
            shift 2
            ;;
        --dtb-file)
            DTB_FILE="$2"
            shift 2
            ;;
        --idbloader)
            IDBLOADER_IMG="$2"
            shift 2
            ;;
        --uboot-itb)
            UBOOT_ITB="$2"
            shift 2
            ;;
        --trust)
            TRUST_IMG="$2"
            shift 2
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

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

for tool in sgdisk losetup mkfs.ext4 mount umount mountpoint rsync dd truncate; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Missing required tool: ${tool}" >&2
        exit 1
    fi
done

if [[ ! -d "${ROOTFS_A_DIR}" ]]; then
    echo "Rootfs A directory not found: ${ROOTFS_A_DIR}" >&2
    exit 1
fi

if [[ ! -d "${ROOTFS_B_DIR}" ]]; then
    echo "Rootfs B directory not found: ${ROOTFS_B_DIR}" >&2
    exit 1
fi

if [[ ! -f "${BOOT_DIR}/Image" ]]; then
    echo "Missing kernel Image in: ${BOOT_DIR}" >&2
    exit 1
fi

if [[ ! -f "${BOOT_DIR}/${DTB_FILE}" ]]; then
    echo "Missing DTB file: ${BOOT_DIR}/${DTB_FILE}" >&2
    exit 1
fi

if [[ ! -f "${BOOT_SCR}" ]]; then
    echo "Missing boot.scr: ${BOOT_SCR}" >&2
    exit 1
fi

if [[ -n "${IDBLOADER_IMG}" && ! -f "${IDBLOADER_IMG}" ]]; then
    echo "idbloader file not found: ${IDBLOADER_IMG}" >&2
    exit 1
fi

if [[ -n "${UBOOT_ITB}" && ! -f "${UBOOT_ITB}" ]]; then
    echo "u-boot.itb file not found: ${UBOOT_ITB}" >&2
    exit 1
fi

if [[ -n "${TRUST_IMG}" && ! -f "${TRUST_IMG}" ]]; then
    echo "trust.img file not found: ${TRUST_IMG}" >&2
    exit 1
fi

mkdir -p "$(dirname "${IMAGE_PATH}")"

if [[ -e "${IMAGE_PATH}" ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
        rm -f "${IMAGE_PATH}"
    else
        echo "Image already exists: ${IMAGE_PATH}" >&2
        echo "Use --force to overwrite." >&2
        exit 1
    fi
fi

truncate -s "${IMAGE_SIZE}" "${IMAGE_PATH}"

sgdisk --zap-all "${IMAGE_PATH}"
sgdisk -n 1:32768:+16M -t 1:8300 -c 1:uboot_env "${IMAGE_PATH}"
sgdisk -n 2:0:+256M -t 2:8300 -c 2:boot "${IMAGE_PATH}"
sgdisk -n 3:0:+5632M -t 3:8300 -c 3:rootfs_a "${IMAGE_PATH}"
sgdisk -n 4:0:+5632M -t 4:8300 -c 4:rootfs_b "${IMAGE_PATH}"
sgdisk -n 5:0:+1024M -t 5:8300 -c 5:config "${IMAGE_PATH}"
sgdisk -n 6:0:+1024M -t 6:8300 -c 6:logs "${IMAGE_PATH}"
sgdisk -n 7:0:0 -t 7:8300 -c 7:data "${IMAGE_PATH}"

LOOPDEV=""
MNT_DIR="$(mktemp -d)"

cleanup() {
    set +e
    for mountpoint_path in "${MNT_DIR}/boot" "${MNT_DIR}/rootfs_a" "${MNT_DIR}/rootfs_b"; do
        if mountpoint -q "${mountpoint_path}"; then
            umount "${mountpoint_path}"
        fi
    done
    if [[ -n "${LOOPDEV}" ]]; then
        losetup -d "${LOOPDEV}"
    fi
    rm -rf "${MNT_DIR}"
}

trap cleanup EXIT

LOOPDEV="$(losetup --find --show --partscan "${IMAGE_PATH}")"

mkfs.ext4 -F -L boot "${LOOPDEV}p2"
mkfs.ext4 -F -L rootfs_a "${LOOPDEV}p3"
mkfs.ext4 -F -L rootfs_b "${LOOPDEV}p4"
mkfs.ext4 -F -L config "${LOOPDEV}p5"
mkfs.ext4 -F -L logs "${LOOPDEV}p6"
mkfs.ext4 -F -L data "${LOOPDEV}p7"

mkdir -p "${MNT_DIR}/boot" "${MNT_DIR}/rootfs_a" "${MNT_DIR}/rootfs_b"

mount "${LOOPDEV}p3" "${MNT_DIR}/rootfs_a"
rsync -aHAX --numeric-ids "${ROOTFS_A_DIR}/" "${MNT_DIR}/rootfs_a/"
umount "${MNT_DIR}/rootfs_a"

mount "${LOOPDEV}p4" "${MNT_DIR}/rootfs_b"
rsync -aHAX --numeric-ids "${ROOTFS_B_DIR}/" "${MNT_DIR}/rootfs_b/"
umount "${MNT_DIR}/rootfs_b"

mount "${LOOPDEV}p2" "${MNT_DIR}/boot"
install -m 0644 "${BOOT_DIR}/Image" "${MNT_DIR}/boot/Image"
install -m 0644 "${BOOT_DIR}/${DTB_FILE}" "${MNT_DIR}/boot/${DTB_FILE}"
install -m 0644 "${BOOT_SCR}" "${MNT_DIR}/boot/boot.scr"
sync
umount "${MNT_DIR}/boot"

if command -v mkenvimage >/dev/null 2>&1; then
    TMP_ENV="$(mktemp)"
    mkenvimage -s 0x4000 -o "${TMP_ENV}" "${PROJECT_DIR}/config/uboot-rk3576-ab.env"
    dd if="${TMP_ENV}" of="${LOOPDEV}p1" conv=notrunc status=none
    dd if="${TMP_ENV}" of="${LOOPDEV}p1" bs=1 seek=$((0x4000)) conv=notrunc status=none
    rm -f "${TMP_ENV}"
else
    echo "mkenvimage not found, skipping initial U-Boot env preseed"
fi

sync

if [[ -n "${IDBLOADER_IMG}" ]]; then
    dd if="${IDBLOADER_IMG}" of="${IMAGE_PATH}" seek=64 conv=notrunc,fsync status=none
fi

if [[ -n "${UBOOT_ITB}" ]]; then
    dd if="${UBOOT_ITB}" of="${IMAGE_PATH}" seek=16384 conv=notrunc,fsync status=none
fi

if [[ -n "${TRUST_IMG}" ]]; then
    dd if="${TRUST_IMG}" of="${IMAGE_PATH}" seek=24576 conv=notrunc,fsync status=none
fi

echo "Created image: ${IMAGE_PATH}"
