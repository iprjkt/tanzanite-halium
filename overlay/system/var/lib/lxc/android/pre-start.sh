#!/bin/sh

# These things can be done only of rootfs is writable i.e. is ramdisk.
if [ -w $LXC_ROOTFS_PATH ]; then
    rm $LXC_ROOTFS_PATH/sbin/adbd 2>/dev/null || true

    sed -i '/mount_all /d' $LXC_ROOTFS_PATH/init.*.rc 2>/dev/null || true
    sed -i '/swapon_all /d' $LXC_ROOTFS_PATH/init.*.rc 2>/dev/null || true
    sed -i '/on nonencrypted/d' $LXC_ROOTFS_PATH/init.rc 2>/dev/null || true

    # Strip any reboot_on_failure in container services
    sed -i 's/^[[:space:]]*reboot_on_failure/# &/' $LXC_ROOTFS_PATH/init*.rc $LXC_ROOTFS_PATH/system/etc/init/*.rc $LXC_ROOTFS_PATH/system/etc/init/*/*.rc 2>/dev/null || true

    # Config snippet scripts
    run-parts /var/lib/lxc/android/pre-start.d || true
fi

# Make sure bind-mount-points are available.
mkdir -p /dev/__properties__ /dev/socket
