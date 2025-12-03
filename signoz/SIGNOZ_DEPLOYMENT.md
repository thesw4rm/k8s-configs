# SigNoz Dual-Stack Deployment on Kubernetes

## Overview

SigNoz observability platform deployed on a dual-stack Kubernetes cluster with both IPv4 and IPv6 LoadBalancer services using MetalLB L2 mode.

## Access URLs

### SigNoz UI
- **IPv4**: `http://10.10.141.33:8080`
- **IPv6**: `http://[fdde:5353:4242:141:1200:100:0:2]:8080`

### OTEL Collector
- **IPv4**:
  - gRPC: `http://10.10.141.34:4317`
  - HTTP: `http://10.10.141.34:4318`
- **IPv6**:
  - gRPC: `http://[fdde:5353:4242:141:1200:100:0:3]:4317`
  - HTTP: `http://[fdde:5353:4242:141:1200:100:0:3]:4318`

## Deployed Services

| Service | Type | IP Family | External IP |
|---------|------|-----------|-------------|
| signoz | LoadBalancer | PreferDualStack | 10.10.141.33 |
| signoz-ipv6 | LoadBalancer | SingleStack IPv6 | fdde:5353:4242:141:1200:100:0:2 |
| signoz-otel-collector | LoadBalancer | PreferDualStack | 10.10.141.34 |
| signoz-otel-collector-ipv6 | LoadBalancer | SingleStack IPv6 | fdde:5353:4242:141:1200:100:0:3 |

## Configuration Files

### 1. `values.yaml`
Helm values file containing:
- **ClickHouse DNS Fix**: Custom DNS configuration to resolve Alpine Linux musl libc issues in dual-stack clusters
- **PreferDualStack Services**: Configuration for signoz and otelCollector services
- **Storage Class**: Uses `local-path` provisioner

```bash
helm install signoz signoz/signoz -n platform -f values.yaml
```

### 2. `signoz-ipv6-service.yaml`
Standalone IPv6 LoadBalancer services that provide IPv6 external IPs.

Apply after Helm installation:
```bash
kubectl apply -f signoz-ipv6-service.yaml
```

### 3. `apply-dns-fix.sh`
Script to patch ClickHouse with DNS configuration after Helm operations.

Run after fresh install or upgrade:
```bash
./apply-dns-fix.sh
```

### 4. `clickhouse-dns-patch.yaml`
Documentation of the DNS patch applied to ClickHouseInstallation CRD.

## How Dual-Stack LoadBalancers Work

Following the nginx deployment pattern in this cluster:

1. **PreferDualStack Services** (`signoz`, `signoz-otel-collector`):
   - Get both IPv4 and IPv6 ClusterIPs
   - MetalLB automatically assigns IPv4 LoadBalancer IPs from `public-ipv4` pool
   - No annotations required

2. **SingleStack IPv6 Services** (`signoz-ipv6`, `signoz-otel-collector-ipv6`):
   - Get only IPv6 ClusterIPs
   - MetalLB automatically assigns IPv6 LoadBalancer IPs from `public-ipv6` pool
   - Same pod selectors as IPv4 services (route to same backends)
   - No annotations required

3. **MetalLB L2 Advertisements**:
   - `public-l2-ipv4`: Announces IPv4 pool on interface `ens18`
   - `public-l2-ipv6`: Announces IPv6 pool on interface `ens18`
   - Auto-assigns based on service IP family policy

## ClickHouse DNS Fix (Important!)

### Problem
Alpine Linux containers (used by ClickHouse) have DNS resolution issues in dual-stack Kubernetes clusters due to musl libc limitations. This causes:
- Init containers failing to download from github.com
- ClickHouse unable to resolve Zookeeper service names
- CrashLoopBackOff errors

### Solution
Custom DNS configuration in ClickHouseInstallation pod template:
```yaml
clickhouse:
  podTemplate:
    spec:
      dnsPolicy: None
      dnsConfig:
        nameservers:
          - 10.96.0.10  # CoreDNS service (IPv4 only)
        searches:
          - platform.svc.cluster.local
          - svc.cluster.local
          - cluster.local
        options:
          - name: single-request-reopen
          - name: ndots
            value: "5"
```

This configuration:
- Disables default dual-stack DNS (`dnsPolicy: None`)
- Uses IPv4-only nameserver (10.96.0.10 = CoreDNS service IP)
- Maintains Kubernetes service discovery via search domains
- Adds `single-request-reopen` for Alpine compatibility

## Installation Steps

### Fresh Install

1. **Create namespace**:
   ```bash
   kubectl create namespace platform
   ```

2. **Add SigNoz Helm repo**:
   ```bash
   helm repo add signoz https://charts.signoz.io
   helm repo update
   ```

3. **Install SigNoz**:
   ```bash
   helm install signoz signoz/signoz -n platform -f values.yaml
   ```

4. **Apply DNS fix** (required for dual-stack clusters):
   ```bash
   ./apply-dns-fix.sh
   ```

5. **Create IPv6 services**:
   ```bash
   kubectl apply -f signoz-ipv6-service.yaml
   ```

6. **Verify deployment**:
   ```bash
   kubectl get pods -n platform
   kubectl get svc -n platform -l shouldExpose=true
   ```

### Upgrade Existing Installation

1. **Upgrade with Helm**:
   ```bash
   helm upgrade signoz signoz/signoz -n platform -f values.yaml
   ```

2. **Reapply DNS fix** (Helm may reset ClickHouseInstallation):
   ```bash
   ./apply-dns-fix.sh
   ```

3. **Verify IPv6 services** (should persist):
   ```bash
   kubectl get svc -n platform | grep ipv6
   ```

## Troubleshooting

### ClickHouse CrashLoopBackOff

Check if DNS fix is applied:
```bash
kubectl get clickhouseinstallation signoz-clickhouse -n platform -o yaml | grep dnsPolicy
```

If not present, run:
```bash
./apply-dns-fix.sh
```

### No IPv6 LoadBalancer IP

Check MetalLB speaker logs:
```bash
kubectl logs -n metallb-system -l component=speaker --tail=50 | grep serviceAnnounced
```

Should see:
```
"event":"serviceAnnounced","ips":["fdde:5353:4242:141:1200:100:0:2"]
```

### Services Pending

Check MetalLB controller events:
```bash
kubectl describe svc signoz -n platform | tail -20
```

Common issues:
- ❌ **"unknown pool"**: Don't use `metallb.universe.tf/address-pool` annotation (deprecated)
- ✅ **Solution**: Remove annotation, let MetalLB auto-assign based on IP family

## MetalLB Configuration

### IP Address Pools

```yaml
# public-ipv4
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

```yaml
# public-ipv6
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

### L2 Advertisements

Both advertisements use interface `ens18`:
- `public-l2-ipv4`: Announces `public-ipv4` pool
- `public-l2-ipv6`: Announces `public-ipv6` pool

## Architecture Notes

- **Namespace**: `platform`
- **Storage**: `local-path` provisioner
- **CNI**: Cilium with kube-proxy replacement
- **LoadBalancer**: MetalLB L2 mode
- **Database**: ClickHouse (managed by ClickHouse Operator)
- **Coordination**: Zookeeper
- **Schema**: Managed by schema-migrator jobs (Helm hooks)

## Known Issues & Workarounds

1. **Helm doesn't support ClickHouse DNS config natively**
   - Workaround: Use `apply-dns-fix.sh` after Helm operations

2. **MetalLB doesn't support multiple pools in single annotation**
   - Workaround: Use separate SingleStack IPv6 services

3. **PreferDualStack services only get IPv4 LoadBalancer IPs**
   - Expected behavior: MetalLB assigns from first IP family (IPv4)
   - Solution: Create separate IPv6 services for IPv6 LoadBalancer IPs

## Testing Connectivity

### From External Network

```bash
# IPv4
curl http://10.10.141.33:8080

# IPv6
curl http://[fdde:5353:4242:141:1200:100:0:2]:8080
```

### From Within Cluster

```bash
# Via ClusterIP (IPv4)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://10.101.13.70:8080

# Via ClusterIP (IPv6)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://[fd00:10:96::6:a073]:8080
```

## Additional Resources

- [SigNoz Documentation](https://signoz.io/docs/)
- [SigNoz Helm Chart](https://github.com/SigNoz/charts)
- [MetalLB L2 Configuration](https://metallb.universe.tf/configuration/_advanced_l2_configuration/)
- [Kubernetes Dual-Stack Services](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
