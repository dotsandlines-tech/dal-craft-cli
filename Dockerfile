### -----------------------
# --- Stage: cli-a3cloud
# --- Purpose: Image for actual deployment
# --- Current PHP version: 8.2.19
# --- https://github.com/craftcms/docker
# --- https://github.com/atmoz/sftp/blob/master/Dockerfile
# See https://hub.docker.com/r/craftcms/cli/tags
# See https://hub.docker.com/r/craftcms/php-fpm/tags
# -> craftcms/php-fpm:8.2@sha256:585af3833e28e9a15e2b9683484ee7d855542ccafe89f230337f05909d731395
### -----------------------
FROM craftcms/cli:8.2@sha256:92c51779ac863a27bda8b6e850d30cab66b2039ad864535ad74088359b09009e as cli-a3cloud

# switch back to the root user (we will spawn the actual queue through the **www-data** user later.)
# this user is used to actually run the container as we will spawn a ssh-server
# users will then exclusively connect through it.
USER root

# - changed debian apt-get to alpine apk
# - added 'shadow' package for useradd command (create-sftp-user script)
# - added USER root for apk to work correctly
# - files/create-sftp-user: 
#     - removed 'chown root:root "home/${user}"'
#     - added .profile file for autosetting ENVs and auto-cd to /app
#     - customized /etc/motd on start reading namespace from ENV.
#
# ---------------------------------------------------------------
# Steps done in one RUN layer:
# - Install packages
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
# - Add some craft specific deps and utils: mysql-client and mariadb-client

RUN apk add --update --no-cache \
    # envsubst
    gettext \
    # openssh specific deps
    bash shadow openssh-server rsync sudo \
    # snapshot-a3cloud deps
    jq yq \
    # additionals
    tmux tzdata openssl ca-certificates lz4-libs libacl mariadb-connector-c mysql-client curl \
    && mkdir -p /var/run/sshd \
    && rm -f /etc/ssh/ssh_host_*key*

# openssh files
COPY templates/sshd_config /opt/templates/sshd_config
COPY files/create-sftp-user /usr/local/bin/
COPY files/entrypoint /

# snapshots cli
COPY --chmod=0755 files/snapshots-a3cloud /usr/bin/snapshots
COPY --chmod=0755 files/backup-ns.sh /usr/bin/backup-ns.sh

RUN ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" \
    && KUBECTL_VERSION="1.27.14" \
    && curl -sLO https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl && \
    mv kubectl /usr/bin/kubectl && \
    chmod +x /usr/bin/kubectl

EXPOSE 22

ENTRYPOINT ["/entrypoint"]


### -----------------------
# --- Stage: borgmatic-builder
# --- Purpose: borgmatic build scripts to later inject into cli image
# --- https://github.com/b3vis/docker-borgmatic/blob/master/base/Dockerfile
# See https://hub.docker.com/_/alpine/tags
### -----------------------
FROM alpine:3.18 as borgmatic-builder
LABEL maintainer='infrastructure+dal-craft-cli@dotsandlines.io'

# https://pypi.org/project/borgbackup/
ARG BORG_VERSION=1.2.4

# https://pypi.org/project/borgmatic/#history
ARG BORGMATIC_VERSION=1.5.24

# https://pypi.org/project/llfuse/#history
ARG LLFUSE_VERSION=1.4.2

# https://pkgs.alpinelinux.org/packages?name=python3-dev&branch=v3.18&repo=&arch=&maintainer=
ARG PYTHON_VERSION=3.11.8-r0

RUN apk upgrade --no-cache \
    && apk add --no-cache \
    alpine-sdk \
    python3-dev=${PYTHON_VERSION} \
    py3-pip \
    openssl-dev \
    lz4-dev \
    acl-dev \
    linux-headers \
    fuse-dev \
    attr-dev \
    py3-wheel \
    && pip3 install --no-cache-dir --break-system-packages --upgrade pip \
    && pip3 install --no-cache-dir --break-system-packages --upgrade borgbackup==${BORG_VERSION} \
    && pip3 install --no-cache-dir --break-system-packages --upgrade borgmatic==${BORGMATIC_VERSION} \
    && pip3 install --no-cache-dir --break-system-packages --upgrade llfuse==${LLFUSE_VERSION}


### -----------------------
# --- Stage: cli-borgmatic
# --- Purpose: Image for legacy deployment with borgmatic snapshots
### -----------------------

FROM cli-a3cloud as cli-borgmatic

# switch back to the root user (we will spawn the actual queue through the **www-data** user later.)
# this user is used to actually run the container as we will spawn a ssh-server
# users will then exclusively connect through it.
USER root

# - changed debian apt-get to alpine apk
# - added 'shadow' package for useradd command (create-sftp-user script)
# - added USER root for apk to work correctly
# - files/create-sftp-user:
#     - removed 'chown root:root "home/${user}"'
#     - added .profile file for autosetting ENVs and auto-cd to /app
#     - customized /etc/motd on start reading namespace from ENV.
#
# ---------------------------------------------------------------
# Steps done in one RUN layer:
# - Install packages
# - add
# - Add craft specific deps: mariadb-client

RUN apk add --update --no-cache \
    # borg crypto
    libcrypto3 \
    # borgmatic specific deps (https://github.com/b3vis/docker-borgmatic/blob/master/base/Dockerfile)
    tzdata sshfs python3 openssl fuse ca-certificates lz4-libs libacl mariadb-connector-c mysql-client curl

# borgmatch files from other stage
# Attention, most be in sync with above PYTHON_VERSION
COPY --from=borgmatic-builder /usr/lib/python3.11/site-packages /usr/lib/python3.11/
COPY --from=borgmatic-builder /usr/bin/borg /usr/bin/
COPY --from=borgmatic-builder /usr/bin/borgfs /usr/bin/
COPY --from=borgmatic-builder /usr/bin/borgmatic /usr/bin/
COPY --from=borgmatic-builder /usr/bin/generate-borgmatic-config /usr/bin/
COPY --from=borgmatic-builder /usr/bin/upgrade-borgmatic-config /usr/bin/

# check borg and borgmatic can execute
RUN borg --version && borgmatic --version

# borgmatic snapshots cli
COPY --chmod=0755 files/snapshots-borgmatic /usr/bin/snapshots

EXPOSE 22

ENTRYPOINT ["/entrypoint"]