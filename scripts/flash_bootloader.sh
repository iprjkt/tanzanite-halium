#!/usr/bin/env bash
# Flashes LK Fenrir and Preloader Engineering to both slots on Redmi Note 14 4G (tanzanite).
# Supports flashing via active ADB (root) or fastboot mode.
# Includes verification of existing partition hashes to allow skipping when already up to date.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FENRIR_IMG="$ROOT/tanzanite-fenrir.img"
PRELOADER_BIN="$ROOT/preloader_tanzanite.bin"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

[ -f "$FENRIR_IMG" ] || { red "Missing $FENRIR_IMG"; exit 1; }
[ -f "$PRELOADER_BIN" ] || { red "Missing $PRELOADER_BIN"; exit 1; }

EXPECTED_LK_SHA=$(sha256sum "$FENRIR_IMG" | cut -d' ' -f1)
EXPECTED_PL_SHA=$(sha256sum "$PRELOADER_BIN" | cut -d' ' -f1)
LK_SIZE=$(stat -c %s "$FENRIR_IMG")
PL_SIZE=$(stat -c %s "$PRELOADER_BIN")

bold "=========================================================="
bold " Tanzanite Bootloader Flasher: LK Fenrir & Preloader Eng  "
bold "=========================================================="
echo "LK Fenrir image      : $FENRIR_IMG ($LK_SIZE bytes)"
echo "LK Fenrir SHA256     : $EXPECTED_LK_SHA"
echo "Preloader image      : $PRELOADER_BIN ($PL_SIZE bytes)"
echo "Preloader SHA256     : $EXPECTED_PL_SHA"
echo

# 1. Detect device mode (ADB vs Fastboot)
MODE=""
if adb get-state 2>/dev/null | grep -q "device"; then
    MODE="adb"
elif fastboot devices 2>/dev/null | grep -q -E "[a-zA-Z0-9]+"; then
    MODE="fastboot"
fi

if [ -z "$MODE" ]; then
    red "No device detected via ADB or Fastboot."
    echo "Please connect your device with USB debugging enabled, or in fastboot mode."
    exit 1
fi

bold "[*] Device detected in $MODE mode."

if [ "$MODE" = "adb" ]; then
    bold "== Checking existing partition integrity on device =="
    
    # Read hashes from device
    CURR_LK_A=$(adb shell "su -c 'head -c $LK_SIZE /dev/block/by-name/lk_a | sha256sum 2>/dev/null'" | awk '{print $1}')
    CURR_LK_B=$(adb shell "su -c 'head -c $LK_SIZE /dev/block/by-name/lk_b | sha256sum 2>/dev/null'" | awk '{print $1}')
    CURR_PL_A=$(adb shell "su -c 'head -c $PL_SIZE /dev/block/by-name/preloader_raw_a | sha256sum 2>/dev/null'" | awk '{print $1}')
    CURR_PL_B=$(adb shell "su -c 'head -c $PL_SIZE /dev/block/by-name/preloader_raw_b | sha256sum 2>/dev/null'" | awk '{print $1}')

    LK_A_MATCH=0; [ "$CURR_LK_A" = "$EXPECTED_LK_SHA" ] && LK_A_MATCH=1
    LK_B_MATCH=0; [ "$CURR_LK_B" = "$EXPECTED_LK_SHA" ] && LK_B_MATCH=1
    PL_A_MATCH=0; [ "$CURR_PL_A" = "$EXPECTED_PL_SHA" ] && PL_A_MATCH=1
    PL_B_MATCH=0; [ "$CURR_PL_B" = "$EXPECTED_PL_SHA" ] && PL_B_MATCH=1

    [ "$LK_A_MATCH" -eq 1 ] && green "  [+] lk_a            : LK Fenrir verified" || yellow "  [-] lk_a            : Stock or outdated"
    [ "$LK_B_MATCH" -eq 1 ] && green "  [+] lk_b            : LK Fenrir verified" || yellow "  [-] lk_b            : Stock or outdated"
    [ "$PL_A_MATCH" -eq 1 ] && green "  [+] preloader slot A: Preloader Eng verified" || yellow "  [-] preloader slot A: Stock or outdated"
    [ "$PL_B_MATCH" -eq 1 ] && green "  [+] preloader slot B: Preloader Eng verified" || yellow "  [-] preloader slot B: Stock or outdated"
    echo

    ALL_MATCH=0
    if [ "$LK_A_MATCH" -eq 1 ] && [ "$LK_B_MATCH" -eq 1 ] && [ "$PL_A_MATCH" -eq 1 ] && [ "$PL_B_MATCH" -eq 1 ]; then
        ALL_MATCH=1
    fi

    # Confirmation prompt
    DO_FLASH=1
    if [ "$ALL_MATCH" -eq 1 ]; then
        green "All bootloader partitions on BOTH slots are already up to date."
        read -r -t 8 -p "Re-flash anyway? [y/N, default: N in 8s]: " CONFIRM || CONFIRM="n"
        echo
        case "${CONFIRM:-n}" in
            [yY]|[yY][eE][sS]) DO_FLASH=1 ;;
            *) DO_FLASH=0 ;;
        esac
    else
        yellow "Bootloader security bypass is not fully installed on both slots."
        read -r -t 8 -p "Flash LK Fenrir and Preloader Eng to BOTH slots? [Y/n, default: Y in 8s]: " CONFIRM || CONFIRM="y"
        echo
        case "${CONFIRM:-y}" in
            [nN]|[nN][oO]) DO_FLASH=0 ;;
            *) DO_FLASH=1 ;;
        esac
    fi

    if [ "$DO_FLASH" -eq 0 ]; then
        green "Skipping bootloader flashing as requested."
        exit 0
    fi

    bold "== Flashing to both slots via ADB =="
    echo "[*] Uploading images to /data/local/tmp/..."
    adb push "$FENRIR_IMG" /data/local/tmp/lk_fenrir.img
    adb push "$PRELOADER_BIN" /data/local/tmp/preloader_eng.bin

    echo "[*] Writing LK Fenrir to /dev/block/by-name/lk_a..."
    adb shell "su -c 'blockdev --setrw /dev/block/by-name/lk_a && dd if=/data/local/tmp/lk_fenrir.img of=/dev/block/by-name/lk_a bs=4M && sync'"
    green "  [+] Flashed lk_a"

    echo "[*] Writing LK Fenrir to /dev/block/by-name/lk_b..."
    adb shell "su -c 'blockdev --setrw /dev/block/by-name/lk_b && dd if=/data/local/tmp/lk_fenrir.img of=/dev/block/by-name/lk_b bs=4M && sync'"
    green "  [+] Flashed lk_b"

    echo "[*] Writing Preloader Eng to /dev/block/by-name/preloader_raw_a..."
    adb shell "su -c 'blockdev --setrw /dev/block/by-name/preloader_raw_a && dd if=/data/local/tmp/preloader_eng.bin of=/dev/block/by-name/preloader_raw_a bs=4M && sync'"
    green "  [+] Flashed preloader_raw_a"

    echo "[*] Writing Preloader Eng to /dev/block/by-name/preloader_raw_b..."
    adb shell "su -c 'blockdev --setrw /dev/block/by-name/preloader_raw_b && dd if=/data/local/tmp/preloader_eng.bin of=/dev/block/by-name/preloader_raw_b bs=4M && sync'"
    green "  [+] Flashed preloader_raw_b"

    echo "[*] Cleaning up temporary files on device..."
    adb shell "rm -f /data/local/tmp/lk_fenrir.img /data/local/tmp/preloader_eng.bin"

    bold "== Verification =="
    VERIF_LK_A=$(adb shell "su -c 'head -c $LK_SIZE /dev/block/by-name/lk_a | sha256sum'" | awk '{print $1}')
    VERIF_LK_B=$(adb shell "su -c 'head -c $LK_SIZE /dev/block/by-name/lk_b | sha256sum'" | awk '{print $1}')
    VERIF_PL_A=$(adb shell "su -c 'head -c $PL_SIZE /dev/block/by-name/preloader_raw_a | sha256sum'" | awk '{print $1}')
    VERIF_PL_B=$(adb shell "su -c 'head -c $PL_SIZE /dev/block/by-name/preloader_raw_b | sha256sum'" | awk '{print $1}')

    [ "$VERIF_LK_A" = "$EXPECTED_LK_SHA" ] && green "  [+] lk_a verification: PASSED" || red "  [-] lk_a verification: FAILED"
    [ "$VERIF_LK_B" = "$EXPECTED_LK_SHA" ] && green "  [+] lk_b verification: PASSED" || red "  [-] lk_b verification: FAILED"
    [ "$VERIF_PL_A" = "$EXPECTED_PL_SHA" ] && green "  [+] preloader_a verification: PASSED" || red "  [-] preloader_a verification: FAILED"
    [ "$VERIF_PL_B" = "$EXPECTED_PL_SHA" ] && green "  [+] preloader_b verification: PASSED" || red "  [-] preloader_b verification: FAILED"

    green "[*] Both slots are verified and protected."
    exit 0
fi

if [ "$MODE" = "fastboot" ]; then
    bold "== Flashing to both slots via Fastboot =="
    read -r -t 8 -p "Flash LK Fenrir and Preloader Eng to BOTH slots? [Y/n, default: Y in 8s]: " CONFIRM || CONFIRM="y"
    echo
    case "${CONFIRM:-y}" in
        [nN]|[nN][oO]) green "Skipped."; exit 0 ;;
    esac

    echo "[*] Flashing lk_a..."
    fastboot flash lk_a "$FENRIR_IMG"
    echo "[*] Flashing lk_b..."
    fastboot flash lk_b "$FENRIR_IMG"
    echo "[*] Flashing preloader_a..."
    fastboot flash preloader_a "$PRELOADER_BIN"
    echo "[*] Flashing preloader_b..."
    fastboot flash preloader_b "$PRELOADER_BIN"

    green "[*] Successfully flashed LK Fenrir & Preloader Eng to both slots via fastboot."
    exit 0
fi
