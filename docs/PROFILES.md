# Profiles

A profile is a directory under `profiles/` containing a `preseed.cfg` file. The script auto-discovers all profiles -- drop a new directory, it builds.

## Directory structure

```
profiles/
  default/preseed.cfg
  minimal/preseed.cfg
```

## Preseed file

Place a complete `preseed.cfg` directly in the profile directory. The file is injected as-is into the initrd.

List discovered profiles at any time:

```bash
./debian-preseed-iso-generator.sh --list
```

## Architecture

A profile's `preseed.cfg` is architecture-agnostic. The same profile builds for any supported arch via `-a/--arch`:

```bash
./debian-preseed-iso-generator.sh --profile default --arch amd64
./debian-preseed-iso-generator.sh --profile default --arch arm64
./debian-preseed-iso-generator.sh --profile default --arch i386
```

Default arch is `amd64`. The script downloads the matching netinst ISO per arch.

## Output naming

Generated ISOs land in `out/` with the pattern:

```
out/<profile>-preseed-debian-<arch>-netinst.iso
```

## Creating a new profile

```bash
PROFILE=my-server
mkdir -p profiles/"${PROFILE}"
cp profiles/default/preseed.cfg profiles/"${PROFILE}"/preseed.cfg
# edit profiles/my-server/preseed.cfg
./debian-preseed-iso-generator.sh --profile my-server
```

## Generating password hashes

```bash
mkpasswd -m sha-512
```
