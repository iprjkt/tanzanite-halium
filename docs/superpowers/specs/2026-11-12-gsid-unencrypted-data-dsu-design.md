# Desain Bypass Pengecekan `uses_dm` pada `gsid` untuk DSU di `/data` Unencrypted (`ext4`)

**Tanggal**: 2026-11-12  
**Target Device**: Xiaomi Redmi Note 14 4G (`tanzanite`, MT6789)  
**Komponen**: `/system/bin/gsid` (HyperOS) & Modul KernelSU `gsid_unencrypted_fix`

---

## 1. Latar Belakang & Akar Masalah

Pada konfigurasi dual-boot HyperOS + Ubuntu Touch (`tanzanite-halium`), partisi `userdata` (`/dev/block/sdc75`) diformat sebagai `ext4` tanpa enkripsi agar initramfs Halium dapat me-mount `/data/ubuntu` secara langsung saat booting ke Ubuntu Touch.

Akibat penghapusan opsi `keydirectory=/metadata/vold/metadata_encryption` di `/vendor/etc/fstab.mt6789`, Android me-mount `/dev/block/sdc75` secara langsung ke `/data` (bukan di atas `/dev/block/dm-*`). Saat pengguna menginstal DSU (`one_ui9.zip`) menggunakan DSU Sideloader, `gsid` berhasil mengalokasikan `/data/gsi/dsu/dsu/userdata.img` (16 GiB), namun gagal pada tahap akhir pemetaan `dm-linear` dengan error:

```text
E/gsid : Cannot map image: /data must be mounted on top of device-mapper.
I/DynamicSystemService: Failed to create partition: userdata
```

Hasil pembongkaran `/system/bin/gsid` menunjukkan:
- Fungsi `DetermineBlockDeviceForFile` (`0x6e9a0`, dari `system/fs_mgr/libfiemap/fiemap_writer.cpp`) mencari block device tempat file berada (`top_dev` = `sdc75`), lalu menelusuri `/sys/block/<dev>/slaves` untuk mencari partisi fisik paling bawah (`bottom_dev` = `sdc75`).
- Pada offset `0x6eac4`, instruksi `cset w8, ne` (`1a9f07e8`) mengisi `*uses_dm = (top_dev != bottom_dev)`. Karena `/data` di-mount langsung di `sdc75`, maka `*uses_dm` bernilai `0` (`false`).
- Fungsi `ImageManagerImpl::MapImageDevice` (`0x6c390`) memeriksa `if (!uses_dm)` pada offset `0x6c510` (`tbz w8, #0x0, 0x6c59c`) dan menggagalkan proses jika `uses_dm == 0`.
- Padahal fungsi pemetaan sesungguhnya (`MapImageWithDeviceMapper` di `0x6bef0`) maupun `FirstStageMount` dan `TransformFstabForDsu` di `/system/bin/init` saat booting DSU bekerja langsung di atas partisi fisik `userdata` (`/dev/block/sdc75`) dan mengubah entri `/data` di fstab menjadi logical partition `userdata_gsi` (`/dev/block/mapper/userdata_gsi`).

---

## 2. Solusi Arsitektur

1. **Binary Patch `/system/bin/gsid` (1 Instruksi ARM64)**:
   - Lokasi file offset / virtual address: `0x6eac4` di dalam fungsi `DetermineBlockDeviceForFile` (`0x6e9a0`).
   - Instruksi asli: `1a9f07e8` (`cset w8, ne`)
   - Instruksi pengganti: `52800028` (`mov w8, #1`)
   - Efek: `*uses_dm` selalu diset ke `1` (`true`), sedangkan `bdev` (`bottom_dev`) tetap menghasilkan `/dev/block/sdc75`. Dengan demikian:
     - `ImageManagerImpl::ZeroFillNewImage` (`0x6b658`) tetap melakukan zero-fill 1 MB pertama pada `userdata_gsi` sehingga `fs_mgr` di DSU mengenali `userdata_gsi` sebagai partisi baru yang siap diformat `ext4`.
     - `ImageManagerImpl::MapImageDevice` (`0x6c390`) melewati pengecekan `if (!uses_dm)` dan memetakan `userdata_gsi` serta `system_gsi` melalui `dm-linear`.

2. **Pemasangan Persisten via Modul KernelSU (`gsid_unencrypted_fix`)**:
   - Direktori modul di device: `/data/adb/modules/gsid_unencrypted_fix/`
   - Struktur file:
     - `module.prop`: metadata modul KernelSU.
     - `system/bin/gsid`: binary `gsid` yang sudah dipatch (`0755`, `root:shell`, SELinux context `u:object_r:gsid_exec:s0`).
     - `post-fs-data.sh`: memastikan SELinux context `u:object_r:gsid_exec:s0` pada `$MODDIR/system/bin/gsid` dan melakukan bind-mount ke `/system/bin/gsid` jika belum ter-mount oleh overlay modul.
   - Aktivasi langsung tanpa reboot: bind-mount `/data/adb/modules/gsid_unencrypted_fix/system/bin/gsid` ke `/system/bin/gsid` dan menghentikan proses `gsid` lama agar panggilan DSU berikutnya langsung menjalankan binary yang sudah dipatch.
   - Salinan binary patch dan template modul juga disimpan di repositori `tanzanite-halium` agar terdokumentasi dan mudah dipasang ulang bila diperlukan.

---

## 3. Verifikasi & Kriteria Keberhasilan

1. Verifikasi instruksi hasil patch menggunakan `llvm-objdump` pada offset `0x6eac4` (`mov w8, #1`).
2. Verifikasi `/system/bin/gsid` di device memiliki ukuran, izin (`0755`), kepemilikan (`root:shell`), dan konteks SELinux (`u:object_r:gsid_exec:s0`) yang benar.
3. Verifikasi proses instalasi DSU (`DynamicSystemInstallationService` / `gsid`) tidak lagi menghasilkan error `Cannot map image: /data must be mounted on top of device-mapper`.
