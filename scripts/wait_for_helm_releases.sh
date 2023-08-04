#!/bin/bash

set -e

BB_HELM_RELEASE=$(kubectl get HelmRelease  --ignore-not-found -n bigbang bigbang)

if ! [[ "$BB_HELM_RELEASE" ]]; then
  sleep 2m
fi

declare -a helm_releases=(bigbang gatekeeper istio-operator istio monitoring fluent-bit jaeger cluster-auditor ek eck-operator kiali)
WAIT_TIMEOUT=900

for release in "${helm_releases[@]}"
do
  echo "Checking for status of helm release $release"
  kubectl wait --for=condition=Ready=true --timeout "${WAIT_TIMEOUT}s" -n bigbang HelmRelease/$release
  echo "Ready state for helm release is set to true"
done
