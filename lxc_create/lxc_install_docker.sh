#!/bin/bash
# ===============================================================================
# LXC Docker Installation Script — Derelien Project
# Installs Docker inside an existing LXC container
#
# Usage: bash /root/scripts/lxc_install_docker.sh <ctid>
# ===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\e[32m'
BLUE='\e[34m'
RED='\e[31m'
RESET='\e[0m'

# ===============================================================================
# Functions
# ===============================================================================

install_docker() {
    local ctid="$1"

    echo -e "${BLUE}=== Installing Docker in LXC $ctid ===${RESET}"

    # Check if LXC exists
    if ! pct status "$ctid" &>/dev/null; then
        echo -e "${RED}Error: LXC $ctid does not exist${RESET}"
        return 1
    fi

    # Get OS type
    local os_type
    os_type=$(pct config "$ctid" | grep "ostype:" | awk '{print $2}')
    if [[ -z "$os_type" ]]; then
        os_type="debian"
    fi

    echo "OS Type: $os_type"

    # Install Docker
    echo -e "${BLUE}Installing Docker...${RESET}"
    pct exec "$ctid" -- bash -c "
        set -e

        # Remove old Docker
        apt-get remove -y docker docker-engine docker.io containerd runc || true

        # Install prerequisites
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release

        # Add Docker GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$os_type/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add Docker repository
        echo \\
            \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$os_type \\
            \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | \\
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Start Docker
        systemctl start docker
        systemctl enable docker

        echo 'Docker installed successfully'
    "

    # Add user to docker group (extract from LXC config, fallback to 'user')
    local user
    user=$(pct config "$ctid" 2>/dev/null | grep -A1 "ssh-public-keys" | tail -1 | awk -F/ '{print $NF}' || echo "user")
    pct exec "$ctid" -- bash -c "usermod -aG docker $user 2>/dev/null || true"

    # Verify Docker is running
    echo -e "${BLUE}Verifying Docker...${RESET}"
    local docker_version
    docker_version=$(pct exec "$ctid" -- docker --version 2>&1)
    pct exec "$ctid" -- systemctl is-active --quiet docker || {
        echo -e "${RED}Error: Docker daemon is not running!${RESET}"
        return 1
    }

    echo ""
    echo -e "${GREEN}=== Docker Installed Successfully ===${RESET}"
    echo "CTID: $ctid"
    echo "$docker_version"
    echo ""
    echo "Next steps:"
    echo "  - Install Portainer: bash $SCRIPT_DIR/lxc_install_portainer.sh $ctid"
    echo "  - Or run: pct exec $ctid -- docker run hello-world"

    return 0
}

# ===============================================================================
# Main
# ===============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <ctid>"
        echo ""
        echo "Arguments:"
        echo "  ctid - Container ID of existing LXC"
        echo ""
        echo "Examples:"
        echo "  $0 100"
        echo "  $0 101"
        exit 1
    fi
    
    install_docker "$1"
fi
