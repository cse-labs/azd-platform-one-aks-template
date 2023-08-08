#!/bin/bash

PWD=$(dirname "$0")

export AKV_GPG_SECRET_NAME=sops-gpg
export AKV_ISTIO_CRT_SECRET_NAME=istio-gw-crt
export AKV_ISTIO_KEY_SECRET_NAME=istio-gw-key
export K8_NAMESPACE=bigbang
DOMAIN=bigbang.dev

. $PWD/scripts/common.sh

function createIstioCerts() {
    AKV_CERT_EXISTS_CHECK=$(az keyvault secret list --vault-name ${AZURE_KEY_VAULT_NAME} --query "contains([].id, '${AZURE_KEY_VAULT_ENDPOINT}secrets/${AKV_ISTIO_CRT_SECRET_NAME}')")

    if [[ "$AKV_CERT_EXISTS_CHECK" = true ]]; then
      echo "Skip creating istio certificate as it already exists";
    else
      ## Create Certs
      $PWD/scripts/create-root-cert.sh
      $PWD/scripts/create-domain-cert.sh $DOMAIN
      ISTIO_GW_CRT=$(cat ${DOMAIN}.crt | base64 -w0)
      ISTIO_GW_KEY=$(cat ${DOMAIN}.key | base64 -w0)
      ## Store in AKV as secrets
      az keyvault secret set --name ${AKV_ISTIO_CRT_SECRET_NAME} --vault-name ${AZURE_KEY_VAULT_NAME} --encoding base64 --value "$ISTIO_GW_CRT" > /dev/null
      az keyvault secret set --name ${AKV_ISTIO_KEY_SECRET_NAME} --vault-name ${AZURE_KEY_VAULT_NAME} --encoding base64 --value "$ISTIO_GW_KEY" > /dev/null
      rm ${DOMAIN}.* ca.*
    fi;

    azd env set AKV_ISTIO_CRT_SECRET_NAME $AKV_ISTIO_CRT_SECRET_NAME
    azd env set AKV_ISTIO_KEY_SECRET_NAME $AKV_ISTIO_KEY_SECRET_NAME
    azd env set HOSTNAME $DOMAIN
}

function createPgpPrivateKey() {
  azd env set AKV_GPG_SECRET_NAME $AKV_GPG_SECRET_NAME
  AKV_PGP_EXISTS_CHECK=$(az keyvault secret list --vault-name ${AZURE_KEY_VAULT_NAME} --query "contains([].id, '${AZURE_KEY_VAULT_ENDPOINT}secrets/${AKV_GPG_SECRET_NAME}')")
  
  if [[ "$AKV_PGP_EXISTS_CHECK" = true ]]; then
    echo "Skip creating GPG key as it already exists";
  else
    ## Create GPG Key
    echo "Creating GPG certificate ${AKV_GPG_SECRET_NAME}"
    $PWD/scripts/create-gpg-key.sh ${AKV_GPG_SECRET_NAME} ${AZURE_KEY_VAULT_NAME} ${AKV_GPG_SECRET_NAME}
  fi;
}

function createInitialNamespaces() {
  azd env set K8_NAMESPACE $K8_NAMESPACE

  for namespace in flux-system $K8_NAMESPACE; do
    NS_EXISTS=$(kubectl get namespace $namespace --ignore-not-found);

    if ! [[ "$NS_EXISTS" ]]; then
      echo -e "\n\e[36m###\e[33m 📦 Creating namespaces $namespace\e[39m"
      kubectl create namespace $namespace
    fi;
  done;
}

sourceAzdEnvVars

echo "Retrieving cluster credentials"
az aks get-credentials --resource-group ${AZURE_RESOURCE_GROUP} --name ${AZURE_AKS_CLUSTER_NAME}

createIstioCerts
createPgpPrivateKey
createInitialNamespaces

$PWD/scripts/deploy-bb-to-aks.sh
