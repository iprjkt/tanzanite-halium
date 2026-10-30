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

find_part() {
  local name="$1"
  for cand in \
    "/dev/block/by-name/$name" \
    "/dev/block/platform/soc/11270000.ufshci/by-name/$name" \
    "/dev/block/platform/bootdevice/by-name/$name" \
    "/dev/block/mapper/$name"; do
    if [ -e "$cand" ]; then
      echo "$cand"
      return 0
    fi
  done
  case "$name" in
    lk_a) [ -e "/dev/block/sdc31" ] && echo "/dev/block/sdc31" && return 0 ;;
    lk_b) [ -e "/dev/block/sdc55" ] && echo "/dev/block/sdc55" && return 0 ;;
  esac
  return 1
}

find_preloader_part() {
  local slot="$1"
  if [ -e "/dev/block/by-name/preloader_raw_${slot}" ]; then
    echo "/dev/block/by-name/preloader_raw_${slot}"
  elif [ -e "/dev/block/mapper/pl_${slot}" ]; then
    echo "/dev/block/mapper/pl_${slot}"
  elif [ -e "/dev/block/by-name/preloader_${slot}" ]; then
    echo "/dev/block/by-name/preloader_${slot}"
  elif [ "$slot" = "a" ] && [ -e "/dev/block/sda" ]; then
    echo "/dev/block/sda"
  elif [ "$slot" = "b" ] && [ -e "/dev/block/sdb" ]; then
    echo "/dev/block/sdb"
  fi
}

extract_kernel_ver() {
  local target="$1"
  local ver=""
  local decomp=""

  if [ -x "$BB" ]; then
    decomp="$BB zcat"
  elif command -v zcat >/dev/null 2>&1; then
    decomp="zcat"
  else
    decomp="gzip -dc"
  fi

  # 1. Decompressed gzip stream (Android boot v4 kernel at offset 4096)
  ver=$(dd if="$target" bs=4096 skip=1 count=4096 2>/dev/null | $decomp 2>/dev/null | strings 2>/dev/null | grep -m1 "Linux version [0-9]" | sed -E 's/.*Linux version ([0-9]+\.[0-9]+\.[0-9]+[^ ]*).*/\1/' || true)
  if [ -n "$ver" ]; then
    echo "$ver"
    return 0
  fi

  # 2. Raw uncompressed image check
  ver=$(dd if="$target" bs=4096 count=4096 2>/dev/null | strings 2>/dev/null | grep -m1 "Linux version [0-9]" | sed -E 's/.*Linux version ([0-9]+\.[0-9]+\.[0-9]+[^ ]*).*/\1/' || true)
  if [ -n "$ver" ]; then
    echo "$ver"
    return 0
  fi

  return 1
}

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

if [ -z "$VENDOR_PART" ] || [ ! -e "$VENDOR_PART" ]; then
  abort "Vendor partition for slot $SLOT not found!"
fi
umount -fl "$VENDOR_PART" 2>/dev/null || true
blockdev --setrw "$VENDOR_PART" 2>/dev/null || true

ORIG_SIZE=$(blockdev --getsize64 "$VENDOR_PART")
ui_print "[*] Found vendor partition: $VENDOR_PART ($ORIG_SIZE bytes)"
[ "$ORIG_SIZE" -gt 0 ] || abort "Vendor partition size is 0!"

# 3. Detect Vendor Filesystem (EROFS vs EXT4)
VENDOR_FS=""
if [ -x "$BB" ]; then
  VENDOR_FS=$("$BB" blkid "$VENDOR_PART" 2>/dev/null | "$BB" grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || true)
fi
if [ -z "$VENDOR_FS" ]; then
  VENDOR_FS=$(blkid "$VENDOR_PART" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || true)
fi
if [ -z "$VENDOR_FS" ]; then
  EROFS_MAGIC=$(dd if="$VENDOR_PART" skip=1024 bs=1 count=4 2>/dev/null | "$BB" od -An -tx1 | tr -d ' \n' || true)
  EXT4_MAGIC=$(dd if="$VENDOR_PART" skip=1080 bs=1 count=2 2>/dev/null | "$BB" od -An -tx1 | tr -d ' \n' || true)
  if [ "$EROFS_MAGIC" = "e2f5654c" ]; then
    VENDOR_FS="erofs"
  elif [ "$EXT4_MAGIC" = "53ef" ]; then
    VENDOR_FS="ext4"
  fi
fi
ui_print "[*] Detected vendor filesystem: ${VENDOR_FS:-unknown}"

if [ "$VENDOR_FS" = "ext4" ]; then
  ui_print "[*] Processing ext4 vendor partition..."
  MNT_VENDOR="$WORK/mnt_vendor"
  mkdir -p "$MNT_VENDOR"
  blockdev --setrw "$VENDOR_PART" 2>/dev/null || true
  e2fsck -fy "$VENDOR_PART" >/dev/null 2>&1 || true

  if mount -t ext4 -o rw "$VENDOR_PART" "$MNT_VENDOR" 2>/dev/null || mount -o rw "$VENDOR_PART" "$MNT_VENDOR" 2>/dev/null; then
    # Backup original vendor partition if /sdcard is accessible
    if [ -d "/sdcard" ] && mountpoint -q /sdcard 2>/dev/null || [ -d "/data/media/0" ]; then
      SDCARD_DIR="/sdcard"
      [ -d "/data/media/0" ] && ! mountpoint -q /sdcard 2>/dev/null && SDCARD_DIR="/data/media/0"
      mkdir -p "$SDCARD_DIR/.backup"
      if [ ! -s "$SDCARD_DIR/.backup/vendor_orig${SLOT}.img" ]; then
        ui_print "[*] Saving vendor backup to $SDCARD_DIR/.backup/vendor_orig${SLOT}.img..."
        dd if="$VENDOR_PART" of="$SDCARD_DIR/.backup/vendor_orig${SLOT}.img" bs=4M || true
      fi
    fi

    # Check if fstab is already configured for unencrypted ext4 userdata
    ALREADY_PATCHED=true
    FOUND_DATA_ENTRY=false
    for F in "$MNT_VENDOR/etc/"fstab*; do
      [ -f "$F" ] || continue
      if "$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" >/dev/null 2>&1; then
        FOUND_DATA_ENTRY=true
        DATA_LINE=$("$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" | head -n 1)
        FS_ENTRY=$(echo "$DATA_LINE" | awk '{print $3}')
        if [ "$FS_ENTRY" != "ext4" ]; then
          ALREADY_PATCHED=false
          break
        fi
        if echo "$DATA_LINE" | "$BB" grep -qiE 'fileencryption=|forceencrypt=|encryptable=|keydirectory='; then
          ALREADY_PATCHED=false
          break
        fi
      fi
    done

    if [ "$FOUND_DATA_ENTRY" = "true" ] && [ "$ALREADY_PATCHED" = "true" ]; then
      ui_print "[+] Vendor fstab is ALREADY configured for unencrypted ext4 userdata!"
      ui_print "    $DATA_LINE"
      ui_print "[*] Skipping vendor patch."
      umount "$MNT_VENDOR" 2>/dev/null || true
      rmdir "$MNT_VENDOR" 2>/dev/null || true
    else
      ui_print "[*] Patching fstab in ext4 vendor..."
      PATCHED_ANY=false
      for F in "$MNT_VENDOR/etc/"fstab*; do
        [ -f "$F" ] || continue
        if "$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" >/dev/null 2>&1; then
          ui_print "    [*] Patching $(basename "$F") (/data -> unencrypted ext4)..."
          "$BB" sed -i 's|^/dev/block/by-name/userdata[[:space:]].*|/dev/block/by-name/userdata /data ext4 noatime,nosuid,nodev,discard,resgid=1065 wait,check,formattable,quota,latemount,resize,reservedsize=128m|' "$F"
          PATCHED_ANY=true
        fi
      done
      [ "$PATCHED_ANY" = "true" ] || abort "No active /data fstab entry found to patch in ext4 vendor!"
      sync
      umount "$MNT_VENDOR" 2>/dev/null || true
      rmdir "$MNT_VENDOR" 2>/dev/null || true
      ui_print "[+] Successfully patched ext4 vendor in-place!"
    fi
  else
    abort "Failed to mount ext4 vendor partition read-write!"
  fi
else
  # EROFS vendor handling
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
  [ -d "$WORK/extracted/etc" ] || abort "Failed to extract vendor EROFS!"

  # Check if fstab is already configured for unencrypted ext4 userdata
  ALREADY_PATCHED=true
  FOUND_DATA_ENTRY=false
  for F in "$WORK/extracted/etc/"fstab*; do
    [ -f "$F" ] || continue
    if "$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" >/dev/null 2>&1; then
      FOUND_DATA_ENTRY=true
      DATA_LINE=$("$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" | head -n 1)
      FS_ENTRY=$(echo "$DATA_LINE" | awk '{print $3}')
      if [ "$FS_ENTRY" != "ext4" ]; then
        ALREADY_PATCHED=false
        break
      fi
      if echo "$DATA_LINE" | "$BB" grep -qiE 'fileencryption=|forceencrypt=|encryptable=|keydirectory='; then
        ALREADY_PATCHED=false
        break
      fi
    fi
  done

  if [ "$FOUND_DATA_ENTRY" = "true" ] && [ "$ALREADY_PATCHED" = "true" ]; then
    ui_print "[+] Vendor fstab is ALREADY configured for unencrypted ext4 userdata!"
    ui_print "    $DATA_LINE"
    ui_print "[*] Skipping vendor repacking and flashing."
    rm -rf "$WORK/extracted" "$WORK/vendor_orig.img"
  else
    # 5. Patch fstab files
    ui_print "[*] Patching vendor fstab (/data -> unencrypted ext4)..."
    PATCHED_ANY=false
    for F in "$WORK/extracted/etc/"fstab*; do
      [ -f "$F" ] || continue
      if "$BB" grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/data[[:space:]]+' "$F" >/dev/null 2>&1; then
        ui_print "    [*] Patching $(basename "$F")..."
        "$BB" sed -i 's|^/dev/block/by-name/userdata[[:space:]].*|/dev/block/by-name/userdata /data ext4 noatime,nosuid,nodev,discard,resgid=1065 wait,check,formattable,quota,latemount,resize,reservedsize=128m|' "$F"
        PATCHED_ANY=true
      fi
    done
    [ "$PATCHED_ANY" = "true" ] || abort "No active /data fstab entry found to patch in vendor!"

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
      ui_print "[!] Repacked image ($NEW_SIZE bytes) exceeds partition size ($ORIG_SIZE bytes)."
      if [ -e "/dev/block/by-name/super" ] && [ -x "$WORK/tools/lptools" ]; then
        ui_print "[*] Expanding dynamic partition vendor${SLOT} via lptools..."

        # Align target size to 1MB + 2MB headroom
        TARGET_SIZE=$(( ((NEW_SIZE + 1048575) / 1048576) * 1048576 + 2097152 ))
        ui_print "[*] Target partition size: $TARGET_SIZE bytes"

        # Unmount and unmap vendor before resizing
        umount -fl "$VENDOR_PART" 2>/dev/null || true
        umount -fl /vendor 2>/dev/null || true
        "$WORK/tools/lptools" --super /dev/block/by-name/super --slot "$SLOT_NUM" --suffix "$SLOT" --unmap "vendor${SLOT}" 2>/dev/null || true
        "$WORK/tools/lptools" --super /dev/block/by-name/super --slot "$SLOT_NUM" --unmap "vendor${SLOT}" 2>/dev/null || true

        # Resize partition in super metadata
        # Try the known lptools invocations in order. The resulting partition size is
        # compared against TARGET_SIZE below, which is the authoritative check.
        for attempt in \
            "--suffix $SLOT --resize vendor${SLOT}" \
            "--suffix $SLOT --unlimited-group --resize vendor${SLOT}" \
            "--resize vendor${SLOT}" \
            "--suffix $SLOT --resize vendor"; do
          if "$WORK/tools/lptools" --super /dev/block/by-name/super \
              --slot "$SLOT_NUM" $attempt "$TARGET_SIZE" 2>&1; then
            break
          fi
        done

        # Remap partition to update device-mapper table in kernel
        "$WORK/tools/lptools" --super /dev/block/by-name/super --slot "$SLOT_NUM" --suffix "$SLOT" --map "vendor${SLOT}" || true

        if [ -e "/dev/block/mapper/vendor${SLOT}" ]; then
          VENDOR_PART="/dev/block/mapper/vendor${SLOT}"
        fi

        blockdev --setrw "$VENDOR_PART" 2>/dev/null || true
        ORIG_SIZE=$(blockdev --getsize64 "$VENDOR_PART" 2>/dev/null || echo 0)
        ui_print "[*] New vendor${SLOT} partition size: $ORIG_SIZE bytes"

        if [ "$NEW_SIZE" -le "$ORIG_SIZE" ]; then
          ui_print "[+] Successfully resized vendor${SLOT} dynamic partition!"
        else
          abort "Failed to resize vendor partition (size $ORIG_SIZE is still smaller than $NEW_SIZE)!"
        fi
      else
        abort "Repacked vendor image ($NEW_SIZE) exceeds partition size ($ORIG_SIZE) and lptools is unavailable!"
      fi
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
  fi
fi

# 8. Handle VBMETA (__VBMETA_MODE__)
VBMETA_MODE="__VBMETA_MODE__"
if [ "$VBMETA_MODE" = "prebuilt" ] || [ -f "$WORK/vbmeta/vbmeta.img" ]; then
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

# 9. Extract Partition Images & Handle Bootloader Security (LK Fenrir & Preloader Engineering)
ui_print "[*] Extracting partition images from installer zip..."
unzip -o "$ZIPFILE" "partitions/*" -d "$WORK" >/dev/null 2>&1
for p in boot vendor_boot dtbo; do
  [ -s "$WORK/partitions/${p}.img" ] || abort "Extracted Halium $p.img is missing or empty!"
  [ -e "/dev/block/by-name/${p}${SLOT}" ] || abort "Target partition /dev/block/by-name/${p}${SLOT} not found!"
done

# Tanzanite Kernel Safety & Version Validation (STRICT: Only Linux 5.10.xxx is supported)
# Flashing this Halium build, LK Fenrir, or Preloader Eng on kernel 6.12.xxx firmware WILL HARDBRICK the device!
ui_print "=============================================="
ui_print " Tanzanite Kernel Safety & Version Validation "
ui_print "=============================================="

# 1. Validate Target Halium Kernel in boot.img
HALIUM_KERNEL_VER=$(extract_kernel_ver "$WORK/partitions/boot.img" || true)
if [ -n "$HALIUM_KERNEL_VER" ]; then
  ui_print "[*] Target Halium kernel version: $HALIUM_KERNEL_VER"
  case "$HALIUM_KERNEL_VER" in
    5.10.*)
      ui_print "    [+] Validated target kernel: 5.10.xxx (MT6789 GKI 5.10 baseline)"
      ;;
    6.12.*)
      abort "HARDBRICK RISK: Target kernel is $HALIUM_KERNEL_VER! Tanzanite Halium ONLY supports 5.10.xxx. Kernel 6.12 is incompatible and causes a hardbrick!"
      ;;
    *)
      abort "Unsupported target kernel: $HALIUM_KERNEL_VER! Only 5.10.xxx is supported."
      ;;
  esac
fi

# 2. Validate Currently Installed Stock Firmware Kernel on Device
ACTIVE_BOOT_PART="/dev/block/by-name/boot${SLOT}"
ACTIVE_KERNEL_VER=""
if [ -e "$ACTIVE_BOOT_PART" ]; then
  ACTIVE_KERNEL_VER=$(extract_kernel_ver "$ACTIVE_BOOT_PART" || true)
fi
if [ -z "$ACTIVE_KERNEL_VER" ] && [ -r "/proc/version" ]; then
  ACTIVE_KERNEL_VER=$(grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+[^ ]*' /proc/version | sed -E 's/.*Linux version ([0-9]+\.[0-9]+\.[0-9]+[^ ]*).*/\1/' || true)
fi

if [ -n "$ACTIVE_KERNEL_VER" ]; then
  ui_print "[*] Detected device firmware kernel: $ACTIVE_KERNEL_VER"
  case "$ACTIVE_KERNEL_VER" in
    6.12.*)
      ui_print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      ui_print "[!] FATAL: DEVICE IS RUNNING LINUX KERNEL 6.12.xxx!"
      ui_print "[!] Flashing this port onto a 6.12 baseline WILL HARDBRICK the device."
      ui_print "[!] MediaTek preloader, LK Fenrir, and vendor blobs require kernel 5.10."
      ui_print "[!] Please downgrade your stock firmware to Android 12-14 (Kernel 5.10) first!"
      ui_print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      abort "Installation aborted to prevent a permanent device hardbrick."
      ;;
    5.10.*)
      ui_print "    [+] Firmware baseline verified: 5.10.xxx (Safe to install)"
      ;;
    *)
      ui_print "    [!] Warning: Unrecognized firmware kernel version: $ACTIVE_KERNEL_VER"
      ui_print "    [!] Tanzanite Halium requires a 5.10.xxx firmware baseline."
      ;;
  esac
fi

# Flash LK Fenrir and Preloader Engineering to BOTH slots (with smart hash verification & skip confirmation)
LK_IMG="$WORK/partitions/lk_fenrir.img"
PL_IMG="$WORK/partitions/preloader_eng.bin"

if [ -f "$LK_IMG" ] && [ -f "$PL_IMG" ]; then
  ui_print "=============================================="
  ui_print " MT6789 Bootloader Security: LK Fenrir & Preloader "
  ui_print "=============================================="

  TARGET_LK_A=$(find_part lk_a || echo "/dev/block/by-name/lk_a")
  TARGET_LK_B=$(find_part lk_b || echo "/dev/block/by-name/lk_b")
  TARGET_PL_A=$(find_preloader_part a || echo "/dev/block/by-name/preloader_raw_a")
  TARGET_PL_B=$(find_preloader_part b || echo "/dev/block/by-name/preloader_raw_b")

  LK_SIZE=$("$BB" wc -c < "$LK_IMG" | tr -d ' \r\n')
  PL_SIZE=$("$BB" wc -c < "$PL_IMG" | tr -d ' \r\n')

  EXPECTED_LK_SHA=$("$BB" sha256sum "$LK_IMG" | cut -d' ' -f1)
  EXPECTED_PL_SHA=$("$BB" sha256sum "$PL_IMG" | cut -d' ' -f1)

  ui_print "[*] Verifying existing bootloader hashes across both slots..."

  CURR_LK_A_SHA=""
  CURR_LK_B_SHA=""
  CURR_PL_A_SHA=""
  CURR_PL_B_SHA=""

  if [ -e "$TARGET_LK_A" ]; then
    CURR_LK_A_SHA=$(dd if="$TARGET_LK_A" bs=4096 count=$(( (LK_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$LK_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
  fi
  if [ -e "$TARGET_LK_B" ]; then
    CURR_LK_B_SHA=$(dd if="$TARGET_LK_B" bs=4096 count=$(( (LK_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$LK_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
  fi

  if [ -e "$TARGET_PL_A" ]; then
    if [ "$TARGET_PL_A" = "/dev/block/sda" ]; then
      CURR_PL_A_SHA=$(dd if="$TARGET_PL_A" bs=4096 skip=1 count=$(( (PL_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$PL_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
    else
      CURR_PL_A_SHA=$(dd if="$TARGET_PL_A" bs=4096 count=$(( (PL_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$PL_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
    fi
  fi

  if [ -e "$TARGET_PL_B" ]; then
    if [ "$TARGET_PL_B" = "/dev/block/sdb" ]; then
      CURR_PL_B_SHA=$(dd if="$TARGET_PL_B" bs=4096 skip=1 count=$(( (PL_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$PL_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
    else
      CURR_PL_B_SHA=$(dd if="$TARGET_PL_B" bs=4096 count=$(( (PL_SIZE + 4095) / 4096 )) 2>/dev/null | head -c "$PL_SIZE" | "$BB" sha256sum | cut -d' ' -f1)
    fi
  fi

  LK_A_OK=0; [ "$CURR_LK_A_SHA" = "$EXPECTED_LK_SHA" ] && LK_A_OK=1
  LK_B_OK=0; [ "$CURR_LK_B_SHA" = "$EXPECTED_LK_SHA" ] && LK_B_OK=1
  PL_A_OK=0; [ "$CURR_PL_A_SHA" = "$EXPECTED_PL_SHA" ] && PL_A_OK=1
  PL_B_OK=0; [ "$CURR_PL_B_SHA" = "$EXPECTED_PL_SHA" ] && PL_B_OK=1

  [ "$LK_A_OK" -eq 1 ] && ui_print "    [+] lk_a            : LK Fenrir verified" || ui_print "    [-] lk_a            : Stock or outdated"
  [ "$LK_B_OK" -eq 1 ] && ui_print "    [+] lk_b            : LK Fenrir verified" || ui_print "    [-] lk_b            : Stock or outdated"
  [ "$PL_A_OK" -eq 1 ] && ui_print "    [+] preloader slot A: Preloader Eng verified" || ui_print "    [-] preloader slot A: Stock or outdated"
  [ "$PL_B_OK" -eq 1 ] && ui_print "    [+] preloader slot B: Preloader Eng verified" || ui_print "    [-] preloader slot B: Stock or outdated"

  ALL_BOOTLOADER_MATCH=0
  if [ "$LK_A_OK" -eq 1 ] && [ "$LK_B_OK" -eq 1 ] && [ "$PL_A_OK" -eq 1 ] && [ "$PL_B_OK" -eq 1 ]; then
    ALL_BOOTLOADER_MATCH=1
  fi

  # Detect volume key input device
  KPD_DEV=""
  for ev in /dev/input/event*; do
    ev_name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
    case "$ev_name" in
      *kpd*|*keys*|*keyboard*) KPD_DEV="$ev"; break ;;
    esac
  done

  ACTION_FLASH_BOOTLOADER=1
  if [ "$ALL_BOOTLOADER_MATCH" -eq 1 ]; then
    ui_print "[+] LK Fenrir & Preloader Eng are ALREADY up to date on both slots!"
    ui_print "[?] Skip flashing bootloader? (Default: SKIP in 5s)"
    ui_print "    -> Press Volume UP within 5s to FORCE RE-FLASH"
    ui_print "    -> Press Volume DOWN or wait 5s to SKIP"

    KEY_PRESSED=""
    if [ -n "$KPD_DEV" ] && [ -e "$KPD_DEV" ] && which getevent >/dev/null 2>&1; then
      EV_DATA=$("$BB" timeout 5 getevent -c 2 "$KPD_DEV" 2>/dev/null || true)
      case "$EV_DATA" in
        *0073*|*0001*0073*) KEY_PRESSED="UP" ;;
        *0072*|*0001*0072*) KEY_PRESSED="DOWN" ;;
      esac
    else
      "$BB" sleep 5 2>/dev/null || sleep 5
    fi

    if [ "$KEY_PRESSED" = "UP" ]; then
      ui_print "[!] Volume UP pressed: Force re-flashing both slots..."
      ACTION_FLASH_BOOTLOADER=1
    else
      ui_print "[+] Skipping bootloader flashing (already up to date)."
      ACTION_FLASH_BOOTLOADER=0
    fi
  else
    ui_print "[!] Bootloader security is NOT fully installed on both slots."
    ui_print "[?] Flash LK Fenrir & Preloader Eng to BOTH slots? (Default: FLASH in 5s)"
    ui_print "    -> Press Volume UP within 5s to SKIP"
    ui_print "    -> Press Volume DOWN or wait 5s to FLASH"

    KEY_PRESSED=""
    if [ -n "$KPD_DEV" ] && [ -e "$KPD_DEV" ] && which getevent >/dev/null 2>&1; then
      EV_DATA=$("$BB" timeout 5 getevent -c 2 "$KPD_DEV" 2>/dev/null || true)
      case "$EV_DATA" in
        *0073*|*0001*0073*) KEY_PRESSED="UP" ;;
        *0072*|*0001*0072*) KEY_PRESSED="DOWN" ;;
      esac
    else
      "$BB" sleep 5 2>/dev/null || sleep 5
    fi

    if [ "$KEY_PRESSED" = "UP" ]; then
      ui_print "[!] Volume UP pressed: User chose to SKIP bootloader flashing."
      ACTION_FLASH_BOOTLOADER=0
    else
      ui_print "[+] Proceeding to flash LK Fenrir & Preloader Eng to BOTH slots..."
      ACTION_FLASH_BOOTLOADER=1
    fi
  fi

  if [ "$ACTION_FLASH_BOOTLOADER" -eq 1 ]; then
    ui_print "[*] Flashing LK Fenrir to both slots..."
    if [ -n "$TARGET_LK_A" ] && [ -e "$TARGET_LK_A" ]; then
      blockdev --setrw "$TARGET_LK_A" 2>/dev/null || true
      dd if="$LK_IMG" of="$TARGET_LK_A" bs=4M
      ui_print "    [+] Flashed lk_a <- LK Fenrir"
    fi
    if [ -n "$TARGET_LK_B" ] && [ -e "$TARGET_LK_B" ]; then
      blockdev --setrw "$TARGET_LK_B" 2>/dev/null || true
      dd if="$LK_IMG" of="$TARGET_LK_B" bs=4M
      ui_print "    [+] Flashed lk_b <- LK Fenrir"
    fi

    ui_print "[*] Flashing Preloader Engineering to both slots..."
    if [ -n "$TARGET_PL_A" ] && [ -e "$TARGET_PL_A" ]; then
      blockdev --setrw "$TARGET_PL_A" 2>/dev/null || true
      if [ "$TARGET_PL_A" = "/dev/block/sda" ]; then
        dd if="$PL_IMG" of="$TARGET_PL_A" bs=4096 seek=1
      else
        dd if="$PL_IMG" of="$TARGET_PL_A" bs=4M
      fi
      ui_print "    [+] Flashed preloader slot A ($TARGET_PL_A) <- Preloader Eng"
    fi
    if [ -n "$TARGET_PL_B" ] && [ -e "$TARGET_PL_B" ]; then
      blockdev --setrw "$TARGET_PL_B" 2>/dev/null || true
      if [ "$TARGET_PL_B" = "/dev/block/sdb" ]; then
        dd if="$PL_IMG" of="$TARGET_PL_B" bs=4096 seek=1
      else
        dd if="$PL_IMG" of="$TARGET_PL_B" bs=4M
      fi
      ui_print "    [+] Flashed preloader slot B ($TARGET_PL_B) <- Preloader Eng"
    fi
    sync
    ui_print "[+] Bootloader security bypass active on both slots A & B."
  fi
fi

# 10. Backup Stock Boot Partitions and Provision Rootfs

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

    # Secure Halium & Stock boot/vendor_boot/dtbo backups early before rootfs extraction
    BACKUP_DIR="/data/media/0/.backup"
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    cp -f "$WORK/partitions/boot.img" "$BACKUP_DIR/boot_halium.img" 2>/dev/null || true
    cp -f "$WORK/partitions/vendor_boot.img" "$BACKUP_DIR/vendor_boot_halium.img" 2>/dev/null || true
    cp -f "$WORK/partitions/dtbo.img" "$BACKUP_DIR/dtbo_halium.img" 2>/dev/null || true

    for p in boot vendor_boot dtbo; do
      if [ -s "$WORK/stock_backup/${p}_stock.img" ]; then
        [ -s "$BACKUP_DIR/${p}_stock.img" ] || cp -f "$WORK/stock_backup/${p}_stock.img" "$BACKUP_DIR/${p}_stock.img" 2>/dev/null || true
      fi
    done
    ui_print "[+] Secured kernel backups in $BACKUP_DIR"

    # Check if a valid Ubuntu Touch rootfs is already installed
    IS_ROOTFS_INSTALLED=0
    DO_CLEAN_INSTALL=0

    if [ -f "/data/.clean_install" ] || [ -f "/data/ubuntu/.clean_install" ] || [ -f "/sdcard/.clean_install" ]; then
      ui_print "[!] Clean install flag detected (.clean_install)."
      DO_CLEAN_INSTALL=1
    elif [ -d "/data/ubuntu/usr" ] && [ -d "/data/ubuntu/etc" ] && [ -f "/data/ubuntu/etc/os-release" ]; then
      IS_ROOTFS_INSTALLED=1
    fi

    # Interactive prompt if an existing rootfs is found (defaults to Direct Update without wiping rootfs)
    if [ "$IS_ROOTFS_INSTALLED" -eq 1 ] && [ "$DO_CLEAN_INSTALL" -eq 0 ]; then
      if [ -f "/data/.update" ] || [ -f "/data/ubuntu/.update" ] || [ -f "/sdcard/.update" ]; then
        ui_print "[+] Direct update flag detected (.update). Preserving /data/ubuntu rootfs."
        DO_CLEAN_INSTALL=0
      else
        ui_print "=============================================="
        ui_print " Ubuntu Touch Direct Update Selection "
        ui_print "=============================================="
        ui_print "[*] Existing Ubuntu Touch installation detected in /data/ubuntu."
        ui_print "[?] Choose installation mode (Default: DIRECT UPDATE in 5s):"
        ui_print "    -> DIRECT UPDATE: Preserves /data/ubuntu (keeps apps, personal files & data)."
        ui_print "                      Updates Halium kernel, bootloader, and device system overlay."
        ui_print "    -> CLEAN INSTALL: Wipes /data/ubuntu and performs a fresh rootfs extraction."
        ui_print ""
        ui_print "    -> Press Volume UP within 5s for CLEAN INSTALL (Wipe /data/ubuntu)"
        ui_print "    -> Press Volume DOWN or wait 5s for DIRECT UPDATE (Preserve rootfs)"

        KEY_PRESSED=""
        if [ -n "$KPD_DEV" ] && [ -e "$KPD_DEV" ] && which getevent >/dev/null 2>&1; then
          EV_DATA=$("$BB" timeout 5 getevent -c 2 "$KPD_DEV" 2>/dev/null || true)
          case "$EV_DATA" in
            *0073*|*0001*0073*) KEY_PRESSED="UP" ;;
            *0072*|*0001*0072*) KEY_PRESSED="DOWN" ;;
          esac
        else
          "$BB" sleep 5 2>/dev/null || sleep 5
        fi

        if [ "$KEY_PRESSED" = "UP" ]; then
          ui_print "[!] Volume UP pressed: Clean install selected."
          DO_CLEAN_INSTALL=1
        else
          ui_print "[+] Direct update selected: Preserving /data/ubuntu rootfs & user data."
          DO_CLEAN_INSTALL=0
        fi
      fi
    fi

    if [ "$DO_CLEAN_INSTALL" -eq 1 ]; then
      ui_print "[*] Removing existing /data/ubuntu rootfs for clean install..."
      rm -rf /data/ubuntu
      mkdir -p /data/ubuntu
      rm -f /data/.clean_install /data/ubuntu/.clean_install /sdcard/.clean_install 2>/dev/null || true
      ui_print "[*] Extracting ubuntu-touch-hybris-rootfs-arm64.tar.gz to /data/ubuntu..."
      unzip -p "$ZIPFILE" "ubuntu-touch-hybris-rootfs-arm64.tar.gz" | "$BB" tar --numeric-owner -xzpf - -C /data/ubuntu/
    else
      if [ "$IS_ROOTFS_INSTALLED" -eq 1 ]; then
        ui_print "[*] Preserving existing /data/ubuntu rootfs (user data, configs, packages kept intact)."
        ui_print "[*] Proceeding with direct update of device overlay, kernel, and configs..."
      else
        ui_print "[*] Fresh install: Extracting ubuntu-touch-hybris-rootfs-arm64.tar.gz to /data/ubuntu..."
        unzip -p "$ZIPFILE" "ubuntu-touch-hybris-rootfs-arm64.tar.gz" | "$BB" tar --numeric-owner -xzpf - -C /data/ubuntu/
      fi
    fi

    # Extract Halium 12 LXC container (android-rootfs.img)
    mkdir -p /data/ubuntu/var/lib/lxc/android
    if [ ! -s "/data/ubuntu/var/lib/lxc/android/android-rootfs.img" ]; then
      if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "halium_halium_arm64.tar.xz"; then
        ui_print "[*] Extracting android-rootfs.img from halium_halium_arm64.tar.xz..."
        unzip -p "$ZIPFILE" "halium_halium_arm64.tar.xz" | "$BB" xzcat | "$BB" tar --numeric-owner -xpf - --strip-components=1 -C /data/ubuntu/ system/var/lib/lxc/android/android-rootfs.img 2>/dev/null || \
        unzip -p "$ZIPFILE" "halium_halium_arm64.tar.xz" | "$BB" tar --numeric-owner -xJf - --strip-components=1 -C /data/ubuntu/ system/var/lib/lxc/android/android-rootfs.img 2>/dev/null || true
      elif unzip -l "$ZIPFILE" 2>/dev/null | grep -q "android-rootfs.img"; then
        ui_print "[*] Extracting android-rootfs.img..."
        unzip -p "$ZIPFILE" "android-rootfs.img" > /data/ubuntu/var/lib/lxc/android/android-rootfs.img
      fi
      chmod 644 /data/ubuntu/var/lib/lxc/android/android-rootfs.img 2>/dev/null || true
    else
      ui_print "[*] Android LXC container (android-rootfs.img) already present, skipping."
    fi

    ui_print "[*] Applying device_tanzanite_system.tar.gz overlay to /data/ubuntu..."
    rm -f /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/server-platform/graphics-android.so.15 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/server-platform/graphics-android-caf.so.15 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/client-platform/android.so.5 \
          /data/ubuntu/usr/lib/aarch64-linux-gnu/mir/client-platform/android-caf.so.5

    # Decompress outside chroot via busybox gzip, pass uncompressed stream to chroot tar with explicit PATH, fallback to busybox tar
    if ! unzip -p "$ZIPFILE" "device_tanzanite_system.tar.gz" | "$BB" gzip -dc | chroot /data/ubuntu /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/tar --numeric-owner --overwrite -xpf - -C / 2>/dev/null; then
      ui_print "[*] Using busybox tar to apply device overlay..."
      unzip -p "$ZIPFILE" "device_tanzanite_system.tar.gz" | "$BB" gzip -dc | "$BB" tar --numeric-owner -xpf - -C /data/ubuntu/
    fi
    touch /data/ubuntu/.writable_image /data/.writable_image /data/.force-adb /data/ubuntu/.rootfs_installed

    [ -d "/data/ubuntu/usr" ] && [ -d "/data/ubuntu/etc" ] && [ -s "/data/ubuntu/var/lib/lxc/android/android-rootfs.img" ] || abort "Rootfs extraction verification failed!"
    if [ "$IS_ROOTFS_INSTALLED" -eq 1 ]; then
      ui_print "[+] Ubuntu Touch rootfs updated with latest device overlay!"
    else
      ui_print "[+] Ubuntu Touch rootfs, Android LXC container & device overlay extracted to /data/ubuntu!"
    fi

    # Write build manifest to /data/ubuntu/etc/tanzanite-build.prop
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "META-INF/tanzanite/build.prop"; then
      unzip -p "$ZIPFILE" "META-INF/tanzanite/build.prop" > /data/ubuntu/etc/tanzanite-build.prop 2>/dev/null || true
      chmod 644 /data/ubuntu/etc/tanzanite-build.prop 2>/dev/null || true
      ui_print "[+] Updated build manifest: /etc/tanzanite-build.prop"
    fi

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

# 11. Flash Halium boot, vendor_boot, and dtbo to active slot
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
