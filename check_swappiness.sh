#!/bin/bash

# Log file setup
LOGFILE="/home/diablo/k8s/lab/swappiness_update_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# List of VMs with IPs starting with 10.10
declare -a vms=(
    "fedora_template" "kube-master" "kube-worker"
    "kube-worker-big" "nix.dev" "mysql" "radarr"
    "jellyfin" "r1.duri" "r2.duri" "h1.duri" "h2.duri"
    "minecraft" "docs" "paperless"
    "bitty" "budget" "irc_root" "docker-registry"
    "mysql-sensit" "recipes"
    "home-media"
)

# Arrays to track VMs by status
declare -a updated_vms=()
declare -a already_configured_vms=()
declare -a unreachable_vms=()
declare -a non_linux_vms=()
declare -a failed_vms=()

echo "======================================================================"
echo "VM Swappiness Update Script"
echo "Started: $(date)"
echo "Log file: $LOGFILE"
echo "======================================================================"
echo ""
echo "Checking vm.swappiness on all VMs with IPs starting with 10.10..."
echo "======================================================================"
echo ""

for vm in "${vms[@]}"; do
    echo "Checking $vm..."

    # Test connectivity with 2 second timeout
    if ! ssh -o ConnectTimeout=2 -o BatchMode=yes "$vm" "exit" 2>/dev/null; then
        echo "  ❌ Not reachable - skipping"
        unreachable_vms+=("$vm")
        echo ""
        continue
    fi

    # Check if it's a Linux system
    os=$(ssh -o ConnectTimeout=2 "$vm" "uname -s" 2>/dev/null)
    if [ "$os" != "Linux" ]; then
        echo "  ⚠️  Not a Linux system (OS: $os) - skipping"
        non_linux_vms+=("$vm ($os)")
        echo ""
        continue
    fi

    echo "  ✓ Reachable Linux system"

    # Check current swappiness
    current=$(ssh "$vm" "sysctl vm.swappiness 2>/dev/null | awk '{print \$3}'")
    echo "  Current vm.swappiness: $current"

    # Check if it's set in /etc/sysctl.conf
    in_conf=$(ssh "$vm" "grep -E '^vm.swappiness' /etc/sysctl.conf 2>/dev/null || echo 'not found'")
    echo "  In /etc/sysctl.conf: $in_conf"

    if [ "$current" != "10" ] || [ "$in_conf" == "not found" ]; then
        echo "  🔧 Needs update"

        # Remove existing vm.swappiness lines and add new one
        if ssh "$vm" "sed -i '/^vm.swappiness/d' /etc/sysctl.conf && echo 'vm.swappiness = 10' | tee -a /etc/sysctl.conf > /dev/null" 2>/dev/null; then
            # Apply immediately
            ssh "$vm" "sysctl -w vm.swappiness=10 > /dev/null" 2>/dev/null

            # Verify
            new_val=$(ssh "$vm" "sysctl vm.swappiness 2>/dev/null | awk '{print \$3}'")
            echo "  ✅ Updated to: $new_val"
            updated_vms+=("$vm")
        else
            echo "  ❌ Failed to update"
            failed_vms+=("$vm")
            echo ""
            continue
        fi
    else
        echo "  ✅ Already set to 10"
        already_configured_vms+=("$vm")
    fi

    # Clear page cache, dentries and inodes (on all Linux VMs)
    echo "  🧹 Clearing cached files in memory..."
    if ssh "$vm" "sync && echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null; then
        echo "  ✅ Cache cleared successfully"
    else
        echo "  ⚠️  Failed to clear cache"
    fi

    echo ""
done

echo ""
echo "======================================================================"
echo "Summary Report"
echo "======================================================================"
echo ""
echo "Updated VMs (${#updated_vms[@]}):"
for vm in "${updated_vms[@]}"; do
    echo "  - $vm"
done
echo ""

echo "Already Configured VMs (${#already_configured_vms[@]}):"
for vm in "${already_configured_vms[@]}"; do
    echo "  - $vm"
done
echo ""

echo "Unreachable VMs (${#unreachable_vms[@]}):"
for vm in "${unreachable_vms[@]}"; do
    echo "  - $vm"
done
echo ""

echo "Non-Linux VMs (${#non_linux_vms[@]}):"
for vm in "${non_linux_vms[@]}"; do
    echo "  - $vm"
done
echo ""

if [ ${#failed_vms[@]} -gt 0 ]; then
    echo "Failed VMs (${#failed_vms[@]}):"
    for vm in "${failed_vms[@]}"; do
        echo "  - $vm"
    done
    echo ""
fi

echo "======================================================================"
echo "Completed: $(date)"
echo "Full log saved to: $LOGFILE"
echo "======================================================================"
