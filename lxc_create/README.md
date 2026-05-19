# 📂 Linux Shell Scripts Collection

Welcome to the `scripts_sh` directory. This folder contains various automation scripts designed for Linux administration, specifically tailored for **Proxmox VE** environments and general DevOps tasks.

## 🚀 Getting Started

To use these scripts, follow the steps below to ensure they are downloaded and executed correctly.

### 1. Clone the repository
If you haven't already, clone this repository to your local machine:
```bash
git clone https://github.com/your-username/your-repo-name.git
cd your-repo-name/scripts_sh
```

### 2. Set Permissions
By default, scripts might not have execution permissions. Grant them using `chmod`:
```bash
chmod +x proxmox_lxc_script.sh
```
*(Repeat for any other script you wish to run.)*

### 3. Execution
Run the scripts with root or sudo privileges (required for system-level changes):
```bash
sudo ./proxmox_lxc_script.sh
```

---

## 🛠 Featured Script: Proxmox LXC Super Script

The main highlight of this folder is the **Proxmox LXC Super Script**. It provides an interactive menu to deploy Linux Containers (LXC) quickly and efficiently.

**Key Features:**
*   **Menu-Driven:** Easy-to-use CLI interface.
*   **Pre-flight Checks:** Verifies root access and Proxmox version.
*   **Automated Setup:** Handles package updates, locale configuration, and user creation.
*   **Software Stack:** Optional one-click installation of **Docker** and **Portainer CE**.
*   **SSD Optimization:** Automatically sets up `fstrim` cron jobs.

---

## ⚙️ Customization

If you need to change default settings (such as default storage, RAM, or usernames), you can easily edit the variables at the beginning of each script:

```bash
nano proxmox_lxc_script.sh
```

Look for the section labeled `# --- Default configuration inputs ---` and modify the values to match your infrastructure.

---

## ⚠️ Security Warning

*   **Root Access:** These scripts perform high-level system changes. Always review the source code before running them.
*   **Passwords:** The scripts use default passwords for initial setup. **Change your root and user passwords immediately** after the script finishes.
*   **SSH Keys:** It is highly recommended to use the SSH key integration for better security.

---

## 📝 License
Feel free to use, modify, and distribute these scripts for your personal or professional projects.

**Author:** Gemini & User
**Last Updated:** 2024-08-02
