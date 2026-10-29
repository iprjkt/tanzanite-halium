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
| **Kernel Source** | [iprjkt/evernight-gki](https://github.com/iprjkt/evernight-gki) (GKI Linux 5.10 / 6.12 dual-generation) |
| **Dual-Boot Mode** | Slot A partition swap with stock HyperOS fallback on Slot B |

---

## Hardware Working Status

| Hardware / Feature | Status | Notes |
| :--- | :--- | :--- |
| **Display / Touchscreen** | Working | Full resolution, multi-touch responsive |
| **Lomiri UI / Compositor** | Working | Native Wayland via `lomiri-system-compositor` |
| **GPU Acceleration** | Working | Mali-G57 MC2 via libhybris / Android 12 Gralloc & EGL |
| **Battery & Power Management** | Working | Accurate fuelgauge reporting via UPower BMS filter shim |
| **Audio (Speaker / Playback)** | Working | Pinned 48kHz native rate, SiA81xx smartPA & full Aurisys DSP libraries |
| **Audio (Microphone / Input)** | Working | Primary mic routed through Droid source |
| **Haptics / Vibration** | Working | `regulator-vibrator` via timed_output udev rule |
| **Flashlight / Torch** | Working | `tanzanite-flashlight-bridge` daemon + MTK flashlight drivers |
| **Screen Rotation / Sensors** | Working | Accelerometer & Orientation via HIDL 2.0 sensorfw |
| **Cellular / 4G LTE Data** | Working | Dual SIM slots detected via ofono-sailfish & MTK IRadio@1.2 |
| **WiFi & Bluetooth** | Working | Managed by ConnMan & Bluez / Bluebinder |
| **Camera** | In Progress | ISP & AF kernel modules restored; Halium 12 HAL binding in progress |

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
   - Dual-generation kernel validation enforcing compatibility with Linux 5.10.xxx and 6.12.xxx trees.
   - Automatic vendor fstab patching for unencrypted ext4 userdata.
   - Full AVB verification handling (`vbmeta`, `vbmeta_system`, `vbmeta_vendor`).
   - Integrated bootloader security flashing (LK Fenrir and Preloader Engineering) with interactive skip detection.
   - Terminal status display with creator and support links.

4. **Rootfs & Subdir Dual-Boot**:
   - Boots Ubuntu Touch rootfs from `/data/ubuntu` on the userdata partition.
   - Pre-configured fixes for HyperOS `/sdcard` storage permissions and Ubuntu Touch `apt` sandbox compatibility.

---

## Installation and Flashing Guide

Detailed step-by-step flashing guides are available in the documentation:
- [English Flashing Guide](docs/FLASHING_GUIDE_en.md)
- [Panduan Flashing (Bahasa Indonesia)](docs/FLASHING_GUIDE_id.md)

Installation workflow overview:
1. **Format Userdata to ext4**: Format the `/data` partition to unencrypted `ext4` via the recovery menu or by flashing `Format-Data-Ext4-Tanzanite.zip`, then reboot recovery.
2. **Set Active Slot to Slot A**: Verify that the recovery is active on Slot A.
3. **Flash `tanzanite-halium.zip`**: Install the zip through recovery to patch vendor fstab, disable AVB, extract the Ubuntu Touch rootfs to `/data/ubuntu`, and install the Halium kernel.
4. **Reboot System**: Boot into the Ubuntu Touch Focal user interface.
5. **Dual-Boot Switching**:
   - From Ubuntu Touch to Android: Run `sudo boot-to-android` in the terminal.
   - From Android to Ubuntu Touch: Open the **Tanzanite Switcher** app and tap *Switch to Ubuntu Touch*.

---

## Repository Layout

- [`deviceinfo`](file:///home/fxxyz73/tanzanite-halium/deviceinfo): Halium 12 device configuration for Redmi Note 14 4G.
- [`switcher-app/`](file:///home/fxxyz73/tanzanite-halium/switcher-app): Android dual-boot switcher app (Jetpack Compose + Miuix).
- [`flashable_zips/`](file:///home/fxxyz73/tanzanite-halium/flashable_zips): Template scripts and binaries for the recovery installer.
- [`overlay/`](file:///home/fxxyz73/tanzanite-halium/overlay): Ubuntu Touch rootfs overlay files (drivers, audio, graphics, udev rules).
- [`ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/ramdisk-overlay): Boot ramdisk modifications.
- [`vendor-ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/vendor-ramdisk-overlay): Prebuilt MediaTek vendor kernel modules (385 modules including `vendor_dlkm`).
- [`scripts/`](file:///home/fxxyz73/tanzanite-halium/scripts): Tooling and hardware consistency checkers (`check_modules.sh`, `check_device_config.sh`, etc.).
- [`docs/`](file:///home/fxxyz73/tanzanite-halium/docs): Technical documentation and troubleshooting guides:
  - [`BOOTLOADER_AVB_LK.md`](file:///home/fxxyz73/tanzanite-halium/docs/BOOTLOADER_AVB_LK.md): Technical analysis of MT6789 boot security and rationale for retaining Preloader Engineering and LK Fenrir.
  - [`MODULE_AUDIT.md`](file:///home/fxxyz73/tanzanite-halium/docs/MODULE_AUDIT.md): Technical audit of vendor kernel modules, GKI `vendor_dlkm`, and peripheral subsystems.
  - [`FLASHING_GUIDE_en.md`](file:///home/fxxyz73/tanzanite-halium/docs/FLASHING_GUIDE_en.md): Complete flashing and dual-boot installation guide (English).
  - [`FLASHING_GUIDE_id.md`](file:///home/fxxyz73/tanzanite-halium/docs/FLASHING_GUIDE_id.md): Complete flashing and dual-boot installation guide (Bahasa Indonesia).
  - [`TROUBLESHOOTING_SDCARD_APT.md`](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md): Resolution guide for HyperOS storage permissions and Ubuntu Touch `apt` sandbox.

---

## Attribution & Credits

- Port maintainer and dual-boot ecosystem: [iprjkt](https://github.com/iprjkt)
- Audio DSP configuration, 48kHz policy pinning, vendor_dlkm module auditing, and hardware validation scripts adapted from work by [itswill00](https://github.com/itswill00/tanzanite-ubuntu-touch), used under the Apache-2.0 license.

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
