# debian-preseed-iso-generator

[![Debian](https://img.shields.io/badge/Debian-preseed-D70A53?logo=debian&style=for-the-badge)](https://www.debian.org/)
[![Version](https://img.shields.io/github/v/tag/bergmann-max/debian-preseed-iso-generator?label=version&color=green&sort=semver&style=for-the-badge)](https://github.com/bergmann-max/debian-preseed-iso-generator/tags)
[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)

Generate Debian netinst ISOs with embedded preseed configuration, one ISO per profile.

## Requirements

`bash` >= 4.x (uses `mapfile`).

```bash
sudo apt install wget curl xorriso cpio gzip gnupg
```

For amd64/i386 builds, also install `isolinux` (Debian/Ubuntu) or `syslinux` (Arch) -- the script needs `isohdpfx.bin` for the BIOS boot loader.

Optional: install `debian-archive-keyring` (or `debian-keyring`) for GPG signature verification of the Debian ISO checksums.

## Quickstart

```bash
git clone https://github.com/bergmann-max/debian-preseed-iso-generator.git
cd debian-preseed-iso-generator
./debian-preseed-iso-generator.sh
```

The script downloads the latest Debian netinst ISO, injects each profile's preseed.cfg, and writes the result to `out/<profile>-preseed-debian-<arch>-netinst.iso`.

## Profiles

```
profiles/
  default/preseed.cfg
  minimal/preseed.cfg
```

Each profile directory contains a `preseed.cfg` file that is injected directly into the ISO's initrd. Copy an existing profile and edit the preseed directives to create a new variant. See [docs/PROFILES.md](docs/PROFILES.md) for details.

## CLI

```
Usage: ./debian-preseed-iso-generator.sh [OPTIONS]

Options:
  -p, --profile NAME   build only specified profile
  -l, --list           list available profiles and exit
  -n, --dry-run        show what would be done without executing
  -o, --output DIR     output directory (default: out/)
  -a, --arch ARCH      target architecture (default: amd64)
  -V, --version        print version and exit
  -h, --help           show this help

With no options, builds all profiles found in profiles/.
```

## UEFI support

The generated ISO boots on both BIOS and UEFI systems. Test with:

```bash
# BIOS
qemu-system-x86_64 -cdrom out/minimal-preseed-debian-amd64-netinst.iso -m 2G

# UEFI
qemu-system-x86_64 -cdrom out/minimal-preseed-debian-amd64-netinst.iso -m 2G \
  -bios /usr/share/ovmf/OVMF.fd
```

## Notes

- The generated ISO contains a regenerated `md5sum.txt` (Debian installer uses this to verify its components at boot). The original GPG signature on `md5sum.txt` is lost because `preseed.cfg` is added to the initrd. Verify the generated ISO with `md5sum out/<file>.iso` against the expected hash if integrity matters.
- Architecture: `--arch amd64` and `--arch i386` produce a BIOS + UEFI hybrid ISO. `--arch arm64` is UEFI-only.
- The downloaded netinst ISO is cached in the script directory (not in `out/`). Delete the cached `debian-*-netinst.iso` files to reclaim disk space.

## Links

- [Debian preseed documentation](https://www.debian.org/releases/stable/amd64/apb.en.html)
- [Example preseed file](https://www.debian.org/releases/stable/example-preseed.txt)

## License

[MIT](LICENSE)

## Author

Max Bergmann
