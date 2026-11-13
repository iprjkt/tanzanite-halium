// userdata_wrap: create a 1:1 dm-linear device ("userdata-wrapper") on top of
// the userdata partition before `mount_all --late`.
//
// libfs_mgr's WrapUserdataIfNeeded() sees a holder on the userdata partition
// and reuses the existing "userdata-wrapper" device, so /data ends up mounted
// on /dev/block/dm-N. gsid then treats /data as device-mapper backed and can
// map DSU images (system_gsi / userdata_gsi) with dm-linear.
//
// Statically linked on purpose: binaries under /vendor run in the vendor
// linker namespace and cannot load /system libraries such as libdm.
//
// Usage: userdata_wrap [name] [block_device]
//   defaults: userdata-wrapper /dev/block/by-name/userdata

#include <errno.h>
#include <fcntl.h>
#include <linux/dm-ioctl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define BUF_SIZE 16384

static void dm_init(struct dm_ioctl *io, size_t size, const char *name) {
    memset(io, 0, size);
    io->version[0] = DM_VERSION_MAJOR;
    io->version[1] = 0;
    io->version[2] = 0;
    io->data_size = size;
    io->data_start = sizeof(*io);
    strncpy(io->name, name, sizeof(io->name) - 1);
}

static int read_sysfs_sectors(unsigned int maj, unsigned int min, uint64_t *out) {
    char path[128];
    snprintf(path, sizeof(path), "/sys/dev/block/%u:%u/size", maj, min);
    FILE *f = fopen(path, "re");
    if (!f) return -1;
    unsigned long long v = 0;
    int ok = fscanf(f, "%llu", &v) == 1;
    fclose(f);
    if (!ok || v == 0) return -1;
    *out = v;
    return 0;
}

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "userdata-wrapper";
    const char *blk = argc > 2 ? argv[2] : "/dev/block/by-name/userdata";

    struct stat st;
    if (stat(blk, &st) != 0 || !S_ISBLK(st.st_mode)) {
        fprintf(stderr, "userdata_wrap: stat %s: %s\n", blk, strerror(errno));
        return 1;
    }
    unsigned int maj = major(st.st_rdev), min = minor(st.st_rdev);

    uint64_t sectors = 0;
    int bfd = open(blk, O_RDONLY | O_CLOEXEC);
    if (bfd >= 0) {
        uint64_t bytes = 0;
        if (ioctl(bfd, BLKGETSIZE64, &bytes) == 0) sectors = bytes / 512;
        close(bfd);
    }
    if (sectors == 0 && read_sysfs_sectors(maj, min, &sectors) != 0) {
        fprintf(stderr, "userdata_wrap: cannot get size of %s\n", blk);
        return 1;
    }

    int fd = open("/dev/device-mapper", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "userdata_wrap: open /dev/device-mapper: %s\n", strerror(errno));
        return 1;
    }

    char buf[BUF_SIZE] __attribute__((aligned(8)));
    struct dm_ioctl *io = (struct dm_ioctl *)buf;

    dm_init(io, sizeof(*io), name);
    if (ioctl(fd, DM_DEV_CREATE, io) != 0) {
        if (errno == EBUSY) {
            fprintf(stderr, "userdata_wrap: %s already exists\n", name);
            close(fd);
            return 0;
        }
        fprintf(stderr, "userdata_wrap: DM_DEV_CREATE: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    dm_init(io, sizeof(buf), name);
    io->target_count = 1;
    struct dm_target_spec *spec = (struct dm_target_spec *)(buf + sizeof(*io));
    spec->sector_start = 0;
    spec->length = sectors;
    spec->status = 0;
    strncpy(spec->target_type, "linear", sizeof(spec->target_type) - 1);
    char *params = (char *)(spec + 1);
    int plen = snprintf(params, sizeof(buf) - sizeof(*io) - sizeof(*spec), "%u:%u 0", maj, min);
    size_t spec_size = sizeof(*spec) + (size_t)plen + 1;
    spec_size = (spec_size + 7) & ~(size_t)7;
    spec->next = spec_size;
    io->data_size = sizeof(*io) + spec_size;

    if (ioctl(fd, DM_TABLE_LOAD, io) != 0) {
        fprintf(stderr, "userdata_wrap: DM_TABLE_LOAD: %s\n", strerror(errno));
        goto fail;
    }

    dm_init(io, sizeof(*io), name);
    if (ioctl(fd, DM_DEV_SUSPEND, io) != 0) {
        fprintf(stderr, "userdata_wrap: resume: %s\n", strerror(errno));
        goto fail;
    }

    fprintf(stderr, "userdata_wrap: created %s -> %u:%u (%llu sectors), dm minor %u\n", name, maj,
            min, (unsigned long long)sectors, minor(io->dev));
    close(fd);
    return 0;

fail:
    dm_init(io, sizeof(*io), name);
    ioctl(fd, DM_DEV_REMOVE, io);
    close(fd);
    return 1;
}
