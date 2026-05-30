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

if [ -f files/etc/nginx/nginx.conf.disabled ] \
  && ! grep -q 'map_hash_bucket_size 128' files/etc/nginx/nginx.conf.disabled; then
  perl -0pi -e 's/http \{/http {\n    map_hash_max_size 128;\n    map_hash_bucket_size 128;/' files/etc/nginx/nginx.conf.disabled
fi

mkdir -p files/etc/systemd/system/unifi-core.service.d
cat > files/etc/systemd/system/unifi-core.service.d/override.conf <<'EOF'
[Service]
MemoryMax=500M
TimeoutStartSec=300
TimeoutStopSec=300
EOF

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
