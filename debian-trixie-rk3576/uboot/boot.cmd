if test -z "${devtype}"; then
    setenv devtype mmc
fi

if test -z "${devnum}"; then
    setenv devnum 0
fi

if test -z "${boot_partition}"; then
    setenv boot_partition 2
fi

if test -z "${active_slot}"; then
    setenv active_slot A
fi

if test -z "${upgrade_available}"; then
    setenv upgrade_available 0
fi

if test -z "${bootcount_limit}"; then
    setenv bootcount_limit 3
fi

if test -z "${bootcount}"; then
    setenv bootcount 0
fi

if test -z "${console}"; then
    setenv console ttyS2,1500000n8
fi

if test -z "${kernel_addr_r}"; then
    setenv kernel_addr_r 0x08200000
fi

if test -z "${fdt_addr_r}"; then
    setenv fdt_addr_r 0x0a100000
fi

if test "${upgrade_available}" = "1"; then
    if itest ${bootcount} -ge ${bootcount_limit}; then
        echo "A/B fallback: bootcount limit reached, switching slot"
        if test "${active_slot}" = "A"; then
            setenv active_slot B
        else
            setenv active_slot A
        fi
        setenv bootcount 0
        setenv upgrade_available 0
        saveenv
    fi
fi

if test "${active_slot}" = "A"; then
    setenv root_label rootfs_a
else
    setenv root_label rootfs_b
fi

setenv bootargs "console=${console} root=PARTLABEL=${root_label} rootwait rw fsck.repair=yes"

echo "Booting slot ${active_slot} from ${devtype} ${devnum}:${boot_partition}"
if ext4load ${devtype} ${devnum}:${boot_partition} ${kernel_addr_r} /Image; then
    if ext4load ${devtype} ${devnum}:${boot_partition} ${fdt_addr_r} /rk3576-evb1-v10.dtb; then
        booti ${kernel_addr_r} - ${fdt_addr_r}
    fi
fi

echo "Boot script failed"
reset
