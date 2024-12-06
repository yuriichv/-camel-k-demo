#!/bin/bash

# Global variables
REGISTRY_DOMAIN="registry.local"

main(){
  echo "used: $0 $*"
  case "$1" in
    k3s) k3s_install ;;
    kubectl) kubectl_install ;;
    helm) helm_install ;;
    harbor) harbor_install ;;
    registry) registry_install ;;
    camel-k) camel_k_install ;;
    dns-config) dns_config ;;
    kamel) kamel_install ;;
    all)
      k3s_install
      kubectl_install
      helm_install
      registry_install
      camel_k_install
      dns_config
      kamel_install
      ;;
    *)
      echo "Usage: $0 {k3s|kubectl|helm|registry|camel-k|dns-config|kamel|all}"
      exit 1
      ;;
  esac
}

# https://docs.k3s.io/installation/configuration
k3s_install(){
  command -v k3s >/dev/null 2>&1 && echo "K3s already installed, skipping..." && return
  curl https://get.k3s.io/ -o k3s-install.sh
  chmod +x k3s-install.sh
  ./k3s-install.sh
}

# https://kubernetes.io/ru/docs/tasks/tools/install-kubectl/
kubectl_install(){
  command -v kubectl >/dev/null 2>&1 && echo "Kubectl already installed, skipping..." && return
  local kubectl_url="https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  local user_id=$(id -u)
  local group_id=$(id -g)

  curl -LO "$kubectl_url"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null
  test -d ~/.zsh.d && echo 'source <(kubectl completion zsh)' >>~/.zsh.d/kubectl
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown "$user_id:$group_id" ~/.kube/config
}

# https://helm.sh/docs/
helm_install(){
  command -v helm >/dev/null 2>&1 && echo "Helm already installed, skipping..." && return
  local helm_url="https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz"

  curl "$helm_url" | tar xzf - linux-amd64/helm --strip-components=1
  sudo mv helm /usr/local/bin
}

# Camel-k prerequisite: Registry
harbor_install(){
  local harbor_namespace="harbor"
  kubectl get namespace "$harbor_namespace" >/dev/null 2>&1 && echo "Harbor already installed in namespace '$harbor_namespace', skipping..." && return

  local harbor_hostname=$REGISTRY_DOMAIN
  local harbor_admin_password="admin"

  test -f "$harbor_hostname.key" || openssl req -x509 -newkey rsa:4096 -sha256 -days 1365 -nodes \
    -keyout "$harbor_hostname.key" -out "$harbor_hostname.crt" -subj "/CN=$harbor_hostname"

  kubectl create secret tls harbor-tls --cert="$harbor_hostname.crt" --key="$harbor_hostname.key" \
    --namespace $harbor_namespace --dry-run=client -o yaml | kubectl apply -f -

  helm repo add harbor https://helm.goharbor.io
  helm upgrade harbor harbor/harbor --install --namespace $harbor_namespace --create-namespace \
    --set expose.ingress.hosts.core=$harbor_hostname \
    --set expose.tls.secretName=harbor-tls \
    --set persistence.enabled=false \
    --set registry.enabled=true \
    --set harborAdminPassword=$harbor_admin_password
}

# https://github.com/twuni/docker-registry.helm
# curl -u admin:admin http://registry.local/v2/_catalog
registry_install(){
  local registry_namespace="registry"
  kubectl get namespace "$registry_namespace" >/dev/null 2>&1 && echo "Registry already installed in namespace '$registry_namespace', skipping..." && return

  local registry_hostname=$REGISTRY_DOMAIN
  local registry_user="admin"
  local registry_password_hash='$2y$05$vvdOTiHTcqpWRyhd9tNJ6ev84kZDdAHx8qU.ZQwwqhBaP65yg3rqy'
  local tls_config="registry-san.conf"

  test -f "$registry_hostname.key" || openssl req -x509 -newkey rsa:4096 -sha256 -days 1365 -nodes \
    -keyout "$registry_hostname.key" -out "$registry_hostname.crt" -subj "/CN=$registry_hostname" \
    -config $tls_config -extensions req_ext

  sudo cp "$registry_hostname.crt" /usr/local/share/ca-certificates
  sudo update-ca-certificates
  sudo systemctl restart k3s.service

  kubectl create secret tls registry-tls --cert="$registry_hostname.crt" --key="$registry_hostname.key" --namespace $registry_namespace
  helm repo add twuni https://helm.twun.io
  helm upgrade --install docker-registry twuni/docker-registry --namespace $registry_namespace --create-namespace \
    --set ingress.enabled=true \
    --set ingress.className=traefik \
    --set persistence.enabled=true \
    --set persistence.size=1Gi \
    --set persistence.storageClass=local-path \
    --set secrets.htpasswd="$registry_user:$registry_password_hash" \
    --set ingress.hosts[0]=$registry_hostname \
    --set tls.secretName=registry-tls
}

# DNS Config
dns_config(){
  local dns_configmap_name="coredns-custom"
  local dns_namespace="kube-system"
  local ip="192.168.58.8"
  local domains=("$REGISTRY_DOMAIN" "linux.local")

  kubectl get configmap $dns_configmap_name -n $dns_namespace >/dev/null 2>&1 && echo "DNS ConfigMap '$dns_configmap_name' already exists, skipping..." && return

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $dns_configmap_name
  namespace: $dns_namespace
data:
  linux.local.server: |
    linux.local:53 {
      hosts {
        $ip linux.local
        fallthrough
      }
    }
  registry.local.server: |
    registry.local:53 {
      hosts {
        $ip $REGISTRY_DOMAIN
        fallthrough
      }
    }
EOF
  echo "DNS ConfigMap '$dns_configmap_name' applied successfully."
}

# https://camel.apache.org/camel-k/next/installation/installation.html
camel_k_install(){
  local camel_k_namespace="camel-k"
  kubectl get namespace "$camel_k_namespace" >/dev/null 2>&1 && echo "Camel K already installed in namespace '$camel_k_namespace', skipping..." && return

  local camel_k_registry_address="docker-registry.svc.cluster.local:5000"
  local registry_hostname=$REGISTRY_DOMAIN
  local registry_user="admin"
  local registry_password="admin"
  local docker_email="admin@example.com"

  helm repo add camel-k https://apache.github.io/camel-k/charts/
  helm upgrade camel-k camel-k/camel-k --install --namespace $camel_k_namespace --create-namespace --set platform.build.registry.address=$camel_k_registry_address

  kubectl create secret docker-registry registry-secret \
    --docker-server=$registry_hostname \
    --docker-username=$registry_user \
    --docker-password=$registry_password \
    --docker-email=$docker_email \
    --namespace=$camel_k_namespace
}

# https://camel.apache.org/camel-k/next/installation/installation.html
kamel_install(){
  command -v kamel >/dev/null 2>&1 && echo "Kamel already installed, skipping..." && return
  local kamel_url="https://github.com/apache/camel-k/releases/download/v2.4.0/camel-k-client-2.4.0-linux-amd64.tar.gz"

  curl -L -O "$kamel_url"
  sudo tar -xzf camel-k-client-2.4.0-linux-amd64.tar.gz -C /usr/local/bin && rm camel-k-client-2.4.0-linux-amd64.tar.gz
  sudo chmod +x /usr/local/bin/kamel
}

main $@

