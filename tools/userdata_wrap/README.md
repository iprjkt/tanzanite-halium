# userdata_wrap

Lightweight, statically-linked helper utility for Redmi Note 14 4G (`tanzanite`).

## Purpose

When running Android with an unencrypted `ext4` `/data` partition (for dual-booting Ubuntu Touch with `/data/ubuntu`), Android's stock `fstab` mounts `/dev/block/by-name/userdata` directly to `/data` rather than on top of a device-mapper device.

Android's Dynamic System Updates (DSU) service (`gsid`) requires `/data` to be mounted on top of device-mapper (`uses_dm = true`) and requires `bd_holder` on the underlying userdata partition to be managed by device-mapper (`_dm_claim_ptr`) so that DSU images (`system_gsi` and `userdata_gsi`) can be mapped via `dm-linear`.

`userdata_wrap` runs in `vendor` (`init.mt6789.rc` `on late-fs` before `mount_all --late`) under `u:object_r:vold_exec:s0`. It creates a 1:1 `dm-linear` device named `userdata-wrapper` on top of `/dev/block/by-name/userdata`.

When `init` executes `mount_all --late`, `libfs_mgr`'s built-in `WrapUserdataIfNeeded()` detects the active device-mapper holder on `/dev/block/by-name/userdata`, finds `userdata-wrapper`, and mounts `/dev/block/dm-X` on `/data`.

This satisfies both `gsid` and the kernel's `dm-linear` block device claiming checks without requiring any binary patching to `/system/bin/gsid` or modifying `fstab.mt6789`.

## Building

```bash
make
```

Requires either `zig` or `aarch64-linux-gnu-gcc`.
Output binary is a static ARM64 executable stripped to ~50KB with zero external shared library dependencies.
