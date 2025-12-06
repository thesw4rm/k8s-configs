# Cilium Configuration

This directory contains the Cilium CNI configuration for the Kubernetes cluster.

## Files

- `values.yaml` - Helm values for Cilium installation
- `apply.sh` - Script to apply Cilium configuration with necessary patches

## Key Configuration

### Direct API Server Access
To prevent chicken-and-egg issues after cluster restarts, Cilium is configured to connect directly to the Kubernetes API server IP rather than using the service IP:
```yaml
k8sServiceHost: 10.10.141.12
k8sServicePort: 6443
```

### Gateway API with Host Networking
Gateway API is enabled with host networking mode. This requires the `NET_BIND_SERVICE` capability for envoy to bind to privileged ports (< 1024).

**Important**: When using `hostNetwork: true`, multiple gateways cannot bind to the same port. If you have both IPv4 and IPv6 gateways, they must use different ports (e.g., 80 and 8080).

### Envoy Capabilities
The envoy daemonset requires the `NET_BIND_SERVICE` capability to bind to port 80. This is applied via a manual patch in `apply.sh` since the helm parameter `envoy.securityContext.capabilities.keepCapNetBindService` doesn't currently work as expected.

## Applying Configuration

Use the provided script to apply the configuration:
```bash
./cilium/apply.sh
```

Or manually:
```bash
helm upgrade cilium cilium/cilium --version 1.18.4 -n kube-system -f cilium/values.yaml

# Add NET_BIND_SERVICE capability
kubectl patch daemonset cilium-envoy -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/capabilities/add/-", "value": "NET_BIND_SERVICE"}]'
```

## Troubleshooting

### Cilium pods stuck in Init state after restart
This happens when cilium tries to connect to the Kubernetes API via the service IP but service routing isn't working yet. Solution: Configure direct API server access (already done in values.yaml).

### Envoy fails with "Permission denied" binding to port 80
Envoy needs the `NET_BIND_SERVICE` capability. Apply the patch using `apply.sh`.

### Gateway shows "duplicate address" error
Both IPv4 and IPv6 gateways are trying to bind to the same port with hostNetwork mode. Use different ports for each gateway in `cilium-gateway/gateway.yaml`.
