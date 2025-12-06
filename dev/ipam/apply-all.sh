#!/bin/bash
# Apply all Cilium LB IPAM configurations
set -e

echo "=== Applying Cilium LB IPAM Configuration ==="
echo ""

# Apply IP pools first
echo "[1/2] Creating IP address pools..."
kubectl apply -f ip-pool-public.yaml

# Apply L2 announcement policies
echo "[2/2] Creating L2 announcement policies..."
kubectl apply -f l2-policy-public.yaml

echo ""
echo "=== Configuration Applied ==="
echo ""
echo "Verify with:"
echo "  kubectl get ciliumloadbalancerippools"
echo "  kubectl get ciliuml2announcementpolicies"
echo ""
echo "To view details:"
echo "  kubectl describe ciliumloadbalancerippools public"
echo "  kubectl describe ciliuml2announcementpolicies public-l2-policy"
