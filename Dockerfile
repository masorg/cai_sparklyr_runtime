# Base Cloudera AI Runtime
FROM docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-workbench-r4.5-standard:2026.01.1-b6

# Switch to root to install R packages if needed
USER root

# Install sparklyr without pulling Spark dependencies
# (sparklyr itself does not install Spark unless explicitly requested via spark_install())
# install.packages() exits 0 even when a package fails to build, which would let
# the image ship without sparklyr and only fail at session time. Guard it so the
# build hard-fails if sparklyr is not importable afterwards.
RUN R -e "install.packages('sparklyr', repos='https://cloud.r-project.org', dependencies=TRUE); if (!requireNamespace('sparklyr', quietly=TRUE)) quit(status=1)"

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

# Replace git-lfs with the official upstream release, which is built on a patched
# Go toolchain. The base image ships git-lfs compiled with a vulnerable Go stdlib
# (CVE-2025-68121, crypto/tls); the Go version is baked into the compiled binary,
# so apt cannot fix it and we overwrite the binary itself.
ARG GIT_LFS_VERSION=3.7.1
RUN set -eux; \
    curl -fL "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-amd64-v${GIT_LFS_VERSION}.tar.gz" \
        -o /tmp/git-lfs.tgz; \
    tar -xzf /tmp/git-lfs.tgz -C /tmp; \
    install -m0755 "$(find /tmp -name git-lfs -type f | head -n1)" /usr/bin/git-lfs; \
    rm -rf /tmp/git-lfs*; \
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
