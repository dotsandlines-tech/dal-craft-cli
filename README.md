# dal-craft-cli

This image marries 3 containers into a locked down Docker-based management cli for [craftcms](https://craftcms.com/) services - accessable via SSH:
* [atmoz/sftp](https://github.com/atmoz/sftp)
* [witten/borgmatic](https://github.com/witten/borgmatic)
* [craftcms/cli](https://github.com/craftcms/docker)

The idea is to provide a minimal separate management container for craftcms services that allows:
* locked down access **via ssh** via a set of predefined users, 
* backup/snapshoting capabilities and
* direct usage of the `./craft` management cli.

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

container:/app$ snapshots create
# + borgmatic --init -e none
# + borgmatic --verbosity 1
# /etc/borgmatic.d/config.yaml: Running command for pre-prune hook
# Starting pruning.
# /etc/borgmatic.d/config.yaml: Running command for pre-backup hook
# Starting a backup.
# /etc/borgmatic.d/config.yaml: Running command for pre-check hook
# Starting checks.
# /mnt/snapshots/.repo: Pruning archives
# /mnt/snapshots/.repo: Creating archive
# /mnt/snapshots/.repo: Removing MySQL database dumps
# /mnt/snapshots/.repo: Dumping MySQL databases
# Creating archive at "/mnt/snapshots/.repo::backup-{now}"
# /mnt/snapshots/.repo: Running consistency checks
# Starting repository check
# Starting repository index check
# Index object count match.
# Completed repository check, no problems found.
# Starting archive consistency check...
# Analyzing archive backup-2021-05-26T10:15:22 (1/3)
# Analyzing archive backup-2021-05-26T16:43:17 (2/3)
# Analyzing archive backup-2021-05-27T10:30:43 (3/3)
# Orphaned objects check skipped (needs all archives checked).
# Archive consistency check complete, no problems found.
# /etc/borgmatic.d/config.yaml: Running command for post-prune hook
# Finished pruning.
# /etc/borgmatic.d/config.yaml: Removing MySQL database dumps
# /etc/borgmatic.d/config.yaml: Running command for post-backup hook
# Finished a backup.
# /etc/borgmatic.d/config.yaml: Running command for post-check hook
# Finished checks.
# summary:
# /etc/borgmatic.d/config.yaml: Successfully ran configuration file

container:/app$ cd current/

container:/app/current$ ./craft off
# The system is now offline.

container:/app/current$ ./craft on
# The system is already online.
```

### Typical configuration

* We mount the craftcms working directory at `/app/current`.
* A separate backup volume is mounted at `/mnt/snapshots`, including a temporary `/dumps` directory (emptydir).
* Regarding `ssh` access:
  * We set the `ENV`-var `SFTP_USERS` (e.g. `<username>:<pass>:82:82:app,snapshots`) to a k8s secret to setup our sftp users and keys and additionally mount a common ssh host key at `/etc/ssh/ssh_host_ed25519_key` and `/etc/ssh/ssh_host_rsa_key`.
  * Furthermore we mount the respective user-specific ssh public keys at `/home/<username>/.ssh/keys/user-ssh-key.pub`.
  * All ssh users get uid/gid `82:82` (www-user, as used by the official craftcms images)
  * We also mount the craftcms working directory at `/home/<username>/app` and backups at `/home/<username>/snapshots` to make them available while using `sftp`.
* We set a the `ENV`-var `MOTD_MESSAGE` to a nice message. This is displayed to each ssh user connecting via ssh.
* The borgmatic config gets mounted at `/etc/borgmatic.d/config.yaml`.


### Sample borgmatic configuration

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
```

## License

[MIT](LICENSE)