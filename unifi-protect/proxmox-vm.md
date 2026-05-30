# UniFi Protect x86 VM Experiment

This is the safer way to test the unofficial UniFi Protect container on x86:
put the entire Docker/QEMU experiment inside a disposable VM.

Do not run this directly on the Proxmox host.

## Suggested VM

- OS: Debian 12
- CPU: 4 cores minimum
- RAM: 8 GB preferred, 4 GB minimum
- Boot disk: 32 GB minimum
- Recording disk: dedicated virtual disk or passthrough disk
- Network: bridged LAN interface
- IPv6: enabled

Protect wants ports `80` and `443`, so give this VM its own IP address and do
not put Traefik or another web server on the same VM.

## Startup Script

The startup script can do the VM setup, Docker install, ARM64 emulation setup,
file generation, and image build for you.

```bash
sudo nano /root/unifi-protect-startup.sh
sudo chmod +x /root/unifi-protect-startup.sh
sudo START_PROTECT=1 /root/unifi-protect-startup.sh
```

Paste the contents of `debian-qcow2-startup.sh` into
`/root/unifi-protect-startup.sh`. The script is self-contained and does not
clone this private homelab repo.

It installs Docker using Docker's official Debian repository, installs the
Docker Compose plugin, enables ARM64 binfmt, writes the local compose/build
files into `/opt/stacks/unifi-protect`, clones the public upstream Protect
project, and runs the QEMU build.

## Manual Build

If you want to run the steps by hand after the startup script has installed
Docker and generated the files, or if you ran the startup script without
`START_PROTECT=1`:

```bash
cd /opt/stacks/unifi-protect
./build-x86-qemu.sh
UNIFI_PROTECT_IMAGE=unifi-protect-unvr:edge docker compose \
  -f compose.yml \
  -f compose-x86-qemu.yml \
  up -d
```

Then open:

```text
http://<vm-ip>/
```

## Stop

```bash
docker compose \
  -f compose.yml \
  -f compose-x86-qemu.yml \
  down
```

## Notes

- Take a Proxmox snapshot before first start.
- Use 8 GB RAM if possible. The startup script creates an 8 GB swapfile by
  default because ARM64 package installs under QEMU can run out of memory.
- Keep this VM off your main reverse proxy until it proves stable.
- Initial setup should be done offline if following the upstream project notes.
- Disable automatic UniFi OS/application updates after setup.
- If this fails, delete or roll back the VM rather than debugging on the
  Proxmox host.
