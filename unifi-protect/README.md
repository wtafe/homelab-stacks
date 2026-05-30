# UniFi Protect

Ubiquiti does not provide a supported Docker or Swarm deployment for UniFi
Protect. Their supported self-hosting path is UniFi OS Server, but that only
self-hosts the UniFi Network application; Protect must run on a compatible
UniFi Console.

This directory contains an experimental ARM64 Compose file based on:

https://github.com/dciancu/unifi-protect-unvr-docker-arm64

Notes before using it:

- This is not supported by Ubiquiti.
- It is ARM64-only. Running it on x86 means emulating ARM64 with QEMU.
- It is not a good Docker Swarm stack target because Protect needs host
  networking, privileged mode, cgroups, tmpfs mounts, and systemd-like behavior
  inside the container.
- The image must be built by you. The upstream project intentionally does not
  ship prebuilt images.
- Protect expects IPv6 enabled and at least 4 GB RAM.
- Initial setup should be done offline, then automatic UniFi OS/application
  updates should be disabled.

Build and deploy on an ARM64 host:

```bash
git clone https://github.com/dciancu/unifi-protect-unvr-docker-arm64.git
cd unifi-protect-unvr-docker-arm64
BUILD_EDGE=1 BUILD_TAG_VERSION=1 DOCKER_IMAGE=unifi-protect-unvr bash build.sh
cd -
UNIFI_PROTECT_IMAGE=unifi-protect-unvr:edge docker compose -f unifi-protect/compose.yml up -d
```

Experimental x86/QEMU build:

Issue #39 reports success on Ubuntu 24.04 x86_64 with a newer QEMU by forcing
`linux/arm64`, adding a fake `policy-rc.d`, increasing nginx map hash sizing,
and loosening `unifi-core` service limits. Issue #55 reports that this route
may no longer start reliably for everyone.

Prepare the x86 Docker host for ARM64 emulation:

```bash
docker run --privileged --rm tonistiigi/binfmt --install arm64
```

Build the ARM64 image under QEMU:

```bash
cd unifi-protect
./build-x86-qemu.sh
```

Deploy on the x86 host:

```bash
UNIFI_PROTECT_IMAGE=unifi-protect-unvr:edge docker compose \
  -f unifi-protect/compose.yml \
  -f unifi-protect/compose-x86-qemu.yml \
  up -d
```

In Portainer, create this as a standalone Compose stack, not a Swarm stack, and
include both `compose.yml` and `compose-x86-qemu.yml`.

For Proxmox, prefer running this inside a dedicated VM. See
`proxmox-vm.md`.

Access Protect at:

```text
http://<host-ip>/
```
