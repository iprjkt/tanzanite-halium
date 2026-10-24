#!/sbin/sh
# Tanzanite Vendor EROFS Fstab Patch & Ubuntu Touch Rootfs Installer
# Supports dynamic A/B slot detection, EROFS unpack/repack, AVB handling, and rootfs provisioning

set -e

OUTFD="/proc/self/fd/$2"
ZIPFILE="$3"

ui_print() {
  echo "ui_print $1" >> "$OUTFD"
  echo "ui_print" >> "$OUTFD"
}

abort() {
  ui_print "[!] ERROR: $1"
  ui_print "[!] Aborting installation..."
  rm -rf "$WORK" 2>/dev/null || true
  exit 1
}

ui_print "=============================================="
ui_print "                          .-.                 "
ui_print "                    .-'\`\`(|||)                "
ui_print "                 ,\`\\ \\    \`-\`.                "
ui_print "                /   \\ '\`\`-.   \`               "
ui_print "              .-.  ,       \`___:              "
ui_print "             (:::) :        ___               "
ui_print "              \`-\`  \`       ,   :              "
ui_print "                \\   / ,..-\`   ,               "
ui_print "                 \`./ /    .-.\`                "
ui_print "                    \`-..-(   )                "
ui_print "                          \`-\`                 "
ui_print "  _   _ _                 _                   "
ui_print " | | | | |__  _   _ _ __ | |_ _   _           "
ui_print " | | | | '_ \\| | | | '_ \\| __| | | |          "
ui_print " | |_| | |_) | |_| | | | | |_| |_| |          "
ui_print "  \\___/|_.__/ \\__,_|_| |_|\\__|\\__,_|          "
ui_print "               T O U C H                      "
ui_print "=============================================="
ui_print " Redmi Note 14 4G (tanzanite) Halium Patcher  "
ui_print " GitHub  : https://github.com/iprjkt          "
ui_print " Telegram: https://t.me/anotherside551        "
ui_print "=============================================="

WORK="/tmp/tanzanite_patch"
rm -rf "$WORK"
mkdir -p "$WORK/tools" "$WORK/extracted" "$WORK/vbmeta"

ui_print "[*] Extracting tools from zip..."
unzip -oq "$ZIPFILE" "tools/*" "vbmeta/*" -d "$WORK" 2>/dev/null || unzip -oq "$ZIPFILE" "tools/*" -d "$WORK"
chmod -R 755 "$WORK/tools"
export PATH="$WORK/tools:$PATH"

BB="$WORK/tools/busybox"

# 1. Detect Active Slot Dynamically
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null || true)
if [ -z "$SLOT" ]; then
  SLOT=$(grep -o 'androidboot.slot_suffix=[^ ]*' /proc/cmdline | cut -d= -f2 || true)
fi
if [ -z "$SLOT" ]; then
  SLOT_RAW=$(getprop ro.boot.slot 2>/dev/null || grep -o 'androidboot.slot=[^ ]*' /proc/cmdline | cut -d= -f2 || true)
  [ -n "$SLOT_RAW" ] && SLOT="_${SLOT_RAW#_}"
fi

if [ "$SLOT" != "_a" ] && [ "$SLOT" != "_b" ]; then
  abort "Could not detect valid active slot (got: '$SLOT')"
fi
SLOT_NUM=0
[ "$SLOT" = "_b" ] && SLOT_NUM=1

ui_print "[*] Active slot detected: $SLOT (index $SLOT_NUM)"

# 2. Locate Vendor Partition (by-name or dynamic mapper)
umount -fl /vendor 2>/dev/null || true
VENDOR_PART=""
if [ -e "/dev/block/mapper/vendor${SLOT}" ]; then
  VENDOR_PART="/dev/block/mapper/vendor${SLOT}"
elif [ -e "/dev/block/by-name/vendor${SLOT}" ]; then
  VENDOR_PART="/dev/block/by-name/vendor${SLOT}"
elif [ -e "/dev/block/by-name/super" ]; then
  ui_print "[*] Mapping logical partition vendor${SLOT} from super..."
  "$WORK/tools/lptools" --super /dev/block/by-name/super --slot "$SLOT_NUM" --suffix "$SLOT" --map "vendor${SLOT}" || true
  [ -e "/dev/block/mapper/vendor${SLOT}" ] && VENDOR_PART="/dev/block/mapper/vendor${SLOT}"
fi

[ -n "$VENDOR_PART" ] && [ -e "$VENDOR_PART" ] || abort "Vendor partition for slot $SLOT not found!"
umount -fl "$VENDOR_PART" 2>/dev/null || true
blockdev --setrw "$VENDOR_PART" 2>/dev/null || true

ORIG_SIZE=$(blockdev --getsize64 "$VENDOR_PART")
ui_print "[*] Found vendor partition: $VENDOR_PART ($ORIG_SIZE bytes)"
[ "$ORIG_SIZE" -gt 0 ] || abort "Vendor partition size is 0!"

# 3. Dump Vendor Partition
ui_print "[*] Dumping vendor${SLOT} to $WORK/vendor_orig.img..."
dd if="$VENDOR_PART" of="$WORK/vendor_orig.img" bs=4M
[ -s "$WORK/vendor_orig.img" ] || abort "Failed to dump vendor${SLOT}!"

# Backup original vendor & boot partitions if /sdcard is accessible
if [ -d "/sdcard" ] && mountpoint -q /sdcard 2>/dev/null || [ -d "/data/media/0" ]; then
  SDCARD_DIR="/sdcard"
  [ -d "/data/media/0" ] && ! mountpoint -q /sdcard 2>/dev/null && SDCARD_DIR="/data/media/0"
  mkdir -p "$SDCARD_DIR/.backup"
  if [ ! -s "$SDCARD_DIR/.backup/vendor_orig${SLOT}.img" ]; then
    ui_print "[*] Saving vendor backup to $SDCARD_DIR/.backup/vendor_orig${SLOT}.img..."
    cp -f "$WORK/vendor_orig.img" "$SDCARD_DIR/.backup/vendor_orig${SLOT}.img" || true
  fi
fi

# 4. Extract EROFS
ui_print "[*] Extracting vendor EROFS image..."
"$WORK/tools/extract.erofs" -i "$WORK/vendor_orig.img" -x "$WORK/extracted"
FSTAB="$WORK/extracted/etc/fstab.mt6789"
[ -f "$FSTAB" ] || abort "fstab.mt6789 not found in extracted vendor!"

# 5. Patch fstab.mt6789
ui_print "[*] Patching /vendor/etc/fstab.mt6789 (/data -> unencrypted ext4)..."
"$BB" sed -i 's|^/dev/block/by-name/userdata[[:space:]].*|/dev/block/by-name/userdata /data ext4 noatime,nosuid,nodev,discard,resgid=1065 wait,check,formattable,quota,latemount,resize,reservedsize=128m|' "$FSTAB"

if ! "$BB" grep -q "^/dev/block/by-name/userdata /data ext4 " "$FSTAB"; then
  abort "fstab.mt6789 patch verification failed!"
fi
ui_print "[+] Verified patched line:"
ui_print "    $("$BB" grep '^/dev/block/by-name/userdata /data ' "$FSTAB")"

# 6. Repack EROFS
ui_print "[*] Repacking EROFS image with mkfs.erofs (-zlz4hc,level=12)..."
FC_FILE="$WORK/extracted/etc/selinux/vendor_file_contexts"
COMBINED_FC="$WORK/combined_file_contexts"
if [ -f "$FC_FILE" ]; then
  if [ -f "/plat_file_contexts" ]; then
    cat "/plat_file_contexts" "$FC_FILE" > "$COMBINED_FC"
  elif [ -f "/system/etc/selinux/plat_file_contexts" ]; then
    cat "/system/etc/selinux/plat_file_contexts" "$FC_FILE" > "$COMBINED_FC"
  else
    echo '/(vendor|system/vendor)(/.*)? u:object_r:vendor_file:s0' > "$COMBINED_FC"
    echo '/(vendor|system/vendor)/bin/boringssl_self_test(32|64) u:object_r:vendor_boringssl_self_test_exec:s0' >> "$COMBINED_FC"
    cat "$FC_FILE" >> "$COMBINED_FC"
  fi
  "$WORK/tools/mkfs.erofs" -zlz4hc,level=12 -T 1230768000 -U 49911ede-c544-3978-11fe-1cb76c7de057 --mount-point=/vendor --file-contexts="$COMBINED_FC" "$WORK/vendor_patched.img" "$WORK/extracted" >/dev/null
else
  "$WORK/tools/mkfs.erofs" -zlz4hc,level=12 -T 1230768000 -U 49911ede-c544-3978-11fe-1cb76c7de057 --mount-point=/vendor "$WORK/vendor_patched.img" "$WORK/extracted" >/dev/null
fi

[ -s "$WORK/vendor_patched.img" ] || abort "Repacked vendor_patched.img is empty or missing!"
NEW_SIZE=$("$BB" stat -c '%s' "$WORK/vendor_patched.img")
ui_print "[*] Repacked EROFS size: $NEW_SIZE bytes (limit: $ORIG_SIZE bytes)"
if [ "$NEW_SIZE" -gt "$ORIG_SIZE" ]; then
  abort "Repacked vendor image ($NEW_SIZE) exceeds partition size ($ORIG_SIZE)!"
fi

# Free space in /tmp before flashing
rm -rf "$WORK/extracted" "$WORK/vendor_orig.img"

# 7. Flash Patched Vendor Image
ui_print "[*] Flashing patched vendor image to $VENDOR_PART..."
blockdev --setrw "$VENDOR_PART" 2>/dev/null || true
dd if="$WORK/vendor_patched.img" of="$VENDOR_PART" bs=4M
sync
rm -f "$WORK/vendor_patched.img"
ui_print "[+] Successfully flashed vendor${SLOT}!"

# 8. Handle VBMETA (__VBMETA_MODE__)
VBMETA_MODE="__VBMETA_MODE__"
if [ "$VBMETA_MODE" = "prebuilt" ]; then
  ui_print "[*] Flashing pre-disabled vbmeta images to slot $SLOT..."
  for part in vbmeta vbmeta_system vbmeta_vendor; do
    TARGET_PART="/dev/block/by-name/${part}${SLOT}"
    IMG_FILE="$WORK/vbmeta/${part}.img"
    [ -e "$TARGET_PART" ] || abort "Partition $TARGET_PART not found!"
    [ -s "$IMG_FILE" ] || abort "Bundled image $IMG_FILE missing or empty!"
    blockdev --setrw "$TARGET_PART" 2>/dev/null || true
    dd if="$IMG_FILE" of="$TARGET_PART" bs=4M
    ui_print "    [+] Flashed ${part}${SLOT}"
  done
else
  ui_print "[*] Disabling AVB verification and dm-verity on vbmeta*${SLOT}..."
  if [ -x "$WORK/tools/avbctl" ]; then
    "$WORK/tools/avbctl" --force disable-verification 2>/dev/null || true
    "$WORK/tools/avbctl" --force disable-verity 2>/dev/null || true
  fi
  for part in vbmeta vbmeta_system vbmeta_vendor; do
    TARGET_PART="/dev/block/by-name/${part}${SLOT}"
    [ -e "$TARGET_PART" ] || abort "Partition $TARGET_PART not found!"
    blockdev --setrw "$TARGET_PART" 2>/dev/null || true
    MAGIC=$(dd if="$TARGET_PART" bs=1 count=4 2>/dev/null || true)
    if [ "$MAGIC" != "AVB0" ]; then
      abort "$TARGET_PART does not have valid AVB0 magic!"
    fi
    printf '\x03' | dd of="$TARGET_PART" bs=1 seek=123 count=1 conv=notrunc 2>/dev/null
    FLAG_HEX=$(dd if="$TARGET_PART" bs=1 skip=123 count=1 2>/dev/null | "$BB" od -An -tx1 | tr -d ' \n')
    [ "$FLAG_HEX" = "03" ] || abort "Failed to set AVB flag 0x03 on $TARGET_PART (got $FLAG_HEX)!"
    ui_print "    [+] Patched ${part}${SLOT} flags -> 0x03 (verity+verification disabled)"
  done
fi
sync

# 9. Backup Stock Boot Partitions, Extract & Flash Halium Boot Partitions, and Provision Rootfs
ui_print "[*] Extracting Halium boot, vendor_boot, and dtbo images..."
unzip -o "$ZIPFILE" "partitions/*" -d "$WORK" >/dev/null 2>&1
for p in boot vendor_boot dtbo; do
  [ -s "$WORK/partitions/${p}.img" ] || abort "Extracted Halium $p.img is missing or empty!"
  [ -e "/dev/block/by-name/${p}${SLOT}" ] || abort "Target partition /dev/block/by-name/${p}${SLOT} not found!"
done

# Backup current slot boot/vendor_boot/dtbo to $WORK/stock_backup before overwriting
mkdir -p "$WORK/stock_backup"
ui_print "[*] Backing up current slot ($SLOT) boot, vendor_boot, and dtbo..."
for p in boot vendor_boot dtbo; do
  dd if="/dev/block/by-name/${p}${SLOT}" of="$WORK/stock_backup/${p}_stock.img" bs=4M
  [ -s "$WORK/stock_backup/${p}_stock.img" ] || abort "Failed to backup /dev/block/by-name/${p}${SLOT}!"
done

USERDATA_PART="/dev/block/by-name/userdata"
if [ -e "$USERDATA_PART" ]; then
  dmctl delete userdata 2>/dev/null || true
  FS_TYPE=$("$BB" blkid "$USERDATA_PART" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || true)
  [ -z "$FS_TYPE" ] && FS_TYPE=$(blkid "$USERDATA_PART" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || true)
  ui_print "[*] Detected userdata filesystem: ${FS_TYPE:-unknown}"
  if [ "$FS_TYPE" = "ext4" ]; then
    ui_print "[*] Mounting /data (ext4) to provision Ubuntu Touch rootfs..."
    mkdir -p /data
    mountpoint -q /data 2>/dev/null || mount -t ext4 "$USERDATA_PART" /data
    mkdir -p /data/ubuntu

    ui_print "[*] Extracting ubuntu-touch-hybris-rootfs-arm64.tar.gz to /data/ubuntu..."
    unzip -p "$ZIPFILE" "ubuntu-touch-hybris-rootfs-arm64.tar.gz" | "$BB" tar --numeric-owner -xzpf - -C /data/ubuntu/

    if unzip -l "$ZIPFILE" "android-rootfs.img" >/dev/null 2>&1; then
      ui_print "[*] Extracting android-rootfs.img (Halium 12 LXC container)..."
      mkdir -p /data/ubuntu/var/lib/lxc/android
      unzip -p "$ZIPFILE" "android-rootfs.img" > /data/ubuntu/var/lib/lxc/android/android-rootfs.img
      chmod 644 /data/ubuntu/var/lib/lxc/android/android-rootfs.img
    fi

    ui_print "[*] Extracting device_tanzanite_system.tar.gz overlay to /data/ubuntu..."
    rm -f /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/server-platform/graphics-android.so.15 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/server-platform/graphics-android-caf.so.15 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/client-platform/android.so.5 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/client-platform/android-caf.so.5
    unzip -p "$ZIPFILE" "device_tanzanite_system.tar.gz" | chroot /data/ubuntu /bin/tar --numeric-owner --overwrite -xzpf - -C /
    touch /data/ubuntu/.writable_image /data/.writable_image /data/.force-adb

    [ -d "/data/ubuntu/usr" ] && [ -d "/data/ubuntu/etc" ] && [ -s "/data/ubuntu/var/lib/lxc/android/android-rootfs.img" ] || abort "Rootfs extraction verification failed!"
    ui_print "[+] Ubuntu Touch rootfs, Android LXC container & device overlay extracted to /data/ubuntu!"

    # Provision Ubuntu Touch apt dependencies and sandbox fixes
    ui_print "[*] Configuring apt dependencies and sandbox in /data/ubuntu..."
    if [ -f "/data/ubuntu/var/lib/dpkg/status" ]; then
      "$BB" sed -i 's/mir-graphics-drivers-android, mir-graphics-drivers-android-caf/mir-graphics-drivers-android2/' /data/ubuntu/var/lib/dpkg/status
    fi
    mkdir -p /data/ubuntu/etc/apt/apt.conf.d
    echo 'APT::Sandbox::User "root";' > /data/ubuntu/etc/apt/apt.conf.d/90-android-sandbox.conf
    mkdir -p /data/ubuntu/etc/sudoers.d
    echo 'phablet ALL=(ALL) NOPASSWD: /usr/bin/boot-to-android' > /data/ubuntu/etc/sudoers.d/99-boot-to-android
    chmod 440 /data/ubuntu/etc/sudoers.d/99-boot-to-android

    # Provision KernelSU post-fs-data fix for HyperOS /sdcard (disable fuse-bpf)
    ui_print "[*] Installing HyperOS FUSE-BPF fix to /data/adb/post-fs-data.d/..."
    mkdir -p /data/adb/post-fs-data.d
    cat << 'EOF' > /data/adb/post-fs-data.d/99-disable-fuse-bpf.sh
#!/system/bin/sh
resetprop ro.fuse.bpf.enabled false
resetprop ro.fuse.bpf.is_running false
resetprop persist.sys.fuse.bpf.override false
resetprop persist.sys.fuse.passthrough.enable false
EOF
    chmod 755 /data/adb/post-fs-data.d/99-disable-fuse-bpf.sh

    # Save Halium & Stock boot/vendor_boot/dtbo backups to /data/media/0/.backup (/sdcard/.backup)
    BACKUP_DIR="/data/media/0/.backup"
    mkdir -p "$BACKUP_DIR"
    cp -f "$WORK/partitions/boot.img" "$BACKUP_DIR/boot_halium.img"
    cp -f "$WORK/partitions/vendor_boot.img" "$BACKUP_DIR/vendor_boot_halium.img"
    cp -f "$WORK/partitions/dtbo.img" "$BACKUP_DIR/dtbo_halium.img"

    for p in boot vendor_boot dtbo; do
      if [ ! -s "$BACKUP_DIR/${p}_stock.img" ]; then
        cp -f "$WORK/stock_backup/${p}_stock.img" "$BACKUP_DIR/${p}_stock.img"
      fi
    done

    # Ensure /data/media/0 has proper 2770 media_rw setgid permissions
    chown -R 1023:1023 /data/media 2>/dev/null || true
    chmod 770 /data/media 2>/dev/null || true
    chmod 2770 /data/media/0 2>/dev/null || true
    chmod 777 "$BACKUP_DIR" 2>/dev/null || true
    chmod 666 "$BACKUP_DIR"/* 2>/dev/null || true
    sync
    ui_print "[+] Backups stored in /sdcard/.backup/ (/data/media/0/.backup/)"
  else
    ui_print "[!] Note: userdata is currently '$FS_TYPE' (not ext4)."
    ui_print "    Skip rootfs extraction. Format userdata & metadata to ext4 first,"
    ui_print "    then re-flash this zip to auto-provision /data/ubuntu."
    if [ -d "/sdcard" ] && mountpoint -q /sdcard 2>/dev/null; then
      mkdir -p "/sdcard/.backup"
      cp -f "$WORK/partitions/boot.img" "/sdcard/.backup/boot_halium.img"
      cp -f "$WORK/partitions/vendor_boot.img" "/sdcard/.backup/vendor_boot_halium.img"
      cp -f "$WORK/partitions/dtbo.img" "/sdcard/.backup/dtbo_halium.img"
      for p in boot vendor_boot dtbo; do
        [ -s "/sdcard/.backup/${p}_stock.img" ] || cp -f "$WORK/stock_backup/${p}_stock.img" "/sdcard/.backup/${p}_stock.img"
      done
    fi
  fi
fi

# 10. Flash Halium boot, vendor_boot, and dtbo to active slot
ui_print "[*] Flashing Halium boot, vendor_boot, and dtbo to slot $SLOT..."
for p in boot vendor_boot dtbo; do
  TARGET_PART="/dev/block/by-name/${p}${SLOT}"
  blockdev --setrw "$TARGET_PART" 2>/dev/null || true
  dd if="$WORK/partitions/${p}.img" of="$TARGET_PART" bs=4M
  ui_print "    [+] Flashed ${p}${SLOT} <- Halium ${p}.img"
done
sync

rm -rf "$WORK"
sync
ui_print "=============================================="
ui_print "[+] Patching completed successfully!"
ui_print "=============================================="
exit 0
