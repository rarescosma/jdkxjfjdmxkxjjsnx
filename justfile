# just manual: https://github.com/casey/just/#readme

KEDA_V := "2.16.0"
PROM_STACK_V := "66.2.1"
PULSAR_V := "3.7.0"

_default:
  @just --list

# Set up the required helm repos.
[group('helm charts')]
helm_repos:
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add apache https://pulsar.apache.org/charts
    helm repo update

# Start a local kubernetes cluster via minikube.
[group('cluster')]
minikube driver='docker':
    minikube start --cpus=8 --memory=12g \
      --driver={{driver}} \
      --extra-config=scheduler.bind-address=0.0.0.0 \
      --extra-config=controller-manager.bind-address=0.0.0.0 \
      --extra-config=etcd.listen-metrics-urls=http://0.0.0.0:2381 \
      --container-runtime=containerd \
      --addons=metrics-server

# Route the service and pod CIDRs through minikube.
[group('cluster')]
route_minikube_cidrs:
    #!/usr/bin/env bash

    MINIKUBE_IP=$(minikube ip)

    # https://stackoverflow.com/a/61685899
    SVC_CIDR=$(echo '{"apiVersion":"v1","kind":"Service","metadata":{"name":"tst"},"spec":{"clusterIP":"1.1.1.1","ports":[{"port":443}]}}' | kubectl apply -f - 2>&1 | sed 's/.*valid IPs is //')
    POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' | head -1)

    sudo ip route add $SVC_CIDR via $MINIKUBE_IP
    sudo ip route add $POD_CIDR via $MINIKUBE_IP

# Point the system resolver to an in-cluster CoreDNS pod.
[group('hacks')]
hijack_dns:
    #!/usr/bin/env bash

    set -xeu

    KCTL="kubectl -n kube-system"
    SELECTOR="-l k8s-app=kube-dns"

    # 1. Apply the new CoreDNS config
    $KCTL apply -f "{{invocation_directory()}}/hacks/coredns-cm.yaml"

    # 2. Delete existing CoreDNS pods
    $KCTL delete pod $SELECTOR

    # 3. Wait for replacement
    $KCTL wait --for=condition=Ready pod $SELECTOR

    # 4. Get its IP
    dns_ip=$($KCTL get pod $SELECTOR -o jsonpath='{.items[0].status.podIP}')

    # 5. Chill until CoreDNS can actually resolve something
    while ! dig svc.cluster.local +timeout=1 @${dns_ip} >/dev/null 2>&1; do
      echo -n "."
    done

    # 6. Mangle resolv.conf
    sudo chattr -i /etc/resolv.conf
    printf "search svc.cluster.local\nnameserver $dns_ip\n" | sudo tee /etc/resolv.conf
    sudo chattr +i /etc/resolv.conf

# Install keda using helm.
[group('helm charts')]
keda helm_op="install":
    helm {{helm_op}} keda kedacore/keda \
      --namespace keda --create-namespace \
      --version {{KEDA_V}}

# Install kube-prometheus-stack using helm.
[group('helm charts')]
prom_stack helm_op="install":
    helm {{helm_op}} prom-stack prometheus-community/kube-prometheus-stack \
      --namespace monitoring --create-namespace \
      --version {{PROM_STACK_V}} \
      -f prom-stack/values.yaml

# Install pulsar using helm.
[group('helm charts')]
pulsar helm_op="install":
    kubectl get ns pulsar 2>/dev/null || kubectl create ns pulsar
    ./pulsar/helm-chart/scripts/pulsar/prepare_helm_release.sh -n pulsar -k pulsar-mini
    helm {{helm_op}} pulsar-mini apache/pulsar \
      --namespace pulsar \
      --version {{PULSAR_V}} \
      -f pulsar/values.yaml

# Deploy the example application from manifests.
[group('app')]
app:
    kubectl apply -f app/manifest.yaml -f app/scaled-objects/response-time.yaml
