_: {
  flake.modules.nixos.dbus = _: {
    # dbus-broker is the modern, faster D-Bus implementation: lower
    # latency, structured journal logging, kdbus-style design without
    # the kernel module. Drop-in replacement for the legacy
    # dbus-daemon. NixOS keeps both available; pick broker explicitly.
    services.dbus.implementation = "broker";
  };
}
