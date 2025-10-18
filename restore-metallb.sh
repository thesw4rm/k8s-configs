#!/bin/bash
# MetalLB Restoration Script
# This script restores the cluster to use MetalLB for LoadBalancer services
# Created: 2025-10-18

set -e

echo "=== MetalLB Restoration Script ==="
echo ""
echo "This script will:"
echo "  1. Remove Cilium LB IPAM configurations"
echo "  2. Reinstall MetalLB"
echo "  3. Restore MetalLB configuration (IP pools and L2 advertisements)"
echo "  4. Verify services are working"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Remove Cilium LB IPAM configurations
echo ""
echo "[1/4] Removing Cilium LB IPAM configurations..."
kubectl delete ciliumloadbalancerippools --all 2>/dev/null || echo "No Cilium LB IP pools to remove"
kubectl delete ciliumpodippools --all 2>/dev/null || echo "No Cilium pod IP pools to remove"
kubectl delete ciliuml2announcementpolicies --all 2>/dev/null || echo "No Cilium L2 policies to remove"

# Step 2: Install MetalLB
echo ""
echo "[2/4] Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB controller to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=controller \
  --timeout=120s

echo "Waiting for MetalLB speaker to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=speaker \
  --timeout=120s

# Step 3: Apply MetalLB configuration
echo ""
echo "[3/4] Applying MetalLB configuration..."

# Create IPAddressPool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public
  namespace: metallb-system
spec:
  addresses:
  - 10.10.141.50/27
  autoAssign: true
  avoidBuggyIPs: false
EOF

# Create L2Advertisement
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: public-l2-advertisement
  namespace: metallb-system
EOF

# Step 4: Verify service
echo ""
echo "[4/4] Verifying LoadBalancer service..."
sleep 5

kubectl get svc healthcheck-global-service

echo ""
echo "=== Restoration Complete ==="
echo ""
echo "Your cluster has been restored to use MetalLB."
echo "Check that the healthcheck-global-service has the external IP: 10.10.141.33"
echo ""
echo "To verify:"
echo "  kubectl get svc healthcheck-global-service"
echo "  kubectl get ipaddresspool -n metallb-system"
echo "  kubectl get l2advertisement -n metallb-system"
