#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INPUT_CMD="${PROJECT_DIR}/uboot/boot.cmd"
OUTPUT_SCR="${PROJECT_DIR}/out/boot.scr"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --input <file>    U-Boot script source (boot.cmd)
  --output <file>   U-Boot script binary (boot.scr)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT_CMD="$2"
            shift 2
            ;;
        --output)
            OUTPUT_SCR="$2"
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

if ! command -v mkimage >/dev/null 2>&1; then
    echo "mkimage not found. Install u-boot-tools." >&2
    exit 1
fi

if [[ ! -f "${INPUT_CMD}" ]]; then
    echo "Input script not found: ${INPUT_CMD}" >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_SCR}")"

mkimage -A arm64 -T script -C none \
    -n "RK3576 EVB1 V10 A/B boot script" \
    -d "${INPUT_CMD}" "${OUTPUT_SCR}"

echo "Generated ${OUTPUT_SCR}"
