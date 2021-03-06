#!/bootrec/busybox sh

# Disable printing/echo of commands
set +x

############
# SETTINGS #
############

REAL_INIT="/init.real"

LOG_FILE="/bootrec/boot-log.txt"
RECOVERY_CPIO="/bootrec/recovery.cpio"

KEY_EVENT_DELAY=2
WARMBOOT_RECOVERY=0x77665502

LED_RED="/sys/class/leds/led:rgb_red/brightness"
LED_GREEN="/sys/class/leds/led:rgb_green/brightness"
LED_BLUE="/sys/class/leds/led:rgb_blue/brightness"

############
#   CODE   #
############

# Save current PATH variable, then change it
_PATH="$PATH"
export PATH=/bootrec:/sbin

# Use root as base dir
busybox cd /

# Log current date/time
busybox chmod 755 ${LOG_FILE}
busybox date >> ${LOG_FILE}

# Redirect stdout and stderr to log file
exec >> ${LOG_FILE} 2>&1

# Re-enable printing commands
set -x

# Delete this script
busybox rm -f /init

# Create directories
busybox mkdir -m 755 -p /dev/input
busybox mkdir -m 555 -p /proc
busybox mkdir -m 755 -p /sys

# Create device nodes
# Per linux Documentation/devices.txt
for i in $(busybox seq 0 12); do
	busybox mknod -m 600 /dev/input/event${i} c 13 $(busybox expr 64 + ${i})
done
busybox mknod -m 666 /dev/null c 1 3

# Mount filesystems
busybox mount -t proc proc /proc
busybox mount -t sysfs sysfs /sys

# Methods for controlling LED
led_purple() {
  busybox echo 255 > ${LED_RED}
  busybox echo   0 > ${LED_GREEN}
  busybox echo 255 > ${LED_BLUE}
}
led_blue() {
  busybox echo   0 > ${LED_RED}
  busybox echo 100 > ${LED_GREEN}
  busybox echo 255 > ${LED_BLUE}
}
led_off() {
  busybox echo   0 > ${LED_RED}
  busybox echo   0 > ${LED_GREEN}
  busybox echo   0 > ${LED_BLUE}
}

# Set LED to purple to indicate it's time to press keys
led_purple

# Keycheck will exit with code 42 if vol up/down is pressed
busybox timeout -t ${KEY_EVENT_DELAY} keycheck

# Check if we detected volume key pressing or the user rebooted into recovery mode
if [ $? -eq 42 ] || busybox grep -q warmboot=${WARMBOOT_RECOVERY} /proc/cmdline; then
  echo "Entering Recovery Mode" >> ${LOG_FILE}

  # Set LED to blue to indicate recovery mode
  led_blue

  # Make sure root is in read-write mode
  busybox mount -o remount,rw /

  # Clean up rc scripts in root to avoid problems
  busybox rm -f /init*.rc /init*.sh

  # Unpack ramdisk to root
  busybox cpio -i -u < ${RECOVERY_CPIO}

  # Delete recovery ramdisk
  busybox rm -f ${RECOVERY_CPIO}
else
  echo "Booting Normally" >> ${LOG_FILE}

  # Move real init script into position
  busybox mv ${REAL_INIT} /init
fi

# Clean up, start with turning LED off
led_off

# Remove folders and devices
busybox umount /proc
busybox umount /sys
busybox rm -rf /dev/*

# Remove dangerous files to avoid security problems
busybox rm -f /bootrec/recovery.cpio /bootrec/init.sh /bootrec/keycheck

# Reset PATH
export PATH="${_PATH}"

# All done, now boot
exec /init $@
