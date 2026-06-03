# Preseeds

A preseed is a directory under `preseeds/` containing a `preseed.cfg` file. The script auto-discovers all preseeds -- drop a new directory, it builds.

## Directory structure

```
preseeds/
  default/preseed.cfg
  minimal/preseed.cfg
```

## Preseed file

Place a complete `preseed.cfg` directly in the preseed directory. The file is injected as-is into the initrd.

List discovered preseeds at any time:

```bash
./debian-preseed-iso-generator.sh --list
```

## Architecture

A preseed's `preseed.cfg` is architecture-agnostic. The same preseed builds for any supported arch via `-a/--arch`:

```bash
./debian-preseed-iso-generator.sh --preseed default --arch amd64
./debian-preseed-iso-generator.sh --preseed default --arch arm64
./debian-preseed-iso-generator.sh --preseed default --arch i386
```

Default arch is `amd64`. The script downloads the matching netinst ISO per arch.

## Output naming

Generated ISOs land in `out/` with the pattern:

```
out/<preseed>-preseed-debian-<arch>-netinst.iso
```

## Creating a new preseed

```bash
PRESEED=my-server
mkdir -p preseeds/"${PRESEED}"
cp preseeds/default/preseed.cfg preseeds/"${PRESEED}"/preseed.cfg
# edit preseeds/my-server/preseed.cfg
./debian-preseed-iso-generator.sh --preseed my-server
```

## Generating password hashes

```bash
mkpasswd -m sha-512
```
