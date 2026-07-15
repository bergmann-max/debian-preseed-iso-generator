# debian-preseed-iso-generator

[![Debian](https://img.shields.io/badge/Debian-preseed-D70A53?logo=debian&style=for-the-badge)](https://www.debian.org/releases/stable/amd64/apb.en.html)
[![Version](https://img.shields.io/github/v/tag/bergmann-max/debian-preseed-iso-generator?label=version&color=green&sort=semver&style=for-the-badge)](https://github.com/bergmann-max/debian-preseed-iso-generator/tags)
[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)

Build bootable Debian netinst ISOs, each with its own preseed injected.

## Requirements

`bash` >= 4.x

```bash
sudo apt install wget curl xorriso cpio gzip gnupg
```

For amd64/i386 builds, also install `isolinux` (Debian/Ubuntu) or `syslinux` (Arch) -- the script needs `isohdpfx.bin` for the BIOS boot loader.

Optional: install `debian-archive-keyring` (or `debian-keyring`) for GPG signature verification of the Debian ISO checksums.

## Quickstart

```bash
git clone https://github.com/bergmann-max/debian-preseed-iso-generator.git
cd debian-preseed-iso-generator
chmod u+x debian-preseed-iso-generator.sh
./debian-preseed-iso-generator.sh
```

The script downloads the latest Debian netinst ISO, injects each preseed's preseed.cfg, and writes the result to `out/<preseed>-preseed-debian-<arch>-netinst.iso`.

## Preseeds

```
preseeds/
  default/preseed.cfg
  minimal/preseed.cfg
```

Each preseed directory contains a `preseed.cfg` file that is injected directly into the ISO's initrd. Copy an existing preseed and edit the preseed directives to create a new variant. See [docs/PRESEEDS.md](docs/PRESEEDS.md) for details.

## CLI

```
Usage: ./debian-preseed-iso-generator.sh [OPTIONS]

Options:
  -p, --preseed NAME   build only specified preseed
  -l, --list           list available preseeds and exit
  -n, --dry-run        show what would be done without executing
  -o, --output DIR     output directory (default: out/)
  -a, --arch ARCH      target architecture (default: amd64)
      --no-color       disable colored output
  -V, --version        print version and exit
  -h, --help           show this help

With no options, builds all preseeds found in preseeds/.
```

## UEFI support

The generated ISO boots on both BIOS and UEFI systems. Test with:

```bash
# BIOS
qemu-system-x86_64 -cdrom out/minimal-preseed-debian-amd64-netinst.iso -m 2G

# UEFI (copy OVMF_VARS so QEMU can write to it)
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd
qemu-system-x86_64 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -cdrom out/minimal-preseed-debian-amd64-netinst.iso -m 2G
```

OVMF paths by distro (adjust as needed):

| Distro          | OVMF path                                |
|-----------------|------------------------------------------|
| Arch | `/usr/share/edk2/x64/OVMF_*.4m.fd`       |
| Debian / Ubuntu | `/usr/share/OVMF/OVMF_CODE.fd`           |
| Fedora          | `/usr/share/edk2/ovmf/OVMF_CODE.fd`      |

## Notes

- This project builds **bootable bare-metal ISOs** with the preseed baked into the initrd - for USB sticks, BMC/iLO virtual media, air-gapped installs, and anything else that needs to boot from an ISO. If your target is a VM- or cloud-image (qcow2, OVA, AMI, etc.) instead, use [Packer](https://developer.hashicorp.com/packer).
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
