#!/bin/sh

# install docker
# ubuntu/debian
# x64/arm64


set -e


if [ -z "$(docker version 2>/dev/null)" ]; then

  # remove conflicting packages
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg -y || true; done
  
  # Add Docker's official GPG key:
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  
  OS=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  
  # Use correct GPG key URL based on OS
  if [ "$OS" = "ubuntu" ]; then
    GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
  else
    GPG_URL="https://download.docker.com/linux/debian/gpg"
  fi
  
  sudo curl -fsSL "$GPG_URL" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  
  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS} \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  
  # Install docker
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Add user to docker group
  sudo usermod -aG docker $USER
  echo "Added $USER to docker group. Please log out and back in for changes to take effect."
fi
