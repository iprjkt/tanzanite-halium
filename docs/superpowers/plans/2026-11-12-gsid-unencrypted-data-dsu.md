# Bypass `uses_dm` pada `gsid` untuk DSU di `/data` Unencrypted Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memungkinkan instalasi DSU (`gsid` / `DynamicSystemInstallationService`) di HyperOS pada partisi `/data` (`ext4` unencrypted) tanpa harus mengaktifkan enkripsi atau memformat ulang `/data`.

**Architecture:** Mem-patch 1 instruksi ARM64 pada fungsi `DetermineBlockDeviceForFile` di `/system/bin/gsid` (offset `0x6eac4`: `cset w8, ne` -> `mov w8, #1`) agar `*uses_dm` selalu bernilai `1` (`true`) sementara `bottom_dev` tetap mengarah ke `/dev/block/sdc75`, lalu memasangnya secara persisten melalui modul KernelSU `/data/adb/modules/gsid_unencrypted_fix` dan mengaktifkannya langsung via bind-mount.

**Tech Stack:** ARM64 ELF binary patching (`python3`, `llvm-objdump`), KernelSU module (`module.prop`, `post-fs-data.sh`), Android `adb` / `su`.

**Spec:** `/home/fxxyz73/tanzanite-halium/docs/superpowers/specs/2026-11-12-gsid-unencrypted-data-dsu-design.md`

## Global Constraints

- Jangan menyentuh atau memodifikasi `/data/media/0/.backup/skizophrenic.pem`.
- Jangan mem-flash atau menimpa `vendor_boot_a` (OrangeFox recovery).
- Pertahankan konfigurasi `/data/ubuntu` + `/data` `ext4` unencrypted tanpa format ulang.
- Konteks SELinux pada `/system/bin/gsid` wajib tetap `u:object_r:gsid_exec:s0` dengan izin `0755` dan pemilik `root:shell`.

## Review Focus

- Konteks SELinux `u:object_r:gsid_exec:s0` hilang saat bind-mount -> diverifikasi dengan `ls -laZ /system/bin/gsid` di Task 2.
- Proses `gsid` lama (PID yang sudah berjalan sebelum bind-mount) masih memegang binary lama di memori -> dihentikan (`killall gsid` / `stop gsid`) dan diverifikasi `/proc/$(pidof gsid)/maps` atau pembuatan ulang proses di Task 2.
- Ukuran atau byte di luar offset `0x6eac4` ikut berubah saat patching -> diverifikasi dengan perbandingan byte-per-byte (`cmp -l`) di Task 1.

---

### Task 1: Buat Modul KernelSU & Patch Binary `gsid` di Repositori `tanzanite-halium`

**Files:**
- Create: `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/module.prop`
- Create: `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/post-fs-data.sh`
- Create: `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/system/bin/gsid`

**Interfaces:**
- Consumes: `/tmp/gsid_bin` (binary asli `/system/bin/gsid` dari device, ukuran 902392 byte, instruksi `1a9f07e8` pada offset `0x6eac4`).
- Produces: Direktori modul KernelSU `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/` dengan binary `system/bin/gsid` yang telah dipatch pada offset `0x6eac4` menjadi `52800028` (`mov w8, #1`).

- [ ] **Step 1: Verifikasi instruksi asli pada `/tmp/gsid_bin` di offset `0x6eac4`**

Run: `llvm-objdump -d --start-address=0x6eabc --stop-address=0x6eacc /tmp/gsid_bin`
Expected: Menampilkan `6eac4: 1a9f07e8 cset w8, ne`

- [ ] **Step 2: Buat file `module.prop`, `post-fs-data.sh`, dan binary `system/bin/gsid` yang sudah dipatch**

Patch 4 byte pada offset `0x6eac4` dari `\xe8\x07\x9f\x1a` (`cset w8, ne`) menjadi `\x28\x00\x80\x52` (`mov w8, #1`), simpan ke `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/system/bin/gsid`, dan buat `module.prop` serta `post-fs-data.sh` (yang mengatur `chown root:shell`, `chmod 0755`, `chcon u:object_r:gsid_exec:s0`, dan bind-mount ke `/system/bin/gsid`).

- [ ] **Step 3: Verifikasi hasil patch dengan `llvm-objdump` dan `cmp -l`**

Run: `llvm-objdump -d --start-address=0x6eabc --stop-address=0x6eacc /home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/system/bin/gsid && cmp -l /tmp/gsid_bin /home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/system/bin/gsid`
Expected: `6eac4: 52800028 mov w8, #0x1` dan hanya 4 byte pada offset desimal `453317..453320` (`0x6eac4..0x6eac7` + 1) yang berbeda.

---

### Task 2: Pasang Modul KernelSU di Device & Aktifkan Secara Langsung

**Files:**
- Create (on device): `/data/adb/modules/gsid_unencrypted_fix/module.prop`
- Create (on device): `/data/adb/modules/gsid_unencrypted_fix/post-fs-data.sh`
- Create (on device): `/data/adb/modules/gsid_unencrypted_fix/system/bin/gsid`

**Interfaces:**
- Consumes: `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/` dari Task 1.
- Produces: `/system/bin/gsid` aktif di device dengan patch `mov w8, #1` dan konteks SELinux `u:object_r:gsid_exec:s0`.

- [ ] **Step 1: Push modul `gsid_unencrypted_fix` ke `/data/adb/modules/gsid_unencrypted_fix` di device**

Push isi `/home/fxxyz73/tanzanite-halium/ksu_modules/gsid_unencrypted_fix/` ke device, setel izin `0755`, pemilik `root:shell`, dan konteks SELinux `u:object_r:gsid_exec:s0` pada `/data/adb/modules/gsid_unencrypted_fix/system/bin/gsid`.

- [ ] **Step 2: Aktifkan bind-mount `/system/bin/gsid` dan restart `gsid` di device**

Jalankan `/data/adb/modules/gsid_unencrypted_fix/post-fs-data.sh` dan hentikan proses `gsid` lama (`killall gsid` atau `stop gsid`) agar panggilan DSU berikutnya memakai binary baru.

- [ ] **Step 3: Verifikasi `/system/bin/gsid` yang ter-mount di device**

Run: `adb -s 4dovx8w8nbpfjz6l shell "su -c 'ls -laZ /system/bin/gsid; md5sum /system/bin/gsid /data/adb/modules/gsid_unencrypted_fix/system/bin/gsid'"`
Expected: Konteks SELinux `u:object_r:gsid_exec:s0`, izin `-rwxr-xr-x`, pemilik `root shell`, dan MD5 `/system/bin/gsid` identik dengan `/data/adb/modules/gsid_unencrypted_fix/system/bin/gsid`.
