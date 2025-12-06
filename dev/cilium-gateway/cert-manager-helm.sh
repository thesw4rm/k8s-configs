helm repo add jetstack https://charts.jetstack.io

helm template cert-manager jetstack/cert-manager --version v1.19 \
    --namespace cert-manager \
    --set crds.enabled=true \
    --create-namespace \
    --set config.apiVersion="controller.config.cert-manager.io/v1" \
    --set config.kind="ControllerConfiguration" \
    --set config.enableGatewayAPI=true \
    > cert-manager-deploy.yaml
