#!/bin/bash
kubespray_data_dir=${kubespray_data_dir}
expose_services_dir=${expose_services_dir}

echo "=== Starting Kubespray Setup ==="

# Wait for cloud-init to complete
echo "Waiting for cloud-init to complete..."
cloud-init status --wait > /dev/null 2>&1 || true
sleep 10

# Disable interactive prompts
echo "Disabling interactive prompts..."
sudo sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf 2>/dev/null || true
sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf 2>/dev/null || true

# Wait for apt locks using fuser (usually pre-installed)
echo "Waiting for apt locks to be released..."
wait_time=0
max_wait=600
while sudo fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock 2>/dev/null; do
    if [ "$wait_time" -ge "$max_wait" ]; then
        echo "Timeout waiting for apt lock"
        exit 1
    fi
    echo "Apt is locked, waiting..."
    sleep 10
    wait_time=$((wait_time + 10))
done
echo "Apt locks released."

# Install required tools
echo "Installing required tools (curl)..."
sudo apt-get update -o DPkg::Lock::Timeout=600
sudo apt-get install -y -o DPkg::Lock::Timeout=600 curl

# Verify if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."

    # Download Docker installation script
    if ! curl -fsSL https://get.docker.com -o get-docker.sh; then
        echo "Error downloading Docker installation script. Exiting." >&2
        exit 1
    fi

    # Check and add DPkg::Lock::Timeout=600 to apt-get install if not already present
    if ! grep -q 'apt-get install.*DPkg::Lock::Timeout=600' get-docker.sh; then
        sed -i 's/apt-get install/apt-get install -o DPkg::Lock::Timeout=600/g' get-docker.sh
    fi

    # Check and add DPkg::Lock::Timeout=600 to apt-get update if not already present
    if ! grep -q 'apt-get update.*DPkg::Lock::Timeout=600' get-docker.sh; then
        sed -i 's/apt-get update/apt-get update -o DPkg::Lock::Timeout=600/g' get-docker.sh
    fi

    # Install Docker
    if ! sudo sh get-docker.sh; then
        echo "Error installing Docker. Exiting." >&2
        exit 1
    fi

    # Clean up by removing the Docker installation script
    rm -f get-docker.sh

    # Add current user to the `docker` group
    sudo usermod -aG docker $USER

    echo "Docker installed successfully."
else
    echo "Docker is already installed."
fi

mkdir -p "$kubespray_data_dir"
# `$$` is a terraform templatefile escape, rendered to `$` at deploy time.
# shellcheck disable=SC1083
rm -rf "$${kubespray_data_dir:?}"/*
chmod 700 "$kubespray_data_dir"

mkdir -p "$expose_services_dir"
rm -rf "$${expose_services_dir:?}"/*
chmod 700 "$expose_services_dir"

echo "=== Kubespray Setup Script Complete ==="
