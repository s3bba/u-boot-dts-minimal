#!/usr/bin/env bash
set -euo pipefail

if ! command -v fw_setenv >/dev/null 2>&1; then
    echo "fw_setenv not found. Cannot mark slot successful." >&2
    exit 1
fi

slot="unknown"
if command -v fw_printenv >/dev/null 2>&1; then
    slot="$(fw_printenv -n active_slot 2>/dev/null || echo unknown)"
fi

fw_setenv upgrade_available 0
fw_setenv bootcount 0

echo "Marked slot ${slot} as healthy (upgrade_available=0, bootcount=0)"
