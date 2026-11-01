/*
 * sndcardparser_stub.c
 *
 * Minimal no-op stub for libsndcardparser.so.
 *
 * Purpose: tinyalsa/tinycompress's snd_utils_get_dev_node() dlopen()s
 * "libsndcardparser.so" and dlsym()s four required symbols
 * (snd_card_def_get_card, snd_card_def_put_card, snd_card_def_get_node,
 * snd_card_def_get_int, snd_card_def_get_str). If dlopen() or any dlsym()
 * fails, tinyalsa itself fails gracefully (returns NULL) -- but
 * pulseaudio-modules-droid apparently does not null-check this result
 * and crashes (SIGABRT -> SIGBUS) when the real lib is absent.
 *
 * This stub exists purely so dlopen()/dlsym() succeed. It does NOT parse
 * any real card-defs.xml and does NOT describe real hardware -- it reports
 * "no card found" for every lookup, which is a form tinyalsa's callers are
 * expected to handle (card not found is an ordinary, expected outcome,
 * unlike dlopen/dlsym failure).
 *
 * Build (on-device / NDK toolchain), produce BOTH 32-bit and 64-bit:
 *
 *   # 32-bit (ARM, matches /vendor/lib, /system/lib)
 *   clang --target=armv7a-linux-androideabi21 -shared -fPIC -nostdlib \
 *     -o libsndcardparser.so sndcardparser_stub.c -llog
 *
 *   # 64-bit (AArch64, matches /vendor/lib64, /system/lib64)
 *   clang --target=aarch64-linux-android21 -shared -fPIC -nostdlib \
 *     -o libsndcardparser.so sndcardparser_stub.c -llog
 *
 * If -nostdlib causes link errors (missing __stack_chk_fail etc.), drop
 * -nostdlib and just link normally against the NDK's libc; this stub only
 * uses libc malloc/strdup equivalents indirectly if you extend it, so for
 * the no-op version below plain libc linking is simplest and safest:
 *
 *   clang --target=armv7a-linux-androideabi21 -shared -fPIC \
 *     -o libsndcardparser.so sndcardparser_stub.c
 *   clang --target=aarch64-linux-android21 -shared -fPIC \
 *     -o libsndcardparser.so sndcardparser_stub.c
 */

#include <stddef.h>

/*
 * Opaque "card" and "node" handles. tinyalsa only ever treats these as
 * opaque void* -- it never dereferences their contents itself, it only
 * passes them back into the functions below. So we can return any
 * non-NULL sentinel pointer here without needing to match a real struct
 * layout, EXCEPT for the "card not found" paths, which must return NULL
 * as tinyalsa expects.
 */

/* snd_card_def_get_card(unsigned int card_num) -> void* card_node */
void *snd_card_def_get_card(unsigned int card)
{
    /*
     * Returning NULL here is the "safe" choice: it tells
     * snd_utils_get_dev_node() that this card number has no custom
     * node definition, which is an ORDINARY outcome tinyalsa already
     * handles (falls through to err_resolve_symbols / treats node as
     * absent) -- NOT a dlopen/dlsym failure, which is the actual crash
     * trigger. This keeps PCM open falling back to plain hw_ops instead
     * of plug_ops, which is what you want when there's no real plugin
     * card-defs.xml on this device.
     */
    (void)card;
    return NULL;
}

/* snd_card_def_put_card(void *card_node) -> void */
void snd_card_def_put_card(void *card_node)
{
    (void)card_node;
    /* no-op: nothing was allocated, nothing to free */
}

/* snd_card_def_get_node(void *card_node, unsigned int device, int type) -> void* dev_node */
void *snd_card_def_get_node(void *card_node, unsigned int device, int type)
{
    (void)card_node;
    (void)device;
    (void)type;
    return NULL;
}

/* snd_card_def_get_int(void *dev_node, const char *prop, int *val) -> int (0 = success) */
int snd_card_def_get_int(void *dev_node, const char *prop, int *val)
{
    (void)dev_node;
    (void)prop;
    (void)val;
    return -1; /* -ENODEV-ish: property not found */
}

/* snd_card_def_get_str(void *dev_node, const char *prop, char **val) -> int (0 = success) */
int snd_card_def_get_str(void *dev_node, const char *prop, char **val)
{
    (void)dev_node;
    (void)prop;
    (void)val;
    return -1;
}
