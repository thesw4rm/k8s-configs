#!/bin/bash
# Apply DNS fix to ClickHouse after Helm operations
# This is needed because Alpine containers have DNS issues in dual-stack clusters

echo "Applying DNS fix to ClickHouse..."
kubectl patch clickhouseinstallation signoz-clickhouse -n platform --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/templates/podTemplates/0/spec/dnsPolicy",
    "value": "None"
  },
  {
    "op": "add",
    "path": "/spec/templates/podTemplates/0/spec/dnsConfig",
    "value": {
      "nameservers": ["10.96.0.10"],
      "searches": [
        "platform.svc.cluster.local",
        "svc.cluster.local",
        "cluster.local"
      ],
      "options": [
        {"name": "single-request-reopen"},
        {"name": "ndots", "value": "5"}
      ]
    }
  }
]'

echo "Restarting ClickHouse pod..."
kubectl delete pod -n platform chi-signoz-clickhouse-cluster-0-0-0

echo "DNS fix applied. Waiting for ClickHouse to be ready..."
kubectl wait --for=condition=ready pod -n platform -l app.kubernetes.io/component=clickhouse --timeout=120s

echo "ClickHouse is ready!"
