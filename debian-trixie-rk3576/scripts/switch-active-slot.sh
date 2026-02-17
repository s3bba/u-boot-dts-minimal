#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 [A|B|toggle]

Without an argument, the slot is toggled.
The selected slot is used on next boot.
EOF
}

target="${1:-toggle}"

if [[ "${target}" = "-h" || "${target}" = "--help" ]]; then
    usage
    exit 0
fi

if ! command -v fw_setenv >/dev/null 2>&1; then
    echo "fw_setenv not found. Install u-boot-tools/libubootenv-tool." >&2
    exit 1
fi

current="A"
if command -v fw_printenv >/dev/null 2>&1; then
    current="$(fw_printenv -n active_slot 2>/dev/null || echo A)"
fi

case "${target}" in
    A|a)
        next="A"
        ;;
    B|b)
        next="B"
        ;;
    toggle)
        if [[ "${current}" = "A" ]]; then
            next="B"
        else
            next="A"
        fi
        ;;
    *)
        echo "Invalid slot selection: ${target}" >&2
        usage
        exit 1
        ;;
esac

fw_setenv active_slot "${next}"
fw_setenv upgrade_available 1
fw_setenv bootcount 0

echo "Current slot: ${current}"
echo "Next boot slot: ${next}"
echo "Marked as upgrade_available=1 for rollback protection"
