# Tanzanite Halium 12 Dual-Boot Flashing & Installation Guide

> **Device**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789) — dual-boot HyperOS + Ubuntu Touch 20.04 (Halium 12), unencrypted ext4 `/data`.
> 
> 🌐 **Other Languages / Bahasa Lain**: [Bahasa Indonesia (FLASHING_GUIDE_id.md)](FLASHING_GUIDE_id.md)

---

Step-by-step installation guide for setting up **Ubuntu Touch 20.04 (Focal Fossa)** in a dual-boot configuration alongside **HyperOS / Android** on the **Redmi Note 14 4G (`tanzanite`)**.

---

## 📋 1. Prerequisites & Required Files

### Device Requirements
- **Device**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Unlocked (UBL).
- **Custom Recovery**: **OrangeFox Recovery** or **TWRP** installed with A/B slot and terminal support.
- **Android Root (HyperOS)**: **KernelSU** installed (recommended) or Magisk to permit the switcher app to manage boot partitions.

### Required Files
1. **`Format-Data-Ext4-Tanzanite.zip`**: Flashable recovery utility to format `/data` (`userdata`) to clean unencrypted ext4 (fixes OrangeFox GUI format bugs).
2. **`tanzanite-halium.zip`**: Flashable recovery installer package (contains Halium kernel, vendor fstab patch, AVB patch, Ubuntu Touch rootfs, and device overlay).
3. **`TanzaniteSwitcher-v1.0.0.apk`**: Native Android companion app for 1-tap switching.
4. MicroSD card or USB OTG flash drive (or a PC with ADB cable for ADB Sideload / ADB Push).

> [!CAUTION]
> **IMPORTANT: Back Up All Personal Data!**
> Ubuntu Touch requires the `/data` (`userdata`) partition to be formatted as **unencrypted ext4 (FBE disabled)**. Performing the data format will **ERASE ALL USER DATA** from internal storage. Back up all vital files to a PC or MicroSD card before proceeding.

---

## 🛠️ 2. Step-by-Step Installation

### Step 1: Boot into Custom Recovery
1. Power off the device completely.
2. Press and hold **Power + Volume Up** buttons simultaneously until the recovery splash screen (OrangeFox / TWRP) appears.

### Step 2: Format Data to Unencrypted ext4
> [!TIP]
> **Resolving OrangeFox Tanzanite Format Bugs**:
> OrangeFox on Tanzanite frequently encounters errors or fails to completely strip FBE/F2FS metadata when formatting `/data` via the recovery touch GUI (partition left busy or misdetected). Use **Method A** with the provided flashable zip for a guaranteed clean format.

#### Method A: Flashable Zip Utility (Highly Recommended)
1. Copy `Format-Data-Ext4-Tanzanite.zip` to a MicroSD / USB OTG drive (or use **Advanced > ADB Sideload**).
2. In recovery, select **Install** (or run `adb sideload Format-Data-Ext4-Tanzanite.zip`).
3. Swipe to confirm flash. The script will automatically:
   - Terminate active locks and forcefully unmount `/data` & `/sdcard`.
   - Zero out partition headers and footers (erasing F2FS magic and FBE crypto tokens).
   - Format `userdata` to 4K ext4 (`-b 4096`) with a 1% reservation ratio.
   - Initialize `/data/media/0` internal storage directory structure with proper `media_rw` permissions.
4. **Mandatory Recovery Reboot**:
   - Go to **Reboot** > select **Recovery**.
   - *This step is essential so the recovery kernel refreshes its partition table.*

#### Method B: Manual via Recovery GUI
1. From the recovery main menu, navigate to **Wipe** > select **Format Data**.
2. Type `yes` and confirm.
3. Open **Manage Partitions** / **Partition Options**:
   - Select the **Data** partition -> tap **Change FS** -> choose **ext4** -> swipe to confirm.
   - (If accessible in the recovery menu) Perform the same step for the **Metadata** partition to format it to **ext4**.
4. **Mandatory Recovery Reboot**:
   - Go to **Reboot** > select **Recovery**.

### Step 3: Ensure Active Slot is Slot A
1. Navigate to the **Reboot** menu in recovery.
2. Verify that the active slot is **Slot A**:
   - If currently set to Slot B, switch to Slot A and reboot into recovery once more.
   - *Note*: Slot B is preserved untouched as a clean stock HyperOS rescue/fallback slot.

### Step 4: Flash `tanzanite-halium.zip`
1. Connect the phone to your PC or insert your MicroSD/OTG drive.
2. Push or copy `tanzanite-halium.zip` to the device:
   ```bash
   adb push tanzanite-halium.zip /sdcard/
   # or if /sdcard is not mounted yet:
   adb push tanzanite-halium.zip /tmp/
   ```
3. In recovery, go to **Install / Files**.
4. Select `tanzanite-halium.zip` and swipe to confirm (**Swipe to Flash**).
5. The installer will execute the following tasks automatically:
   - Identifies the active slot (`_a`).
   - Patches `/vendor/etc/fstab.mt6789` (changes userdata mount to unencrypted ext4).
   - Patches AVB verification and dm-verity on `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` (flags set to `0x03`).
   - Backs up stock `boot`, `vendor_boot`, and `dtbo` partitions to `/sdcard/.backup/`.
   - Extracts Ubuntu Touch rootfs & the Halium LXC container into `/data/ubuntu`.
   - Deploys HWC2 display platform drivers (`mir-android2`), audio routing, and udev rules.
   - Sets up `apt` sandbox configuration and the KernelSU FUSE-BPF fix under `/data/adb/post-fs-data.d/`.
   - Flashes the Halium kernel (`boot`, `vendor_boot`, `dtbo`) directly into Slot A.

### Step 5: Initial Boot into Ubuntu Touch
1. Once the terminal displays `Patching completed successfully!`, select **Reboot System**.
2. The device will boot straight into the **Ubuntu Touch (Lomiri)** desktop environment.
3. Complete the initial setup wizard (language, Wi-Fi, lockscreen passcode).
   - **Default Credentials**:
     - User: `phablet`
     - Root/Terminal access: `sudo` without password for predefined utility commands.

---

## 🔄 3. Using Dual-Boot Switching

### Switching from Ubuntu Touch to HyperOS (Android)
1. Open the **Terminal** app on Ubuntu Touch.
2. Run:
   ```bash
   sudo boot-to-android
   ```
3. The script will restore the stock Android boot kernel and reboot your phone straight into HyperOS.

### Switching from HyperOS to Ubuntu Touch
1. Once booted into HyperOS, install the switcher companion app:
   - Install [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Launch the **Tanzanite Switcher** app.
3. Grant **Root / Superuser** permissions when prompted by KernelSU / Magisk.
4. On the main dashboard, tap **Switch to Ubuntu Touch**.
5. The app writes the Halium boot partition from local backup and automatically reboots the phone into Ubuntu Touch.

---

## 🔧 4. Technical Notes & Troubleshooting

### A. Internal Storage (`/sdcard`) Permission Denied on HyperOS
If HyperOS apps cannot access your photos, downloads, or internal storage:
- **Cause**: FUSE-BPF on the MT6789 kernel enforces strict lower-inode credential checks. If `/data/media/0` lacks `media_rw` group ownership, apps are denied access.
- **Fix**:
  1. Ensure the KernelSU post-fs-data hook exists at `/data/adb/post-fs-data.d/99-disable-fuse-bpf.sh`:
     ```sh
     resetprop ro.fuse.bpf.enabled false
     resetprop ro.fuse.bpf.is_running false
     resetprop persist.sys.fuse.bpf.override false
     resetprop persist.sys.fuse.passthrough.enable false
     ```
  2. Open a root terminal in Android and restore directory permissions:
     ```sh
     chown -R 1023:1023 /data/media
     chmod 770 /data/media
     chmod 2770 /data/media/0
     ```

### B. `apt install` Package Dependency Errors in Ubuntu Touch
- **Cause**: Sandboxing for the `_apt` user fails inside Halium LXC containers, and obsolete metapackages depend on deprecated HWC1 drivers.
- **Fix**: The `tanzanite-halium.zip` installer configures this automatically. For manual recovery, verify `/etc/apt/apt.conf.d/90-android-sandbox.conf` contains:
  ```text
  APT::Sandbox::User "root";
  ```
- Refer to [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md) for deeper technical analysis.

---

## 👥 5. Community & Support

- **Repository**: [https://github.com/iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium)
- **Telegram Discussion Group**: [https://t.me/idiscuss1](https://t.me/idiscuss1)
- **Telegram Maintainer Contact**: [https://t.me/anotherside551](https://t.me/anotherside551)
- **Donation & Support**: [https://sociabuzz.com/fxxyz73/tribe](https://sociabuzz.com/fxxyz73/tribe)
