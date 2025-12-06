helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 
helm repo update
helm upgrade --install infisical infisical-helm-charts/infisical-standalone --values ./infisical/values.yaml 
