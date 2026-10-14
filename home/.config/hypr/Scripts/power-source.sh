#!/bin/sh
# power-source.sh ac|battery — exit 0 if the machine is on that power source.
#
# hypridle's condition_cmd, so each idle listener can have an AC and a
# battery variant. "On battery" means a system battery exists and no mains or
# USB supply is online; a desktop with no battery is always on AC. Batteries
# with scope "Device" (a wireless mouse, say) are not the machine's and are
# skipped.

# POWER_SUPPLY_DIR overrides the sysfs path, for testing.
battery=0
online=0
for dev in "${POWER_SUPPLY_DIR:-/sys/class/power_supply}"/*; do
    [ -e "$dev/type" ] || continue
    [ "$(cat "$dev/scope" 2>/dev/null)" = Device ] && continue
    case "$(cat "$dev/type")" in
        Battery) battery=1 ;;
        Mains|USB) [ "$(cat "$dev/online" 2>/dev/null)" = 1 ] && online=1 ;;
    esac
done

if [ "$battery" = 1 ] && [ "$online" = 0 ]; then
    source=battery
else
    source=ac
fi

[ "$source" = "$1" ]
