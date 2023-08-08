# Triggering a deployment

Once the application has been registered with the Coral platform, the application can be deployed repeatedly. The workflow suggested below takes advantage of the secrets configured during the registration process and greatly simplifies the process.

## Create a workfow

Create a new workflow in the application repo using the following yaml definition:

``` yaml
name: "Trigger App Re-Render"

on:
  workflow_dispatch:

jobs:
  log-the-inputs:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Rendering workflow in the control plane repo
        run: |
          echo "Triggering workflow run on: $CP_REPO - $CP_REF"
          export GH_REPO=$CP_REPO
          GITHUB_TOKEN=$CP_REPO_TOKEN gh workflow run "$WORKFLOW" --ref "$CP_REF"
        env:
          CP_REPO_TOKEN: ${{ secrets.CP_REPO_TOKEN }}
          CP_REPO: ${{ secrets.CP_REPO }}
          CP_REF: ${{ secrets.CP_REF}}
          WORKFLOW: 'transform.yaml'
```

## Trigger the workflow

Every time you trigger this workflow, the Coral transform.yaml workflow will be triggered in the control plane repo and changes in the registered application/branch will be picked up by the platform and deployed accordingly.

## Other ways to trigger the workflow

The workflow above is configured with a `workflow_dispatch` event. In other words, it can only be triggered manually. You can tailor the workflow to your needs by changing the events that trigger it. You can refer to the [documentation in github](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows) for information on events that can trigger this workflow.

## See Also

* [Introduction](../README.md)
* [Registering an application with the Coral platform](application-registration.md)
