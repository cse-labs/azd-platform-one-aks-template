#!/bin/bash
# set -e

#
# This is a script that deploys BigBang into Kubernetes
#
PWD=$(dirname "$0")
export BB_TAG="2.5.0"
export GITOPS_REPO_PATH=/environments/${AZURE_ENV_NAME}/src/manifests
BB_REPO="https://repo1.dso.mil/platform-one/big-bang/bigbang.git"
TEMPLATE_ROOT=$PWD/../../../../src/platform-dialtone/manifests/
BB_DEPLOYMENT_YAML_FILENAME=bigbang.yaml

indent() {
  local indentSize=2
  local indent=1
  if [ -n "$1" ]; then indent=$1; fi
  pr -to $(($indent * $indentSize))
}

render_template() {
  local template=$1
  local template_source=$2
  echo "Rendering template: $template from $template_source"
  
  YAML_DESTINATION=$(echo "${GITOPS_DIR}/${template}" | sed 's|.template||')

  mkdir -p $(dirname ${YAML_DESTINATION})
  envsubst <$template_source >$YAML_DESTINATION

  echo "Rendered template: ${template_source} to folder ${YAML_DESTINATION}"
}

pre_validation () {
  for cmd in gpg sops kubectl kustomize; do
    which $cmd >/dev/null || {
      echo -e "💥 Error! Command $cmd not installed"
      exit 1
    }
  done

  for varName in AKV_GPG_SECRET_NAME K8_NAMESPACE AZURE_ENV_NAME GITOPS_CWD P1_REGISTRY_USERNAME P1_REGISTRY_PASSWORD AZURE_KEY_VAULT_ENDPOINT AKV_ISTIO_CRT_SECRET_NAME AKV_ISTIO_KEY_SECRET_NAME; do
    varVal=$(eval echo "\${$varName}")
    [[ -z $varVal ]] && {
      echo "💥 Error! Required variable '$varName' is not set!"
      varUnset=true
    }
  done
  [[ $varUnset ]] && exit 1
}

retrieveSecrets() {
  export ISTIO_GW_CRT=$(az keyvault secret show --id ${AZURE_KEY_VAULT_ENDPOINT}secrets/${AKV_ISTIO_CRT_SECRET_NAME} --query 'value' -o tsv | base64 -d | indent 8)
  export ISTIO_GW_KEY=$(az keyvault secret show --id ${AZURE_KEY_VAULT_ENDPOINT}secrets/${AKV_ISTIO_KEY_SECRET_NAME} --query 'value' -o tsv | base64 -d | indent 8)

  az keyvault secret show --id ${AZURE_KEY_VAULT_ENDPOINT}secrets/${AKV_GPG_SECRET_NAME} --query 'value' -o tsv | base64 --decode >pgp.asc
  gpg --import pgp.asc
  rm pgp.asc

  export FINGER_PRINT=$(gpg -K $AKV_GPG_SECRET_NAME | sed -e 's/ *//;2q;d;')
}

commitManifestsToGitOpsRepo() {
  pushd ${GITOPS_CWD}

  git add -A
  # We dont want to check in the GitOps Repo Definition as it should be run via kubectl
  git reset -- ${GITOPS_DIR}/${BB_DEPLOYMENT_YAML_FILENAME}
  git commit -m "Updated K8 operational manifests by AZD deployment script $(date)"
  git push -f

  popd
}

installFluxAgent() {
  IS_FLUX_INSTALLED=$(kubectl get deployment --ignore-not-found -n flux-system helm-controller)
  
  # kubectl create secret docker-registry private-registry --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD --docker-email=DOCKER_EMAIL

  if [[ "$IS_FLUX_INSTALLED" ]]; then
    echo "Skip initializing flux as it's already installed"
  else
    bb_cwd=$(mktemp -d -t bb-XXXXXXXXX)
    echo -e "\n\e[36m###\e[33m 🚀 Installing flux from bigbang install script\e[39m"
    git clone -b $BB_TAG --single-branch $BB_REPO $bb_cwd/bigbang
    pushd $bb_cwd/bigbang
    ./scripts/install_flux.sh \
      --registry-username "${P1_REGISTRY_USERNAME}" \
      --registry-password "${P1_REGISTRY_PASSWORD}" \
      --registry-email bigbang@bigbang.dev
    popd
    rm -rf $bb_cwd

    # Wait for flux to complete
    kubectl get deploy -o name -n flux-system | xargs -n1 -t kubectl rollout status -n flux-system
  fi

  echo -e "\n\e[36m###\e[33m 🔨 Removing flux-system 'allow-scraping' network policy\e[39m"
  # If we don't remove this then kustomization won't be able to reconcile!
  CHECK_NETWORK_POLICY=$(kubectl get netpol --ignore-not-found -n flux-system allow-scraping)

  if [[ "$CHECK_NETWORK_POLICY" ]]; then
    echo -e "\n\e[36m###\e[33m 🔨 Removing flux-system 'allow-scraping' network policy\e[39m"
    kubectl delete netpol -n flux-system allow-scraping
  else
    echo "Network policy allow-scraping doesn't exist";
  fi
}

echo -e "\n\e[34m╔════════════════════════════════════════╗
║   \e[35mBigBang Automated Deployer v0.2 🚀\e[34m   ║
╚════════════════════════════════════════╝\e[39m"

pre_validation
export GITOPS_DIR=${GITOPS_CWD}/${GITOPS_REPO_PATH}
azd env set GITOPS_DIR $GITOPS_DIR

kubectl version
kubectl version >/dev/null 2>&1 || {
  echo -e "💥 Error! kubectl is not pointing at a cluster, configure KUBECONFIG or $HOME/.kube/config"
  exit 1
}

echo
echo -e "You are connected to Kubenetes: $(kubectl config view | grep 'server:' | sed 's/\s*server://')"

retrieveSecrets

echo "Rendering K8 Manifest Templates"
for template in $(find $TEMPLATE_ROOT -type f -name "*.template");
do
  DESTINATION=$(echo "$template" | sed 's|'${TEMPLATE_ROOT}'||g')
  render_template $DESTINATION $template
done;

for sops_dec in $(find $GITOPS_DIR -type f -name "secrets.*");
do
  echo "Encrypting SOPS file: $sops_dec"
  sops --encrypt --in-place --encrypted-regex '^(data|stringData)$' --pgp $FINGER_PRINT $sops_dec
done;

commitManifestsToGitOpsRepo

echo -e "\n\e[36m###\e[33m 🔐 Creating secret sops-gpg in $K8_NAMESPACE\e[39m"
gpg --export-secret-key --armor ${FINGER_PRINT} | kubectl create secret generic ${AKV_GPG_SECRET_NAME} -n $K8_NAMESPACE --from-file=bigbangkey.asc=/dev/stdin

installFluxAgent

echo -e "\n\e[36m###\e[33m 💣 Deploying BigBang for environment: ${AZURE_ENV_NAME} !\e[39m"
# Setup K8 generic secret so that the cluster has permission to poll / pull manifests from the GitOps repository
kubectl create secret generic private-git --namespace ${K8_NAMESPACE} --from-literal=username=${GITHUB_USERNAME} --from-literal=password=${GITHUB_TOKEN}
kubectl apply -f "${GITOPS_DIR}/${BB_DEPLOYMENT_YAML_FILENAME}"