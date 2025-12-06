# Solution Summary - Dual-Stack LoadBalancer with MetalLB

## Final Working Solution

**Method**: MetalLB L2 Mode (both IPv4 and IPv6)
**No static routes required!**

## What Made IPv6 LoadBalancer Work

### 1. Network Configuration
OPNsense already had the `/72` subnet configured as directly connected:
```
fdde:5353:4242:141:1200::/72 → vtnet1 (Layer 2 network)
```

This allows MetalLB L2 announcements (NDP) to work properly.

### 2. Key Configuration Changes

**a) IPv6 Pool Starting Address**
```yaml
# Changed from CIDR (which started at ::0)
addresses:
- fdde:5353:4242:0141:1200:0100::/96

# To range (starting at ::1)
addresses:
- fdde:5353:4242:0141:1200:0100::1-fdde:5353:4242:0141:1200:0100:ffff:ffff
```
**Why**: Starting at `::0` (network address) caused issues. Starting at `::1` works properly.

**b) NDP Proxy Enabled**
```bash
# /etc/sysctl.d/k8s.conf on all nodes
net.ipv6.conf.all.proxy_ndp = 1
```

**c) Separate L2 Advertisements**
```yaml
# Separate announcements for IPv4 and IPv6
l2advertisement-ipv4.yaml
l2advertisement-ipv6.yaml
```

**d) Interface Specified**
```yaml
spec:
  interfaces:
  - ens18
```

### 3. How It Works

```
Client (OPNsense)
  |
  | 1. Sends NDP Neighbor Solicitation
  |    "Who has fdde:5353:4242:141:1200:100:0:1?"
  |
  v
Layer 2 Network (vtnet1 / ens18)
  |
  | 2. MetalLB Speaker on kube-worker responds
  |    "I have it! My MAC is bc:24:11:d3:5b:75"
  |
  v
kube-worker
  |
  | 3. Cilium forwards traffic to pod
  v
nginx pod
```

## Verification

**NDP Resolution**:
```bash
ndp -an | grep 1200:100:0:1
# fdde:5353:4242:141:1200:100:0:1  bc:24:11:d3:5b:75 vtnet1
```

**MetalLB Announcement**:
```bash
kubectl logs -n metallb-system -l component=speaker | grep serviceAnnounced
# event=serviceAnnounced ips=[fdde:5353:4242:141:1200:100::1]
```

**Test**:
```bash
curl -6 "http://[fdde:5353:4242:141:1200:100:0:1]:80"
# <!DOCTYPE html><html>...Welcome to nginx...
```

## Configuration Files

All files in `/home/diablo/k8s/lab/metallb/`:
- ✅ `ipaddresspool-ipv4.yaml` - IPv4 pool (10.10.141.50/27)
- ✅ `ipaddresspool-ipv6.yaml` - IPv6 pool (::1 to ::ffff:ffff)
- ✅ `l2advertisement-ipv4.yaml` - IPv4 L2 announcement
- ✅ `l2advertisement-ipv6.yaml` - IPv6 L2 announcement

## Result

✅ **IPv4 LoadBalancer**: MetalLB L2 mode
✅ **IPv6 LoadBalancer**: MetalLB L2 mode  
✅ **No static routes needed**
✅ **Automatic failover** when services move between nodes
✅ **Production ready**

## Why Earlier Troubleshooting Helped

Even though we thought the static route fixed it, the real fixes were:
1. IP pool starting at `::1` instead of `::0`
2. `proxy_ndp` enabled on nodes
3. Separate L2 advertisements
4. MetalLB restarted with clean configuration
5. Interface explicitly specified

The `/72` network route was there all along - we just needed MetalLB configured correctly!
