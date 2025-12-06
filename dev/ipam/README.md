# Cilium LB IPAM Configuration

This directory contains Cilium LoadBalancer IP Address Management (LB IPAM) configurations.

## Overview

Cilium LB IPAM replaces MetalLB by providing native LoadBalancer service support through:
- **CiliumLoadBalancerIPPool**: Defines pools of IP addresses for LoadBalancer services
- **CiliumL2AnnouncementPolicy**: Configures Layer 2 (ARP) announcements for IPs

## Files

- `ip-pool-public.yaml` - Public IP address pool (10.10.141.50/27)
- `l2-policy-public.yaml` - L2 announcement policy for the public pool
- `apply-all.sh` - Script to apply all configurations

## IP Pool Configuration

### Public Pool
- **CIDR**: 10.10.141.50/27 (30 usable IPs: .50-.81)
- **Purpose**: External LoadBalancer services
- **Mode**: L2 (ARP announcements on local network)

## Usage

### Apply All Configurations
```bash
./apply-all.sh
```

### Apply Individual Files
```bash
kubectl apply -f ip-pool-public.yaml
kubectl apply -f l2-policy-public.yaml
```

### Verify Configuration
```bash
# Check IP pools
kubectl get ciliumloadbalancerippools

# Check L2 policies
kubectl get ciliuml2announcementpolicies

# Check LoadBalancer services
kubectl get svc -A | grep LoadBalancer
```

## Migration Notes

This configuration replaces MetalLB with equivalent functionality:
- MetalLB IPAddressPool → CiliumLoadBalancerIPPool
- MetalLB L2Advertisement → CiliumL2AnnouncementPolicy

To restore MetalLB, run:
```bash
../restore-metallb.sh
```

## Extending

### Add New IP Pool
Create a new file `ip-pool-<name>.yaml`:
```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: <pool-name>
spec:
  blocks:
  - cidr: <your-cidr>
```

### Service-Specific IP Pools
Use annotations on services:
```yaml
annotations:
  io.cilium/lb-ipam-ips: "10.10.141.55"  # Specific IP
  # or
  io.cilium/ipam-pool: "<pool-name>"     # Specific pool
```

### Disable Pool for Specific Services
```yaml
annotations:
  io.cilium/lb-ipam-ips: "disabled"
```

## Troubleshooting

### Service Stuck in Pending
```bash
kubectl describe svc <service-name>
# Look for IPAMRequestSatisfied condition
```

### Check Cilium LB IPAM Status
```bash
kubectl get ciliumloadbalancerippools -o yaml
kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i ipam
```

### Verify L2 Announcements
```bash
# From another machine on the network:
arping -I <interface> <loadbalancer-ip>
```
