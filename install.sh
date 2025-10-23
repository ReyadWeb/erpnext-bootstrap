#!/usr/bin/env bash
set -Eeuo pipefail

# --- prerequisites -----------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1; }
if ! need curl; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y curl
fi
if ! need unzip; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y unzip
fi

# --- config ------------------------------------------------------------------
REPO_OWNER="ReyadWeb"
REPO_NAME="erpnext-manager"
REF="main"

# Try to obtain a token automatically for the private repo
GHTOKEN="${GHTOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-$(command -v gh >/dev/null 2>&1 && gh auth token || true)}}}"

ZIP_URL_PUBLIC="https://github.com/${REPO_OWNER}/${REPO_NAME}/zipball/${REF}"
ZIP_URL_PRIVATE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/zipball/${REF}"

TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

download_zip() {
  # Try public first (works if repo becomes public later)
  if curl -fsSL -o "$TMP/repo.zip" "$ZIP_URL_PUBLIC"; then
    return 0
  fi
  # Fall back to private API (requires token)
  if [[ -n "$GHTOKEN" ]]; then
    curl -fsSL -H "Authorization: Bearer $GHTOKEN" -L "$ZIP_URL_PRIVATE" -o "$TMP/repo.zip"
    return 0
  fi
  echo "This installer needs access to ${REPO_OWNER}/${REPO_NAME} (private)."
  echo "Please set a token in one of: GHTOKEN, GH_TOKEN, GITHUB_TOKEN, or run 'gh auth login'."
  echo "Token scope: fine-grained PAT → Repository contents: Read"
  exit 2
}

echo "Fetching ${REPO_OWNER}/${REPO_NAME}@${REF} ..."
download_zip

# --- install to /opt/erpnext-manager ----------------------------------------
sudo rm -rf /opt/erpnext-manager
sudo unzip -q "$TMP/repo.zip" -d /opt

# Move versioned folder to stable path
TARGET="$(bash -lc 'shopt -s nullglob; set -- /opt/*-'"${REPO_NAME}"'-* /opt/*_'"${REPO_NAME}"'-*; echo "$1"')"
if [[ -z "$TARGET" ]]; then
  echo "Failed to locate extracted folder; aborting."
  exit 1
fi
sudo mv "$TARGET" /opt/erpnext-manager

# Normalize line endings & permissions
sudo find /opt/erpnext-manager -type f -name "*.sh" -exec sed -i "s/\r$//" {} \; -exec chmod +x {} \;

# --- launch ------------------------------------------------------------------
cd /opt/erpnext-manager
exec sudo ./erpnext-manager.sh
