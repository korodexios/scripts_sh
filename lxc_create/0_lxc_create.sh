#!/bin/bash

# ===============================================================================
# Proxmox LXC Creation Menu — Derelien Project
# User-friendly menu that CALLS modular scripts (does NOT create LXC itself)
# 
# Location: /root/scripts/00_cr_lxc_docker_portainer.sh
# Usage: bash /root/scripts/00_cr_lxc_docker_portainer.sh
# ===============================================================================

# Don't exit on error - we handle errors ourselves
# set -e  ← REMOVED
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

separator() { echo -e "${CYAN}-----------------------------------------------------${RESET}"; }

# --- Defaults ---
DEFAULT_ROOTFS_STORAGE="local-lvm"
DEFAULT_ROOTFS_SIZE=4
DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_USER="kleo"
DEFAULT_PASS="123456"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_UNPRIVILEGED=1
DEFAULT_SSH_KEY="$SCRIPT_DIR/id_ed25519.pub"

# --- Validation Functions ---
validate_ctid() {
    local ctid="$1"
    if [[ ! "$ctid" =~ ^[0-9]+$ ]]; then
        echo "error"
        return 1
    fi
    if pct status "$ctid" &>/dev/null; then
        echo "exists"
        return 1
    fi
    echo "ok"
}

validate_hostname() {
    local hostname=$1
    if [[ -z "$hostname" ]]; then echo "empty"; return 1; fi
    if [[ "$hostname" =~ \  ]]; then echo "spaces"; return 1; fi
    if [[ "$hostname" =~ _ ]]; then echo "underscore"; return 1; fi
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$ ]]; then echo "invalid"; return 1; fi
    echo "ok"
}

# ===============================================================================
# Main Menu
# ===============================================================================

echo -e "${CYAN}${BOLD}=== Proxmox LXC Creation Menu ===${RESET}"
separator

echo -e "${YELLOW}What do you want to create?${RESET}"
echo ""
echo -e "  ${GREEN}1)${RESET} Basic LXC container only"
echo -e "  ${GREEN}2)${RESET} LXC + Docker"
echo -e "  ${GREEN}3)${RESET} LXC + Docker + Portainer"
echo -e "  ${GREEN}4)${RESET} Add Docker to existing LXC"
echo -e "  ${GREEN}5)${RESET} Add Portainer to existing LXC"
echo ""
separator

# Get choice
read -p "$(echo -e "${MAGENTA}Choice [1-5] (default: 1): ${RESET}")" CHOICE
[[ -z "$CHOICE" ]] && CHOICE=1 && echo -e "${GREEN}Using default: Basic LXC${RESET}"

# ===============================================================================
# Get Parameters (for new LXC creation)
# ===============================================================================

if [[ "$CHOICE" == "1" || "$CHOICE" == "2" || "$CHOICE" == "3" ]]; then
    echo ""
    echo -e "${BLUE}=== New LXC Configuration ===${RESET}"
    separator
    
    # CTID with validation loop
    while true; do
        read -p "$(echo -e "${MAGENTA}Enter Container ID (e.g., 100): ${RESET}")" CTID
        result=$(validate_ctid "$CTID")
        if [[ "$result" == "error" ]]; then
            echo -e "${RED}✗ CTID must be a number.${RESET}"
            continue
        elif [[ "$result" == "exists" ]]; then
            echo -e "${RED}✗ CTID $CTID already exists! Choose different ID.${RESET}"
            continue
        fi
        echo -e "${GREEN}✓ CTID $CTID is available${RESET}"
        break
    done
    
    # Hostname with validation loop
    while true; do
        read -p "$(echo -e "${MAGENTA}Enter hostname (e.g., docker-lxc): ${RESET}")" HOSTNAME
        result=$(validate_hostname "$HOSTNAME")
        case "$result" in
            "empty") echo -e "${RED}✗ Hostname cannot be empty.${RESET}"; continue ;;
            "spaces") echo -e "${RED}✗ Hostname cannot contain spaces.${RESET}"; continue ;;
            "underscore") echo -e "${RED}✗ Hostname cannot contain underscores. Use hyphens (docker-lxc).${RESET}"; continue ;;
            "invalid") echo -e "${RED}✗ Hostname must start/end with alphanumeric, can contain hyphens.${RESET}"; continue ;;
        esac
        echo -e "${GREEN}✓ Hostname '$HOSTNAME' is valid${RESET}"
        break
    done
    
    # Template list
    echo ""
    echo -e "${BLUE}Available templates:${RESET}"
    TEMPLATE_STORAGE="local"
    AVAILABLE_TEMPLATES=()
    i=1
    while IFS= read -r line; do
        full_template_id=$(echo "$line" | tr -d '\r' | awk '{print $1}')
        if [[ "$full_template_id" == *".tar.zst"* && -n "$full_template_id" ]]; then
            template_name=$(echo "$full_template_id" | sed -e "s/^$TEMPLATE_STORAGE:vztmpl\///" -e 's/\.tar\.zst$//')
            if [[ -n "$template_name" ]]; then
                AVAILABLE_TEMPLATES+=("$template_name")
                echo -e "${YELLOW}$i) ${RESET}${GREEN}$template_name${RESET}"
                ((i++))
            fi
        fi
    done < <(pveam list "$TEMPLATE_STORAGE")
    
    if [ ${#AVAILABLE_TEMPLATES[@]} -eq 0 ]; then
        echo -e "${RED}✗ No templates found!${RESET}"
        exit 1
    fi
    separator
    
    # Template choice with loop
    while true; do
        read -p "$(echo -e "${MAGENTA}Select template [1-${#AVAILABLE_TEMPLATES[@]}]: ${RESET}")" TEMPLATE_CHOICE
        if ! [[ "$TEMPLATE_CHOICE" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}✗ Invalid choice. Enter a number.${RESET}"
            continue
        fi
        if [ "$TEMPLATE_CHOICE" -lt 1 ] || [ "$TEMPLATE_CHOICE" -gt ${#AVAILABLE_TEMPLATES[@]} ]; then
            echo -e "${RED}✗ Choice out of range. Select 1-${#AVAILABLE_TEMPLATES[@]}.${RESET}"
            continue
        fi
        break
    done
    TEMPLATE="${AVAILABLE_TEMPLATES[$((TEMPLATE_CHOICE-1))]}"
    
    # Other parameters
    read -p "$(echo -e "${MAGENTA}RootFS storage (default: ${BOLD}$DEFAULT_ROOTFS_STORAGE${RESET}${MAGENTA}): ${RESET}")" ROOTFS_STORAGE
    ROOTFS_STORAGE=${ROOTFS_STORAGE:-$DEFAULT_ROOTFS_STORAGE}
    
    read -p "$(echo -e "${MAGENTA}RootFS size in GB (default: ${BOLD}$DEFAULT_ROOTFS_SIZE${RESET}${MAGENTA}): ${RESET}")" ROOTFS_SIZE_INPUT
    ROOTFS_SIZE=${ROOTFS_SIZE_INPUT:-$DEFAULT_ROOTFS_SIZE}
    
    read -p "$(echo -e "${MAGENTA}CPU cores (default: ${BOLD}$DEFAULT_CORES${RESET}${MAGENTA}): ${RESET}")" CORES_INPUT
    CORES=${CORES_INPUT:-$DEFAULT_CORES}
    
    read -p "$(echo -e "${MAGENTA}Memory in MB (default: ${BOLD}$DEFAULT_MEMORY${RESET}${MAGENTA}): ${RESET}")" MEMORY_INPUT
    MEMORY=${MEMORY_INPUT:-$DEFAULT_MEMORY}
    
    read -p "$(echo -e "${MAGENTA}Network bridge (default: ${BOLD}$DEFAULT_BRIDGE${RESET}${MAGENTA}): ${RESET}")" BRIDGE_INPUT
    BRIDGE=${BRIDGE_INPUT:-$DEFAULT_BRIDGE}
    
    read -p "$(echo -e "${MAGENTA}Username (default: ${BOLD}$DEFAULT_USER${RESET}${MAGENTA}): ${RESET}")" USER_INPUT
    USER=${USER_INPUT:-$DEFAULT_USER}
    
    read -p "$(echo -e "${MAGENTA}Password (default: ${BOLD}$DEFAULT_PASS${RESET}${MAGENTA}): ${RESET}")" PASS_INPUT
    PASS=${PASS_INPUT:-$DEFAULT_PASS}
    
    # Unprivileged
    read -p "$(echo -e "${MAGENTA}Create Unprivileged container? [Y/n] (default: Y): ${RESET}")" UNPRIV_REPLY
    UNPRIV_REPLY=$(echo "$UNPRIV_REPLY" | tr '[:upper:]' '[:lower:]')
    [[ -z "$UNPRIV_REPLY" || "$UNPRIV_REPLY" == "y" ]] && UNPRIV=1 || UNPRIV=0
    [[ "$UNPRIV" == "1" ]] && echo -e "${GREEN}✓ Status: UNPRIVILEGED${RESET}" || echo -e "${YELLOW}✓ Status: PRIVILEGED${RESET}"
    separator
    
    # SSH Key
    if [[ -f "$DEFAULT_SSH_KEY" ]]; then
        echo -e "${BLUE}SSH Key found: $DEFAULT_SSH_KEY${RESET}"
        read -p "$(echo -e "${MAGENTA}Use this SSH key? [Y/n] (default: Y): ${RESET}")" SSH_REPLY
        SSH_REPLY=$(echo "$SSH_REPLY" | tr '[:upper:]' '[:lower:]')
        if [[ -z "$SSH_REPLY" || "$SSH_REPLY" == "y" ]]; then
            SSH_KEY="$DEFAULT_SSH_KEY"
            echo -e "${GREEN}✓ Will use SSH key${RESET}"
        fi
    fi
    
    separator
    echo -e "${BLUE}=== Summary ===${RESET}"
    echo -e "CTID: ${BOLD}$CTID${RESET}"
    echo -e "Hostname: ${BOLD}$HOSTNAME${RESET}"
    echo -e "Template: ${BOLD}$TEMPLATE${RESET}"
    echo -e "Storage: ${BOLD}$ROOTFS_STORAGE${RESET} ($ROOTFS_SIZE GB)"
    echo -e "Cores: ${BOLD}$CORES${RESET}, Memory: ${BOLD}$MEMORY${RESET} MB"
    echo -e "User: ${BOLD}$USER${RESET}"
    echo -e "SSH Key: ${BOLD}${SSH_KEY:-None}${RESET}"
    separator
    echo ""
    
    # ===============================================================================
    # CALL Modular Scripts (NOT combining them!)
    # ===============================================================================
    
    # Step 1: Create base LXC
    echo -e "${BLUE}→ Calling: lxc_create_base.sh${RESET}"
    echo ""
    
    # Export variables for modular script
    export LXC_ROOTFS_STORAGE="$ROOTFS_STORAGE"
    export LXC_ROOTFS_SIZE="$ROOTFS_SIZE"
    export LXC_CORES="$CORES"
    export LXC_MEMORY="$MEMORY"
    export LXC_USER="$USER"
    export LXC_PASS="$PASS"
    export LXC_SSH_KEY="$SSH_KEY"
    export LXC_BRIDGE="$BRIDGE"
    export LXC_UNPRIVILEGED="$UNPRIV"
    
    # Call modular script
    if ! bash "$SCRIPT_DIR/lxc_create_base.sh" "$CTID" "$HOSTNAME" "$TEMPLATE"; then
        echo -e "${RED}✗ Failed to create base LXC! Aborting.${RESET}"
        exit 1
    fi

    # Step 2: Install Docker if requested
    if [[ "$CHOICE" == "2" || "$CHOICE" == "3" ]]; then
        echo ""
        echo -e "${BLUE}→ Calling: lxc_install_docker.sh${RESET}"
        if ! bash "$SCRIPT_DIR/lxc_install_docker.sh" "$CTID"; then
            echo -e "${RED}✗ Failed to install Docker! Aborting.${RESET}"
            exit 1
        fi
    fi

    # Step 3: Install Portainer if requested
    if [[ "$CHOICE" == "3" ]]; then
        echo ""
        echo -e "${BLUE}→ Calling: lxc_install_portainer.sh${RESET}"
        if ! bash "$SCRIPT_DIR/lxc_install_portainer.sh" "$CTID"; then
            echo -e "${RED}✗ Failed to install Portainer! Aborting.${RESET}"
            exit 1
        fi
    fi
    
    # ===============================================================================
    # Final Summary
    # ===============================================================================
    
    echo ""
    separator
    echo -e "${GREEN}${BOLD}=== Complete ===${RESET}"
    separator
    
    # Get IP (retry up to 10 times with 3s delays for slow DHCP)
    echo -e "${BLUE}Getting IP address...${RESET}"
    CT_IP=""
    for i in {1..10}; do
        CT_IP=$(pct exec "$CTID" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
        [[ -n "$CT_IP" ]] && break
        sleep 3
    done
    
    echo -e "${GREEN}✓ Container $CTID created${RESET}"
    echo -e "${GREEN}✓ Hostname: $HOSTNAME${RESET}"
    [[ -n "$CT_IP" ]] && echo -e "${GREEN}✓ IP: ${CYAN}$CT_IP${RESET}" || echo -e "${YELLOW}⚠ IP not assigned (check DHCP)${RESET}"
    
    if [[ "$CHOICE" == "2" || "$CHOICE" == "3" ]]; then
        echo -e "${GREEN}✓ Docker installed${RESET}"
    fi
    
    if [[ "$CHOICE" == "3" ]]; then
        echo -e "${GREEN}✓ Portainer installed${RESET}"
        [[ -n "$CT_IP" ]] && echo -e "${GREEN}✓ Access: ${YELLOW}https://$CT_IP:9443${RESET}"
    fi
    
    echo ""
    echo -e "${RED}${BOLD}⚠️ SECURITY WARNING:${RESET}"
    echo -e "  Change passwords: ${YELLOW}pct enter $CTID${RESET} → ${YELLOW}passwd root${RESET} & ${YELLOW}passwd $USER${RESET}"
    separator

elif [[ "$CHOICE" == "4" ]]; then
    # Add Docker to existing
    read -p "$(echo -e "${MAGENTA}Enter CTID: ${RESET}")" CTID
    if ! pct status "$CTID" &>/dev/null; then
        echo -e "${RED}✗ LXC $CTID does not exist${RESET}"
        exit 1
    fi
    bash "$SCRIPT_DIR/lxc_install_docker.sh" "$CTID"

elif [[ "$CHOICE" == "5" ]]; then
    # Add Portainer to existing
    read -p "$(echo -e "${MAGENTA}Enter CTID: ${RESET}")" CTID
    if ! pct status "$CTID" &>/dev/null; then
        echo -e "${RED}✗ LXC $CTID does not exist${RESET}"
        exit 1
    fi
    bash "$SCRIPT_DIR/lxc_install_portainer.sh" "$CTID"

else
    echo -e "${RED}✗ Invalid choice.${RESET}"
    exit 1
fi
