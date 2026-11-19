#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * libxwayland_landscape_fix.so
 *
 * On Portrait-native Ubuntu Touch devices (e.g., tanzanite 1080x2400),
 * Lomiri rotates its QML scene in software while Mir/QtMir keeps wl_output
 * permanently at 1080x2400. When rotated to landscape, Mir's XWM resizes
 * Xwayland client windows to 2400x1038, but Xwayland's Screen 0 stays
 * 1080x2400 and clamps all mouse and touch coordinates to x <= 1079,
 * creating a dead input zone across the right half of the screen.
 *
 * Preloaded exclusively into /usr/libexec/Xwayland.lomiri, this shim wraps
 * wl_output (and zxdg_output_v1 if advertised) listeners so Xwayland sees a
 * square screen of max(W, H) x max(W, H) (2400x2400) with matching isotropic
 * physical dimensions. Both portrait (1080x2400) and landscape (2400x1080)
 * X11 windows then fit completely within Screen 0 with 1:1 unclipped input.
 */

struct wl_proxy;

typedef int (*wl_proxy_add_listener_fn)(struct wl_proxy *proxy,
                                        void (**implementation)(void),
                                        void *data);
typedef const char *(*wl_proxy_get_class_fn)(struct wl_proxy *proxy);
typedef uint32_t (*wl_proxy_get_version_fn)(struct wl_proxy *proxy);

struct wl_output_listener_compat {
    void (*geometry)(void *data, struct wl_proxy *wl_output,
                     int32_t x, int32_t y,
                     int32_t physical_width, int32_t physical_height,
                     int32_t subpixel, const char *make, const char *model,
                     int32_t transform);
    void (*mode)(void *data, struct wl_proxy *wl_output,
                 uint32_t flags, int32_t width, int32_t height,
                 int32_t refresh);
    void (*done)(void *data, struct wl_proxy *wl_output);
    void (*scale)(void *data, struct wl_proxy *wl_output, int32_t factor);
    void (*name)(void *data, struct wl_proxy *wl_output, const char *name);
    void (*description)(void *data, struct wl_proxy *wl_output, const char *description);
};

struct zxdg_output_v1_listener_compat {
    void (*logical_position)(void *data, struct wl_proxy *xdg_output,
                             int32_t x, int32_t y);
    void (*logical_size)(void *data, struct wl_proxy *xdg_output,
                         int32_t width, int32_t height);
    void (*done)(void *data, struct wl_proxy *xdg_output);
    void (*name)(void *data, struct wl_proxy *xdg_output, const char *name);
    void (*description)(void *data, struct wl_proxy *xdg_output, const char *description);
};

static wl_proxy_add_listener_fn real_wl_proxy_add_listener = NULL;
static wl_proxy_get_class_fn real_wl_proxy_get_class = NULL;
static wl_proxy_get_version_fn real_wl_proxy_get_version = NULL;

static struct wl_output_listener_compat orig_output_listener;
static int has_orig_output_listener = 0;

static struct zxdg_output_v1_listener_compat orig_xdg_output_listener;
static int has_orig_xdg_output_listener = 0;

static void wrapped_output_geometry(void *data, struct wl_proxy *wl_output,
                                    int32_t x, int32_t y,
                                    int32_t physical_width, int32_t physical_height,
                                    int32_t subpixel, const char *make, const char *model,
                                    int32_t transform) {
    if (physical_width > 0 && physical_height > 0 && physical_width != physical_height) {
        int32_t pdim = (physical_width > physical_height) ? physical_width : physical_height;
        physical_width = pdim;
        physical_height = pdim;
    }
    if (orig_output_listener.geometry) {
        orig_output_listener.geometry(data, wl_output, x, y,
                                      physical_width, physical_height,
                                      subpixel, make, model, transform);
    }
}

static void wrapped_output_mode(void *data, struct wl_proxy *wl_output,
                                uint32_t flags, int32_t width, int32_t height,
                                int32_t refresh) {
    if (width > 0 && height > 0 && width != height) {
        int32_t dim = (width > height) ? width : height;
        width = dim;
        height = dim;
    }
    if (orig_output_listener.mode) {
        orig_output_listener.mode(data, wl_output, flags, width, height, refresh);
    }
}

static void wrapped_output_done(void *data, struct wl_proxy *wl_output) {
    if (orig_output_listener.done)
        orig_output_listener.done(data, wl_output);
}

static void wrapped_output_scale(void *data, struct wl_proxy *wl_output, int32_t factor) {
    if (orig_output_listener.scale)
        orig_output_listener.scale(data, wl_output, factor);
}

static void wrapped_output_name(void *data, struct wl_proxy *wl_output, const char *name) {
    if (orig_output_listener.name)
        orig_output_listener.name(data, wl_output, name);
}

static void wrapped_output_description(void *data, struct wl_proxy *wl_output, const char *description) {
    if (orig_output_listener.description)
        orig_output_listener.description(data, wl_output, description);
}

static struct wl_output_listener_compat wrapped_wl_output_listener = {
    .geometry = wrapped_output_geometry,
    .mode = wrapped_output_mode,
    .done = wrapped_output_done,
    .scale = wrapped_output_scale,
    .name = wrapped_output_name,
    .description = wrapped_output_description,
};

static void wrapped_xdg_logical_position(void *data, struct wl_proxy *xdg_output,
                                         int32_t x, int32_t y) {
    if (orig_xdg_output_listener.logical_position)
        orig_xdg_output_listener.logical_position(data, xdg_output, x, y);
}

static void wrapped_xdg_logical_size(void *data, struct wl_proxy *xdg_output,
                                     int32_t width, int32_t height) {
    if (width > 0 && height > 0 && width != height) {
        int32_t dim = (width > height) ? width : height;
        width = dim;
        height = dim;
    }
    if (orig_xdg_output_listener.logical_size)
        orig_xdg_output_listener.logical_size(data, xdg_output, width, height);
}

static void wrapped_xdg_done(void *data, struct wl_proxy *xdg_output) {
    if (orig_xdg_output_listener.done)
        orig_xdg_output_listener.done(data, xdg_output);
}

static void wrapped_xdg_name(void *data, struct wl_proxy *xdg_output, const char *name) {
    if (orig_xdg_output_listener.name)
        orig_xdg_output_listener.name(data, xdg_output, name);
}

static void wrapped_xdg_description(void *data, struct wl_proxy *xdg_output, const char *description) {
    if (orig_xdg_output_listener.description)
        orig_xdg_output_listener.description(data, xdg_output, description);
}

static struct zxdg_output_v1_listener_compat wrapped_zxdg_output_listener = {
    .logical_position = wrapped_xdg_logical_position,
    .logical_size = wrapped_xdg_logical_size,
    .done = wrapped_xdg_done,
    .name = wrapped_xdg_name,
    .description = wrapped_xdg_description,
};

int wl_proxy_add_listener(struct wl_proxy *proxy,
                          void (**implementation)(void),
                          void *data) {
    if (!real_wl_proxy_add_listener)
        real_wl_proxy_add_listener = (wl_proxy_add_listener_fn)dlsym(RTLD_NEXT, "wl_proxy_add_listener");
    if (!real_wl_proxy_get_class)
        real_wl_proxy_get_class = (wl_proxy_get_class_fn)dlsym(RTLD_NEXT, "wl_proxy_get_class");
    if (!real_wl_proxy_get_version)
        real_wl_proxy_get_version = (wl_proxy_get_version_fn)dlsym(RTLD_NEXT, "wl_proxy_get_version");

    if (!real_wl_proxy_add_listener)
        return -1;

    const char *cls = (real_wl_proxy_get_class && proxy) ? real_wl_proxy_get_class(proxy) : NULL;
    if (cls && implementation) {
        uint32_t ver = real_wl_proxy_get_version ? real_wl_proxy_get_version(proxy) : 2;
        if (strcmp(cls, "wl_output") == 0) {
            if (!has_orig_output_listener) {
                memset(&orig_output_listener, 0, sizeof(orig_output_listener));
                size_t slots = (ver >= 4) ? 6 : (ver >= 2 ? 4 : 2);
                memcpy(&orig_output_listener, implementation, slots * sizeof(void (*)(void)));
                has_orig_output_listener = 1;
            }
            return real_wl_proxy_add_listener(proxy,
                                              (void (**)(void))&wrapped_wl_output_listener,
                                              data);
        }
        if (strcmp(cls, "zxdg_output_v1") == 0) {
            if (!has_orig_xdg_output_listener) {
                memset(&orig_xdg_output_listener, 0, sizeof(orig_xdg_output_listener));
                size_t slots = (ver >= 2) ? 5 : 3;
                memcpy(&orig_xdg_output_listener, implementation, slots * sizeof(void (*)(void)));
                has_orig_xdg_output_listener = 1;
            }
            return real_wl_proxy_add_listener(proxy,
                                              (void (**)(void))&wrapped_zxdg_output_listener,
                                              data);
        }
    }

    return real_wl_proxy_add_listener(proxy, implementation, data);
}
