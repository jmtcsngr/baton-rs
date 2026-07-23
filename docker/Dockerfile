FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Bootstrap: tools needed to fetch the iRODS APT repo signing key, plus
# the `locales` package so the container speaks UTF-8 by default.
# Mirrors upstream baton's dev image conventions
# (wtsi-npg/baton:Dockerfile.ubuntu-*-dev).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        locales \
        lsb-release \
        wget \
    && locale-gen en_GB en_GB.UTF-8 \
    && localedef -i en_GB -c -f UTF-8 -A /usr/share/locale/locale.alias en_GB.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_GB.UTF-8 \
    LANGUAGE=en_GB \
    LC_ALL=en_GB.UTF-8 \
    TZ=Etc/UTC

# iRODS client runtime packages from the official iRODS APT repository.
# `IRODS_VERSION` defaults to the version baton-rs binaries were compiled
# against in `publish.yml`'s build image. Override at build time
# (`--build-arg IRODS_VERSION=4.3.4`) only if rebuilding the image
# against a matching custom binary set.
ARG IRODS_VERSION="4.3.5"

RUN install -d -m 0755 /etc/apt/keyrings \
  && wget -qO- https://packages.irods.org/irods-signing-key.asc \
       | gpg --dearmor -o /etc/apt/keyrings/irods-archive-keyring.gpg \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/irods-archive-keyring.gpg] https://packages.irods.org/apt/ $(lsb_release -sc) main" \
      > /etc/apt/sources.list.d/renci-irods.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
       "irods-runtime=${IRODS_VERSION}-0~$(lsb_release -sc)" \
       "irods-icommands=${IRODS_VERSION}-0~$(lsb_release -sc)" \
  && rm -rf /var/lib/apt/lists/*

# Non-root user mirroring upstream baton's `appuser` (UID/GID 1000).
# Under singularity the host user takes over; under plain `docker run`
# the container runs unprivileged by default.
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=$APP_UID

RUN groupadd --gid $APP_GID $APP_USER \
 && useradd --uid $APP_UID --gid $APP_GID --shell /bin/bash --create-home $APP_USER

COPY target/release/baton-list       /usr/local/bin/
COPY target/release/baton-get        /usr/local/bin/
COPY target/release/baton-put        /usr/local/bin/
COPY target/release/baton-chmod      /usr/local/bin/
COPY target/release/baton-metamod    /usr/local/bin/
COPY target/release/baton-metaquery  /usr/local/bin/
COPY target/release/baton-do         /usr/local/bin/

USER $APP_USER
WORKDIR /app

# Container as a working environment, no implicit entrypoint binary.
# Mirrors upstream baton's `CMD ["/bin/bash"]`. Invoke any binary
# explicitly, e.g. `docker run image baton-do --version` or
# `singularity exec docker://image baton-list /path`.
CMD ["/bin/bash"]
