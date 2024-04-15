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
    && pip3 install --upgrade pip \
    && pip3 install --upgrade borgbackup==${BORG_VERSION} \
    && pip3 install --upgrade borgmatic==${BORGMATIC_VERSION} \
    && pip3 install --upgrade llfuse==${LLFUSE_VERSION}


### -----------------------
# --- Stage: cli
# --- Purpose: Image for actual deployment
# --- Current PHP version: 8.2.18
# --- https://github.com/craftcms/docker
# --- https://github.com/atmoz/sftp/blob/master/Dockerfile
# See https://hub.docker.com/r/craftcms/cli/tags
# See https://hub.docker.com/r/craftcms/php-fpm/tags
# -> craftcms/php-fpm:8.2@sha256:a6b18d3b01e5de2007b74656499162a2c89d63587671ddd58f784951bab91ed9
### -----------------------

FROM craftcms/cli:8.2@sha256:a167f46d5fc984191458898221eb0c4c03dfd9f619143bf028fe22322b5e3f26 as cli

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
# - add
# - Add craft specific deps: mariadb-client

RUN apk update && \
    apk add --no-cache \
    # borg crypto
    libcrypto3 \
    # envsubst
    gettext \
    # openssh specific deps
    bash shadow openssh-server rsync sudo \
    # borgmatic specific deps (https://github.com/b3vis/docker-borgmatic/blob/master/base/Dockerfile)
    tzdata sshfs python3 openssl fuse ca-certificates lz4-libs libacl mariadb-connector-c mysql-client curl \
    && mkdir -p /var/run/sshd \
    && rm -f /etc/ssh/ssh_host_*key*

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

# openssh files
COPY templates/sshd_config /opt/templates/sshd_config
COPY files/create-sftp-user /usr/local/bin/
COPY files/entrypoint /

# snapshots cli
COPY files/snapshots /usr/bin/snapshots

EXPOSE 22

ENTRYPOINT ["/entrypoint"]