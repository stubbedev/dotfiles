#!/usr/bin/env bash
# Rebind the i2c-hid touchpad after a Thunderbolt dock undock.
#
# See src/udev/rules.d/90-touchpad-rebind.rules for the full why: on
# staggio (Lunar Lake) the SNSL0028:00 touchpad stays enumerated but emits
# zero events after undock until its i2c_hid_acpi driver is rebound.
#
# Shared by both deploy paths:
#   - NixOS: systemd.services.touchpad-rebind in modules/nixos/udev.nix
#     runs this body via `script`.
#   - non-NixOS: installed to /etc/udev/scripts/rebind-touchpad.sh and run
#     by /etc/systemd/system/touchpad-rebind.service.
# Both are pulled in by SYSTEMD_WANTS from the udev DRM-hotplug rule.
set -u

# Let the dock power transition settle before touching the driver.
sleep 2

drv=/sys/bus/i2c/drivers/i2c_hid_acpi
dev=i2c-SNSL0028:00

# No-op on any host without this touchpad (the udev rule also guards, but
# the service may be invoked directly).
[ -e "$drv/$dev" ] || exit 0

echo "$dev" > "$drv/unbind" || true
echo "$dev" > "$drv/bind" || true
