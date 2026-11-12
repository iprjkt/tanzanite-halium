/*
 * tanzanite-flashlight-bridge
 *
 * Exposes the MTK torch control as a stable, writable file so that
 * ayatana-indicator-power can toggle the flashlight through a plain path
 * (deviceinfo FlashlightSysfsPath=/run/flashlight_bridge) instead of needing to
 * know about the MediaTek flashlight layout.
 *
 * On Xiaomi Redmi Note 14 4G (tanzanite / board o7), the camera flash/torch LED
 * is driven by the Southchip SC6601 subpmic charger via flashlights-mt6789-o7.ko.
 * The working hardware torch control node is:
 *   /sys/devices/platform/flashlights_mt6789/mt6789_flash
 * which accepts "1\n" (enable 110mA torch mode on SC6601 LED1) and "0\n" (disable).
 *
 * Supports both standard hosted C compilation and freestanding ARM64 Linux
 * compilation (clang --target=aarch64-linux-gnu -ffreestanding -nostdlib -static).
 */

#define BRIDGE_FILE "/run/flashlight_bridge"
#define MT6789_FLASH_NODE "/sys/devices/platform/flashlights_mt6789/mt6789_flash"

#if defined(__aarch64__) && !__STDC_HOSTED__

typedef unsigned int uint32_t;
typedef unsigned long size_t;
typedef long ssize_t;

#define NULL ((void *)0)
#define AT_FDCWD (-100)
#define O_RDONLY 00
#define O_WRONLY 01
#define O_RDWR   02
#define O_CREAT  0100
#define O_TRUNC  01000
#define W_OK     2

#define IN_MODIFY      0x00000002
#define IN_CLOSE_WRITE 0x00000008
#define IN_MOVED_TO    0x00000080
#define IN_CREATE      0x00000100

struct inotify_event {
    int      wd;
    uint32_t mask;
    uint32_t cookie;
    uint32_t len;
    char     name[];
};

static inline long syscall1(long n, long a) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory", "cc");
    return x0;
}

static inline long syscall3(long n, long a, long b, long c) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}

static inline long syscall4(long n, long a, long b, long c, long d) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory", "cc");
    return x0;
}

#define SYS_inotify_init1     26
#define SYS_inotify_add_watch 27
#define SYS_faccessat         48
#define SYS_fchmodat          53
#define SYS_openat            56
#define SYS_close             57
#define SYS_read              63
#define SYS_write             64
#define SYS_exit_group        94

static int sys_open(const char *path, int flags, int mode) {
    return (int)syscall4(SYS_openat, AT_FDCWD, (long)path, flags, mode);
}

static int sys_close(int fd) {
    return (int)syscall1(SYS_close, fd);
}

static ssize_t sys_read(int fd, void *buf, size_t count) {
    return (ssize_t)syscall3(SYS_read, fd, (long)buf, (long)count);
}

static ssize_t sys_write(int fd, const void *buf, size_t count) {
    return (ssize_t)syscall3(SYS_write, fd, (long)buf, (long)count);
}

static int sys_access_w(const char *path) {
    return (int)syscall4(SYS_faccessat, AT_FDCWD, (long)path, W_OK, 0);
}

static int sys_chmod(const char *path, int mode) {
    return (int)syscall4(SYS_fchmodat, AT_FDCWD, (long)path, mode, 0);
}

static int sys_inotify_init(void) {
    return (int)syscall1(SYS_inotify_init1, 0);
}

static int sys_inotify_add_watch(int fd, const char *path, uint32_t mask) {
    return (int)syscall3(SYS_inotify_add_watch, fd, (long)path, mask);
}

static size_t str_len(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

static int str_eq(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++;
        b++;
    }
    return *a == *b;
}

static void log_msg(const char *msg) {
    sys_write(2, msg, str_len(msg));
}

#else

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/inotify.h>

static int sys_open(const char *path, int flags, int mode) {
    return open(path, flags, mode);
}

static int sys_close(int fd) {
    return close(fd);
}

static ssize_t sys_read(int fd, void *buf, size_t count) {
    return read(fd, buf, count);
}

static ssize_t sys_write(int fd, const void *buf, size_t count) {
    return write(fd, buf, count);
}

static int sys_access_w(const char *path) {
    return access(path, W_OK);
}

static int sys_chmod(const char *path, int mode) {
    return chmod(path, (mode_t)mode);
}

static int sys_inotify_init(void) {
    return inotify_init1(0);
}

static int sys_inotify_add_watch(int fd, const char *path, uint32_t mask) {
    return inotify_add_watch(fd, path, mask);
}

static size_t str_len(const char *s) {
    return strlen(s);
}

static int str_eq(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static void log_msg(const char *msg) {
    ssize_t unused = write(2, msg, strlen(msg));
    (void)unused;
}

#endif

struct torch_target {
    const char *path;
    const char *on_str;
    const char *off_str;
};

/* Candidate kernel nodes, most specific first. */
static const struct torch_target torch_candidates[] = {
    { MT6789_FLASH_NODE,                                        "1\n",       "0\n"       },
    { "/sys/class/leds/flashlight/brightness",                  "1\n",       "0\n"       },
    { "/sys/class/leds/torch/brightness",                       "1\n",       "0\n"       },
    { "/sys/class/leds/flash/brightness",                       "1\n",       "0\n"       },
    { "/sys/class/flashlight_core/flashlight/flashlight_torch", "0 0 0 1\n", "0 0 0 0\n" },
    { "/sys/class/flashlight/flashlight_torch",                 "0 0 0 1\n", "0 0 0 0\n" },
    { NULL, NULL, NULL }
};

static const struct torch_target *find_torch_target(void) {
    for (int i = 0; torch_candidates[i].path != NULL; i++) {
        if (sys_access_w(torch_candidates[i].path) == 0)
            return &torch_candidates[i];
    }
    return NULL;
}

static int set_torch(int on) {
    /* Ensure primary mt6789_flash node has write permissions if present */
    sys_chmod(MT6789_FLASH_NODE, 0666);

    const struct torch_target *target = find_torch_target();
    if (!target) {
        log_msg("tanzanite-flashlight: no writable torch node found\n");
        return -1;
    }

    int fd = sys_open(target->path, O_WRONLY, 0);
    if (fd < 0) {
        log_msg("tanzanite-flashlight: failed to open torch node\n");
        return -1;
    }

    const char *payload = on ? target->on_str : target->off_str;
    size_t len = str_len(payload);
    ssize_t written = sys_write(fd, payload, len);
    sys_close(fd);

    if (written < (ssize_t)len) {
        log_msg("tanzanite-flashlight: failed to write torch state\n");
        return -1;
    }

    return 0;
}

static void sync_torch(int *last_state) {
    int fd = sys_open(BRIDGE_FILE, O_RDONLY, 0);
    if (fd < 0)
        return;

    char buf[32];
    ssize_t n = sys_read(fd, buf, sizeof(buf) - 1);
    sys_close(fd);

    if (n <= 0)
        return;
    buf[n] = '\0';

    int i = 0;
    while (buf[i] == ' ' || buf[i] == '\t' || buf[i] == '\r' || buf[i] == '\n')
        i++;

    int on = -1;
    if (buf[i] == '0')
        on = 0;
    else if (buf[i] >= '1' && buf[i] <= '9')
        on = 1;

    if (on < 0 || on == *last_state)
        return;

    if (set_torch(on) == 0) {
        *last_state = on;
        log_msg(on ? "tanzanite-flashlight: torch -> on\n"
                   : "tanzanite-flashlight: torch -> off\n");
    }
}

int main(void) {
    sys_chmod(MT6789_FLASH_NODE, 0666);

    int fd = sys_open(BRIDGE_FILE, O_CREAT | O_RDWR | O_TRUNC, 0666);
    if (fd < 0) {
        log_msg("tanzanite-flashlight: cannot create /run/flashlight_bridge\n");
        return 1;
    }
    sys_write(fd, "0\n", 2);
    sys_close(fd);
    sys_chmod(BRIDGE_FILE, 0666);

    if (!find_torch_target()) {
        log_msg("tanzanite-flashlight: torch node missing at start-up; will retry on toggle\n");
    }

    int inotify_fd = sys_inotify_init();
    if (inotify_fd < 0) {
        log_msg("tanzanite-flashlight: inotify_init failed\n");
        return 1;
    }

    int wd_dir = sys_inotify_add_watch(inotify_fd, "/run", IN_CREATE | IN_MOVED_TO);
    int wd_file = sys_inotify_add_watch(inotify_fd, BRIDGE_FILE, IN_CLOSE_WRITE | IN_MODIFY);

    int last_state = -1;
    sync_torch(&last_state);

    char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
    for (;;) {
        ssize_t len = sys_read(inotify_fd, buf, sizeof(buf));
        if (len <= 0) {
            if (len == -4 /* -EINTR */)
                continue;
            log_msg("tanzanite-flashlight: inotify read failed\n");
            break;
        }

        int should_sync = 0;
        ssize_t offset = 0;
        while (offset < len) {
            struct inotify_event *ev = (struct inotify_event *)(buf + offset);
            if (ev->wd == wd_file) {
                should_sync = 1;
            } else if (ev->wd == wd_dir && ev->len > 0 && str_eq(ev->name, "flashlight_bridge")) {
                sys_chmod(BRIDGE_FILE, 0666);
                wd_file = sys_inotify_add_watch(inotify_fd, BRIDGE_FILE, IN_CLOSE_WRITE | IN_MODIFY);
                should_sync = 1;
            }
            offset += (ssize_t)sizeof(struct inotify_event) + (ssize_t)ev->len;
        }

        if (should_sync)
            sync_torch(&last_state);
    }

    sys_close(inotify_fd);
    return 0;
}

#if defined(__aarch64__) && !__STDC_HOSTED__
__attribute__((noreturn)) void _start(void) {
    int ret = main();
    syscall1(SYS_exit_group, ret);
    __builtin_unreachable();
}
#endif
