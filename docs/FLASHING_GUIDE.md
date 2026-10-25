# Tanzanite Halium 12 Dual-Boot Flashing & Installation Guide

> Device: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789) — dual-boot HyperOS + Ubuntu Touch 20.04 (Halium 12), unencrypted ext4 `/data`.

- [Bahasa Indonesia](#bahasa-indonesia)
- [English](#english)

---

## Bahasa Indonesia

Panduan langkah demi langkah untuk melakukan instalasi **Ubuntu Touch 20.04 (Focal Fossa)** dual-boot bersama **HyperOS / Android** pada **Redmi Note 14 4G (`tanzanite`)**.

### 📋 1. Prasyarat & Bahan

#### Persyaratan Perangkat
- **Perangkat**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Sudah di-*Unlock* (UBL).
- **Custom Recovery**: Terpasang **OrangeFox Recovery** atau **TWRP** yang mendukung perangkat A/B dan terminal.
- **Root di Android (HyperOS)**: Terpasang **KernelSU** (direkomendasikan) atau Magisk agar switcher app dapat berjalan.

#### File yang Dibutuhkan
1. **`Format-Data-Ext4-Tanzanite.zip`**: File flashable recovery untuk memformat partisi `/data` (`userdata`) ke ext4 tanpa enkripsi (mengatasi bug bawaan GUI OrangeFox).
2. **`tanzanite-halium.zip`**: File installer flashable recovery utama (berisi kernel Halium, vendor patch, AVB patch, rootfs Ubuntu Touch, dan overlay driver).
3. **`TanzaniteSwitcher-v1.0.0.apk`**: Aplikasi Android untuk berpindah OS secara instan.
4. MicroSD atau Flashdisk OTG (atau PC dengan kabel data untuk ADB Sideload / ADB Push).

> [!CAUTION]
> **PENTING: Backup Data Anda!**
> Karena Ubuntu Touch memerlukan partisi `/data` (`userdata`) berformat **ext4 tanpa enkripsi (FBE unencrypted)**, Anda **WAJIB** melakukan format data yang akan **MENGHAPUS SEMUA DATA** di penyimpanan internal. Salin semua file penting ke PC atau MicroSD sebelum melanjutkan.

### 🛠️ 2. Langkah-langkah Instalasi

#### Langkah 1: Masuk ke Custom Recovery
1. Matikan perangkat.
2. Tahan tombol **Power + Volume Up** secara bersamaan hingga logo recovery (OrangeFox / TWRP) muncul.

#### Langkah 2: Format Data ke Unencrypted ext4
> [!TIP]
> **Mengatasi Bug Format OrangeFox Tanzanite**:
> OrangeFox versi Tanzanite sering gagal atau mengalami error saat memformat `/data` atau mengubah filesystem ke ext4 lewat menu GUI (partisi tertahan busy, atau enkripsi FBE/F2FS lama tidak terhapus bersih). Gunakan **Metode A** menggunakan script flashable yang telah disediakan.

**Metode A: Menggunakan Flashable Zip (Sangat Direkomendasikan)**:
1. Salin `Format-Data-Ext4-Tanzanite.zip` ke MicroSD / OTG (atau gunakan menu **Advanced > ADB Sideload**).
2. Di recovery, buka menu **Install** (atau `adb sideload Format-Data-Ext4-Tanzanite.zip`).
3. Geser konfirmasi untuk mem-flash. Script akan otomatis:
   - Melepaskan kuncian proses dan melakukan unmount paksa pada `/data` & `/sdcard`.
   - Meng-zero out header & footer partisi (menghapus tuntas signature F2FS & crypto tokens FBE).
   - Memformat partisi `userdata` ke ext4 4K block size (`-b 4096`) dengan reserve 1%.
   - Menginisialisasi kerangka direktori internal storage `/data/media/0` dengan permission `media_rw`.
4. **Wajib Reboot Recovery**:
   - Pilih menu **Reboot** > **Recovery**.
   - *Langkah ini mutlak diperlukan agar kernel recovery memuat ulang tabel partisi ext4 yang baru.*

**Metode B: Manual via Menu Recovery GUI**:
1. Di menu utama recovery, masuk ke menu **Wipe** > pilih **Format Data**.
2. Ketik `yes` lalu konfirmasi.
3. Masuk ke **Manage Partitions** / **Partition Options**:
   - Pilih partisi **Data** -> ketuk **Change FS** -> pilih **ext4** -> geser untuk konfirmasi.
   - (Jika tersedia di opsi menu) Lakukan hal yang sama pada partisi **Metadata** ke **ext4**.
4. **Wajib Reboot Recovery**:
   - Pilih **Reboot** > **Recovery**.

#### Langkah 3: Pastikan Slot Aktif di Slot A
1. Buka menu **Reboot** di recovery.
2. Pastikan slot yang aktif adalah **Slot A**:
   - Jika saat ini di Slot B, ganti ke Slot A lalu reboot recovery kembali ke Slot A.
   - *Catatan*: Slot B dibiarkan utuh sebagai cadangan (fallback/rescue) stock HyperOS.

#### Langkah 4: Flash Installer `tanzanite-halium.zip`
1. Hubungkan HP ke PC via kabel data atau gunakan MicroSD / OTG.
2. Salin file `tanzanite-halium.zip` ke perangkat:
   ```bash
   adb push tanzanite-halium.zip /sdcard/
   # atau jika storage belum termount:
   adb push tanzanite-halium.zip /tmp/
   ```
3. Di recovery, buka menu **Install / Files**.
4. Pilih file `tanzanite-halium.zip` lalu geser untuk mengonfirmasi (*Swipe to Flash*).
5. Tunggu proses instalasi berjalan otomatis:
   - Script akan mem-patch `/vendor/etc/fstab.mt6789` (mengubah userdata ke ext4 unencrypted).
   - Menonaktifkan AVB verification dan dm-verity pada `vbmeta`, `vbmeta_system`, dan `vbmeta_vendor`.
   - Mengambil backup `boot`, `vendor_boot`, dan `dtbo` stock ke `/sdcard/.backup/`.
   - Mengekstrak rootfs Ubuntu Touch + LXC container Halium ke `/data/ubuntu`.
   - Memasang driver grafis HWC2, konfigurasi audio, udev rules, dan fix `apt`.
   - Memasang hook KernelSU FUSE-BPF fix di `/data/adb/post-fs-data.d/`.
   - Mem-flash image kernel Halium (`boot`, `vendor_boot`, `dtbo`) ke Slot A.

#### Langkah 5: Booting Pertama ke Ubuntu Touch
1. Setelah installer menampilkan pesan `Patching completed successfully!`, pilih **Reboot System**.
2. Perangkat akan melakukan booting langsung ke antarmuka **Ubuntu Touch (Lomiri)**.
3. Selesaikan wizard konfigurasi awal (bahasa, Wi-Fi, passcode layar).
   - **Kredensial Default**:
     - Pengguna: `phablet`
     - Terminal/Root: Dapat menggunakan `sudo` tanpa password untuk perintah utilitas tertentu.

### 🔄 3. Menggunakan Fitur Dual-Boot

#### Beralih dari Ubuntu Touch ke HyperOS (Android)
1. Buka aplikasi **Terminal** di Ubuntu Touch.
2. Jalankan perintah:
   ```bash
   sudo boot-to-android
   ```
3. Perangkat akan merestore boot kernel Android secara otomatis dan me-reboot ponsel ke HyperOS.

#### Beralih dari HyperOS ke Ubuntu Touch
1. Setelah masuk ke HyperOS, install aplikasi switcher:
   - Pasang file [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Buka aplikasi **Tanzanite Switcher**.
3. Berikan izin **Root / Superuser** saat jendela KernelSU / Magisk muncul.
4. Pada dashboard aplikasi, ketuk tombol **Switch to Ubuntu Touch**.
5. Aplikasi akan mem-flash boot Halium dari backup lokal dan otomatis me-reboot perangkat kembali ke Ubuntu Touch.

### 🔧 4. Catatan Teknis & Pemecahan Masalah (Troubleshooting)

#### A. Internal Storage (`/sdcard`) Permission Denied di HyperOS
Jika aplikasi di HyperOS tidak dapat membaca galeri, unduhan, atau `/sdcard`:
- **Penyebab**: FUSE-BPF pada kernel MT6789 memblokir akses jika inode direktori `/data/media/0` belum memiliki atribut `media_rw`.
- **Solusi**:
  1. Pastikan script KernelSU berikut aktif di `/data/adb/post-fs-data.d/99-disable-fuse-bpf.sh`:
     ```sh
     resetprop ro.fuse.bpf.enabled false
     resetprop ro.fuse.bpf.is_running false
     resetprop persist.sys.fuse.bpf.override false
     resetprop persist.sys.fuse.passthrough.enable false
     ```
  2. Buka terminal root di Android dan jalankan perbaikan permission:
     ```sh
     chown -R 1023:1023 /data/media
     chmod 770 /data/media
     chmod 2770 /data/media/0
     ```

#### B. Error Paket `apt install` di Ubuntu Touch
- **Penyebab**: Sandboxing user `_apt` tidak didukung pada Halium Android container, serta metapackage lawas bergantung pada driver HWC1.
- **Solusi**: Installer `tanzanite-halium.zip` sudah menyetel konfigurasi ini secara default. Jika terjadi kendala pada instalasi manual, pastikan baris berikut ada di `/etc/apt/apt.conf.d/90-android-sandbox.conf`:
  ```text
  APT::Sandbox::User "root";
  ```
- Detail lengkap troubleshooting dapat dibaca pada [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md).

---

## English

Step-by-step installation guide for setting up **Ubuntu Touch 20.04 (Focal Fossa)** in a dual-boot configuration alongside **HyperOS / Android** on the **Redmi Note 14 4G (`tanzanite`)**.

### 📋 1. Prerequisites & Required Files

#### Device Requirements
- **Device**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Unlocked (UBL).
- **Custom Recovery**: **OrangeFox Recovery** or **TWRP** installed with A/B slot and terminal support.
- **Android Root (HyperOS)**: **KernelSU** installed (recommended) or Magisk to permit the switcher app to manage boot partitions.

#### Required Files
1. **`Format-Data-Ext4-Tanzanite.zip`**: Flashable recovery utility to format `/data` (`userdata`) to clean unencrypted ext4 (fixes OrangeFox GUI format bugs).
2. **`tanzanite-halium.zip`**: Flashable recovery installer package (contains Halium kernel, vendor fstab patch, AVB patch, Ubuntu Touch rootfs, and device overlay).
3. **`TanzaniteSwitcher-v1.0.0.apk`**: Native Android companion app for 1-tap switching.
4. MicroSD card or USB OTG flash drive (or a PC with ADB cable for ADB Sideload / ADB Push).

> [!CAUTION]
> **IMPORTANT: Back Up All Personal Data!**
> Ubuntu Touch requires the `/data` (`userdata`) partition to be formatted as **unencrypted ext4 (FBE disabled)**. Performing the data format will **ERASE ALL USER DATA** from internal storage. Back up all vital files to a PC or MicroSD card before proceeding.

### 🛠️ 2. Step-by-Step Installation

#### Step 1: Boot into Custom Recovery
1. Power off the device completely.
2. Press and hold **Power + Volume Up** buttons simultaneously until the recovery splash screen (OrangeFox / TWRP) appears.

#### Step 2: Format Data to Unencrypted ext4
> [!TIP]
> **Resolving OrangeFox Tanzanite Format Bugs**:
> OrangeFox on Tanzanite frequently encounters errors or fails to completely strip FBE/F2FS metadata when formatting `/data` via the recovery touch GUI (partition left busy or misdetected). Use **Method A** with the provided flashable zip for a guaranteed clean format.

**Method A: Flashable Zip Utility (Highly Recommended)**:
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

**Method B: Manual via Recovery GUI**:
1. From the recovery main menu, navigate to **Wipe** > select **Format Data**.
2. Type `yes` and confirm.
3. Open **Manage Partitions** / **Partition Options**:
   - Select the **Data** partition -> tap **Change FS** -> choose **ext4** -> swipe to confirm.
   - (If accessible in the recovery menu) Perform the same step for the **Metadata** partition to format it to **ext4**.
4. **Mandatory Recovery Reboot**:
   - Go to **Reboot** > select **Recovery**.

#### Step 3: Ensure Active Slot is Slot A
1. Navigate to the **Reboot** menu in recovery.
2. Verify that the active slot is **Slot A**:
   - If currently set to Slot B, switch to Slot A and reboot into recovery once more.
   - *Note*: Slot B is preserved untouched as a clean stock HyperOS rescue/fallback slot.

#### Step 4: Flash `tanzanite-halium.zip`
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

#### Step 5: Initial Boot into Ubuntu Touch
1. Once the terminal displays `Patching completed successfully!`, select **Reboot System**.
2. The device will boot straight into the **Ubuntu Touch (Lomiri)** desktop environment.
3. Complete the initial setup wizard (language, Wi-Fi, lockscreen passcode).
   - **Default Credentials**:
     - User: `phablet`
     - Root/Terminal access: `sudo` without password for predefined utility commands.

### 🔄 3. Using Dual-Boot Switching

#### Switching from Ubuntu Touch to HyperOS (Android)
1. Open the **Terminal** app on Ubuntu Touch.
2. Run:
   ```bash
   sudo boot-to-android
   ```
3. The script will restore the stock Android boot kernel and reboot your phone straight into HyperOS.

#### Switching from HyperOS to Ubuntu Touch
1. Once booted into HyperOS, install the switcher companion app:
   - Install [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Launch the **Tanzanite Switcher** app.
3. Grant **Root / Superuser** permissions when prompted by KernelSU / Magisk.
4. On the main dashboard, tap **Switch to Ubuntu Touch**.
5. The app writes the Halium boot partition from local backup and automatically reboots the phone into Ubuntu Touch.

### 🔧 4. Technical Notes & Troubleshooting

#### A. Internal Storage (`/sdcard`) Permission Denied on HyperOS
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

#### B. `apt install` Package Dependency Errors in Ubuntu Touch
- **Cause**: Sandboxing for the `_apt` user fails inside Halium LXC containers, and obsolete metapackages depend on deprecated HWC1 drivers.
- **Fix**: The `tanzanite-halium.zip` installer configures this automatically. For manual recovery, verify `/etc/apt/apt.conf.d/90-android-sandbox.conf` contains:
  ```text
  APT::Sandbox::User "root";
  ```
- Refer to [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md) for deeper technical analysis.

---

## 👥 Community & Support
- Repository: [https://github.com/iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium)
- Telegram Discussion Group: [https://t.me/idiscuss1](https://t.me/idiscuss1)
- Telegram Maintainer Contact: [https://t.me/anotherside551](https://t.me/anotherside551)
- Donation & Support: [https://sociabuzz.com/fxxyz73/tribe](https://sociabuzz.com/fxxyz73/tribe)
