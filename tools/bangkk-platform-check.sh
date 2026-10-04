#!/system/bin/sh
#
# bangkk-platform-check.sh
#
# Read-only ground-truth diagnostics for the Motorola bangkk
# (crDroid 17.0 / Android 17 / lineage-24.0).
#
# Purpose: F0 platform audit. It records the real SoC, the active CPU
# governor, post-boot script evidence, panel identity, display nodes,
# thermal zones, charging interfaces and kernel identity BEFORE any
# power/thermal tuning is done.
#
# Safety: this script only READS. It never writes sysfs, never changes
# permissions, governors, thermal settings or charging state, and never
# loads/unloads modules. Safe to run as `adb shell` (no root required for
# most of it).
#
# Usage:
#   adb push device/motorola/bangkk/tools/bangkk-platform-check.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/bangkk-platform-check.sh

sec()    { printf '\n===== %s =====\n' "$1"; }
prop()   { printf '%-42s = %s\n' "$1" "$(getprop "$1" 2>/dev/null)"; }
file()   { if [ -r "$1" ]; then printf '%-42s = %s\n' "$1" "$(cat "$1" 2>/dev/null | tr '\n' ' ')"; else printf '%-42s = %s\n' "$1" "(missing)"; fi; }
exists() { if [ -e "$1" ]; then echo "present : $1"; else echo "absent  : $1"; fi; }

echo "bangkk platform check - $(date 2>/dev/null)"
echo "run as: $(id 2>/dev/null)"

sec "1. PRODUCT / PLATFORM IDENTITY"
prop ro.board.platform
prop ro.soc.model
prop ro.soc.manufacturer
prop ro.boot.product.device
prop ro.boot.product.hardware.sku
prop ro.boot.hardware
prop ro.boot.hardware.sku
prop ro.boot.slot_suffix
prop ro.product.device
prop ro.product.model
prop ro.hardware

sec "2. SOC / CHIPSET (kernel sysfs - authoritative)"
for f in soc_id chip_family chip_name chip_version machine family revision; do
    file "/sys/devices/soc0/$f"
done
echo "--- soc0 directory (raw) ---"
ls -l /sys/devices/soc0/ 2>/dev/null

sec "3. BOOT CMDLINE"
file /proc/cmdline

sec "4. KERNEL IDENTITY"
echo "uname -a : $(uname -a 2>/dev/null)"
file /proc/version
if [ -r /proc/wearystars ]; then
    echo "--- /proc/wearystars ---"
    cat /proc/wearystars 2>/dev/null
else
    echo "/proc/wearystars: (missing)"
fi

sec "5. SELINUX / DEBUG STATE (baseline only)"
echo "getenforce        : $(getenforce 2>/dev/null)"
prop ro.debuggable
prop ro.build.type
prop ro.build.tags
prop ro.secure
prop ro.adb.secure
prop ro.boot.verifiedbootstate

sec "6. CPU / CPUFREQ / SCHEDULER"
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    echo "--- $policy ---"
    file "$policy/scaling_governor"
    file "$policy/scaling_available_governors"
    file "$policy/scaling_cur_freq"
    file "$policy/scaling_available_frequencies"
    file "$policy/schedutil/up_rate_limit_us"
    file "$policy/schedutil/down_rate_limit_us"
    file "$policy/schedutil/hispeed_freq"
    file "$policy/schedutil/hispeed_load"
    file "$policy/schedutil/rtg_boost_freq"
done
echo "--- WALT / boost interfaces ---"
file /proc/sys/kernel/sched_boost
file /proc/sys/kernel/sched_util_clamp_min
file /proc/sys/kernel/sched_util_clamp_max
for f in input_boost_ms input_boost_freq sched_boost_on_input; do
    file "/sys/devices/system/cpu/cpu_boost/$f"
done
echo "--- cgroup uclamp (top-app) ---"
file /dev/cpuctl/top-app/cpu.uclamp.min
file /dev/cpuctl/top-app/cpu.uclamp.max
file /dev/cpuctl/top-app/cpu.uclamp.latency_sensitive

sec "7. POST-BOOT SCRIPT EVIDENCE"
exists /vendor/bin/init.kernel.post_boot.sh
exists /vendor/bin/init.kernel.post_boot-holi.sh
exists /vendor/bin/init.kernel.post_boot-blair.sh
echo "NOTE: the dispatcher selects holi when /sys/devices/soc0/chip_family=0x73"
echo "      and blair when chip_family=0x7c. An invalid family leaves the"
echo "      kernel default governor (performance) in place."
echo "--- governor actually applied (see section 6) is the ground truth ---"
echo "--- recent logcat matches ---"
logcat -d -b all 2>/dev/null | grep -iE "post_boot|kernel-post-boot|schedutil" | tail -20
echo "--- recent dmesg matches ---"
dmesg 2>/dev/null | grep -iE "post_boot|schedutil|wrong chip|Invalid chip" | tail -20

sec "8. DISPLAY / PANEL"
file "/proc/device-tree/chosen/mmi,panel_name"
file "/proc/device-tree/chosen/mmi,panel_id"
file "/proc/device-tree/chosen/mmi,panel_ver"
getprop 2>/dev/null | grep -iE "panel|refresh|display" | sort
echo "--- SDE panel feature sysfs nodes ---"
for n in hbm dc acl cabc; do
    exists "/sys/devices/platform/soc/soc:qcom,dsi-display-primary/$n"
done
echo "--- backlight ---"
ls -l /sys/class/backlight/ 2>/dev/null
echo "--- brightness of panel0-backlight (read) ---"
file /sys/class/backlight/panel0-backlight/brightness

sec "9. THERMAL"
echo "--- thermal zones ---"
for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    printf '%-40s type=%-24s temp=%s\n' "$z" \
        "$(cat "$z/type" 2>/dev/null)" "$(cat "$z/temp" 2>/dev/null)"
done
echo "--- cooling devices (count) ---"
ls /sys/class/thermal/cooling_device* 2>/dev/null | wc -l
prop vendor.thermal.mode
echo "--- thermal-engine ---"
exists /vendor/bin/thermal-engine
ls -l /vendor/etc/thermal-engine*.conf 2>/dev/null
echo "--- dumpsys thermalservice (excerpt) ---"
dumpsys thermalservice 2>/dev/null | head -80

sec "10. CHARGING / ADAPTIVE CHARGE"
for p in charging_enabled upper_limit lower_limit blocking; do
    file "/sys/module/qpnp_adaptive_charge/parameters/$p"
done
echo "--- power_supply devices ---"
for ps in /sys/class/power_supply/*; do
    [ -e "$ps" ] || continue
    echo "device: $(basename "$ps")"
done
echo "--- battery power-supply attributes ---"
for a in capacity status health temp cycle_count charge_full charge_full_design charge_counter charge_control_limit charge_control_limit_max constant_charge_current input_current_limit time_to_full_now charge_rate; do
    file "/sys/class/power_supply/battery/$a"
done
echo "--- mmi_chrg_manager ---"
for a in charge_control_limit charge_control_limit_max current_now voltage_now; do
    file "/sys/class/power_supply/mmi_chrg_manager/$a"
done

sec "11. KERNEL MODULES (relevant)"
lsmod 2>/dev/null | grep -iE "rbs_fod_mmi|mmi-smbcharger|mmi_parallel|qpnp_adaptive|bq25980|bq25960|mmi_relay|zram|mmi_sys_temp" 
echo "--- total modules loaded ---"
lsmod 2>/dev/null | wc -l

sec "12. EXPECTED KERNEL INTERFACES"
for p in \
    /sys/kernel/debug/wakeup_sources \
    /sys/class/kgsl/kgsl-3d0/max_pwrlevel \
    /sys/class/devfreq \
    /dev/esfp0 \
    /sys/class/thermal/thermal_zone0/emul_temp ; do
    exists "$p"
done

printf '\n===== END =====\n'
