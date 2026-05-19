#!/bin/bash
# ===============================================================================
# LXC Portainer Installation Script — Derelien Project
# Installs Portainer CE inside an existing LXC with Docker
#
# Usage: bash /root/scripts/lxc_install_portainer.sh <ctid>
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

# Portainer version (pin for reproducibility, update as needed)
PORTAINER_VERSION="${PORTAINER_VERSION:-latest}"

install_portainer() {
    local ctid="$1"
    local user="user"

    echo -e "${BLUE}=== Installing Portainer in LXC $ctid ===${RESET}"

    # Check if LXC exists
    if ! pct status "$ctid" &>/dev/null; then
        echo -e "${RED}Error: LXC $ctid does not exist${RESET}"
        return 1
    fi

    # Check if Docker is installed
    if ! pct exec "$ctid" -- docker --version &>/dev/null; then
        echo -e "${RED}Error: Docker not found in LXC $ctid.${RESET}" >&2
        echo -e "${RED}Install Docker first: bash $SCRIPT_DIR/lxc_install_docker.sh $ctid${RESET}" >&2
        return 1
    fi

    # Get username from LXC config
    user=$(pct config "$ctid" 2>/dev/null | grep -A1 "ssh-public-keys" | tail -1 | awk -F/ '{print $NF}' || echo "user")

    echo "Installing Portainer for user: $user"

    # Install Portainer
    echo -e "${BLUE}Installing Portainer CE (version: $PORTAINER_VERSION)...${RESET}"
    pct exec "$ctid" -- bash -c "
        set -e

        # Create directory
        mkdir -p /home/$user/docker/portainer
        chown $user:$user /home/$user/docker /home/$user/docker/portainer

        # Run Portainer (pull always to ensure latest for the chosen tag)
        docker run -d \\
            --pull always \\
            -p 9000:9000 \\
            -p 9443:9443 \\
            --name=portainer \\
            --restart=always \\
            -v /var/run/docker.sock:/var/run/docker.sock \\
            -v /home/$user/docker/portainer:/data \\
            portainer/portainer-ce:$PORTAINER_VERSION
    "

    # Verify Portainer is running
    echo -e "${BLUE}Verifying Portainer...${RESET}"
    sleep 3
    local container_status
    container_status=$(pct exec "$ctid" -- docker inspect --format='{{.State.Status}}' portainer 2>&1) || {
        echo -e "${RED}Error: Portainer container failed to start!${RESET}"
        pct exec "$ctid" -- docker logs portainer 2>&1 || true
        return 1
    }
    if [[ "$container_status" != "running" ]]; then
        echo -e "${RED}Error: Portainer is not running (status: $container_status)${RESET}"
        pct exec "$ctid" -- docker logs portainer 2>&1 || true
        return 1
    fi
    echo -e "${GREEN}Portainer status: $container_status${RESET}"

    # Get IP
    local ip
    ip=$(pct exec "$ctid" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "<IP>")

    echo ""
    echo -e "${GREEN}=== Portainer Installed Successfully ===${RESET}"
    echo "CTID: $ctid"
    echo "Portainer version: $PORTAINER_VERSION"
    echo "Access Portainer at:"
    echo "  HTTP:  http://$ip:9000"
    echo "  HTTPS: https://$ip:9443"
    echo ""
    echo "Set administrator password on first login!"

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
        echo "  ctid - Container ID of existing LXC with Docker"
        echo ""
        echo "Examples:"
        echo "  $0 100"
        echo "  $0 101"
        exit 1
    fi
    
    install_portainer "$1"
fi
