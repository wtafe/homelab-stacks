#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

PROTECT_DIR="${PROTECT_DIR:-/opt/stacks/unifi-protect}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/dciancu/unifi-protect-unvr-docker-arm64.git}"
UNIFI_PROTECT_IMAGE="${UNIFI_PROTECT_IMAGE:-unifi-protect-unvr:edge}"
UNIFI_PROTECT_IMAGE_REPOSITORY="${UNIFI_PROTECT_IMAGE_REPOSITORY:-unifi-protect-unvr}"
SWAP_SIZE="${SWAP_SIZE:-8G}"
START_PROTECT="${START_PROTECT:-0}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root, or via cloud-init runcmd." >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

if ! swapon --show --noheadings | grep -q .; then
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
fi

docker run --privileged --rm tonistiigi/binfmt --install arm64

mkdir -p "$PROTECT_DIR"

cat > "$PROTECT_DIR/compose.yml" <<'EOF'
services:
  unifi-protect:
    image: ${UNIFI_PROTECT_IMAGE:-unifi-protect-unvr:edge}
    container_name: unifi-protect
    hostname: UNVR
    tty: true
    stop_grace_period: 2m
    cgroup: host
    network_mode: host
    privileged: true
    restart: unless-stopped
    extra_hosts:
      - "UNVR:127.0.1.1"
    cap_add:
      - dac_read_search
      - sys_admin
    security_opt:
      - apparmor=unconfined
      - seccomp=unconfined
    environment:
      - container=docker
      - STORAGE_DISK=${UNIFI_PROTECT_STORAGE_DISK:-/dev/sda}
      - DEBUG=${UNIFI_PROTECT_DEBUG:-false}
    tmpfs:
      - /run
      - /run/lock
      - /tmp:mode=1777
      - /var/run
      - /var/run/lock
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
      - ./storage/srv:/srv
      - ./storage/data:/data
      - ./storage/persistent:/persistent
EOF

cat > "$PROTECT_DIR/compose-x86-qemu.yml" <<'EOF'
services:
  unifi-protect:
    platform: linux/arm64
EOF

cat > "$PROTECT_DIR/build-x86-qemu.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/dciancu/unifi-protect-unvr-docker-arm64.git}"
UPSTREAM_DIR="${UPSTREAM_DIR:-./unifi-protect-unvr-docker-arm64}"
IMAGE_REPOSITORY="${UNIFI_PROTECT_IMAGE_REPOSITORY:-unifi-protect-unvr}"
BUILD_RETRIES="${BUILD_RETRIES:-3}"

if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  git clone "$UPSTREAM_REPO" "$UPSTREAM_DIR"
fi

cd "$UPSTREAM_DIR"
git fetch --all --prune
git pull --ff-only

perl -0pi -e 's/docker build /docker build --platform linux\/arm64 /g' build-protect.sh
perl -0pi -e 's/docker run --rm /docker run --platform linux\/arm64 --rm /g' build-protect.sh

for dockerfile in firmware-base.Dockerfile protect.Dockerfile; do
  perl -0pi -e 's/apt-get install -y apt-transport-https ca-certificates/apt-get install -y ca-certificates/g' "$dockerfile"
  perl -0pi -e 's/\n\s*apt-transport-https \\\n/\n/g' "$dockerfile"
  if ! grep -q 'Acquire::Retries' "$dockerfile"; then
    perl -0pi -e 's|(SHELL \["/usr/bin/env", "bash", "-c"\]\n)|$1RUN printf '\''Acquire::Retries "5";\\nAcquire::http::Timeout "60";\\nAcquire::https::Timeout "60";\\n'\'' > /etc/apt/apt.conf.d/80-retries\n|' "$dockerfile"
  fi
done

if ! grep -q '/usr/sbin/policy-rc.d' protect.Dockerfile; then
  perl -0pi -e 's|(SHELL \["/usr/bin/env", "bash", "-c"\]\n)|$1RUN echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d \\\n    && chmod +x /usr/sbin/policy-rc.d\n|' protect.Dockerfile
fi

for nginx_conf in files/etc/nginx/nginx.conf files/etc/nginx/nginx.conf.disabled; do
  if [ -f "$nginx_conf" ] && ! grep -q 'map_hash_bucket_size 128' "$nginx_conf"; then
    perl -0pi -e 's/http \{/http {\n    map_hash_max_size 128;\n    map_hash_bucket_size 128;/' "$nginx_conf"
  fi
done

mkdir -p files/usr/local/sbin
cat > files/usr/local/sbin/fix-nginx-hash <<'EOINNER'
#!/bin/sh
set -eu

rm -rf /var/run/uos-*.sock

sed -i '/map_hash_/d;/server_names_hash_/d;/types_hash_/d' /etc/nginx/nginx.conf

awk '
  { print }
  $0 ~ /^[[:space:]]*http[[:space:]]*\{/ && !done {
    print "    map_hash_max_size 32768;"
    print "    map_hash_bucket_size 1024;"
    print "    server_names_hash_max_size 32768;"
    print "    server_names_hash_bucket_size 1024;"
    print "    types_hash_max_size 32768;"
    print "    types_hash_bucket_size 1024;"
    done=1
  }
' /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp

mv /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
EOINNER
chmod +x files/usr/local/sbin/fix-nginx-hash

mkdir -p files/etc/systemd/system/nginx.service.d
cat > files/etc/systemd/system/nginx.service.d/hash.conf <<'EOINNER'
[Service]
ExecStartPre=
ExecStartPre=/usr/local/sbin/fix-nginx-hash
EOINNER

mkdir -p files/etc/systemd/system/unifi-core.service.d
cat > files/etc/systemd/system/unifi-core.service.d/override.conf <<'EOINNER'
[Service]
MemoryMax=2G
TimeoutStartSec=300
TimeoutStopSec=300
EOINNER

for attempt in $(seq 1 "$BUILD_RETRIES"); do
  echo "Starting UniFi Protect build attempt $attempt/$BUILD_RETRIES"
  if DOCKER_DEFAULT_PLATFORM=linux/arm64 \
    BUILDKIT_PROGRESS=plain \
    DOCKER_IMAGE="$IMAGE_REPOSITORY" \
    BUILD_EDGE=1 \
    BUILD_TAG_VERSION=1 \
    bash build.sh; then
    exit 0
  fi
  sleep 15
done

exit 1
EOF

chmod +x "$PROTECT_DIR/build-x86-qemu.sh"

cd "$PROTECT_DIR"
UPSTREAM_REPO="$UPSTREAM_REPO" \
UNIFI_PROTECT_IMAGE_REPOSITORY="$UNIFI_PROTECT_IMAGE_REPOSITORY" \
./build-x86-qemu.sh

if [ "$START_PROTECT" = "1" ]; then
  UNIFI_PROTECT_IMAGE="$UNIFI_PROTECT_IMAGE" docker compose \
    -f compose.yml \
    -f compose-x86-qemu.yml \
    up -d
else
  cat <<EOF
Build complete.

To start UniFi Protect:

cd $PROTECT_DIR
UNIFI_PROTECT_IMAGE=$UNIFI_PROTECT_IMAGE docker compose \\
  -f compose.yml \\
  -f compose-x86-qemu.yml \\
  up -d
EOF
fi
