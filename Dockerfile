# -----------------------------
# Stage 1: build git-lfs from source on a patched Go toolchain
# -----------------------------
# The newest upstream git-lfs RELEASE (3.7.1) is compiled with go1.25.3, still
# flagged for CVE-2025-68121 (crypto/tls; fix in the 1.25 branch is go1.25.7).
# Building from source with a current Go toolchain yields a patched stdlib.
# Runs on the native BUILD platform (no qemu) and CROSS-compiles to the target
# arch, avoiding emulation of the Go toolchain (which crashes under qemu
# amd64-on-arm) while still producing a linux/amd64 binary for the final image.
ARG GIT_LFS_VERSION=3.7.1
ARG GO_IMAGE=golang:1.26
FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS gitlfs-builder
ARG GIT_LFS_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN set -eux; \
    git clone --depth 1 --branch "v${GIT_LFS_VERSION}" https://github.com/git-lfs/git-lfs.git /src; \
    cd /src; \
    mkdir -p /out; \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -o /out/git-lfs .; \
    go version /out/git-lfs

# Base Cloudera AI Runtime
FROM docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-workbench-r4.5-standard:2026.01.1-b6

# Switch to root to install R packages if needed
USER root

# Install sparklyr from Posit Package Manager as PREBUILT BINARIES for Ubuntu
# 24.04 (noble). The HTTPUserAgent line is what makes PPM serve binaries instead
# of source tarballs - without it R downloads source and compiles the whole
# tidyverse/arrow stack, which is slow and unreliable (especially under qemu
# amd64-on-arm emulation). Binaries mean zero compilation: the full dependency
# tree installs in ~2 min on any amd64 host, emulated or native.
# (sparklyr does not install Spark unless explicitly requested via spark_install())
# The trailing requireNamespace check hard-fails the build if sparklyr is missing
# (install.packages() otherwise exits 0 even when a package fails).
RUN R -e "options(repos=c(CRAN='https://packagemanager.posit.co/cran/__linux__/noble/latest'), HTTPUserAgent=paste0('R/', getRversion(), ' R (', getRversion(), ' ', R.version[['platform']], ' ', R.version[['arch']], ' ', R.version[['os']], ')')); install.packages('sparklyr', dependencies=TRUE); ok <- requireNamespace('sparklyr', quietly=TRUE); quit(status=if (isTRUE(ok)) 0 else 1)"

# -----------------------------
# Security remediation for base-image CVEs
# -----------------------------
# Patch OS/Python packages inherited from the base image to their fixed versions.
#   postgresql-16 -> CVE-2026-6475 / CVE-2026-6477 (fixed 16.14-0ubuntu0.24.04.1)
#   mysql-8.0     -> CVE-2026-46862 / CVE-2026-46863 (fixed 8.0.46-0ubuntu0.24.04.3)
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Overwrite the base image's git-lfs (compiled with a vulnerable Go stdlib,
# CVE-2025-68121 crypto/tls) with the binary built from source in stage 1 on a
# patched Go toolchain. The binary is static (CGO disabled), so it has no runtime
# dependency on the builder image.
COPY --from=gitlfs-builder /out/git-lfs /usr/bin/git-lfs
RUN set -eux; \
    chmod 0755 /usr/bin/git-lfs; \
    git-lfs version

# Patch the Python cryptography package (GHSA-537c-gmf6-5ccf, fixed in >=48.0.1).
RUN pip3 install --no-cache-dir --upgrade 'cryptography>=48.0.1'

# Override Runtime label and environment variables metadata
ENV ML_RUNTIME_EDITOR="Workbench" \
    ML_RUNTIME_EDITION="Community" \
    ML_RUNTIME_SHORT_VERSION="2026.03" \
    ML_RUNTIME_MAINTENANCE_VERSION="3" \
    ML_RUNTIME_FULL_VERSION="2026.03.3" \
    ML_RUNTIME_DESCRIPTION="Runtime for Nikhil (CVE remediation)"

LABEL com.cloudera.ml.runtime.editor=$ML_RUNTIME_EDITOR \
      com.cloudera.ml.runtime.edition=$ML_RUNTIME_EDITION \
      com.cloudera.ml.runtime.full-version=$ML_RUNTIME_FULL_VERSION \
      com.cloudera.ml.runtime.short-version=$ML_RUNTIME_SHORT_VERSION \
      com.cloudera.ml.runtime.maintenance-version=$ML_RUNTIME_MAINTENANCE_VERSION \
      com.cloudera.ml.runtime.description=$ML_RUNTIME_DESCRIPTION
