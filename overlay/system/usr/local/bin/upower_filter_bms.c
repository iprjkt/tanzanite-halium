#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>

typedef struct _GList GList;
struct _GList {
    void *data;
    GList *next;
    GList *prev;
};

typedef void* GUdevDevice;
typedef void* GUdevClient;

static const char* (*real_g_udev_device_get_name)(GUdevDevice *device) = NULL;
static const char* (*real_g_udev_device_get_subsystem)(GUdevDevice *device) = NULL;
static GList* (*real_g_udev_client_query_by_subsystem)(GUdevClient *client, const char *subsystem) = NULL;
static void (*real_g_object_unref)(void *object) = NULL;
static GList* (*real_g_list_delete_link)(GList *list, GList *link) = NULL;

static int is_ignored_device(const char *name) {
    if (!name) return 0;
    if (strcmp(name, "bms") == 0) return 1;
    if (strcmp(name, "mtk-gauge") == 0) return 1;
    if (strcmp(name, "sc-cp-master") == 0) return 1;
    return 0;
}

const char* g_udev_device_get_name(GUdevDevice *device) {
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");
    return real_g_udev_device_get_name ? real_g_udev_device_get_name(device) : NULL;
}

const char* g_udev_device_get_subsystem(GUdevDevice *device) {
    if (!real_g_udev_device_get_subsystem)
        real_g_udev_device_get_subsystem = dlsym(RTLD_NEXT, "g_udev_device_get_subsystem");
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");

    const char *name = real_g_udev_device_get_name ? real_g_udev_device_get_name(device) : NULL;
    if (is_ignored_device(name)) {
        return "ignored";
    }
    return real_g_udev_device_get_subsystem ? real_g_udev_device_get_subsystem(device) : NULL;
}

GList* g_udev_client_query_by_subsystem(GUdevClient *client, const char *subsystem) {
    if (!real_g_udev_client_query_by_subsystem)
        real_g_udev_client_query_by_subsystem = dlsym(RTLD_NEXT, "g_udev_client_query_by_subsystem");
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");
    if (!real_g_object_unref)
        real_g_object_unref = dlsym(RTLD_NEXT, "g_object_unref");
    if (!real_g_list_delete_link)
        real_g_list_delete_link = dlsym(RTLD_NEXT, "g_list_delete_link");

    if (!real_g_udev_client_query_by_subsystem) return NULL;
    GList *list = real_g_udev_client_query_by_subsystem(client, subsystem);
    if (subsystem && strcmp(subsystem, "power_supply") == 0 && list) {
        GList *curr = list;
        while (curr) {
            GList *next = curr->next;
            GUdevDevice *dev = curr->data;
            const char *name = real_g_udev_device_get_name ? real_g_udev_device_get_name(dev) : NULL;
            if (is_ignored_device(name)) {
                if (real_g_object_unref)
                    real_g_object_unref(dev);
                if (real_g_list_delete_link)
                    list = real_g_list_delete_link(list, curr);
            }
            curr = next;
        }
    }
    return list;
}
