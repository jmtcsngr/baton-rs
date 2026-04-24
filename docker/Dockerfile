FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install iRODS client runtime packages from the official iRODS APT repository.
# The exact version must match the iRODS version the build image compiled against
# (currently 4.3.5 — see the build image referenced in publish.yml).
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc \
      | apt-key add - \
  && echo "deb [arch=amd64] https://packages.irods.org/apt/ $(lsb_release -sc) main" \
      > /etc/apt/sources.list.d/renci-irods.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
       irods-runtime=4.3.5-0~jammy \
       irods-icommands=4.3.5-0~jammy \
  && rm -rf /var/lib/apt/lists/*

COPY target/release/baton-list       /usr/local/bin/
COPY target/release/baton-get        /usr/local/bin/
COPY target/release/baton-put        /usr/local/bin/
COPY target/release/baton-chmod      /usr/local/bin/
COPY target/release/baton-metamod    /usr/local/bin/
COPY target/release/baton-metaquery  /usr/local/bin/
COPY target/release/baton-do         /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/baton-do"]
