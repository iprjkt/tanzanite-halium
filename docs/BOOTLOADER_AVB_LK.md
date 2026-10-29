# Bootloader Security and Chain of Trust on Tanzanite (MT6789)

This document describes the bootloader verification architecture on the Xiaomi Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 / MT6789 SoC). It details why `tanzanite-halium` retains the three-stage bootchain (Preloader Engineering, LK Fenrir, and disabled AVB) rather than adopting a vbmeta-only approach.

---

## 1. Context: Two Approaches in the Community

Two separate approaches exist in the community regarding bootloader verification for Tanzanite:

| Approach | Modified Components | Core Assumption |
| :--- | :--- | :--- |
| **Approach A (vbmeta-only)** | AVB flags byte in `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` (`0x00` changed to `0x03`) | Assumes all image and partition verification is handled exclusively by Android Verified Boot (AVB 2.0). |
| **Approach B (`tanzanite-halium`)** | Preloader Engineering + LK Fenrir + disabled vbmeta (AOSP empty) | Neutralizes verification at the MediaTek hardware firmware level (Preloader and LK) as well as the Android AVB 2.0 layer. |

Users comparing repositories often ask why `tanzanite-halium` requires flashing an engineering preloader and LK Fenrir when modifying vbmeta alone appears simpler.

The decision rests on MediaTek multi-stage boot architecture and documented hardbrick incidents on real hardware.

---

## 2. MediaTek Boot Flow and Verification Stages

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
[Linux Kernel] (boot.img, vendor_boot.img, dtbo.img)
    │
    ▼
[Userspace / Android Init / Halium / systemd]
```

### The Limitation of vbmeta-Only Enforcement

Android Verified Boot (AVB 2.0) checks occur after Little Kernel parses descriptors in the `vbmeta` partitions to validate cryptographic hashes for `boot`, `vendor_boot`, and `system`.

Before AVB is evaluated, internal MediaTek routines inside the **Preloader and Little Kernel (LK)** execute independent integrity checks (`sec_get_vfy_policy()` and partition signature tables). These routines directly validate auxiliary and low-level firmware partitions:
- `dtbo` (Device Tree Blob Overlay)
- `logo` (`logo.bin` bootsplash image)
- `tee` and `gz` (GenieZone)
- `preloader`

If an auxiliary partition is modified without a valid factory signature from Xiaomi or MediaTek, LK and Preloader reject execution and drop the SoC into MediaTek BROM mode (Emergency Download / EDL) before AVB evaluates the `0x03` flag.

---

## 3. Documented Hardbrick Incidents

The bootchain policy in `tanzanite-halium` is based on documented failures during development tests:

### Incident 1: Overclocked DTBO Testing
* **Test Case**: Two identical Redmi Note 14 4G retail units tested the exact same modified `dtbo` image (display and GPU parameter tuning).
* **Device A (vbmeta-only, without LK Fenrir)**:
  - All vbmeta partitions had AVB verification and verity flags set to disabled (`0x03`).
  - After flashing the modified `dtbo`, the device suffered a total hardbrick on reboot.
  - The SoC locked permanently into MediaTek BROM mode, failing to reach Fastboot or Recovery. Recovery required an authorized service center flash.
* **Device B (Preloader Engineering + LK Fenrir + disabled vbmeta)**:
  - Flashed the identical modified `dtbo` image.
  - The device booted without errors, and the DTBO modifications ran stably.

### Incident 2: Custom `logo.bin` Splash Modification
* **Test Case**: Modifying the splash screen image in `logo.bin`.
* **Conditions**: All vbmeta partitions had AVB disabled (`0x03` flag).
* **Result**: The device hardbricked upon reboot. Little Kernel rejected the partition because its signature did not match the internal factory signature table, proving that LK validation operates independently of AVB status.

---

## 4. Component Roles in `tanzanite-halium`

To prevent bricking during active kernel and device development, `tanzanite-halium` implements three complementary safeguards:

1. **Preloader Engineering (`preloader_tanzanite.bin`)**:
   - Built from MediaTek engineering firmware trees.
   - Prevents secure handshake lockups and preserves low-level hardware recovery access.
2. **LK Fenrir (`tanzanite-fenrir.img`)**:
   - Overrides `sec_get_vfy_policy()` inside the EL3 and LK execution contexts.
   - Suppresses signature checks on auxiliary partitions (`dtbo`, `logo`, etc.), preventing permanent lockouts when non-AOSP images are customized.
3. **Disabled vbmeta (`vbmeta_disabled/`)**:
   - Clean AOSP empty vbmeta images that instruct the Linux kernel to skip dm-verity and rootfs hash checks.

---

## 5. Summary and Recommendations

* A **vbmeta-only** approach can boot when auxiliary partitions (`dtbo`, `logo`, and firmware blobs) remain completely unmodified stock Xiaomi binaries.
* For active dual-boot setups involving custom GKI kernels ([`evernight-gki`](https://github.com/iprjkt/evernight-gki)), vendor patches, and custom DTBO modifications, **Preloader Engineering + LK Fenrir is the only method empirically proven to prevent hardbricks**.
* `tanzanite-halium` retains Preloader Engineering and LK Fenrir as standard requirements to protect user hardware from unrecoverable bricking.
