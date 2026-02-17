#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

KERNEL_REPO="https://github.com/rockchip-linux/kernel.git"
KERNEL_BRANCH="develop-6.1"
KERNEL_SRC="${PROJECT_DIR}/work/kernel"
KERNEL_BUILD="${PROJECT_DIR}/out/kernel-build"
KERNEL_OUT="${PROJECT_DIR}/out/kernel"
DEFCONFIG="rockchip_defconfig"
DTB_TARGET="rockchip/rk3576-evb1-v10.dtb"
BOARD_DTS_OVERRIDE=""
CROSS_COMPILE="aarch64-linux-gnu-"
JOBS="$(nproc)"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --repo <url>             Kernel git repository
  --branch <name>          Kernel branch/tag (default: ${KERNEL_BRANCH})
  --src <dir>              Kernel source directory
  --build-dir <dir>        Kernel build output directory
  --out-dir <dir>          Artifact output directory
  --defconfig <name>       Kernel defconfig (default: ${DEFCONFIG})
  --dtb <path>             DTB target under arch/arm64/boot/dts
  --board-dts <file>       Override board DTS before build
  --cross <prefix>         Cross compiler prefix (default: ${CROSS_COMPILE})
  --jobs <n>               Parallel build jobs
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            KERNEL_REPO="$2"
            shift 2
            ;;
        --branch)
            KERNEL_BRANCH="$2"
            shift 2
            ;;
        --src)
            KERNEL_SRC="$2"
            shift 2
            ;;
        --build-dir)
            KERNEL_BUILD="$2"
            shift 2
            ;;
        --out-dir)
            KERNEL_OUT="$2"
            shift 2
            ;;
        --defconfig)
            DEFCONFIG="$2"
            shift 2
            ;;
        --dtb)
            DTB_TARGET="$2"
            shift 2
            ;;
        --board-dts)
            BOARD_DTS_OVERRIDE="$2"
            shift 2
            ;;
        --cross)
            CROSS_COMPILE="$2"
            shift 2
            ;;
        --jobs)
            JOBS="$2"
            shift 2
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

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo "Missing cross compiler: ${CROSS_COMPILE}gcc" >&2
    exit 1
fi

mkdir -p "$(dirname "${KERNEL_SRC}")" "${KERNEL_BUILD}" "${KERNEL_OUT}"

if [[ ! -d "${KERNEL_SRC}/.git" ]]; then
    git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
else
    git -C "${KERNEL_SRC}" fetch --depth 1 origin "${KERNEL_BRANCH}"
    git -C "${KERNEL_SRC}" checkout -q FETCH_HEAD
fi

if [[ -n "${BOARD_DTS_OVERRIDE}" ]]; then
    if [[ ! -f "${BOARD_DTS_OVERRIDE}" ]]; then
        echo "Board DTS override not found: ${BOARD_DTS_OVERRIDE}" >&2
        exit 1
    fi
    DTS_REL="${DTB_TARGET%.dtb}.dts"
    install -D -m 0644 "${BOARD_DTS_OVERRIDE}" \
        "${KERNEL_SRC}/arch/arm64/boot/dts/${DTS_REL}"
fi

make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" \
    ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" "${DEFCONFIG}"

make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" \
    ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" \
    -j "${JOBS}" Image modules dtbs

rm -rf "${KERNEL_OUT}/modules"
make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" \
    ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" \
    INSTALL_MOD_PATH="${KERNEL_OUT}/modules" modules_install

install -m 0644 "${KERNEL_BUILD}/arch/arm64/boot/Image" "${KERNEL_OUT}/Image"
install -m 0644 "${KERNEL_BUILD}/arch/arm64/boot/dts/${DTB_TARGET}" \
    "${KERNEL_OUT}/$(basename "${DTB_TARGET}")"

echo "Kernel artifacts ready in: ${KERNEL_OUT}"
