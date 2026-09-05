# homelab — Flatcar Container Linux home server

An old laptop running [Flatcar Container Linux](https://www.flatcar.org/):
an immutable, container-only OS with no package manager. Everything the box
runs is a Docker container; everything the box *is* comes from the butane
config, transpiled to an Ignition config that is applied once at install time.

Reachable from outside the LAN over WireGuard only — one UDP port forwarded
on the router, nothing else exposed.

## Secrets

This is a **public repo**, so the butane config — which carries the WAN
address, the LAN layout, and the WireGuard settings — is not committed in
plaintext. The encrypted copy lives at `secrets/flatcar-server.bu` (sops,
same age recipients as every other secret here). The plaintext `server.bu`
and the generated `ignition.json` are git-ignored.

Edit the config with:

```sh
sops secrets/flatcar-server.bu     # decrypts, opens $EDITOR, re-encrypts on save
```

## Facts about this network

Concrete values (WAN address, DHCP reservation, subnets) live in the
encrypted butane. Shapes only here:

| | |
|---|---|
| Router | Zyxel EX3301-T0, web UI at `http://192.168.1.1`, ISP Hiper |
| LAN | `192.168.1.0/24` |
| Server LAN address | DHCP reservation (see butane / router) |
| WireGuard | one UDP port, peer subnet `10.13.13.0/24` |

## 1. Build the Ignition config

```sh
./flatcar/build.sh
```

Decrypts the butane with sops and pipes it straight into
`butane --strict` — the plaintext never lands on disk. Writes
`flatcar/ignition.json`. `--strict` turns warnings into errors, so a typo
fails here rather than leaving you with a box you cannot ssh into.

## 2. Install onto the laptop

Ignition is applied **once**, at first boot. There is no second chance short
of reinstalling, so make sure the ssh key in `server.bu` is one you hold.

1. Write the [Flatcar ISO](https://www.flatcar.org/docs/latest/installing/bare-metal/booting-with-iso/)
   to a USB stick and boot the laptop from it.
2. In the laptop's firmware, before installing:
   - disable Secure Boot (Flatcar's stable images are not signed for it),
   - set *power on after AC loss* / *restore on AC power* if the board has it,
     so the server comes back on its own after an outage.
3. From the live session, find the target disk and serve the config from this
   machine:

   ```sh
   # on this desktop, in the flatcar/ directory
   nix run nixpkgs#python3 -- -m http.server 8000
   ```

   ```sh
   # on the laptop, booted from the ISO
   lsblk                       # identify the internal disk, e.g. /dev/sda
   curl -O http://192.168.1.21:8000/ignition.json
   sudo flatcar-install -d /dev/sda -C stable -i ignition.json
   sudo reboot
   ```

   `flatcar-install` **destroys everything on the target disk.** Check `lsblk`
   twice — the USB stick you booted from is in that list too.

4. After reboot: `ssh core@<laptop-ip>`. There is no password; the ssh key is
   the only way in. `core` has passwordless `sudo`.

## 3. Router — Zyxel at `192.168.1.1`

Exact menu names vary by Zyxel model; these are the four things to find.

1. **Reserve the server's address.**
   *Network Setting → Home Networking → LAN Setup* (or *Static DHCP*).
   Add the laptop's ethernet MAC — `ip -br link` on the server prints it —
   and bind it to `192.168.1.10`. Reboot the server or `sudo systemctl restart
   systemd-networkd` to pick it up.

2. **Forward WireGuard.**
   *Network Setting → NAT → Port Forwarding*. One rule:

   | Field | Value |
   |---|---|
   | Service name | `wireguard` |
   | Protocol | UDP |
   | External port | `51820` |
   | Internal IP | `192.168.1.10` |
   | Internal port | `51820` |
   | WAN interface | the one carrying the static IP |

   That is the **only** inbound rule this setup needs.

3. **Confirm the WAN address is the static one.**
   *Connection Status* / *Network Setting → Broadband* should show the static
   IP (the `SERVERURL` value in the butane). If it does not, the static IP is
   not bound to this connection yet and the port forward will point at nothing
   stable.

4. **Close what you are not using.** While you are in there:
   - turn **UPnP off** (*Network Setting → Home Networking → UPnP*) — it lets
     any LAN device open its own port forwards,
   - turn **remote (WAN-side) management off** for HTTP/HTTPS/SSH/Telnet
     (*Maintenance → Remote Management*),
   - change the router admin password if it is still the sticker default.

## 4. Get a WireGuard peer config

The container mints one config per name in `PEERS`:

```sh
sudo docker exec -it wireguard /app/show-peer phone     # QR code for the phone
sudo cat /opt/stacks/wireguard/config/peer_laptop/peer_laptop.conf
```

To add a device, edit `PEERS` in `/opt/stacks/wireguard/docker-compose.yaml`
and `sudo systemctl restart docker-compose@wireguard`.

Peers get `10.13.13.0/24` and `192.168.1.0/24` routed — the VPN and the home
LAN, not a full tunnel, so normal browsing does not detour through the house.

## 5. Adding a service

One systemd template unit runs every stack:

```sh
sudo mkdir -p /opt/stacks/jellyfin
sudo vi /opt/stacks/jellyfin/docker-compose.yaml
sudo systemctl enable --now docker-compose@jellyfin
```

`systemctl restart docker-compose@<name>` after editing a compose file;
`journalctl -u docker-compose@<name>` when it does not come up.

## Updates

Flatcar updates itself and reboots between 04:00 and 05:00
(`/etc/flatcar/update.conf`). `docker compose` is a systemd-sysext kept
current by `systemd-sysupdate`; when it stages a new version it touches
`/run/reboot-required` and the next OS reboot picks it up.

## Not set up yet

- **Public websites.** Nothing but WireGuard is forwarded, so a reverse proxy
  has no public port and Let's Encrypt has no HTTP-01 challenge. Reaching
  public sites needs either 80/443 forwarded to the server plus Traefik, or a
  DNS-01 cert and access over the VPN. Which one depends on whether the sites
  are for you or for the internet.
- **The Nix cache.** `nix.stubbe.dev` currently resolves to `45.32.185.197`, a
  VPS running xilo. Moving it here behind a VPN-only server means every host
  that substitutes from it has to be on the VPN — fine for your own machines,
  not for CI. Worth deciding before moving it.
