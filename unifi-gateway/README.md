# UniFi Gateway Emulator

This is a standalone Docker Compose stack for:

https://github.com/amd989/unifi-gateway

It emulates a UniFi Security Gateway so a third-party router can appear in the
UniFi Controller.

This is not a Docker Swarm stack. The upstream project requires
`network_mode: host` so it can read the real router interfaces. Run it on the
router host, or on a VM/container that can see the same interfaces and lease
files you want reported.

Before running, edit `conf/unifi-gateway.conf`:

- Set `lan_ip` to the router LAN IP.
- Set `lan_mac` to the LAN MAC address the controller should identify.
- Set each `realif` to the real interface name on the host.
- Optionally set `dhcp_lease_file` and `dhcp_lease_format`.

Start:

```bash
UNIFI_ADOPT_URL=http://unifi.home.arpa:8080/inform docker compose -f stack.yml up -d
```

Adoption may need two inform attempts. If the first run shows the gateway in
UniFi, click Adopt, then restart the container:

```bash
docker compose -f stack.yml restart
```
