# CAI SparklyR Runtime

## Objective

This repository shows how to build custom Sparkly R runtimes on top of the Cloudera AI R 4.5 PBJ Workbench base image, publish them to a container registry, and import them into the CAI Runtime Catalog.

Two examples are provided:

| Path | Editor in CAI | Use when |
|------|---------------|----------|
| [`Dockerfile`](Dockerfile) | **Workbench** | Extend the default PBJ Workbench with sparklyr only |
| [`other/Dockerfile_rstudio`](other/Dockerfile_rstudio) | **RStudio** | Add RStudio Server + sparklyr as a third-party editor |

Both follow the same high-level flow:

1. [Choose a Dockerfile](#1-choose-a-dockerfile)
2. [Build and push the image](#2-build-and-push-the-image)
3. [Add registry credentials in CAI (private registries only)](#3-add-registry-credentials-in-cai-private-registries-only)
4. [Import the runtime in the catalog](#4-import-the-runtime-in-the-catalog)
5. [Run a test session](#5-run-a-test-session)

This demo is intended as a general reference for CAI admins and users building custom R runtimes on-premises or in the cloud.

## Requirements

* A CAI Workbench on Cloudera Public Cloud Runtime 7.3.1 or above (or equivalent on-prem CAI).
* Docker installed locally (or a CI build host with access to your registry).
* Access to `docker.repository.cloudera.com` for the base runtime image (or a saved copy loaded locally).
* A container registry reachable from your CAI environment (AWS ECR, ECR Public, or another registry).

On Apple Silicon / arm64 Macs, build with `--platform linux/amd64` — CAI runtimes run on amd64.

---

## 1. Choose a Dockerfile

### Option A — Workbench + sparklyr (minimal)

The root [`Dockerfile`](Dockerfile) installs sparklyr on the standard PBJ Workbench R 4.5 runtime and sets runtime metadata for the **Workbench** editor.

Build context: repository root (`.`).

### Option B — RStudio + sparklyr

The [`other/Dockerfile_rstudio`](other/Dockerfile_rstudio) adds RStudio Server and sparklyr on the same base image and sets metadata for the **RStudio** editor. Supporting files live in `other/`:

* `other/rstudio-cml` — launcher symlinked to `/usr/local/bin/ml-runtime-editor`
* `other/rserver.conf` — RStudio config (`www-port=8090` must match `CDSW_APP_PORT`)

Build context: `other/` (see build commands below).

**Do not build RStudio from the repository root.** Run the commands below from the repo root, but always pass `-f other/Dockerfile_rstudio` and use `other` as the build context (the last argument to `docker build`). Building with `docker build .` at the repo root produces the Workbench image only.

**Important:** Pin a real RStudio Server version at build time. There is no `latest` package on Posit's download site. Check [Posit RStudio Server downloads](https://posit.co/download/rstudio-server/) for the current Ubuntu 22 / amd64 `.deb` filename.

The CAI engineering team maintains official base runtimes in [cloudera/ml-runtimes](https://github.com/cloudera/ml-runtimes).

Runtime metadata (`ML_RUNTIME_*` env vars and Docker labels) is mandatory and must uniquely identify each build. See [Cloudera runtime metadata documentation](https://docs.cloudera.com/machine-learning/cloud/runtimes/topics/ml-metadata-for-custom-runtimes.html).

Bump `ML_RUNTIME_MAINTENANCE_VERSION` and `ML_RUNTIME_FULL_VERSION` (and your image tag) for each new build you import into the catalog.

---

## 2. Build and push the image

Replace placeholders below with your account ID, region, and repository name.

### Workbench runtime

```bash
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=123456789012
export ECR_REPO=cai-sparklyr-rm
export IMAGE_TAG=2026.03.2

# Create repository (skip if it already exists)
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# Authenticate and push
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build --platform linux/amd64 -t $ECR_REPO:$IMAGE_TAG .

docker tag $ECR_REPO:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
```

### RStudio runtime

```bash
export RSTUDIO_VERSION=2026.04.0-526   # verify at posit.co/download/rstudio-server/
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=123456789012
export ECR_REPO=cai-rstudio-sparklyr
export IMAGE_TAG=2026.03.3

# Optional: confirm the .deb exists before building (~150 MB, not a few hundred bytes)
curl -fIL "https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb"

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build --platform linux/amd64 \
  --build-arg RSTUDIO_VERSION=$RSTUDIO_VERSION \
  -t $ECR_REPO:$IMAGE_TAG \
  -f other/Dockerfile_rstudio other

docker tag $ECR_REPO:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
```

### Public registry alternative

If you use a **public** registry (for example AWS ECR Public), you can skip Docker credentials in CAI for import. Authenticate with `aws ecr-public get-login-password --region us-east-1` and push to your public URI, then import the full image path including the tag into the Runtime Catalog.

---

## 3. Add registry credentials in CAI (private registries only)

For **private** registries (standard AWS ECR, on-prem registries, etc.):

**Site Administration → Runtimes → Docker Credentials → Add**

| Field | Example |
|-------|---------|
| Name | `sparklyr-runtime-credentials` |
| Server | `123456789012.dkr.ecr.us-west-2.amazonaws.com/my-repo/` |
| Username | `AWS` (for ECR) or per your registry |
| Password | `aws ecr get-login-password --region us-west-2` (ECR tokens expire; refresh when re-importing) |

Public images do not require this step.

---

## 4. Import the runtime in the catalog

**Site Administration → Runtimes → Runtime Catalog → Add Runtime**

* Select your registry credentials (private registries only).
* Enter the full image URI including tag, for example:
  * `123456789012.dkr.ecr.us-west-2.amazonaws.com/cai-sparklyr-rm:2026.03.2`
  * `123456789012.dkr.ecr.us-west-2.amazonaws.com/cai-rstudio-sparklyr:2026.03.3`
* Click **Validate**, then **Add to Catalog**.

Validation checks Docker labels. For the RStudio image, expect **Editor: RStudio** and **Kernel: R 4.5**.

Enable the runtime in your project under **Project Settings → Runtimes**.

---

## 5. Run a test session

Clone this repository as a CAI project and enable your imported runtime.

### Workbench session

```
Editor:     Workbench
Kernel:     R 4.5
Spark:      enabled (optional, for sparklyr against a cluster)
Resources:  2 vCPU / 4 GiB Memory (or your profile)
```

Run [`sparklyrtest.R`](sparklyrtest.R) and adjust cluster/storage paths for your environment.

### RStudio session

```
Editor:     RStudio
Kernel:     R 4.5
Spark:      off for first test; enable for sparklyr + Hadoop CLI add-on test
Resources:  2 vCPU / 4 GiB Memory (or your profile)
```

The session should stay **Running** (not exit after a few seconds). RStudio loads in the session UI when the editor launcher stays active.

In the R console:

```r
R.version.string
"sparklyr" %in% rownames(installed.packages())
```

Then run `sparklyrtest.R` with Spark enabled if desired.

---

## Summary

**Cloudera AI Runtimes** package reproducible environments for sessions, jobs, and models. Custom images extend official base runtimes with additional packages and editors; the Runtime Catalog registers them for use across projects.

Administrators import images from ECR or other registries, configure credentials for private registries, and assign runtimes to projects. Users select the runtime and editor when starting a session.

### Cloudera AI Runtime documentation

* [Runtime Catalog](https://docs.cloudera.com/machine-learning/1.5.5/runtimes/topics/ml-using-runtime-catalog.html)
* [Adding new ML Runtimes](https://docs.cloudera.com/machine-learning/cloud/managing-runtimes/topics/ml-adding-new-ml-runtimes.html)
* [Docker registry credentials](https://docs.cloudera.com/machine-learning/1.5.5/managing-runtimes/topics/ml-add-docker-registry-credentials-runtimes.html)
* [ML Runtimes overview](https://docs.cloudera.com/machine-learning/cloud/runtimes/index.html)
* [Custom runtimes with editors (blog)](https://blog.cloudera.com/building-custom-runtimes-with-editors-in-cloudera-machine-learning/)
