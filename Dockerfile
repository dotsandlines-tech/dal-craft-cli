### -----------------------
# --- Stage: borgmatic-builder
# --- Purpose: borgmatic build scripts to later inject into cli image
# --- https://github.com/b3vis/docker-borgmatic/blob/master/base/Dockerfile
### -----------------------
FROM alpine:latest@sha256:bc41182d7ef5ffc53a40b044e725193bc10142a1243f395ee852a8d9730fc2ad as borgmatic-builder
LABEL maintainer='infrastructure+dal-craft-cli@dotsandlines.io'

# https://pypi.org/project/borgbackup/
ARG BORG_VERSION=1.1.16

# https://pypi.org/project/borgmatic/#history
ARG BORGMATIC_VERSION=1.5.22

# https://pypi.org/project/llfuse/#history
ARG LLFUSE_VERSION=1.3.8

RUN apk upgrade --no-cache \
    && apk add --no-cache \
    alpine-sdk \
    python3-dev \
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
# --- https://github.com/craftcms/docker
# --- https://github.com/atmoz/sftp/blob/master/Dockerfile
### -----------------------

FROM craftcms/cli:8.1@sha256:1f972a7493e056a21bcc4604c0dd44c497797d9fd2fecb61f5919c263228f2ab as cli

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
    # envsubst
    gettext \
    # openssh specific deps
    bash shadow openssh-server rsync sudo \
    # borgmatic specific deps (https://github.com/b3vis/docker-borgmatic/blob/master/base/Dockerfile)
    tzdata sshfs python3 openssl fuse ca-certificates lz4-libs libacl mariadb-client curl \
    && mkdir -p /var/run/sshd \
    && rm -f /etc/ssh/ssh_host_*key*

# borgmatch files from other stage
COPY --from=borgmatic-builder /usr/lib/python3.10/site-packages /usr/lib/python3.10/
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