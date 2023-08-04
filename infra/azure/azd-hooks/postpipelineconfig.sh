#!/bin/bash
PWD=$(dirname "$0")

. $PWD/scripts/common.sh

GIT_CONTROLLER_URL=$(git remote get-url origin)

pre_validation () {
  local git_url=$1

  [[ ! -z $git_url ]] && {
        echo "💥 Error! Git remote is missing. This script should run after azd pipeline config!"
        exit
  }

  for varName in P1_REGISTRY_USERNAME P1_REGISTRY_PASSWORD GITHUB_TOKEN GITOPS_REPO; do
    varVal=$(eval echo "\${$varName}")
    [[ -z $varVal ]] && {
      echo "💥 Error! Required variable '$varName' is not set!"
      varUnset=true
    }
  done
}

sourceAzdEnvVars
pre_validation
GIT_CONTROLLER_REPO=$(echo $GIT_CONTROLLER_URL | sed 's|https://github.com/||')

gh secret set P1_REGISTRY_PASSWORD --body "${P1_REGISTRY_PASSWORD}" --repo $GIT_CONTROLLER_REPO
gh secret set GH_TOKEN --body "${GITHUB_TOKEN}" --repo $GIT_CONTROLLER_REPO

for env in GITOPS_REPO P1_REGISTRY_USERNAME; do
  echo "setting env variable: ${env} in repo: ${GIT_CONTROLLER_REPO}"
  envVal=$(eval echo "\${$env}")
  gh variable set $env --body "${envVal}" --repo $GIT_CONTROLLER_REPO
done
