# Troubleshooting: `/sdcard` di HyperOS & `apt install` di Ubuntu Touch

> Device: Xiaomi Redmi Note 14 4G (`tanzanite`, MT6789) — dual-boot HyperOS + Ubuntu Touch 20.04 (Halium 12), `/data` ext4 tanpa enkripsi.
> Kernel: `5.10.269-ColumbinaKernel` (KernelSU).

- [Bahasa Indonesia](#bahasa-indonesia)
- [English](#english)

---

## Bahasa Indonesia

### 1. `/sdcard` tidak bisa diakses di HyperOS (termasuk lewat ADB)

#### Gejala
- `adb shell ls /sdcard/` sebagai user `shell` (uid 2000) → `Permission denied`.
- Aplikasi biasa (contoh uid `10148`) → `ls: /sdcard/: Permission denied`.
- `ls -la /storage/emulated/0` menampilkan owner mentah dari `/data/media/0`, bukan atribut sintetis dari FUSE:
  ```
  dr-xr-x---  media_rw media_rw  /storage/emulated
  drwxrws---  media_rw media_rw  /storage/emulated/0
  drwxrwx---  u0_a219  u0_a219   /storage/emulated/0/Download   (dst.)
  ```
- Hanya `root` yang bisa membaca isi `/sdcard`.

#### Akar masalah
1. **FUSE-BPF aktif.** Secara default HyperOS menyetel `ro.fuse.bpf.is_running=true`, sehingga `vold` dan `MediaProvider` (`libfuse_jni.so`) memasang FUSE-BPF dengan *backing inode* ke `/data/media` (internal) dan `/mnt/media_rw/<UUID>` (SD card).
   Di implementasi FUSE-BPF kernel ini, cek izin dilakukan langsung pada inode bawah dengan kredensial pemanggil — lihat `inode_permission(backing_inode, mask)` di `fuse_open_backing()` dan `fuse_access_backing()` (`fs/fuse/backing.c`). Karena `/data/media/0` bermode `2770 media_rw:media_rw`, proses yang tidak ada di grup `media_rw` (ADB `shell`, aplikasi biasa) ditolak, dan `MediaProvider` tidak pernah sempat memberi keputusan.
2. **Owner/grup salah di `/data/media/0/*`.** Folder `/data/media/0/.backup` dibuat dari OrangeFox (sebagai `root:root`) **sebelum** HyperOS boot pertama di `/data` ext4 yang baru diformat. Akibatnya folder standar (`Download`, `DCIM`, `Pictures`, `MIUI`, …) dibuat oleh `MediaProvider` sebagai `u0_a219:u0_a219` mode `0770`, tanpa grup `media_rw` dan tanpa bit setgid.

#### Perbaikan
**a. Matikan FUSE-BPF secara permanen** lewat script `post-fs-data` KernelSU (dijalankan sebelum `vold` me-mount storage):

`/data/adb/post-fs-data.d/99-disable-fuse-bpf.sh`
```sh
#!/system/bin/sh
resetprop ro.fuse.bpf.enabled false
resetprop ro.fuse.bpf.is_running false
resetprop persist.sys.fuse.bpf.override false
resetprop persist.sys.fuse.passthrough.enable false
```
```sh
chmod 755 /data/adb/post-fs-data.d/99-disable-fuse-bpf.sh
```
Setelah reboot, `dmesg` harus menampilkan:
```
vold: fuse-bpf is disabled because of property ro.fuse.bpf.is_running
```

**b. Perbaiki grup & bit setgid di `/data/media/0`** (sebagai root):
```sh
cd /data/media/0
chgrp -R media_rw Alarms Audiobooks DCIM Documents Download MIUI Movies Music \
      Notifications Pictures Podcasts Recordings Ringtones .trash-storage .xlDownload
find /data/media/0 -maxdepth 2 -type d ! -name '.backup' -exec chmod 2770 {} +
chmod 2771 /data/media/0/Android /data/media/0/Android/data \
           /data/media/0/Android/obb /data/media/0/Android/media
```

> [!WARNING]
> Jangan menjalankan `sm unmount 'emulated;0'` untuk menguji perubahan ini secara live. Saat dicoba, perintah itu meninggalkan endpoint FUSE mati (`Transport endpoint is not connected`) dan membuat `sync`/`reboot` hang. Kalau sudah terlanjur, jalankan `for f in /sys/fs/fuse/connections/*/abort; do echo 1 > $f; done` lalu reboot.

#### Verifikasi
```sh
# sebagai shell (uid 2000) dan sebagai uid aplikasi
su 2000  -c 'ls /sdcard/Download'
su 10148 -c 'ls /sdcard/'

# dari PC
adb push test.txt /sdcard/Download/ && adb pull /sdcard/Download/test.txt
adb push test.txt /storage/<UUID-SD>/
```
Hasil yang sudah dicek: File Manager HyperOS bisa membuka **My phone** (Internal storage) dan **SD card**; `adb push`/`adb pull` ke `/sdcard/`, `/sdcard/Download/`, dan `/storage/7EDF-6880/` berhasil.

#### Pencegahan untuk instalasi baru
- Jangan membuat folder di `/data/media` dari recovery sebelum HyperOS boot pertama kali. Simpan backup di luar `/data/media/0` (misalnya di SD card), atau buat folder itu setelah HyperOS selesai setup awal.
- Pasang `99-disable-fuse-bpf.sh` segera setelah KernelSU aktif.

### 2. `apt install` gagal di Ubuntu Touch

#### Gejala
```
ubuntu-touch-hybris : Depends: mir-graphics-drivers-android but it is not installable
                      Depends: mir-graphics-drivers-android-caf but it is not installable
E: Unmet dependencies.
```

#### Akar masalah
Paket grafis HWC1 (`mir-platform-graphics-android15`) sudah diganti HWC2 (`mir-platform-graphics-android2-15`, `mir-client-platform-android2-5`, `mir-graphics-drivers-android2`) supaya Lomiri bisa jalan di MT6789. Tapi metapackage `ubuntu-touch-hybris` di database dpkg masih bergantung pada paket lama, jadi `apt` menolak semua instalasi. Selain itu, `/var/lib/apt/lists/` masih kosong.

#### Perbaikan (bisa dijalankan dari root shell HyperOS lewat `/data/ubuntu`, atau dari Ubuntu Touch tanpa prefix `/data/ubuntu`)
```sh
cp /data/ubuntu/var/lib/dpkg/status /data/ubuntu/var/lib/dpkg/status.bak
sed -i 's/mir-graphics-drivers-android, mir-graphics-drivers-android-caf/mir-graphics-drivers-android2/' \
    /data/ubuntu/var/lib/dpkg/status

# sandbox user _apt tidak bisa jalan di lingkungan Android/Halium
echo 'APT::Sandbox::User "root";' > /data/ubuntu/etc/apt/apt.conf.d/90-android-sandbox.conf

# opsional: boot-to-android tanpa password
echo 'phablet ALL=(ALL) NOPASSWD: /usr/bin/boot-to-android' \
    > /data/ubuntu/etc/sudoers.d/99-boot-to-android
chmod 440 /data/ubuntu/etc/sudoers.d/99-boot-to-android
```
Lalu di Ubuntu Touch:
```sh
sudo apt-get check
sudo apt update
sudo apt install <paket>
```

> [!NOTE]
> Di rootfs ini, `/var/lib/dpkg` dan `/var/lib/apt/lists` berada di `/data/ubuntu` (bukan di `/data/system-data`). Daftar paket sudah diunduh sebelumnya ke `/data/ubuntu/var/lib/apt/lists/`.

> [!IMPORTANT]
> Kalau `ubuntu-touch-hybris` di-upgrade dari repo, dependensi lama bisa muncul lagi. Ulangi patch `sed` di atas, atau pakai `apt-mark hold ubuntu-touch-hybris`.

---

## English

### 1. `/sdcard` inaccessible on HyperOS (including over ADB)

#### Symptoms
- `adb shell ls /sdcard/` as the `shell` user (uid 2000) → `Permission denied`.
- Regular apps (e.g. uid `10148`) → `ls: /sdcard/: Permission denied`.
- `ls -la /storage/emulated/0` shows the raw owners of `/data/media/0` instead of FUSE-synthesized attributes:
  ```
  dr-xr-x---  media_rw media_rw  /storage/emulated
  drwxrws---  media_rw media_rw  /storage/emulated/0
  drwxrwx---  u0_a219  u0_a219   /storage/emulated/0/Download   (etc.)
  ```
- Only `root` can read `/sdcard`.

#### Root cause
1. **FUSE-BPF is active.** HyperOS sets `ro.fuse.bpf.is_running=true` by default, so `vold` and `MediaProvider` (`libfuse_jni.so`) mount FUSE with FUSE-BPF *backing inodes* pointing at `/data/media` (internal) and `/mnt/media_rw/<UUID>` (SD card).
   In this kernel's FUSE-BPF implementation, permission checks run directly against the lower inode using the caller's credentials — see `inode_permission(backing_inode, mask)` in `fuse_open_backing()` and `fuse_access_backing()` (`fs/fuse/backing.c`). Because `/data/media/0` is `2770 media_rw:media_rw`, any process outside the `media_rw` group (ADB `shell`, regular apps) is rejected, and `MediaProvider` never gets to decide.
2. **Wrong owner/group on `/data/media/0/*`.** `/data/media/0/.backup` was created from OrangeFox (as `root:root`) **before** HyperOS first booted on the freshly formatted ext4 `/data`. As a result, `MediaProvider` created the standard folders (`Download`, `DCIM`, `Pictures`, `MIUI`, …) as `u0_a219:u0_a219` mode `0770`, without the `media_rw` group or the setgid bit.

#### Fix
**a. Disable FUSE-BPF permanently** with a KernelSU `post-fs-data` script (it runs before `vold` mounts storage):

`/data/adb/post-fs-data.d/99-disable-fuse-bpf.sh`
```sh
#!/system/bin/sh
resetprop ro.fuse.bpf.enabled false
resetprop ro.fuse.bpf.is_running false
resetprop persist.sys.fuse.bpf.override false
resetprop persist.sys.fuse.passthrough.enable false
```
```sh
chmod 755 /data/adb/post-fs-data.d/99-disable-fuse-bpf.sh
```
After a reboot, `dmesg` should show:
```
vold: fuse-bpf is disabled because of property ro.fuse.bpf.is_running
```

**b. Fix the group and setgid bits in `/data/media/0`** (as root):
```sh
cd /data/media/0
chgrp -R media_rw Alarms Audiobooks DCIM Documents Download MIUI Movies Music \
      Notifications Pictures Podcasts Recordings Ringtones .trash-storage .xlDownload
find /data/media/0 -maxdepth 2 -type d ! -name '.backup' -exec chmod 2770 {} +
chmod 2771 /data/media/0/Android /data/media/0/Android/data \
           /data/media/0/Android/obb /data/media/0/Android/media
```

> [!WARNING]
> Don't run `sm unmount 'emulated;0'` to test this live. When we tried it, it left a dead FUSE endpoint (`Transport endpoint is not connected`) and made `sync`/`reboot` hang. If that happens, run `for f in /sys/fs/fuse/connections/*/abort; do echo 1 > $f; done` and then reboot.

#### Verification
```sh
# as shell (uid 2000) and as an app uid
su 2000  -c 'ls /sdcard/Download'
su 10148 -c 'ls /sdcard/'

# from the PC
adb push test.txt /sdcard/Download/ && adb pull /sdcard/Download/test.txt
adb push test.txt /storage/<SD-UUID>/
```
Checked results: the HyperOS File Manager can open **My phone** (Internal storage) and **SD card**, and `adb push`/`adb pull` to `/sdcard/`, `/sdcard/Download/` and `/storage/7EDF-6880/` succeed.

#### Prevention on fresh installs
- Don't create anything under `/data/media` from recovery before HyperOS's first boot. Keep backups outside `/data/media/0` (e.g. on the SD card), or create the folder after HyperOS finishes initial setup.
- Install `99-disable-fuse-bpf.sh` as soon as KernelSU is available.

### 2. `apt install` fails on Ubuntu Touch

#### Symptoms
```
ubuntu-touch-hybris : Depends: mir-graphics-drivers-android but it is not installable
                      Depends: mir-graphics-drivers-android-caf but it is not installable
E: Unmet dependencies.
```

#### Root cause
The HWC1 graphics packages (`mir-platform-graphics-android15`) were replaced with HWC2 ones (`mir-platform-graphics-android2-15`, `mir-client-platform-android2-5`, `mir-graphics-drivers-android2`) so Lomiri runs on MT6789. The `ubuntu-touch-hybris` metapackage in the dpkg database still depended on the old packages, so `apt` refused every install. `/var/lib/apt/lists/` was also empty.

#### Fix (run from a HyperOS root shell via `/data/ubuntu`, or from Ubuntu Touch without the `/data/ubuntu` prefix)
```sh
cp /data/ubuntu/var/lib/dpkg/status /data/ubuntu/var/lib/dpkg/status.bak
sed -i 's/mir-graphics-drivers-android, mir-graphics-drivers-android-caf/mir-graphics-drivers-android2/' \
    /data/ubuntu/var/lib/dpkg/status

# the _apt sandbox user can't run in the Android/Halium environment
echo 'APT::Sandbox::User "root";' > /data/ubuntu/etc/apt/apt.conf.d/90-android-sandbox.conf

# optional: passwordless boot-to-android
echo 'phablet ALL=(ALL) NOPASSWD: /usr/bin/boot-to-android' \
    > /data/ubuntu/etc/sudoers.d/99-boot-to-android
chmod 440 /data/ubuntu/etc/sudoers.d/99-boot-to-android
```
Then, on Ubuntu Touch:
```sh
sudo apt-get check
sudo apt update
sudo apt install <package>
```

> [!NOTE]
> In this rootfs, `/var/lib/dpkg` and `/var/lib/apt/lists` live in `/data/ubuntu` (not `/data/system-data`). The package lists were pre-downloaded into `/data/ubuntu/var/lib/apt/lists/`.

> [!IMPORTANT]
> If `ubuntu-touch-hybris` gets upgraded from the repo, the old dependencies may come back. Re-apply the `sed` patch above, or run `apt-mark hold ubuntu-touch-hybris`.
