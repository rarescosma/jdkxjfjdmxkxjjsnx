# Podme Assignment

> ### Objective:
>
> Deploy a simple app with autoscaling enabled in a local Kubernetes cluster. Focus on Kubernetes deployments, autoscaling, and resource management. Additionally, deploy a message broker of your choice within the cluster. Implement monitoring using tools like Prometheus and Grafana (or alternatives) within the cluster.
>
> The GitHub repo should be provided with all configuration files and a short guide written in README.md.
> 
> ### Requirements:
>
> - Setup local Kubernetes cluster
> - Deploy the application with autoscaling
>    - The app doesn’t need to perform specific functions, we are focusing more on deployment and autoscaling
> - Deploy a Message Broker
>    - The app doesn’t need to interact with the message broker
> - Setup monitoring
>    - The app doesn’t need to expose metrics, but the monitoring tools should track cluster metrics such as CPU, Memory, etc.

## Prerequisites

- [just]
- [minikube] (do not start a cluster, just ensure the `minikube` binary is available)
- [helm](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)

## TL;DR

```
just minikube
just prom_stack
just keda
just app
just pulsar
```

## Guide

The core functionality of this repository is contained in the [`justfile`](justfile).

Without dwelling too much on the subject: we picked [just] as a modern-day alternative to `make`.

Invoking `just` without any targets simply lists all available recipes:

```shell
$ just

Available recipes:
    [app]
    app                          # Deploy the example application from manifests.

    [cluster]
    minikube driver='docker'     # Start a local kubernetes cluster via minikube.
    route_minikube_cidrs         # Route the service and pod CIDRs through minikube.

    [hacks]
    hijack_dns                   # Point the system resolver to an in-cluster CoreDNS pod.

    [helm charts]
    helm_repos                   # Set up helm repos.
    keda helm_op="install"       # Install keda using helm.
    prom_stack helm_op="install" # Install kube-prometheus-stack using helm.
    pulsar helm_op="install"     # Install pulsar using helm.
```

### 1. Setup local Kubernetes cluster

First, we'll use [minikube] to setup a local Kubernetes cluster:

```shell
just minikube
```

Because cluster monitoring is a later requirement, we'll need to 
instruct `minikube` to install the `metrics-server` addon.

This shows up in the recipe as the `--addons=metrics-server` argument.

> [!NOTE]
> By default this recipe uses the `docker` driver for minikube.
> To experiment with other [drivers](https://minikube.sigs.k8s.io/docs/drivers/), 
> simply pass the driver name as a positional argument to the recipe, e.g.:
>
> ```shell
> just minikube kvm
> ```

#### 1.1. (optional) Route the pod and service CIDRs through the minikube IP

Normally, exposing services running in a minikube cluster can be achieved 
with the `minikube service` command.

However, if we plan to access service and pod IPs directly, it might benefit
us to route the service and pod CIDRs through the IP assigned to the minikube 
VM:

```shell
just route_minikube_cidrs
```

### 2. Deploy the monitoring and autoscaling stacks

For demonstration purposes we chose to autoscale the application based on 
custom Prometheus metrics.

For this, we'll use [keda], an event-driven autoscaling framework that
abstracts over and automatically manages the lifecycle of 
[HorizontalPodAutoscaler] resources.

Keda will pick up metrics from a Prometheus instance that we'll deploy using
the [kube-prometheus-stack] Helm chart, so let's start with that.

#### 2.0. Add the helm repositories and update the index

```shell
just helm_repos
```

#### 2.1. Deploy the `kube-prometheus-stack` chart

```shell
just prom_stack
```

The chart is deployed with a couple of configuration overrides from [`prom-stack/values.yaml`](prom-stack/values.yaml).

What we're overriding:

- disable alertmanager
- specify resource requests and limits for all components
- allow the prometheus operator to pick up arbitrary, non-Helm-managed, pod and service monitors

Once the stack has finished deploying, the grafana instance should be accessible via:

```shell
minikube service -n monitoring prom-stack-grafana
```

#### 2.2. Deploy the `keda` chart

```shell
just keda
```

> [!TIP]
> Targets from the `helm charts` group support a `helm_op` argument.
> This allows us to switch from `helm install` to `helm upgrade`, should
> we decide to make any changes to the `values.yaml` configuration files and/or
> pass different variables to the helm command line:
>
> ```
> $ just keda upgrade
> ```

### 3. Deploy the example application

```shell
just app
```

The app is deployed simply from YAML manifests. The main [`manifests.yaml`](app/manifests.yaml)
file contains definitions for its namespace, deployment, service and service monitor.

To illustrate autoscaling, we also define a [`ScaledObject`](https://keda.sh/docs/2.16/concepts/scaling-deployments/) 
that will act on a custom metric - a fake representation of the application's request latency.

### 4. Deploy the message broker

We chose [Apache Pulsar] as our message broker. It uses a push-based consumption model
(consumers have to ACK/nACK the messages), and an index-based storage architecture.

Since we're running this demo on a local cluster, we configure Pulsar to have as small
of a resource footprint as possible via the Helm chart [`values.yaml`](pulsar/values.yaml) file.

The official documentation mentions a prerequisite script that needs to run before the chart 
itself, which is dependent on the chart git repository. This had the unfortunate effect of us 
having to bundle it as a git submodule.

To deploy Pulsar:

```shell
git submodule update --init --recursive 

just pulsar
```

The [Pulsar documentation](https://pulsar.apache.org/docs/next/getting-started-helm/#step-3-use-pulsar-client-to-produce-and-consume-messages) 
then offers a guide on how we can use the client to test message production and consumption.

[just]: https://github.com/casey/just/?tab=readme-ov-file#pre-built-binaries
[minikube]: https://minikube.sigs.k8s.io/docs/start
[keda]: https://keda.sh/docs/2.16/concepts/
[kube-prometheus-stack]: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
[HorizontalPodAutoscaler]: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
[Apache Pulsar]: https://pulsar.apache.org/docs/4.0.x/concepts-overview/
