#!/bin/bash

PWD=$(dirname "$0")

. $PWD/scripts/common.sh

function enableAzureSubPlugins() {
    echo "Making sure that the features are registered"
    az extension add --upgrade --name aks-preview
    az provider register --namespace Microsoft.ContainerService
    az provider register --namespace Microsoft.OperationsManagement
}

function githubAuthFlow() {
  GH_PAT=$GITHUB_TOKEN

  if [[ -z "$GH_PAT" ]]; then
    echo "Prompting for GH Auth given GITHUB_TOKEN is undefined"
    gh auth login --scopes read:org,repo,workflow
  else
    unset GITHUB_TOKEN # Clear the token to verify
    gh auth logout # Logout to verify 
    tmpfile=$(mktemp /tmp/token_tmp.XXXXXX)
    echo $GH_PAT > $tmpfile
    gh auth login --with-token < $tmpfile
    gh auth status
  fi

  gh auth setup-git
  azd env set GITHUB_TOKEN $(gh auth token)
}

function getIronBankCreds() {
  if [[ -z "${P1_REGISTRY_USERNAME}" ]]; then
    read -r -p "What's the Iron Bank Login Username for P1_REGISTRY_USERNAME? " input
    export P1_REGISTRY_USERNAME=$input

    read -sp "What's the Iron Bank Login Password for P1_REGISTRY_PASSWORD? " input
    export P1_REGISTRY_PASSWORD=$input

    azd env set P1_REGISTRY_USERNAME $P1_REGISTRY_USERNAME
    azd env set P1_REGISTRY_PASSWORD $P1_REGISTRY_PASSWORD
  fi
}

function gitopsRepositorySetup() {
  if [[ -z "${GITOPS_REPO}" ]]; then
    read -r -p "Which GitOps Repo should be used for this project <owner>/<repository> ex. 'erikschlegel/k8-gitops-manifests'?" input
    export GITOPS_REPO=$input
    azd env set GITOPS_REPO $GITOPS_REPO
  fi

  REPO_EXISTS_CHECK=$(gh repo view $GITOPS_REPO --json name | jq '.name')
  if [[ -z "${REPO_EXISTS_CHECK}" ]]; then
    read -r -p "Repository: ${GITOPS_REPO} doesn't exist and will need to be created. Please confirm (Y/N)?" input
    export ANSWER=$input

    if [[ "${ANSWER^^}" -eq "Y" ]]; then
      # Create the new Github Repository
      gh repo create $GITOPS_REPO --private --add-readme
    else
      echo "Exiting run as this project requires a GitOps Repository" 1>&2
      unset GITOPS_REPO
      exit 1
    fi
  fi

  # If we haven't created the GitOps Working Directory
  if [ -z "${GITOPS_CWD}" ] || [ ! -d "${GITOPS_CWD}" ]; then
    # Create the working directory for git operations (ie add, commit, push)
    tmp_dir=$(mktemp -d -t go-XXXXXXXXX)
    export GITOPS_CWD=$tmp_dir
    azd env set GITOPS_CWD $tmp_dir

    GITOPS_REPO_URL=$(gh repo view $GITOPS_REPO --json url | jq '.url' | tr -d '"')
    GITOPS_REPO_OWNER=$(gh repo view $GITOPS_REPO  --json owner | jq '.owner.login' | tr -d '"')
    azd env set GITOPS_REPO_URL $GITOPS_REPO_URL
    azd env set GITHUB_USERNAME $GITOPS_REPO_OWNER

    # Clone the Gitops Repository locally (to the tmp working directory)
    git clone ${GITOPS_REPO_URL} $GITOPS_CWD
  elif [ -d "${GITOPS_CWD}/.git" ]; then # Otherwise verify the CWD has been cloned from GH
    # Rebase local with remote
    git -C $GITOPS_CWD pull
  else
    echo "Fatal Error: working directory ${GITOPS_CWD} is not setup as a git directory. Unset the environment variable GITOPS_CWD and rerun the deployment."
    exit 1
  fi
}

enableAzureSubPlugins
githubAuthFlow
getIronBankCreds
sourceAzdEnvVars
gitopsRepositorySetup