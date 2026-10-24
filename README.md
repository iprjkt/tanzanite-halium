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

Halium 12 / Ubuntu Touch 20.04 (Focal Fossa) dual-boot port and switcher ecosystem for **Redmi Note 14 4G** (`tanzanite`).

---

## 📱 Device Specifications

| Specification | Details |
| :--- | :--- |
| **Device Model** | Redmi Note 14 4G |
| **Codename** | `tanzanite` |
| **SoC** | MediaTek Helio G99 Ultra (`MT6789`) |
| **Architecture** | `arm64-v8a` (64-bit) |
| **Halium Version** | `12` |
| **Target OS** | Ubuntu Touch Focal (20.04 LTS) |
| **Kernel Source** | [iprjkt/evernight-gki](https://github.com/iprjkt/evernight-gki) (GKI Linux 6.1 with KernelSU) |
| **Dual-Boot Mode** | Slot A partition swap with stock HyperOS fallback on Slot B |

---

## ✨ Features & Components

1. **Dual-Boot Architecture**:
   - Primary installation operates on active Slot A without touching Slot B.
   - Slot B remains intact as a clean stock HyperOS rescue / fallback slot.
   - Automatically handles stock boot image backups (`boot`, `vendor_boot`, `dtbo`) in `/sdcard/.backup`.

2. **Tanzanite Switcher App (`switcher-app`)**:
   - Modern Android application built with Jetpack Compose & Miuix KMP.
   - 1-Tap OS switching between Android (HyperOS) and Ubuntu Touch.
   - Adaptive icon designed for HyperOS launcher squircle.
   - Device and partition status dashboard with real-time execution log.
   - HyperCeiler-inspired About screen with Ubuntu branding and community links.

3. **Flashable Recovery Installer**:
   - Standalone TWRP/recovery flashable zip (`tanzanite-halium.zip`) with dynamic A/B slot detection.
   - Automatic vendor fstab patching for unencrypted ext4 userdata.
   - Full AVB verification handling (`vbmeta`, `vbmeta_system`, `vbmeta_vendor`).
   - Ubuntu ASCII banner with creator and support links.

4. **Rootfs & Subdir Dual-Boot**:
   - Boots Ubuntu Touch rootfs from `/data/ubuntu` on the userdata partition.
   - Resolved HyperOS `/sdcard` permissions and Ubuntu Touch `apt` sandbox compatibility.

---

## 🛠️ Repository Layout

- [`deviceinfo`](file:///home/fxxyz73/tanzanite-halium/deviceinfo) - Halium 12 device configuration for Redmi Note 14 4G.
- [`switcher-app/`](file:///home/fxxyz73/tanzanite-halium/switcher-app) - Android dual-boot switcher app (Jetpack Compose + Miuix).
- [`flashable_zips/`](file:///home/fxxyz73/tanzanite-halium/flashable_zips) - Template scripts and binaries for the recovery installer.
- [`overlay/`](file:///home/fxxyz73/tanzanite-halium/overlay) - Ubuntu Touch rootfs overlay files (drivers, audio, graphics, udev rules).
- [`ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/ramdisk-overlay) - Boot ramdisk modifications.
- [`vendor-ramdisk-overlay/`](file:///home/fxxyz73/tanzanite-halium/vendor-ramdisk-overlay) - Prebuilt MediaTek vendor kernel modules.
- [`docs/`](file:///home/fxxyz73/tanzanite-halium/docs) - Technical documentation and troubleshooting guides:
  - [`TROUBLESHOOTING_SDCARD_APT.md`](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md): Fix for HyperOS `/sdcard` storage access & Ubuntu Touch `apt` sandbox.

---

## 👥 Creator & Community

- **Developer / Maintainer**: [iprjkt](https://github.com/iprjkt)
- **Telegram Contact**: [@anotherside551](https://t.me/anotherside551)
- **Telegram Support Group**: [@idiscuss1](https://t.me/idiscuss1)
- **Support & Donation**: [Sociabuzz Tribe](https://sociabuzz.com/fxxyz73/tribe)
- **Documentation**: [UBports Documentation](https://docs.ubports.com)

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
