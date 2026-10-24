#!/bin/sh

# install trivy (vulnerability + misconfig + secret scanner)
# ubuntu/debian, x64/arm64 ; macOS via brew
#
# NOTE: Trivy is NOT a malware scanner. It finds KNOWN vulnerabilities (CVEs)
# in container images, filesystems and git repos, plus IaC misconfigurations
# and committed secrets. Pair it with clamav (install_clamav.sh) when you also
# want file-level malware detection. Typical uses:
#     trivy fs .                 # scan a project dir for vulns/secrets
#     trivy image <name:tag>     # scan a container image
# Installs from the official aquasecurity apt repo so `apt upgrade` keeps it
# current. Requires sudo. Idempotent: skips if trivy already exists.

set -e

if command -v trivy >/dev/null 2>&1; then
  echo "trivy already installed: $(trivy --version 2>/dev/null | head -1)"
  exit 0
fi

OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
  echo "Installing trivy (brew)"
  brew install trivy
  exit 0
fi

echo "Installing trivy (official aquasecurity apt repo)"
sudo apt-get update
sudo apt-get install -y wget gnupg ca-certificates

# Add the signing key and apt source (keyring-based, matches install_docker.sh).
sudo install -m 0755 -d /etc/apt/keyrings
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/trivy.gpg >/dev/null
sudo chmod a+r /etc/apt/keyrings/trivy.gpg

# Trivy's repo is keyed by Debian/Ubuntu release codename. Fall back to a
# widely-available codename when the exact one is not published yet.
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb ${CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null

sudo apt-get update
sudo apt-get install -y trivy

echo "trivy installed: $(trivy --version 2>/dev/null | head -1)"
echo "Scan a project with:  trivy fs ."
