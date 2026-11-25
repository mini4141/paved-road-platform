FROM python:3.12-slim
ARG HELM_VERSION=v3.19.0
ARG KUBECTL_VERSION=v1.34.1
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar -xz -C /usr/local/bin --strip-components=1 linux-amd64/helm \
 && curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl
RUN pip install --no-cache-dir ansible-core==2.18.* kubernetes==31.* PyYAML jsonpatch
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections
WORKDIR /repo/bootstrap
