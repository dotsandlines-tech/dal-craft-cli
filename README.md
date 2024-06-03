# dal-craft-cli

> **Docker Image Compability Matrix: https://github.com/dotsandlines-tech/dal-craft-cli/wiki/Compatibility-Matrix**

This image marries 2-3 containers into a locked down Docker-based management cli for [craftcms](https://craftcms.com/) services - accessable via SSH:
* [atmoz/sftp](https://github.com/atmoz/sftp)
* [craftcms/cli](https://github.com/craftcms/docker)
* either [witten/borgmatic](https://github.com/witten/borgmatic) (the `-borgmatic` image tag variant)
* or it simply bakes `kubectl` (the `-a3cloud` image tag variant) 

The idea is to provide a minimal separate management container for craftcms services that allows:
* locked down access **via ssh** via a set of predefined users, 
* direct usage of the `./craft` management cli and
* backup/snapshoting capabilities either via `borgmatic` or `kubectl` (CSI volume snapshots).

This container may also be interesting for CI deployment steps (syncing craftcms DB / files with CI-built artifacts).

## Usage

All `ENV` configuration requirements of [atmoz/sftp](https://github.com/atmoz/sftp) and [craftcms/cli](https://github.com/craftcms/docker) apply as documented here. Please note that we do not lock down to sftp-only access, ssh-access is granted to all configured users as configured by sftp. 

Regarding [witten/borgmatic](https://github.com/witten/borgmatic), please mount its full configuration at `/etc/borgmatic.d/config.yaml`.

After successfully setting this it, it should be possible to get a ssh shell into this container on port `22`:
```bash
ssh <username>@<container-host> -p <ssh-port>
# $MOTD_MESSAGE: Welcome to <container-host>!
# owner:           www-data (chown 82:82 <file>)
# app disk:        /app
# craft home:      /app/current
# backup disk:     /mnt/snapshots
# Type "snapshots -h" for help regarding adhoc backups (held for **30 days**).

container:/app$ whoami
# www-data

container:/app$ id
# uid=82(www-data) gid=82(www-data) groups=82(www-data)

# -borgmatic image variant only:
container:/app$ ./snapshots -h
# dal-craft-cli snapshots utility
# Usage:
#   snapshots -h                      Display this help message.
#   snapshots print-config            Print current config vars.
#   snapshots init                    Initialize '/mnt/snapshots/{.borg, .repo}'.
#   snapshots list                    List available snapshots.
#   snapshots info                    Info about snapshot size.
#   snapshots create                  Create a new snapshot from '/app/current/**' and prune old snapshots.
#   snapshots export <snapshot>       Export <snapshot> to '/mnt/snapshots/<snapshot>.tar.gz'.
#   snapshots restore <snapshot>      Restore <snapshot> to '/app/current/**' (hotswap).

# -a3cloud image variant only:
container:/app$ snapshots -h
# dal-craft-cli snapshots utility (a3cloud kubectl csi volume snapshot compatible)
# Usage:
#   snapshots -h                      Display this help message.
#   snapshots list|info               List available k8s volume snapshots.
#   snapshots create                  Create a new k8s volume snapshot.
#   snapshots print-config            Prints a3cloud k8s ConfigMap/backup-env
#   snapshots init                    NOOP exit 0
#   snapshots export <snapshot>       NOT IMPLEMENTED, exit 1
#   snapshots restore <snapshot>      NOT IMPLEMENTED, exit 1

container:/app$ snapshots create
# A new snapshot is created either via borgmatic or kubectl, see above.
# Feel free to adapt the bash-script under /usr/bin/snapshots to your needs (mount an executable file there to overwrite)
# For samples see files/snapshots-a3cloud or files/snapshots-borgmatic in this repo.

container:/app$ cd current/

container:/app/current$ ./craft off
# The system is now offline.

container:/app/current$ ./craft on
# The system is already online.
```

### Typical configuration

* We mount the craftcms working directory at `/app/current`.
* `-a3cloud` specific: The container simply reused the mounted service account.
* `-borgmatic` specific: A separate backup volume is mounted at `/mnt/snapshots`, including a temporary `/dumps` directory (emptydir). The borgmatic config gets mounted at `/etc/borgmatic.d/config.yaml`.
* Regarding `ssh` access:
  * We set the `ENV`-var `SFTP_USERS` (e.g. `<username>:<pass>:82:82:app,snapshots`) to a k8s secret to setup our sftp users and keys and additionally mount a common ssh host key at `/etc/ssh/ssh_host_ed25519_key` and `/etc/ssh/ssh_host_rsa_key`.
  * Furthermore we mount the respective user-specific ssh public keys at `/home/<username>/.ssh/keys/user-ssh-key.pub`.
  * All ssh users get uid/gid `82:82` (www-user, as used by the official craftcms images)
  * We also mount the craftcms working directory at `/home/<username>/app` (and `-borgmatic` specific: backups at `/home/<username>/snapshots` to make them available while using `sftp`).
* We set a the `ENV`-var `MOTD_MESSAGE` to a nice message. This is displayed to each ssh user connecting via ssh.


### Sample borgmatic configuration (`-borgmatic` image only)

We typically mount something like that following at `/etc/borgmatic.d/config.yaml`:

```yaml
# https://torsion.org/borgmatic/docs/reference/configuration/
location:
  source_directories:
    - /app/current
  repositories:
    - /mnt/snapshots/.repo

  # Skip craft temp folder
  # exclude_patterns:
  #   - /app/current/temp

  # Path for additional source files used for **temporary** internal state like borgmatic database dumps.
  borgmatic_source_directory: /dumps

storage:
  compression: lz4
  archive_name_format: 'backup-{now}'
  borg_base_directory: /mnt/snapshots/.borg
  # borg_config_directory:    # defaults to $borg_base_directory/.config/borg
  # borg_cache_directory:     # defaults to $borg_base_directory/.cache/borg
  # borg_security_directory:  # defaults to $borg_base_directory/.config/borg/security
  # borg_keys_directory:      # defaults to $borg_base_directory/.config/borg/keys
  lock_wait: 30

retention:
  keep_within: 30d
  prefix: 'backup-'

consistency:
  checks:
    - repository
    - archives
  check_last: 3
  prefix: 'backup-'

hooks:
  before_backup:
    - echo "Starting a backup."
  before_prune:
    - echo "Starting pruning."
  before_check:
    - echo "Starting checks."
  before_extract:
    - echo "Starting extracting."
  after_backup:
    - echo "Finished a backup."
  after_prune:
    - echo "Finished pruning."
  after_check:
    - echo "Finished checks."
  after_extract:
    - echo "Finished extracting."
  on_error:
    - echo "Error during prune/create/check."
  mysql_databases:
    - name: all
      hostname: <db-host>
      port: <db-port>
      username: <db-username>
      password: <db-password>
      # IMPORTANT! do not use --compact with mariadb! https://github.com/arionum/node/issues/13
      options: --default-character-set=utf8 --add-drop-database --add-locks --set-charset --create-options --add-drop-table --lock-tables
```

### TCP forwarding

To enable TCP forwarding via SSH through this container you need to set the `ENV_VAR` `SSHD_ALLOW_TCP_FORWARDING: "yes"`. This is for example needed to directly access a mySQL/MariaDB database through a SSH tunnel via this container.

#### Other SSHD defaults

See `templates/sshd_config`, the following envs will be set and a substituted template written to `/etc/ssh/sshd_config`.

Default values:
```bash
SSHD_HOST_KEY_ED25519="/etc/ssh/ssh_host_ed25519_key"
SSHD_HOST_KEY_RSA="/etc/ssh/ssh_host_rsa_key"
SSHD_USE_DNS="no"
SSHD_ALLOW_TCP_FORWARDING="no"
SSHD_X11_FORWARDING="no"
SSHD_PERMIT_ROOT_LOGIN="no"
```

### Snapshots configuration

We inject a snapshots utility that easens the burden to create snapshots/backups for our default stack.

```bash
# You may configure the following env vars - here are its default values (a new UUID is generated each time):
./snapshots print-config
Using:
  SNAPSHOTS_DIR:            "/mnt/snapshots"
  SRC_DIR:                  "/app/current"

  TMP_RESTORE_UUID:         "cf44881a-4e21-429c-8931-dc653ef96053"
  TMP_RESTORED_BASE_DIR:    "/tmp/.cf44881a-4e21-429c-8931-dc653ef96053"
  TMP_RESTORED_SRC_DIR:     "/tmp/.cf44881a-4e21-429c-8931-dc653ef96053/app/current"
  HOTSWAP_BASE_DIR:         "/app"
  HOTSWAP_RESTORED_DIR:     "/app/.cf44881a-4e21-429c-8931-dc653ef96053"
  HOTSWAP_OLD_DIR:          "/app/.cf44881a-4e21-429c-8931-dc653ef96053_old"
```

## Injected `env`

As users that connect via `ssh`, don't automatically get the same `env` as the root user running this container, we explicitly define env vars that are allowed to be shared with each user, see [`files/create-sftp-user`](files/create-sftp-user). 

Currently expose the following `ENV`-vars from the `root` user (that runs the ssh-server within this container) to each created user:

```bash
export PATH="${PATH}"
export PHP_VERSION="${PHP_VERSION}"
export PHP_MD5="${PHP_VERSION}"
export PHP_INI_DIR="${PHP_INI_DIR}"
export PHP_LDFLAGS="${PHP_LDFLAGS}"
export PHP_SHA256="${PHP_SHA256}"
export PHPIZE_DEPS="${PHPIZE_DEPS}"
export PHP_URL="${PHP_URL}"
export COMPOSER_VERSION="${COMPOSER_VERSION}"
export PHP_CFLAGS="${PHP_CFLAGS}"
export COMPOSER_HOME="${COMPOSER_HOME}"
export PHP_ASC_URL="${PHP_ASC_URL}"
export PHP_CPPFLAGS="${PHP_CPPFLAGS}"

export KUBERNETES_SERVICE_HOST="${KUBERNETES_SERVICE_HOST}"
export KUBERNETES_SERVICE_PORT="${KUBERNETES_SERVICE_PORT}"
export KUBERNETES_SERVICE_PORT_HTTPS="${KUBERNETES_SERVICE_PORT_HTTPS}"
export KUBERNETES_PORT="${KUBERNETES_PORT}"
export KUBERNETES_PORT_443_TCP="${KUBERNETES_PORT_443_TCP}"
export KUBERNETES_PORT_443_TCP_PROTO="${KUBERNETES_PORT_443_TCP_PROTO}"
export KUBERNETES_PORT_443_TCP_ADDR="${KUBERNETES_PORT_443_TCP_ADDR}"
export KUBERNETES_PORT_443_TCP_PORT="${KUBERNETES_PORT_443_TCP_PORT}"

# all provided BAK_* and BACKUP_JOB_* env vars
```

## Development: How to publish new images

1. Replace the `Stage: cli-a3cloud` base image within the `Dockerfile` to your new variant from [craftcms/cli](https://hub.docker.com/r/craftcms/cli/tags?page=1&ordering=last_updated).
2. Replace the `IMAGE_NAME` within `build.sh`.
3. Push into private working branch and check GitHub Actions **build pipeline** for errors.
4. Push into `main` branch and check Github Actions **build and publish pipeline** for errors.
5. Push as new git tag (e.g. `v1.2.0-php8.2`, `git tag -a <TAG> -m "<msg>"`) and check Github Actions **build and publish pipeline** for errors. This will automatically publish 2 tags: `v1.2.0-php8.2-a3cloud` and `v1.2.0-php8.2-borgmatic` 
6. Update the [Compatibility Matrix](https://github.com/dotsandlines-tech/dal-craft-cli/wiki/Compatibility-Matrix)
7. Use the published docker image (e.g. `ghcr.io/dotsandlines-tech/dal-craft-cli:v1.2.0-php8.2-a3cloud`)

## How we check for security issues

You can run this locally.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $HOME/Library/Caches:/root/.cache/ aquasec/trivy image --exit-code 1 --severity HIGH,CRITICAL --no-progress --ignore-unfixed ghcr.io/dotsandlines-tech/dal-craft-cli:v1.2.0-php8.2-a3cloud
```

## License

[MIT](LICENSE)