# BGP Migration Plan: OPNsense + MetalLB

## Overview
Migrate from MetalLB L2 mode to BGP mode with iBGP peering between OPNsense and Kubernetes nodes.

## Architecture
```
OPNsense (10.10.141.126) - BGP Router (AS 64500)
  |
  +-- iBGP Peer --> kube-master (10.10.141.12 / fdde:5353:4242:141:1200::2)
  +-- iBGP Peer --> kube-worker (10.10.141.10 / fdde:5353:4242:141:1200::3)
  +-- iBGP Peer --> kube-worker-big (10.10.141.13 / fdde:5353:4242:141:1200::4)
```

## Prerequisites
- OPNsense router with admin access
- Kubernetes cluster with MetalLB installed
- Network connectivity between OPNsense and all k8s nodes

## Phase 1: OPNsense BGP Setup

### 1.1 Install FRR on OPNsense
```bash
# SSH to OPNsense
ssh root@10.10.141.126

# Install FRR package
pkg install frr

# Enable FRR services
sysrc frr_enable="YES"
sysrc frr_daemons="zebra bgpd"
```

### 1.2 Configure FRR
Edit `/usr/local/etc/frr/frr.conf`:
```
frr version 8.4
frr defaults traditional
hostname opnsense
log syslog informational

# BGP Configuration
router bgp 64500
 bgp router-id 10.10.141.126
 no bgp ebgp-requires-policy
 no bgp default ipv4-unicast

 # IPv4 AFI
 address-family ipv4 unicast
  neighbor KUBE peer-group
  neighbor KUBE remote-as 64500
  neighbor 10.10.141.12 peer-group KUBE
  neighbor 10.10.141.10 peer-group KUBE
  neighbor 10.10.141.13 peer-group KUBE
  network 10.10.141.50/27
 exit-address-family

 # IPv6 AFI
 address-family ipv6 unicast
  neighbor KUBE6 peer-group
  neighbor KUBE6 remote-as 64500
  neighbor fdde:5353:4242:141:1200::2 peer-group KUBE6
  neighbor fdde:5353:4242:141:1200::3 peer-group KUBE6
  neighbor fdde:5353:4242:141:1200::4 peer-group KUBE6
  network fdde:5353:4242:141:1200:100::/96
 exit-address-family
!
line vty
!
```

### 1.3 Start FRR
```bash
service frr start
# Verify BGP daemon is running
vtysh -c "show bgp summary"
```

## Phase 2: MetalLB BGP Configuration

### 2.1 Remove L2 Advertisements
```bash
kubectl delete l2advertisement -n metallb-system public-l2-ipv4
kubectl delete l2advertisement -n metallb-system public-l2-ipv6
```

### 2.2 Create BGP Advertisement
File: `metallb/bgpadvertisement.yaml`
```yaml
---
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: public-bgp
  namespace: metallb-system
spec:
  ipAddressPools:
  - public-ipv4
  - public-ipv6
```

### 2.3 Configure BGP Peers
File: `metallb/bgppeer-opnsense.yaml`
```yaml
---
# BGP Peer to OPNsense
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: opnsense
  namespace: metallb-system
spec:
  myASN: 64500
  peerASN: 64500
  peerAddress: 10.10.141.126
  peerPort: 179
  holdTime: 90s
---
# BGP Peer to OPNsense (IPv6)
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: opnsense-ipv6
  namespace: metallb-system
spec:
  myASN: 64500
  peerASN: 64500
  peerAddress: fdde:5353:4242:141:1200::1
  peerPort: 179
  holdTime: 90s
```

### 2.4 Apply BGP Configuration
```bash
kubectl apply -f metallb/bgpadvertisement.yaml
kubectl apply -f metallb/bgppeer-opnsense.yaml
```

## Phase 3: Verification & Testing

### 3.1 Check BGP Sessions on OPNsense
```bash
ssh root@10.10.141.126
vtysh -c "show bgp summary"
vtysh -c "show bgp ipv4 unicast"
vtysh -c "show bgp ipv6 unicast"
```

Expected output: 3 established BGP sessions (one per node)

### 3.2 Check MetalLB Speaker Logs
```bash
kubectl logs -n metallb-system -l component=speaker --tail=50 | grep BGP
```

### 3.3 Test IPv4 LoadBalancer
```bash
# From OPNsense
curl http://10.10.141.32
```

### 3.4 Test IPv6 LoadBalancer
```bash
# From OPNsense
curl -g http://[fdde:5353:4242:141:1200:100:0:1]/
```

## Phase 4: Troubleshooting

### Check BGP Session Status
```bash
# On OPNsense
vtysh -c "show bgp neighbors"

# On Kubernetes
kubectl get bgppeer -n metallb-system
kubectl describe bgppeer -n metallb-system opnsense
```

### Check Routes
```bash
# On OPNsense - should see routes from k8s nodes
vtysh -c "show ip route bgp"
vtysh -c "show ipv6 route bgp"

# On OPNsense - routing table
netstat -rn | grep 10.10.141.50
netstat -rn -f inet6 | grep 1200:100
```

### Common Issues
1. **BGP not establishing**: Check firewall allows TCP 179
2. **Routes not installed**: Check ASN numbers match (64500)
3. **IPv6 not working**: Ensure IPv6 forwarding enabled on all nodes

## Configuration Summary

**ASN Number**: 64500 (private ASN for iBGP)
**OPNsense Router ID**: 10.10.141.126
**IPv4 LoadBalancer Pool**: 10.10.141.50/27
**IPv6 LoadBalancer Pool**: fdde:5353:4242:141:1200:100::/96

**Kubernetes Nodes**:
- kube-master: 10.10.141.12 / fdde:5353:4242:141:1200::2
- kube-worker: 10.10.141.10 / fdde:5353:4242:141:1200::3
- kube-worker-big: 10.10.141.13 / fdde:5353:4242:141:1200::4

## Rollback Plan

If BGP doesn't work, revert to L2 mode:
```bash
kubectl delete bgppeer -n metallb-system --all
kubectl delete bgpadvertisement -n metallb-system --all
kubectl apply -f metallb/l2advertisement-ipv4.yaml
kubectl apply -f metallb/l2advertisement-ipv6.yaml
```

## Benefits of BGP Mode

1. **No L2 dependencies** - No ARP/NDP issues
2. **Better scalability** - Routes propagate via BGP
3. **Faster failover** - BGP detects node failures quickly
4. **Multi-hop support** - Works across routed networks
5. **Standard protocol** - Well-understood, debuggable

## Next Steps

After successful migration:
1. Remove static routes on OPNsense (no longer needed)
2. Disable proxy_ndp on nodes (no longer needed)
3. Monitor BGP sessions for stability
4. Document the new architecture
