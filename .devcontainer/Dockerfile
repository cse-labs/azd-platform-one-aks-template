ARG IMAGE=dotnet
ARG VARIANT=bullseye-slim
ARG VERSION=0-7.0
ARG SOPS_VERSION=3.7.3
ARG TARGETARCH=amd64

FROM --platform=${TARGETARCH} mcr.microsoft.com/devcontainers/${IMAGE}:${VERSION}-${VARIANT}

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y xdg-utils && \
    curl -fsSL https://aka.ms/install-azd.sh | bash && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Install kustomize
RUN curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash \
    && mv kustomize /usr/local/bin/kustomize

# Install SOPS
RUN sudo wget https://github.com/getsops/sops/releases/download/v3.7.3/sops_3.7.3_amd64.deb
RUN dpkg -i sops_3.7.3_amd64.deb
RUN rm sops*

RUN sudo apt-get install xdg-utils

# Flux
RUN curl -s https://fluxcd.io/install.sh | bash