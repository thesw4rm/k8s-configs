#!/bin/bash
# Script to apply Cilium configuration
# This script applies the Cilium Helm chart with the custom values and patches
# the envoy daemonset to add NET_BIND_SERVICE capability

set -e

echo "Applying Cilium configuration..."
helm upgrade cilium cilium/cilium --version 1.18.4 -n kube-system -f cilium/values.yaml

echo "Waiting for helm upgrade to complete..."
sleep 10

echo "Patching cilium-envoy daemonset to add NET_BIND_SERVICE capability..."
kubectl patch daemonset cilium-envoy -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/capabilities/add/-", "value": "NET_BIND_SERVICE"}]'

echo "Waiting for envoy pods to restart..."
sleep 30

echo "Checking cilium pod status..."
kubectl get pods -n kube-system | grep cilium

echo ""
echo "Configuration applied successfully!"
echo "Note: If using Gateway API with hostNetwork mode, ensure gateways use different ports"
