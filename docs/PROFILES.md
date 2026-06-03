# Profiles

A profile is a directory under `profiles/` that defines preseed configuration for one Debian variant. The script auto-discovers all profiles -- drop a new directory, it builds.

## Directory structure

```
profiles/
  default/preseed.cfg          # raw preseed
  minimal/minimal.env           # template variables
templates/
  preseed.cfg.tmpl              # reusable Debian 13 preseed template
```

## Two modes

### Raw mode

Place a complete `preseed.cfg` directly in the profile directory.

- No template rendering -- the file is injected as-is into the initrd.
- Good for: existing preseed files, one-off variants that diverge from the template.

Example:

```
profiles/
  my-server/preseed.cfg
```

### Template mode

Place a `<profile>.env` file with `KEY=value` pairs in the profile directory. The script renders `templates/preseed.cfg.tmpl` via `envsubst`.

- Reuse one template for many profiles -- only variables differ.
- Good for: standardized builds, quick creation of new variants.

Example:

```
profiles/
  my-server/my-server.env
```

The file **must** be named `<profile>.env` (matching the directory name). Raw `preseed.cfg` takes precedence if both files exist.

## Variable reference

These variables can be set in `<profile>.env`. The template uses Debian 13 (Trixie) directives.

| Variable               | Preseed directive                        | Description                                          |
|------------------------|------------------------------------------|------------------------------------------------------|
| `LOCALE`               | `debian-installer/locale`                | Language + locale (e.g. `en_US.UTF-8`)               |
| `KEYMAP`               | `keyboard-configuration/xkb-keymap`      | Keyboard layout (e.g. `us`, `de`)                    |
| `HOSTNAME`             | `netcfg/get_hostname`                    | Machine hostname                                     |
| `DOMAIN`               | `netcfg/get_domain`                      | DNS domain                                           |
| `MIRROR_HOST`          | `mirror/http/hostname`                   | Debian mirror host (e.g. `deb.debian.org`)           |
| `MIRROR_DIR`           | `mirror/http/directory`                  | Mirror base directory (e.g. `/debian`)               |
| `MIRROR_PROXY`         | `mirror/http/proxy`                      | HTTP proxy (empty = none)                            |
| `ROOT_PASSWORD_HASH`   | `passwd/root-password-crypted`           | crypt(3) hash; empty = prompt at install             |
| `USER_FULLNAME`        | `passwd/user-fullname`                   | Normal user display name                             |
| `USER_NAME`            | `passwd/username`                        | Normal user login name                               |
| `USER_PASSWORD_HASH`   | `passwd/user-password-crypted`           | crypt(3) hash; empty = prompt at install             |
| `TIMEZONE`             | `time/zone`                              | Timezone (e.g. `UTC`, `Europe/Berlin`)               |
| `NTP_SERVER`           | `clock-setup/ntp-server`                 | NTP server; empty = default (deb.debian.org pool)    |
| `PARTITION_METHOD`     | `partman-auto/method`                    | `regular`, `lvm`, or `crypto`                        |
| `LVM_SIZE`             | `partman-auto-lvm/guided_size`           | LVM volume group size: `max`, `20 GB`, `80%`         |
| `PARTITION_RECIPE`     | `partman-auto/choose_recipe`             | `atomic`, `home`, `multi`, `server`, `small_disk`    |
| `APT_NON_FREE_FIRMWARE`| `apt-setup/non-free-firmware`            | `true` or `false`                                    |
| `APT_NON_FREE`         | `apt-setup/non-free`                     | `true` or `false`                                    |
| `APT_CONTRIB`          | `apt-setup/contrib`                      | `true` or `false`                                    |
| `TASKS`                | `tasksel tasksel/first`                  | tasksel tasks, comma-separated (e.g. `standard`)     |
| `PACKAGES`             | `pkgsel/include`                         | Extra packages, space-separated (e.g. `vim curl`)    |
| `UPGRADE_POLICY`       | `pkgsel/upgrade`                         | `none`, `safe-upgrade`, or `full-upgrade`            |
| `POPCON`               | `popularity-contest/participate`         | `true` or `false`                                    |
| `GRUB_ONLY_DEBIAN`     | `grub-installer/only_debian`            | `true` or `false`                                    |
| `GRUB_WITH_OTHER_OS`   | `grub-installer/with_other_os`          | `true` or `false`                                    |
| `LATE_COMMAND`         | `preseed/late_command`                   | Shell command run before reboot; empty = no-op       |

## Creating a new profile

### Via template (recommended)

```bash
PROFILE=my-server
mkdir -p profiles/"${PROFILE}"
cp profiles/minimal/minimal.env profiles/"${PROFILE}/${PROFILE}.env"
# edit profiles/my-server/my-server.env
./debian-preseed-iso-generator.sh --profile my-server
```

### Via raw file

```bash
mkdir -p profiles/my-server
# drop your preseed.cfg into profiles/my-server/
./debian-preseed-iso-generator.sh --profile my-server
```

## Generating password hashes

```bash
mkpasswd -m sha-512
```
