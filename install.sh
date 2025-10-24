#!/usr/bin/env bash
set -Eeuo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if ! need curl; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y curl
fi

if ! need unzip; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y unzip
fi

if ! need awk; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y gawk || apt-get install -y awk || true
fi

REPO_OWNER="ReyadWeb"
REPO_NAME="erpnext-manager"
REF="main"

ZIP_URL_PUBLIC="https://github.com/${REPO_OWNER}/${REPO_NAME}/zipball/${REF}"
ZIP_URL_PRIVATE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/zipball/${REF}"

GHTOKEN="${GHTOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-$(command -v gh >/dev/null 2>&1 && gh auth token || true)}}}"

TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

download_zip() {
  if curl -fsSL -o "$TMP/repo.zip" "$ZIP_URL_PUBLIC"; then
    echo "Downloaded public ZIP."
    return 0
  fi

  if [[ -z "${GHTOKEN:-}" ]] then
    echo "Private repo detected: ${REPO_OWNER}/${REPO_NAME}"
    read -s -p "GitHub token (fine-grained; Repository contents: Read): " GHTOKEN
    echo
  fi

  if ! curl -fsSL -H "Authorization: Bearer ${GHTOKEN}" -L "$ZIP_URL_PRIVATE" -o "$TMP/repo.zip"; then
    echo "ERROR: Failed to fetch private ZIP via API. Check token scopes and repo access."
    exit 3
  fi
  echo "Downloaded private ZIP."
}

echo "Fetching ${REPO_OWNER}/${REPO_NAME}@${REF} ..."
download_zip

sudo rm -rf /opt/erpnext-manager
sudo unzip -q "$TMP/repo.zip" -d /opt

TARGET="$(bash -lc 'shopt -s nullglob; set -- /opt/*-'"${REPO_NAME}"'-* /opt/*_'"${REPO_NAME}"'-*; echo "$1"')"
if [[ -z "$TARGET" ]]; then
  echo "Failed to locate extracted folder; aborting."
  exit 1
fi
sudo mv "$TARGET" /opt/erpnext-manager

sudo find /opt/erpnext-manager -type f -name "*.sh" -exec sed -i "s/\r$//" {} \; -exec chmod +x {} \;

cd /opt/erpnext-manager
exec sudo /opt/erpnext-manager/erpnext-manager.sh </dev/tty
