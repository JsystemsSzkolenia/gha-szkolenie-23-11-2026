#!/usr/bin/env bash
set -euo pipefail
umask 077
trap 'rm -f -- "$0"' EXIT

if command -v cloud-init >/dev/null 2>&1; then
  set +e
  timeout 480 cloud-init status --wait
  cloud_init_status=$?
  set -e
  case "$cloud_init_status" in
    0) ;;
    2) echo '::warning::Cloud-init finished with recoverable warnings; checking its final status.' ;;
    *) echo "Cloud-init did not finish successfully (exit $cloud_init_status)." >&2; exit "$cloud_init_status" ;;
  esac
  cloud_init_details="$(cloud-init status --long 2>&1 || true)"
  if ! printf '%s\n' "$cloud_init_details" | grep -Eq '^[[:space:]]*status:[[:space:]]+done([[:space:]]|$)'; then
    printf '%s\n' "$cloud_init_details" >&2
    echo 'Cloud-init must finish before installing application services.' >&2
    exit 1
  fi
fi

export DEBIAN_FRONTEND=noninteractive
timeout 300 apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=180 update
timeout 600 apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=180 install -y --no-install-recommends \
  docker.io nginx ca-certificates curl

command -v docker >/dev/null
command -v nginx >/dev/null
systemctl enable --now docker
systemctl is-active --quiet docker
docker info >/dev/null

# Manage only the packaged default and this exercise's own virtual host.
rm -f -- /etc/nginx/sites-enabled/default
if [ ! -e /etc/nginx/sites-available/cw03-pogoda ]; then
  cat > /etc/nginx/sites-available/cw03-pogoda <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    return 503;
}
NGINX
  chmod 644 /etc/nginx/sites-available/cw03-pogoda
fi
ln -sfn /etc/nginx/sites-available/cw03-pogoda /etc/nginx/sites-enabled/cw03-pogoda
nginx -t
systemctl enable --now nginx
systemctl reload nginx
echo 'Docker and Nginx are ready; application credentials were not needed for bootstrap.'
