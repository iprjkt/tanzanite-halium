#!/bin/sh

# Ensure wmt_drv and bt_drv_connac1x are loaded early so WMT/BT char devices exist
/usr/sbin/modprobe wmt_drv 2>/dev/null || true
/usr/sbin/modprobe bt_drv_connac1x 2>/dev/null || true
/usr/sbin/modprobe hci_vhci 2>/dev/null || true
/usr/sbin/modprobe bnep 2>/dev/null || true

# Doing a part of Android's first stage init.
mknod -m 666 "${LXC_ROOTFS_MOUNT}/dev/null" c 1 3 2>/dev/null || true
mknod -m 600 "${LXC_ROOTFS_MOUNT}/dev/kmsg" c 1 11 2>/dev/null || true
mknod -m 666 "${LXC_ROOTFS_MOUNT}/dev/random" c 1 8 2>/dev/null || true
mknod -m 666 "${LXC_ROOTFS_MOUNT}/dev/urandom" c 1 9 2>/dev/null || true

chmod 440 "${LXC_ROOTFS_MOUNT}/proc/cmdline" 2>/dev/null || true
touch "${LXC_ROOTFS_MOUNT}/dev/.coldboot_done" 2>/dev/null || true

# Ensure static WMT nodes exist
[ -e /dev/stpwmt ] || mknod -m 660 /dev/stpwmt c 190 0 2>/dev/null || true
if [ -f /sys/devices/virtual/stpbt/stpbt/dev ]; then
    btdevno=$(cat /sys/devices/virtual/stpbt/stpbt/dev)
    btmaj="${btdevno%:*}"
    btmin="${btdevno#*:}"
    rm -f /dev/stpbt
    mknod -m 666 /dev/stpbt c "$btmaj" "$btmin" 2>/dev/null || true
else
    [ -e /dev/stpbt ] || mknod -m 666 /dev/stpbt c 192 0 2>/dev/null || true
fi
[ -e /dev/stpgps ] || mknod -m 660 /dev/stpgps c 191 0 2>/dev/null || true
[ -e /dev/wmtdetect ] || mknod -m 660 /dev/wmtdetect c 154 0 2>/dev/null || true

# Check if wmtWifi is registered in sysfs and create node dynamically
if [ -f /sys/devices/virtual/wmtWifi/wmtWifi/dev ]; then
    devno=$(cat /sys/devices/virtual/wmtWifi/wmtWifi/dev)
    maj="${devno%:*}"
    min="${devno#*:}"
    rm -f /dev/wmtWifi
    mknod -m 666 /dev/wmtWifi c "$maj" "$min"
fi

chown 1000:1000 /dev/stpwmt /dev/stpgps /dev/wmtdetect /dev/hf_manager /dev/scp 2>/dev/null || true
chown 1002:1002 /dev/stpbt 2>/dev/null || true
chmod 666 /dev/stpbt /dev/hf_manager /dev/scp 2>/dev/null || true
[ -e /dev/wmtWifi ] && chown 1001:1001 /dev/wmtWifi 2>/dev/null || true
[ -e /dev/wmtWifi ] && chmod 666 /dev/wmtWifi 2>/dev/null || true

for dev in wmtWifi wmtdetect stpwmt stpbt stpgps mali0 ashmem ion pmsg0 hf_manager scp; do
    if [ -e "/dev/$dev" ]; then
        touch "${LXC_ROOTFS_MOUNT}/dev/$dev"
        mount --bind "/dev/$dev" "${LXC_ROOTFS_MOUNT}/dev/$dev"
    fi
done

[ -e "${LXC_ROOTFS_MOUNT}/dev/wmtWifi" ] && chmod 666 "${LXC_ROOTFS_MOUNT}/dev/wmtWifi" 2>/dev/null || true
[ -e "${LXC_ROOTFS_MOUNT}/dev/hf_manager" ] && chmod 666 "${LXC_ROOTFS_MOUNT}/dev/hf_manager" 2>/dev/null || true
[ -e "${LXC_ROOTFS_MOUNT}/dev/scp" ] && chmod 666 "${LXC_ROOTFS_MOUNT}/dev/scp" 2>/dev/null || true
chmod 660 "${LXC_ROOTFS_MOUNT}/dev/stpwmt" 2>/dev/null || true

mkdir -p /dev/radio
chown 1001:1001 /dev/radio 2>/dev/null || true
chmod 770 /dev/radio 2>/dev/null || true

for dir in dma_heap input snd dri radio; do
    if [ -d "/dev/$dir" ]; then
        mkdir -p "${LXC_ROOTFS_MOUNT}/dev/$dir"
        mount --bind "/dev/$dir" "${LXC_ROOTFS_MOUNT}/dev/$dir"
    fi
done

if [ -w "${LXC_ROOTFS_MOUNT}" ] && [ ! -e "${LXC_ROOTFS_MOUNT}/socket" ]; then
    ln -sf /dev/socket "${LXC_ROOTFS_MOUNT}/socket" || true
fi

# Bind-mount patched ccci_md_all.ko over vendor_dlkm
if [ -f /usr/lib/modules/5.10.269-EvernightKernel-1.1/kernel/ccci_md_all.ko ]; then
    mount --bind /usr/lib/modules/5.10.269-EvernightKernel-1.1/kernel/ccci_md_all.ko /android/vendor_dlkm/lib/modules/ccci_md_all.ko 2>/dev/null || true
    if [ -n "${LXC_ROOTFS_MOUNT}" ] && [ -f "${LXC_ROOTFS_MOUNT}/vendor_dlkm/lib/modules/ccci_md_all.ko" ]; then
        mount --bind /usr/lib/modules/5.10.269-EvernightKernel-1.1/kernel/ccci_md_all.ko "${LXC_ROOTFS_MOUNT}/vendor_dlkm/lib/modules/ccci_md_all.ko" 2>/dev/null || true
    fi
fi


# Bind-mount patched libpowerhal.so
if [ -f /var/lib/lxc/android/libpowerhal_patched.so ]; then
    mount --bind /var/lib/lxc/android/libpowerhal_patched.so /android/vendor/lib64/libpowerhal.so 2>/dev/null || true
    if [ -n "${LXC_ROOTFS_MOUNT}" ] && [ -f "${LXC_ROOTFS_MOUNT}/vendor/lib64/libpowerhal.so" ]; then
        mount --bind /var/lib/lxc/android/libpowerhal_patched.so "${LXC_ROOTFS_MOUNT}/vendor/lib64/libpowerhal.so" 2>/dev/null || true
    fi
fi

exit 0
