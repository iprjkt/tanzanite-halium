# Bootloader Security and Chain of Trust on Tanzanite (MT6789)

This document describes the bootloader verification architecture on the Xiaomi Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 / MT6789 SoC) and how `tanzanite-halium` handles verified boot while keeping stock `lk`, `dtbo`, and `vendor_boot` intact.

---

## 1. MediaTek Boot Flow and Verification Stages

On the MediaTek MT6789 platform, boot execution proceeds through multiple privilege tiers:

```
[BootROM] (Mask ROM in hardware silicon)
    │
    ▼
[Preloader] (Loads into SRAM, initializes DRAM and platform security policy)
    │
    ▼
[BL2_EXT / ATF] (ARM Trusted Firmware running at Exception Level 3 / EL3)
    │
    ▼
[TEE / Little Kernel (LK)] (Fastboot interface, display splash, partition validation)
    │
    ▼
[Linux Kernel] (boot.img with stock vendor_boot.img and stock dtbo.img)
    │
    ▼
[Userspace / Android Init / Halium / systemd]
```

### Partition Verification Rules on Stock Little Kernel (LK)

Android Verified Boot (AVB 2.0) checks descriptors in the `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` partitions to validate cryptographic hashes for `boot`, `vendor_boot`, and dynamic logical partitions.

Before AVB is evaluated, internal MediaTek routines inside the **Preloader and Little Kernel (LK)** execute independent signature checks (`sec_get_vfy_policy()`) on auxiliary partitions such as `dtbo` and `logo`. Because `tanzanite-halium` uses the unmodified stock `dtbo` and preserves `vendor_boot` (for OrangeFox / TWRP recovery), a patched Little Kernel (`lk`) is not required.

---

## 2. Component Roles in `tanzanite-halium`

1. **Preloader Engineering (`preloader_tanzanite.bin`)**:
   - Built from MediaTek engineering firmware trees for the Linux 5.10 baseline.
   - Prevents secure handshake lockups and preserves low-level hardware recovery access across both A and B slots.
2. **Disabled vbmeta (`flashable_zips/v1/vbmeta/`)**:
   - Pre-disabled AVB images (flags `0x03`) for `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` that instruct Little Kernel and the Linux kernel to skip AVB verification and dm-verity.
3. **Preserved Stock `dtbo` and Custom Recovery `vendor_boot`**:
   - The flashable recovery installer and OS switcher only replace `boot` (`boot.img`), leaving stock `dtbo` and `vendor_boot` (OrangeFox recovery) untouched.
