# Panduan Flashing & Instalasi Dual-Boot Tanzanite Halium 12

Panduan langkah demi langkah untuk melakukan instalasi **Ubuntu Touch 20.04 (Focal Fossa)** dual-boot bersama **HyperOS / Android** pada **Redmi Note 14 4G (`tanzanite`)**.

---

## 📋 1. Prasyarat & Bahan

### Persyaratan Perangkat
- **Perangkat**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Sudah di-*Unlock* (UBL).
- **Custom Recovery**: Terpasang **OrangeFox Recovery** atau **TWRP** yang mendukung perangkat A/B dan terminal.
- **Root di Android (HyperOS)**: Terpasang **KernelSU** (direkomendasikan) atau Magisk agar switcher app dapat berjalan.

### File yang Dibutuhkan
1. **`tanzanite-halium.zip`**: File installer flashable recovery (berisi kernel Halium, vendor patch, AVB patch, rootfs Ubuntu Touch, dan overlay driver).
2. **`TanzaniteSwitcher-v1.0.0.apk`**: Aplikasi Android untuk berpindah OS secara instan.
3. MicroSD atau Flashdisk OTG (atau PC dengan kabel data untuk ADB Sideload / ADB Push).

> [!CAUTION]
> **PENTING: Backup Data Anda!**
> Karena Ubuntu Touch memerlukan partisi `/data` (`userdata`) berformat **ext4 tanpa enkripsi (FBE unencrypted)**, Anda **WAJIB** melakukan format data yang akan **MENGHAPUS SEMUA DATA** di penyimpanan internal. Salin semua file penting ke PC atau MicroSD sebelum melanjutkan.

---

## 🛠️ 2. Langkah-langkah Instalasi

### Langkah 1: Masuk ke Custom Recovery
1. Matikan perangkat.
2. Tahan tombol **Power + Volume Up** secara bersamaan hingga logo recovery (OrangeFox / TWRP) muncul.

---

### Langkah 2: Format Data ke Unencrypted ext4
1. Di menu utama recovery, masuk ke menu **Wipe** > pilih **Format Data**.
2. Ketik `yes` lalu konfirmasi.
3. Masuk ke **Manage Partitions** / **Partition Options**:
   - Pilih partisi **Data** -> ketuk **Change FS** -> pilih **ext4** -> geser untuk konfirmasi.
   - (Jika tersedia di opsi menu) Lakukan hal yang sama pada partisi **Metadata** ke **ext4**.
4. **Wajib Reboot Recovery**:
   - Pilih **Reboot** > **Recovery**.
   - Langkah ini krusial agar kernel recovery memuat ulang tabel partisi ext4 yang baru.

---

### Langkah 3: Pastikan Slot Aktif di Slot A
1. Buka menu **Reboot** di recovery.
2. Pastikan slot yang aktif adalah **Slot A**:
   - Jika saat ini di Slot B, ganti ke Slot A lalu reboot recovery kembali ke Slot A.
   - *Catatan*: Slot B dibiarkan utuh sebagai cadangan (fallback/rescue) stock HyperOS.

---

### Langkah 4: Flash Installer `tanzanite-halium.zip`
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

---

### Langkah 5: Booting Pertama ke Ubuntu Touch
1. Setelah installer menampilkan pesan `Patching completed successfully!`, pilih **Reboot System**.
2. Perangkat akan melakukan booting langsung ke antarmuka **Ubuntu Touch (Lomiri)**.
3. Selesaikan wizard konfigurasi awal (bahasa, Wi-Fi, passcode layar).
   - **Kredensial Default**:
     - Pengguna: `phablet`
     - Terminal/Root: Dapat menggunakan `sudo` tanpa password untuk perintah utilitas tertentu.

---

## 🔄 3. Menggunakan Fitur Dual-Boot

### Beralih dari Ubuntu Touch ke HyperOS (Android)
1. Buka aplikasi **Terminal** di Ubuntu Touch.
2. Jalankan perintah:
   ```bash
   sudo boot-to-android
   ```
3. Perangkat akan merestore boot kernel Android secara otomatis dan me-reboot ponsel ke HyperOS.

---

### Beralih dari HyperOS ke Ubuntu Touch
1. Setelah masuk ke HyperOS, install aplikasi switcher:
   - Pasang file [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Buka aplikasi **Tanzanite Switcher**.
3. Berikan izin **Root / Superuser** saat jendela KernelSU / Magisk muncul.
4. Pada dashboard aplikasi, ketuk tombol **Switch to Ubuntu Touch**.
5. Aplikasi akan mem-flash boot Halium dari backup lokal dan otomatis me-reboot perangkat kembali ke Ubuntu Touch.

---

## 🔧 4. Catatan Teknis & Pemecahan Masalah (Troubleshooting)

### A. Internal Storage (`/sdcard`) Permission Denied di HyperOS
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

### B. Error Paket `apt install` di Ubuntu Touch
- **Penyebab**: Sandboxing user `_apt` tidak didukung pada Halium Android container, serta metapackage lawas bergantung pada driver HWC1.
- **Solusi**: Installer `tanzanite-halium.zip` sudah menyetel konfigurasi ini secara default. Jika terjadi kendala pada instalasi manual, pastikan baris berikut ada di `/etc/apt/apt.conf.d/90-android-sandbox.conf`:
  ```text
  APT::Sandbox::User "root";
  ```
- Detail lengkap troubleshooting dapat dibaca pada [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md).

---

## 👥 Bantuan & Dukungan
- Repositori: [https://github.com/iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium)
- Grup Diskusi Telegram: [https://t.me/idiscuss1](https://t.me/idiscuss1)
- Kontak Telegram: [https://t.me/anotherside551](https://t.me/anotherside551)
