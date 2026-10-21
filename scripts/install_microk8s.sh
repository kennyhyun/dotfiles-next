#!/bin/sh

# install microk8s
# ubuntu/debian
# x64/arm64

if [ -z "$(snap microk8s --version 2>/dev/null)" ]; then
  sudo apt install -y snapd
  sudo snap install snapd
  sudo snap install microk8s --classic
  
  # Add user to microk8s group
  sudo usermod -aG microk8s $USER
  echo "Added $USER to microk8s group. Please log out and back in for changes to take effect."
fi

