#!/bin/bash
# ===============================================================================
# LXC Module — Validation Functions
# For use by AI agents
# 
# Usage: source /root/scripts/lxc_module_validation.sh
#        validate_lxc_params "100" "docker-lxc"
# ===============================================================================

# Check if CTID is valid number
validate_ctid_format() {
    local ctid=$1
    if [[ ! "$ctid" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CTID must be a number"
        return 1
    fi
    echo "OK: CTID format valid"
    return 0
}

# Check if CTID already exists
validate_ctid_exists() {
    local ctid="$1"
    if pct status "$ctid" &>/dev/null; then
        echo "ERROR: CTID $ctid already exists"
        return 1
    fi
    echo "OK: CTID $ctid is available"
    return 0
}

# Validate hostname format
validate_hostname() {
    local hostname=$1
    
    if [[ -z "$hostname" ]]; then
        echo "ERROR: Hostname cannot be empty"
        return 1
    fi
    
    if [[ "$hostname" =~ \  ]]; then
        echo "ERROR: Hostname cannot contain spaces"
        return 1
    fi
    
    if [[ "$hostname" =~ _ ]]; then
        echo "ERROR: Hostname cannot contain underscores (use hyphens: docker-lxc)"
        return 1
    fi
    
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$ ]]; then
        echo "ERROR: Hostname must start/end with alphanumeric, can contain hyphens"
        return 1
    fi
    
    echo "OK: Hostname '$hostname' is valid"
    return 0
}

# Full validation
validate_lxc_params() {
    local ctid=$1
    local hostname=$2
    
    echo "Validating LXC parameters..."
    echo "  CTID: $ctid"
    echo "  Hostname: $hostname"
    
    local errors=()
    
    # Validate CTID format
    if [[ ! "$ctid" =~ ^[0-9]+$ ]]; then
        errors+=("CTID must be a number")
    else
        # Validate CTID doesn't exist
        if pct status "$ctid" &>/dev/null; then
            errors+=("CTID $ctid already exists")
        fi
    fi
    
    # Validate hostname
    if [[ -z "$hostname" ]]; then
        errors+=("Hostname cannot be empty")
    elif [[ "$hostname" =~ \  ]]; then
        errors+=("Hostname cannot contain spaces")
    elif [[ "$hostname" =~ _ ]]; then
        errors+=("Hostname cannot contain underscores")
    elif [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$ ]]; then
        errors+=("Hostname format invalid")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "VALIDATION FAILED:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
    
    echo "VALIDATION PASSED"
    return 0
}

# If run directly (not sourced), validate params from command line
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <CTID> <HOSTNAME>"
        echo "Example: $0 100 docker-lxc"
        exit 1
    fi
    validate_lxc_params "$1" "$2"
fi
