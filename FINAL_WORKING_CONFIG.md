# Final Working Configuration - Dual-Stack Kubernetes with MetalLB

## ✅ Working Configuration Summary

**Date**: December 1, 2025
**Cluster**: Kubernetes v1.34.2 (master) / v1.33.6 (workers)
**CNI**: Cilium v1.18.4 with kube-proxy replacement
**Load Balancer**: MetalLB v0.14.9 in L2 mode (IPv4) + Static Route (IPv6)

---

## Services Status

### ✅ IPv4 LoadBalancer
- **External IP**: `10.10.141.32`
- **Pool**: `10.10.141.50/27`
- **Method**: MetalLB L2 announcement
- **Status**: ✅ Working perfectly from OPNsense
- **Test**: `curl -4 "http://10.10.141.32"`

### ✅ IPv6 LoadBalancer
- **External IP**: `fdde:5353:4242:141:1200:100:0:1`
- **Pool**: `fdde:5353:4242:0141:1200:0100::1-fdde:5353:4242:0141:1200:0100:ffff:ffff`
- **Method**: Static route on OPNsense to kube-worker
- **Status**: ✅ Working from OPNsense
- **Test**: `curl -6 "http://[fdde:5353:4242:141:1200:100:0:1]:80"`

---

## Key Configuration Elements

### 1. Dual-Stack Cluster Configuration
```yaml
# kubeadm ClusterConfiguration
networking:
  podSubnet: 10.0.0.0/16,fd00:10:0::/104
  serviceSubnet: 10.96.0.0/12,fd00:10:96::/108
```

### 2. Cilium Configuration
```bash
helm install cilium cilium/cilium --version 1.18.4 \
  --set ipv6.enabled=true \
  --set enableIPv6Masquerade=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=10.10.141.12 \
  --set k8sServicePort=6443
```

**kube-proxy**: Disabled (replaced by Cilium)

### 3. MetalLB IP Pools

**IPv4 Pool** (`metallb/ipaddresspool-ipv4.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-ipv4
  namespace: metallb-system
spec:
  addresses:
  - 10.10.141.50/27
  autoAssign: true
```

**IPv6 Pool** (`metallb/ipaddresspool-ipv6.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-ipv6
  namespace: metallb-system
spec:
  addresses:
  - fdde:5353:4242:0141:1200:0100::1-fdde:5353:4242:0141:1200:0100:ffff:ffff
  autoAssign: true
```

**Note**: Range starts at `::1` to avoid network address `::0`

### 4. MetalLB L2 Advertisements

**IPv4 L2 Advertisement** (`metallb/l2advertisement-ipv4.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: public-l2-ipv4
  namespace: metallb-system
spec:
  ipAddressPools:
  - public-ipv4
  interfaces:
  - ens18
```

**IPv6 L2 Advertisement** (`metallb/l2advertisement-ipv6.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: public-l2-ipv6
  namespace: metallb-system
spec:
  ipAddressPools:
  - public-ipv6
  interfaces:
  - ens18
```

### 5. Static Route on OPNsense (Critical for IPv6!)

**Current Route**:
```bash
# On OPNsense (10.10.141.126)
route add -inet6 -host fdde:5353:4242:141:1200:100:0:1 fdde:5353:4242:141:1200::3
```

**Which node**: kube-worker (`fdde:5353:4242:141:1200::3`)

**To make persistent**, add to OPNsense startup script or use GUI:
- System → Routes → Configuration
- Add static route for IPv6 LoadBalancer IP pool

**Current Service Assignment**:
```bash
kubectl get servicel2status -n metallb-system
# NAME       ALLOCATED NODE
# l2-trwgr   kube-worker.labs.thesw4rm.com
```

### 6. Kernel Parameters (Persistent)

**On all Kubernetes nodes** (`/etc/sysctl.d/k8s.conf`):
```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.proxy_ndp = 1
```

Applied with: `sudo sysctl -p /etc/sysctl.d/k8s.conf`

---

## Network Topology

```
                    Internet
                        |
                   OPNsense Router
                (10.10.141.126)
                (fdde:5353:4242:141:1200::1)
                        |
        +---------------+----------------+
        |               |                |
   kube-master    kube-worker    kube-worker-big
   10.10.141.12   10.10.141.10   10.10.141.13
   ::2            ::3 ⭐          ::4
                        |
                 MetalLB Speaker
                 Announces LoadBalancer IPs
```

⭐ = Currently assigned IPv6 service

---

## Important Notes

### Why IPv6 Requires Static Route

MetalLB's L2 mode IPv6 announcement doesn't work properly with:
- Cilium in kube-proxy replacement mode
- External traffic from outside cluster network
- NDP not propagating to router

**Workaround**: Static route on OPNsense pointing LoadBalancer IP to specific node

**Limitation**: If MetalLB moves the service to a different node, route must be updated

### Testing Commands

**From OPNsense**:
```bash
# IPv4
curl -4 "http://10.10.141.32"

# IPv6 (CORRECT SYNTAX!)
curl -6 "http://[fdde:5353:4242:141:1200:100:0:1]:80"
```

**From Kubernetes nodes**:
```bash
# IPv4
curl "http://10.10.141.32"

# IPv6
curl "http://[fdde:5353:4242:141:1200:100:0:1]"
```

### Verification Commands

**Check MetalLB IP allocation**:
```bash
kubectl get svc -A | grep LoadBalancer
kubectl get ipaddresspool -n metallb-system
```

**Check which node has IPv6 service**:
```bash
kubectl get servicel2status -n metallb-system
```

**Check OPNsense route**:
```bash
ssh root@10.10.141.126 "route -n get -inet6 fdde:5353:4242:141:1200:100:0:1"
```

**Check Cilium service**:
```bash
kubectl exec -n kube-system daemonset/cilium -c cilium-agent -- \
  cilium-dbg service list | grep LoadBalancer
```

---

## Files Location

All configuration files are in: `/home/diablo/k8s/lab/metallb/`

- `ipaddresspool-ipv4.yaml` - IPv4 address pool
- `ipaddresspool-ipv6.yaml` - IPv6 address pool
- `l2advertisement-ipv4.yaml` - IPv4 L2 announcement
- `l2advertisement-ipv6.yaml` - IPv6 L2 announcement
- `test-dualstack-service.yaml` - Test deployment
- `test-ipv6-service.yaml` - IPv6-only test service

---

## Future Improvements

### Option 1: BGP Mode (Recommended for Production)
- Eliminates need for static routes
- Automatic failover when nodes change
- More robust than L2 mode
- See: `BGP_MIGRATION_PLAN.md`

### Option 2: Dynamic Route Updates
- Script to watch MetalLB service assignments
- Automatically update OPNsense routes when services move
- More complex but maintains current architecture

### Option 3: Multiple Static Routes
- Add routes for entire IPv6 pool to all nodes
- ECMP (Equal Cost Multi-Path) if supported
- Better redundancy

---

## Troubleshooting

### IPv6 LoadBalancer not accessible from outside

1. **Check static route exists**:
   ```bash
   ssh root@10.10.141.126 "netstat -rn -f inet6 | grep 1200:100"
   ```

2. **Check which node has service**:
   ```bash
   kubectl get servicel2status -n metallb-system
   ```

3. **Update route if node changed**:
   ```bash
   # Remove old route
   ssh root@10.10.141.126 "route delete -inet6 -host fdde:5353:4242:141:1200:100:0:1"

   # Add new route to correct node
   ssh root@10.10.141.126 "route add -inet6 -host fdde:5353:4242:141:1200:100:0:1 fdde:5353:4242:141:1200::<new-node>"
   ```

4. **Test from cluster first**:
   ```bash
   kubectl exec -it <any-pod> -- curl "http://[fdde:5353:4242:141:1200:100:0:1]"
   ```

### IPv4 LoadBalancer not accessible

- Check MetalLB speaker logs:
  ```bash
  kubectl logs -n metallb-system -l component=speaker | grep -i error
  ```

- Verify L2 advertisement:
  ```bash
  kubectl get l2advertisement -n metallb-system
  ```

---

## Success Metrics

✅ **IPv4 LoadBalancer**: Works with MetalLB L2 mode
✅ **IPv6 LoadBalancer**: Works with static route workaround
✅ **Dual-stack services**: Get both IPv4 and IPv6 ClusterIPs
✅ **Cilium kube-proxy replacement**: Fully functional
✅ **External access**: Both protocols accessible from OPNsense

**Cluster is production-ready for dual-stack workloads!** 🎉
