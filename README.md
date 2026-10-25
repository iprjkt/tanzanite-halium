# Tanzanite Halium 12 (Ubuntu Touch 20.04 Focal)

```text
                          .-.                 
                    .-'``(|||)                
                 ,`\ \    `-`.                
                /   \ '``-.   `               
              .-.  ,       `___:              
             (:::) :        ___               
              `-`  `       ,   :              
                \   / ,..-`   ,               
                 `./ /    .-.`                
                    `-..-(   )                
                          `-`                 
  _   _ _                 _                   
 | | | | |__  _   _ _ __ | |_ _   _           
 | | | | '_ \| | | | '_ \| __| | | |          
 | |_| | |_) | |_| | | | | |_| |_| |          
  \___/|_.__/ \__,_|_| |_|\__|\__,_|          
               T O U C H                      
```

Halium 12 / Ubuntu Touch 20.04 (Focal Fossa) dual-boot port and switcher ecosystem for Redmi Note 14 4G (`tanzanite`).

---

## Device Specifications

| Specification | Details |
| :--- | :--- |
| **Device Model** | Redmi Note 14 4G |
| **Codename** | `tanzanite` |
| **SoC** | MediaTek Helio G99 Ultra (`MT6789`) |
| **Architecture** | `arm64-v8a` (64-bit) |
| **Halium Version** | `12` |
| **Target OS** | Ubuntu Touch Focal (20.04 LTS) |
| **Kernel Source** | [iprjkt/evernight-gki](https://github.com/iprjkt/evernight-gki) (GKI Linux 5.10 with KernelSU) |
| **Dual-Boot Mode** | Slot A partition swap with stock HyperOS fallback on Slot B |

---

## Hardware Working Status

| Hardware / Feature | Status | Notes |
| :--- | :--- | :--- |
| **Display / Touchscreen** | Working | Full resolution, multi-touch responsive |
| **Lomiri UI / Compositor** | Working | Native Wayland via `lomiri-system-compositor` |
| **GPU Acceleration** | Working | Mali-G57 MC2 via libhybris / Android 12 Gralloc & EGL |
| **Audio (Speaker / Playback)** | Working | PulseAudio with Droid HAL 30 & clean Aurisys routing |
| **Audio (Microphone / Input)** | Working | Primary mic routed through Droid source |
| **Flashlight / Torch** | Working | Controlled via Ayatana Power Indicator & sysfs bridge daemon |
| **Screen Rotation / Sensors** | Working | Accelerometer & Orientation via HIDL 2.0 sensorfw |
| **Cellular / 4G LTE Data** | Working | Dual SIM slots detected via ofono-sailfish & MTK IRadio@1.2 |
| **WiFi & Bluetooth** | Working | Managed by ConnMan & Bluez / Bluebinder |
| **Camera** | In Progress | Halium 12 camera metadata service binding in progress |

---

## Features and Components

1. **Dual-Boot Architecture**:
   - Primary installation operates on active Slot A without modifying Slot B.
   - Slot B remains intact as a clean stock HyperOS fallback slot.
   - Automatically handles stock boot image backups (`boot`, `vendor_boot`, `dtbo`) in `/sdcard/.backup`.

2. **Tanzanite Switcher App (`switcher-app`)**:
   - Android application built with Jetpack Compose & Miuix KMP.
   - One-tap switching between Android (HyperOS) and Ubuntu Touch.
   - Adaptive launcher icon fitted for HyperOS squircle geometry.
   - Device and partition status dashboard with execution log.
   - About screen with Ubuntu branding and community links.

3. **Flashable Recovery Installer**:
   - Standalone TWRP/recovery flashable zip (`tanzanite-halium.zip`) with dynamic A/B slot detection.
   - Automatic vendor fstab patching for unencrypted ext4 userdata.
   - Full AVB verification handling (`vbmeta`, `vbmeta_system`, `vbmeta_vendor`).
   - Terminal status display with creator and support links.

4. **Rootfs & Subdir Dual-Boot**:
   - Boots Ubuntu Touch rootfs from `/data/ubuntu` on the userdata partition.
   - Pre-configured fixes for HyperOS `/sdcard` storage permissions and Ubuntu Touch `apt` sandbox compatibility.

---

## Installation and Flashing Guide

Panduan instalasi dual-boot tersedia dalam dua bahasa:
- [Panduan Flashing (Bahasa Indonesia)](docs/FLASHING_GUIDE_id.md)
- [Flashing Guide (English)](docs/FLASHING_GUIDE_en.md)

Ringkasan alur instalasi:
1. **Format Data ke ext4**: Format data ke filesystem `ext4` tanpa enkripsi lewat menu recovery atau flash `Format-Data-Ext4-Tanzanite.zip`, lalu reboot ke recovery.
2. **Set Active Slot ke Slot A**: Pastikan recovery berada di Slot A.
3. **Flash `tanzanite-halium.zip`**: Pasang zip melalui recovery untuk mem-patch vendor, disable AVB, mengekstrak rootfs ke `/data/ubuntu`, dan memasang kernel Halium.
4. **Reboot System**: Masuk ke antarmuka Ubuntu Touch Focal.
5. **Dual-Boot Switching**:
   - Dari Ubuntu Touch ke Android: Jalankan perintah `sudo boot-to-android` di terminal.
   - Dari Android ke Ubuntu Touch: Buka aplikasi **Tanzanite Switcher** lalu ketuk tombol *Switch to Ubuntu Touch*.

---

## Repository Layout

- [`deviceinfo`](file:///home/fxxyz73/tanzanite-halium/deviceinfo): Halium 12 device configuration for Redmi Note 14 4G.
- [`switcher-app/`](file:///home/fxxyz73/tanzanite-halium/switcher-app): Android dual-boot switcher app (Jetpack Compose + Miuix).
- [`flashable_zips/`](file:///home/fxxyz73/tanzanite-halium/flashable_zips): Template scripts and binaries for the recovery installer.
- [`overlay/`](file:///home/fxxyz73/tanzanite-halium/overlay): Ubuntu Touch rootfs overlay files (drivers, audio, graphics, udev rules).
- [`ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/ramdisk-overlay): Boot ramdisk modifications.
- [`vendor-ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/vendor-ramdisk-overlay): Prebuilt MediaTek vendor kernel modules.
- [`docs/`](file:///home/fxxyz73/tanzanite-halium/docs): Technical documentation and troubleshooting guides:
  - [`FLASHING_GUIDE_id.md`](file:///home/fxxyz73/tanzanite-halium/docs/FLASHING_GUIDE_id.md): Panduan lengkap flashing dan instalasi dual-boot (Bahasa Indonesia).
  - [`FLASHING_GUIDE_en.md`](file:///home/fxxyz73/tanzanite-halium/docs/FLASHING_GUIDE_en.md): Step-by-step flashing and dual-boot installation guide (English).
  - [`TROUBLESHOOTING_SDCARD_APT.md`](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md): Technical analysis for HyperOS storage permissions and Ubuntu Touch `apt` sandbox.

---

## Creator and Community

- **Developer / Maintainer**: [iprjkt](https://github.com/iprjkt)
- **Telegram Contact**: [@anotherside551](https://t.me/anotherside551)
- **Telegram Support Group**: [@idiscuss1](https://t.me/idiscuss1)
- **Support & Donation**: [Sociabuzz Tribe](https://sociabuzz.com/fxxyz73/tribe)
- **Documentation**: [UBports Documentation](https://docs.ubports.com)

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
