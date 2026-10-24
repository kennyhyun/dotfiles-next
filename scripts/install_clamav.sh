#!/bin/sh

# install clamav (on-demand malware scanner)
# ubuntu/debian, x64/arm64 ; macOS via brew
#
# Detects BOTH Windows and Linux malware signatures in files -- useful for
# scanning external disks that may be moved between OSes. Installs the
# on-demand scanner (clamscan) + the signature-DB updater (freshclam) only.
# We deliberately do NOT enable the resident clamav-daemon (clamd): it keeps
# the whole signature set (~hundreds of MB) in RAM and is overkill for a box
# that scans on demand. Run a scan with:
#     clamscan -r --infected /mnt/disk1
# Requires sudo. Idempotent: skips the install if clamscan already exists.

set -e

if command -v clamscan >/dev/null 2>&1; then
  echo "clamav already installed: $(clamscan --version 2>/dev/null | head -1)"
else
  OS=$(uname -s)
  if [ "$OS" = "Darwin" ]; then
    echo "Installing clamav (brew)"
    brew install clamav
  else
    echo "Installing clamav (clamscan + freshclam)"
    sudo apt-get update
    # clamav      = clamscan CLI ; clamav-freshclam = signature DB updater.
    # clamav-daemon is intentionally omitted (resident scanner, heavy in RAM).
    sudo apt-get install -y clamav clamav-freshclam
  fi
fi

# Refresh the signature database once so the first scan is not empty.
# freshclam locks the DB against its own systemd timer; stop it briefly if the
# timer owns the lock, then let it resume.
echo "Updating ClamAV signature database (freshclam)"
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl stop clamav-freshclam 2>/dev/null || true
fi
sudo freshclam 2>/dev/null \
  || echo "freshclam update reported an issue (DB may update later via its timer)."
if command -v systemctl >/dev/null 2>&1; then
  # Leave the periodic updater running so signatures stay current.
  sudo systemctl start clamav-freshclam 2>/dev/null || true
fi

echo "clamav installed. Scan a disk with:  clamscan -r --infected /mnt/disk1"
