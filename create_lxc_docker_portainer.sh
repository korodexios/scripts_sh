#!/bin/bash

# ===============================================================================
# Proxmox LXC Super Script
# This script creates a menu to easily create different types of LXC containers
# with pre-installed applications like Docker and Portainer.
# It combines robust pre-flight checks with a clean, user-friendly menu.
#
# Author: Gemini & User
# Date: 2024-08-02
# ===============================================================================

# --- Strict error handling: exit on error ---
set -e
# Get script directory for default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Exit if any command fails.

# --- Color definitions ---
# Predefined color codes for improved readability of the output.
RED='\e[31m'
# Red text color
GREEN='\e[32m'
# Green text color
YELLOW='\e[33m'
# Yellow text color
BLUE='\e[34m'
# Blue text color
MAGENTA='\e[35m'
# Magenta text color
CYAN='\e[36m'
# Cyan text color
BOLD='\e[1m'
# Bold font
RESET='\e[0m'
# Reset formatting

# --- Default configuration inputs ---
# These are the default values used if the user just presses Enter.
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_ROOTFS_STORAGE="local-lvm"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_USER="user"
DEFAULT_PASS="123456" # WARNING: Change this immediately after creation.
DEFAULT_ROOTFS_SIZE=2 # in GB
DEFAULT_CORES=2
DEFAULT_MEMORY=2048 # in MB
DEFAULT_SWAP=0 # in MB
DEFAULT_UNPRIVILEGED=1 # 1 = Unprivileged, 0 = Privileged

# --- Global variables for script logic ---
CTID=""
HOSTNAME=""
SELECTED_TEMPLATE_NAME=""
OS_TYPE=""
ROOTFS_STORAGE=""
BRIDGE=""
NEW_USER=""
PASSWORD=""
SSH_KEY_PATH=""

# ===============================================================================
# --- Helper Functions ---
# ===============================================================================

# Function to print a separator line for better visual organization
separator() {
    echo -e "${CYAN}-----------------------------------------------------${RESET}"
}

# Function to handle errors
error_handler() {
    local exit_code=$?
    local last_command=$BASH_COMMAND
    if [ "$exit_code" -ne "0" ]; then
        echo -e "\n${RED}${BOLD}--- FATAL ERROR ---${RESET}"
        echo -e "${RED}An error occurred at line ${BOLD}$1${RESET}${RED} while executing command:${RESET}"
        echo -e "${RED}${BOLD}$last_command${RESET}"
        echo -e "${RED}Script terminating.${RESET}"
        exit 1
    fi
}
# Set up a trap to call the error_handler function on any command failure
trap 'error_handler $LINENO' ERR

# Function for pre-flight checks to ensure the environment is suitable
pre_flight_checks() {
    echo -e "${BLUE}${BOLD}--- Running Pre-flight Checks ---${RESET}"
    separator

    # Check if the script is run as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run as root. Exiting.${RESET}"
        exit 1
    fi

    # Check for Proxmox VE version
    if ! pveversion | grep -E "pve-manager/[89]"; then
        echo -e "${YELLOW}Warning: This script is primarily tested on Proxmox VE 8.x and 9.x.${RESET}"
        echo -e "${YELLOW}Proceed with caution on other versions.${RESET}"
        sleep 2
    fi

    # Check if Proxmox is running on amd64 architecture
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        echo -e "${RED}This script is intended for amd64 architecture. Exiting.${RESET}"
        exit 1
    fi

    echo -e "${GREEN}${BOLD}All pre-flight checks passed.${RESET}"
    separator
}

# Function to get user input for general LXC settings
get_user_input() {
    echo -e "${CYAN}${BOLD}--- Proxmox LXC Super Script Menu ---${RESET}"
    echo -e "${YELLOW}This script helps you create and configure LXC containers.${RESET}"
    separator

    # Get Container ID (CTID) from user
    read -p "$(echo -e "${MAGENTA}Enter Container ID (e.g., 101): ${RESET}")" CTID
    if [[ ! "$CTID" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Container ID must be a number. Exiting.${RESET}"
        exit 1
    fi

    # Get Hostname from user
    read -p "$(echo -e "${MAGENTA}Enter hostname for the container (e.g., mycontainer): ${RESET}")" HOSTNAME
    if [[ -z "$HOSTNAME" ]]; then
        echo -e "${RED}Error: Hostname cannot be empty. Exiting.${RESET}"
        exit 1
    fi

    # Get available templates from Proxmox server
    echo -e "\n${BLUE}Getting list of available templates from storage '${BOLD}$DEFAULT_TEMPLATE_STORAGE${RESET}${BLUE}'...${RESET}"
    AVAILABLE_TEMPLATES=()
    i=1
    while IFS= read -r line; do
        full_template_id=$(echo "$line" | tr -d '\r' | awk '{print $1}')
        if [[ "$full_template_id" == *".tar.zst"* && -n "$full_template_id" ]]; then
            template_name=$(echo "$full_template_id" | sed -e "s/^$DEFAULT_TEMPLATE_STORAGE:vztmpl\///" -e 's/\.tar\.zst$//')
            if [[ -n "$template_name" ]]; then
                AVAILABLE_TEMPLATES+=("$template_name")
                echo -e "${YELLOW}$i) ${RESET}${GREEN}$template_name${RESET}"
                ((i++))
            fi
        fi
    done < <(pveam list "$DEFAULT_TEMPLATE_STORAGE")

    if [ ${#AVAILABLE_TEMPLATES[@]} -eq 0 ]; then
        echo -e "${RED}${BOLD}Error: No .tar.zst templates found in storage '$DEFAULT_TEMPLATE_STORAGE'.${RESET}"
        echo -e "${RED}Make sure you have downloaded templates.${RESET}"
        exit 1
    fi
    separator
    read -p "$(echo -e "${MAGENTA}Enter the number of the template to use [1-${#AVAILABLE_TEMPLATES[@]}]: ${RESET}")" TEMPLATE_CHOICE
    if ! [[ "$TEMPLATE_CHOICE" =~ ^[0-9]+$ ]] || [ "$TEMPLATE_CHOICE" -lt 1 ] || [ "$TEMPLATE_CHOICE" -gt ${#AVAILABLE_TEMPLATES[@]} ]; then
        echo -e "${RED}Invalid template choice. Exiting.${RESET}"
        exit 1
    fi
    SELECTED_TEMPLATE_NAME=${AVAILABLE_TEMPLATES[$((TEMPLATE_CHOICE-1))]}

    # Determine OS type based on selected template
    if [[ "$SELECTED_TEMPLATE_NAME" == *"ubuntu"* ]]; then
        OS_TYPE="ubuntu"
    elif [[ "$SELECTED_TEMPLATE_NAME" == *"debian"* ]]; then
        OS_TYPE="debian"
    else
        echo -e "${RED}Error: The selected template name does not contain 'ubuntu' or 'debian'. Exiting.${RESET}"
        exit 1
    fi

    # Get rootfs storage name
    read -p "$(echo -e "${MAGENTA}Enter the rootfs storage name (default: ${BOLD}$DEFAULT_ROOTFS_STORAGE${RESET}${MAGENTA}): ${RESET}")" ROOTFS_STORAGE_TEMP
    ROOTFS_STORAGE=${ROOTFS_STORAGE_TEMP:-$DEFAULT_ROOTFS_STORAGE}

    # Get network bridge name
    read -p "$(echo -e "${MAGENTA}Enter the network bridge name (default: ${BOLD}$DEFAULT_BRIDGE${RESET}${MAGENTA}): ${RESET}")" BRIDGE_TEMP
    BRIDGE=${BRIDGE_TEMP:-$DEFAULT_BRIDGE}

    # Get user name and password
    read -p "$(echo -e "${MAGENTA}Enter the user name to create in the container (default: ${BOLD}$DEFAULT_USER${RESET}${MAGENTA}): ${RESET}")" USER_TEMP
    NEW_USER=${USER_TEMP:-$DEFAULT_USER}

    read -p "$(echo -e "${MAGENTA}Enter the default password for root and user (default: ${BOLD}$DEFAULT_PASS${RESET}${MAGENTA}): ${RESET}")" PASS_TEMP
    PASSWORD=${PASS_TEMP:-$DEFAULT_PASS}

    # Get SSH Public Key path with smart defaults
    LOCAL_KEY="$SCRIPT_DIR/id_rsa.pub"
    if [[ -f "$LOCAL_KEY" ]]; then
        read -p "$(echo -e "${MAGENTA}SSH Key found in script folder. Use it? (default: ${BOLD}$LOCAL_KEY${RESET}${MAGENTA}): ${RESET}")" SSH_KEY_TEMP
        SSH_KEY_PATH=${SSH_KEY_TEMP:-$LOCAL_KEY}
    else
        read -p "$(echo -e "${MAGENTA}Enter path to SSH Public Key file (leave empty to skip): ${RESET}")" SSH_KEY_PATH
    fi

    if [[ -n "$SSH_KEY_PATH" ]]; then
        if [[ ! -f "$SSH_KEY_PATH" ]]; then
            echo -e "${YELLOW}Warning: SSH Key file ($SSH_KEY_PATH) NOT FOUND. Proceeding without SSH key.${RESET}"
            SSH_KEY_PATH=""
        fi
    fi

    echo -e "\n${BLUE}Password used (not displayed for security reasons).${RESET}"
    separator
}

# Function to create and configure a basic LXC container
create_lxc_basic() {
    echo -e "${BLUE}Creating a basic LXC container...${RESET}"

    # Set the OS type based on the selected template name
    if [[ "$SELECTED_TEMPLATE_NAME" == *"ubuntu"* ]]; then
        lxc_ostype="ubuntu"
    else
        lxc_ostype="debian"
    fi

    # Construct specific options array
    PCT_OPTIONS=(
        $CTID "$DEFAULT_TEMPLATE_STORAGE:vztmpl/$SELECTED_TEMPLATE_NAME.tar.zst"
        --storage "$ROOTFS_STORAGE"
        --rootfs "volume=$ROOTFS_STORAGE:$DEFAULT_ROOTFS_SIZE,mountoptions=noatime,acl=1"
        --ostype "$lxc_ostype"
        --arch amd64
        --password "$PASSWORD"
        --unprivileged "$DEFAULT_UNPRIVILEGED"
        --cores "$DEFAULT_CORES"
        --memory "$DEFAULT_MEMORY"
        --swap "$DEFAULT_SWAP"
        --hostname "$HOSTNAME"
        --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp,type=veth"
        --features "nesting=1"
        --start true
    )

    # Add SSH keys if provided
    if [[ -n "$SSH_KEY_PATH" ]]; then
        PCT_OPTIONS+=(--ssh-public-keys "$SSH_KEY_PATH")
    fi

    # Create the container
    pct create "${PCT_OPTIONS[@]}"

    sleep 15 # Wait for initialization
    echo -e "${BLUE}Updating packages, setting locale, and creating user...${RESET}"
    # Install locales and update system first to prevent locale errors
    pct exec $CTID -- bash -c "apt-get update && apt-get upgrade -y && apt-get install -y locales sudo curl wget gpg ca-certificates"

    # Set locale after locales package is installed
    pct exec $CTID -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen en_US.UTF-8"
    pct exec $CTID -- bash -c "update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8"

    # Create new user and set permissions
    pct exec $CTID -- bash -c "useradd -m -s /bin/bash $NEW_USER && echo '$NEW_USER:$PASSWORD' | chpasswd && usermod -aG sudo $NEW_USER"

    # Configure SSH keys for the new user if they were provided for root
    if [[ -n "$SSH_KEY_PATH" ]]; then
        echo -e "${BLUE}Configuring SSH keys for user '$NEW_USER'...${RESET}"
        pct exec $CTID -- bash -c "
            mkdir -p /home/$NEW_USER/.ssh
            if [ -f /root/.ssh/authorized_keys ]; then
                cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/authorized_keys
                chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                chmod 700 /home/$NEW_USER/.ssh
                chmod 600 /home/$NEW_USER/.ssh/authorized_keys
            fi
        "
    fi

    # Add daily fstrim cron job for SSD optimization (alternative to discard mount option)
    echo -e "${BLUE}Setting up daily fstrim (SSD optimization)...${RESET}"
    pct exec $CTID -- bash -c "echo '0 2 * * * root /sbin/fstrim -av' > /etc/cron.d/fstrim"
}
# Function to install Docker inside the container, dynamically choosing between Debian and Ubuntu
install_docker() {
    echo -e "${BLUE}Installing Docker and Docker Compose for $OS_TYPE...${RESET}"
    pct exec $CTID -- bash -c "
        set -e
        apt-get remove -y docker docker-engine docker.io containerd runc || true
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release

        echo -e \"${BLUE}Adding official Docker GPG key...${RESET}\"
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS_TYPE/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo -e \"${BLUE}Setting up Docker repository...${RESET}\"
        echo \\
            \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS_TYPE \\
            \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | \\
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        echo -e \"${BLUE}Updating package list after adding Docker repository...${RESET}\"
        apt-get update

        echo -e \"${BLUE}Installing Docker Engine CLI Containerd and plugins...${RESET}\"
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        echo -e \"${BLUE}Starting and enabling Docker service...${RESET}\"
        systemctl start docker
        systemctl enable docker
    "
    pct exec $CTID -- usermod -aG docker "$NEW_USER"
    echo -e "${GREEN}${BOLD}Docker and Docker Compose were successfully installed!${RESET}"
}

# Function to install Portainer inside the container
install_portainer() {
    echo -e "${BLUE}Installing Portainer CE...${RESET}"
    pct exec $CTID -- bash -c "
        set -e
        mkdir -p /home/$NEW_USER/docker/portainer && chown $NEW_USER:$NEW_USER /home/$NEW_USER/docker /home/$NEW_USER/docker/portainer
        docker run -d \\
            -p 9000:9000 \\
            -p 9443:9443 \\
            --name=portainer \\
            --restart=always \\
            -v /var/run/docker.sock:/var/run/docker.sock \\
            -v /home/$NEW_USER/docker/portainer:/data \\
            portainer/portainer-ce:latest
    "
}

# ===============================================================================
# --- Main Script Logic ---
# ===============================================================================

# 1. Run pre-flight checks
pre_flight_checks

# 2. Get general user input
get_user_input

# 3. Present the main menu for configuration choice
echo -e "\n${BLUE}What kind of container do you want to create?${RESET}"
echo -e "${YELLOW}1) ${GREEN}Basic LXC container (user and updates only)${RESET}"
echo -e "${YELLOW}2) ${GREEN}LXC container with Docker${RESET}"
echo -e "${YELLOW}3) ${GREEN}LXC container with Docker and Portainer CE${RESET}"
separator
read -p "$(echo -e "${MAGENTA}Your choice [1-3]: ${RESET}")" CHOICE

case $CHOICE in
    1)
        create_lxc_basic
        ;;
    2)
        create_lxc_basic
        install_docker
        ;;
    3)
        create_lxc_basic
        install_docker
        install_portainer
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${RESET}"
        exit 1
        ;;
esac

# --- Get IP Address of the container ---
echo -e "${BLUE}Retrieving container IP address...${RESET}"
# Try to get IP (5 attempts), might take a few seconds for DHCP to assign
CT_IP=""
for i in {1..5}; do
    CT_IP=$(pct exec $CTID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    if [[ -n "$CT_IP" ]]; then break; fi
    echo -e "${YELLOW}Attempt $i: IP not yet assigned, waiting...${RESET}"
    sleep 2
done

# --- Print completion message and security warning ---
separator
echo -e "${GREEN}${BOLD}Operation completed successfully!${RESET}"
echo -e "Container ${BOLD}$CTID${RESET}${GREEN} with hostname ${BOLD}$HOSTNAME${RESET}${GREEN} has been created.${RESET}"
if [[ -n "$CT_IP" ]]; then
    echo -e "IP Address: ${CYAN}${BOLD}$CT_IP${RESET}"
else
    echo -e "IP Address: ${YELLOW}IP not found (check DHCP or Proxmox settings)${RESET}"
fi
echo -e "User ${BOLD}$NEW_USER${RESET}${GREEN} was created with password ${BOLD}$PASSWORD${RESET}${GREEN}.${RESET}"

if [[ "$CHOICE" == "2" || "$CHOICE" == "3" ]]; then
    echo -e "Docker was successfully installed.${RESET}"
    echo -e "${YELLOW}User ${BOLD}$NEW_USER${RESET}${YELLOW} was added to the docker group. You may need a new login (e.g., container restart or new SSH session) for changes to take effect.${RESET}"
fi

if [[ "$CHOICE" == "3" ]]; then
    echo -e "Portainer CE is running on ports ${BOLD}9000 http${RESET}${GREEN} and ${BOLD}9443 https${RESET}${GREEN}.${RESET}"
    if [[ -n "$CT_IP" ]]; then
        echo -e "Access Portainer here: ${YELLOW}${BOLD}https://$CT_IP:9443${RESET}"
    else
        echo -e "Access Portainer here: ${YELLOW}https://<IP_ADDRESS>:9443${RESET}"
    fi
    echo -e "Remember to set the administrator password upon first login.${RESET}"
fi

echo -e "\n${RED}${BOLD}--- IMPORTANT SECURITY WARNING ---${RESET}"
echo -e "${RED}${BOLD}Passwords for root and user '$NEW_USER' were set to the default password ('$PASSWORD').${RESET}"
echo -e "${RED}${BOLD}IT IS NECESSARY TO CHANGE THEM IMMEDIATELY!${RESET}"
echo -e "${RED}1. Log into the container: ${YELLOW}${BOLD}pct enter $CTID${RESET}"
echo -e "${RED}2. Change password for root: ${YELLOW}${BOLD}passwd root${RESET}"
echo -e "${RED}3. Change password for user '$NEW_USER': ${YELLOW}${BOLD}passwd $NEW_USER${RESET}"
echo -e "${GREEN}${BOLD}-----------------------------------------------------\e[0m"

exit 0
