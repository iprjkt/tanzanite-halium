#!/bin/sh

# Ensure vendor_dlkm symlink exists
[ -e /vendor_dlkm ] || ln -sf /android/vendor_dlkm /vendor_dlkm

# Wait for vendor_dlkm to be mounted
for i in $(seq 1 50); do
    [ -d /android/vendor_dlkm/lib/modules ] && break
    sleep 0.2
done

# Step 1: Load SSPM platform driver first
/usr/sbin/modprobe sspm_v3 2>/dev/null || true
sleep 0.2

# Step 2: Load SCP core driver
/usr/sbin/modprobe scp 2>/dev/null || true
sleep 0.2

# Step 3: Load touchscreen driver now that real SCP is available
/usr/sbin/modprobe ft3519t 2>/dev/null || true

# Step 4: Load Audio DSP, IPI, and SCP audio
/usr/sbin/modprobe adsp 2>/dev/null || true
/usr/sbin/modprobe audio_ipi 2>/dev/null || true
/usr/sbin/modprobe snd-soc-audiodsp-common 2>/dev/null || true
/usr/sbin/modprobe mtk-scp-audiocommon 2>/dev/null || true
/usr/sbin/modprobe mtk-scp-audio 2>/dev/null || true

# Step 5: Load AFE and ALSA SoC platform drivers
/usr/sbin/modprobe mtk-afe-external 2>/dev/null || true
/usr/sbin/modprobe snd-soc-mtk-common 2>/dev/null || true
/usr/sbin/modprobe snd-soc-mt6789-afe 2>/dev/null || true
/usr/sbin/modprobe snd-soc-mt6366 2>/dev/null || true

# Step 6: Load speaker / headphone codec amps
/usr/sbin/modprobe snd-soc-aw87xx 2>/dev/null || true
/usr/sbin/modprobe snd-soc-rt5512 2>/dev/null || true
/usr/sbin/modprobe snd-soc-tfa98xx 2>/dev/null || true
/usr/sbin/modprobe snd-soc-sipa 2>/dev/null || true
/usr/sbin/modprobe snd-soc-sipa-tuning 2>/dev/null || true

# Step 7: Load GPU and DVFS platform drivers
/usr/sbin/modprobe fhctl 2>/dev/null || true
/usr/sbin/modprobe mtk_gpufreq_mt6789 2>/dev/null || true
/usr/sbin/modprobe mali_mgm 2>/dev/null || true
/usr/sbin/modprobe mali_prot_alloc 2>/dev/null || true
/usr/sbin/modprobe mali_kbase_mt6789 2>/dev/null || true
