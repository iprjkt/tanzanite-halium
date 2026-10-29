# Bootloader Security & Chain of Trust pada Tanzanite (MT6789)

Dokumen ini menjelaskan arsitektur verifikasi bootloader pada Xiaomi Redmi Note 14 4G (`tanzanite`, SoC MediaTek Helio G99 / MT6789), serta mendokumentasikan secara objektif alasan teknis mengapa **`tanzanite-halium` secara konsisten mempertahankan boot-chain Preloader Engineering + LK Fenrir + AVB Disabled**, dibandingkan pendekatan alternatif *vbmeta-only* yang beredar di komunitas.

---

## 1. Konteks: Dua Pendekatan di Komunitas

Dalam pengembangan Ubuntu Touch dan custom ROM untuk Tanzanite, terdapat dua aliran pendekatan verifikasi bootloader:

| Pendekatan | Komponen yang Dimodifikasi | Asumsi Kerja |
| :--- | :--- | :--- |
| **Pendekatan A (vbmeta-only)** | Hanya byte flags di `vbmeta`, `vbmeta_system`, `vbmeta_vendor` (`0x00` -> `0x03`) | Mengasumsikan seluruh verifikasi integritas ditangani semata-mata oleh Android Verified Boot (AVB 2.0). |
| **Pendekatan B (`tanzanite-halium`)** | Preloader Engineering + LK Fenrir + vbmeta disabled (AOSP empty) | Menetralkan verifikasi di level firmware hardware MediaTek (Preloader & LK) *dan* level Android AVB 2.0. |

Pengguna yang baru membandingkan kedua repositori mungkin bertanya: *"Jika pendekatan vbmeta-only tampak lebih sederhana, mengapa `tanzanite-halium` mewajibkan flash Preloader dan LK Fenrir?"*

Jawabannya bertumpu pada **bukti empiris insiden nyata (hardbrick)** dan arsitektur keamanan bertingkat MediaTek.

---

## 2. Arsitektur Keamanan MediaTek (Multi-Stage Boot Flow)

Pada platform MediaTek Helio G99 (MT6789), rantai bootloader (*chain of trust*) dieksekusi secara bertingkat:

```
[BootROM] (Mask ROM hardware)
    │
    ▼
[Preloader] (SRAM, inisialisasi DRAM & security policy)
    │
    ▼
[BL2_EXT / ATF] (ARM Trusted Firmware, berjalan di Exception Level 3 / EL3)
    │
    ▼
[TEE / Little Kernel (LK)] (Bootloader antarmuka, fastboot, splash)
    │
    ▼
[Linux Kernel] (boot.img + vendor_boot.img + dtbo.img)
    │
    ▼
[Userspace / Android Init / Halium / Systemd]
```

### Keterbatasan Asumsi vbmeta-Only
Android Verified Boot (AVB 2.0) baru dievaluasi ketika LK membaca deskriptor di partisi `vbmeta*` untuk memverifikasi hash `boot`, `vendor_boot`, dan `system`.

Namun, sebelum AVB dievaluasi, rutinitas internal MediaTek di **Preloader dan Little Kernel (LK)** menjalankan verifikasi integritas mandiri (`sec_get_vfy_policy()` dan pengecekan signature tabel partisi hardware) terhadap partisi non-GKI tertentu, seperti:
- `dtbo` (Device Tree Blob Overlay)
- `logo` (`logo.bin` / bootsplash)
- `tee` / `gz` (GenieZone)
- `preloader`

Jika sebuah partisi dimodifikasi di luar signature pabrik Xiaomi/MediaTek, rutinitas LK/Preloader akan menolak boot dan mengunci SoC ke mode BROM (Emergency Download / EDL) **bahkan sebelum AVB membaca byte flags `0x03` di vbmeta**.

---

## 3. Bukti Empiris & Insiden Hardbrick Nyata

Keputusan `tanzanite-halium` mempertahankan LK Fenrir bukan didasarkan pada spekulasi teoritis, melainkan pada **dua insiden fatal yang terjadi pada perangkat pengujian**:

### Insiden 1: Pengujian DTBO Overclock
* **Skenario**: Dua unit Redmi Note 14 4G menguji file modifikasi `dtbo` yang sama (overclock display/GPU parameter).
* **Perangkat A (vbmeta-only, tanpa LK Fenrir)**:
  - Partisi `vbmeta` telah di-patch disable (`flags=0x03`).
  - Setelah DTBO dimodifikasi di-flash, perangkat mengalami **hardbrick total** saat reboot.
  - Perangkat terjebak di mode MediaTek BROM dan tidak bisa menyala ke Fastboot maupun Recovery (memerlukan auth flash Xiaomi Service Center).
* **Perangkat B (Preloader Eng + LK Fenrir + vbmeta)**:
  - Menggunakan file DTBO modifikasi yang identik.
  - Perangkat berhasil boot normal tanpa kendala, dan perubahan DTBO teraplikasi dengan stabil.

### Insiden 2: Modifikasi `logo.bin`
* **Skenario**: Modifikasi splash screen partisi `logo.bin`.
* **Kondisi**: AVB vbmeta sudah dalam kondisi `0x03` (verity & verification disabled).
* **Hasil**: Perangkat tetap mengalami **hardbrick**. Little Kernel menolak partisi logo karena checksum signature tidak cocok dengan tabel keamanan internal LK, membuktikan bahwa proteksi LK beroperasi sepenuhnya terpisah dari status AVB.

---

## 4. Peran Masing-Masing Komponen pada `tanzanite-halium`

Berdasarkan fakta empiris di atas, `tanzanite-halium` menggunakan pertahanan 3 lapis yang saling melengkapi:

1. **Preloader Engineering (`preloader_tanzanite.bin`)**:
   - Berasal dari engineering build MediaTek/Xiaomi.
   - Mencegah *secure handshake lockup* dan membuka akses recovery perintah hardware tingkat rendah.
2. **LK Fenrir (`tanzanite-fenrir.img`)**:
   - Mem-bypass fungsi `sec_get_vfy_policy()` pada execution context EL3/LK.
   - Menghilangkan validasi signature internal terhadap partisi auxiliary (`dtbo`, `logo`, dll), mencegah hardbrick permanen saat partisi non-AOSP dimodifikasi.
3. **AVB Disabled (`vbmeta_disabled/`)**:
   - Partisi AOSP empty/disabled yang menginstruksikan kernel bahwa verifikasi dm-verity dan OS hash dimatikan untuk rootfs Halium/Ubuntu Touch.

---

## 5. Kesimpulan & Rekomendasi

* Pendekatan **vbmeta-only** mungkin terlihat berhasil pada skenario booting sederhana di mana partisi `dtbo`, `logo`, dan firmware low-level dibiarkan 100% murni sesuai stock firmware Xiaomi tanpa modifikasi apapun.
* Namun, dalam pengembangan dual-boot aktif, modifikasi kernel GKI (`evernight-gki`), overlay DTBO, serta patching vendor, **pendekatan Preloader Eng + LK Fenrir adalah satu-satunya metode yang terbukti aman secara empiris dari risiko hardbrick**.
* Demi keselamatan perangkat pengguna, `tanzanite-halium` tetap mempertahankan implementasi LK Fenrir dan Preloader Eng sebagai standar instalasi resmi.
