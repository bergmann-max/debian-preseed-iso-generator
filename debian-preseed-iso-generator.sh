#!/usr/bin/env bash
# Generate Debian netinst ISOs with embedded preseed, one per profile.
#
# Profiles are directories under profiles/ containing a preseed.cfg.
# Drop a new directory with a preseed.cfg, it builds.

set -u  # Treat unset variables as errors
set -o pipefail  # Fail if a piped command fails
# NOTE: set -e is NOT used because bash 5.x has edge-case issues with pushd/popd + set -e

VERSION="0.2.0"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Define constants
readonly PROFILES_DIR="profiles"
readonly DEFAULT_OUTPUT_DIR="out"
readonly DEFAULT_ARCH="amd64"

# Global temp dirs for cleanup trap
CURRENT_ISOFILEDIR=""
CURRENT_PRESEED_TMPD=""

cleanup() {
    rm -f "${SHA256SUMS_FILE:-}" "${SHA256SUMS_SIGN_FILE:-}"
    [[ -n "${CURRENT_ISOFILEDIR:-}" && -d "${CURRENT_ISOFILEDIR}" ]] && rm -rf "${CURRENT_ISOFILEDIR}"
    [[ -n "${CURRENT_PRESEED_TMPD:-}" && -d "${CURRENT_PRESEED_TMPD}" ]] && rm -rf "${CURRENT_PRESEED_TMPD}"
}

# Arg parsing
SELECTED_PROFILE=""
LIST_ONLY=0
DRY_RUN=0
ARCH="${DEFAULT_ARCH}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            [[ $# -lt 2 ]] && { err "--profile requires NAME"; }
            SELECTED_PROFILE="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;; 
        -o|--output)
            [[ $# -lt 2 ]] && { err "--output requires DIR"; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -a|--arch)
            [[ $# -lt 2 ]] && { err "--arch requires ARCH"; }
            ARCH="$2"
            shift 2
            ;; 
        -h|--help)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -p, --profile NAME   build only specified profile
  -l, --list           list available profiles and exit
  -o, --output DIR     output directory (default: ${DEFAULT_OUTPUT_DIR}/)
  -a, --arch ARCH      target architecture (default: ${DEFAULT_ARCH})
                       supported: amd64, arm64, i386
  -n, --dry-run        show what would be done without executing
  -h, --help           show this help
  -V, --version        print version and exit

With no options, builds all profiles found in ${PROFILES_DIR}/.
EOF
            exit 0
            ;;
        -V|--version)
            echo "debian-preseed-iso-generator ${VERSION}"
            exit 0
            ;;
        *)
            err "Unknown argument '$1' (try --help)"
            ;;
    esac
done

# Validate architecture and map to initrd directory
case "${ARCH}" in
    amd64) INITRD_DIR="install.amd" ;;
    arm64) INITRD_DIR="install.a64" ;;
    i386)  INITRD_DIR="install.i386" ;;
    *)     err "Unsupported architecture '${ARCH}'. Supported: amd64, arm64, i386" ;;
esac

NETINSTISO="https://cdimage.debian.org/debian-cd/current/${ARCH}/iso-cd/"
CHECKSUM="${NETINSTISO}SHA256SUMS"

# Change to the script directory
BASEDIR=$(dirname "$0")
_orig_dir="${PWD}"
cd "${BASEDIR}" || exit 1

# Resolve output directory to absolute path
if [[ "${OUTPUT_DIR}" = /* ]]; then
    OUTPUT_DIR_ABS="${OUTPUT_DIR}"
else
    OUTPUT_DIR_ABS="${PWD}/${OUTPUT_DIR}"
fi
mkdir -p "${OUTPUT_DIR_ABS}"

# Discover profiles
if [[ ! -d "${PROFILES_DIR}" ]]; then
    err "Profiles directory '${PROFILES_DIR}/' not found."
fi
mapfile -t PROFILES < <(find "${PROFILES_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if [[ ${#PROFILES[@]} -eq 0 ]]; then
    err "No profiles found in ${PROFILES_DIR}/"
fi

# --list: print profiles and exit
if [[ ${LIST_ONLY} -eq 1 ]]; then
    printf '%s\n' "${PROFILES[@]}"
    exit 0
fi

# --profile NAME: filter to single profile
if [[ -n "${SELECTED_PROFILE}" ]]; then
    found=0
    for p in "${PROFILES[@]}"; do
        [[ "$p" == "${SELECTED_PROFILE}" ]] && found=1
    done
    if [[ ${found} -eq 0 ]]; then
        err "Profile '${SELECTED_PROFILE}' not found. Available: ${PROFILES[*]}"
    fi
    PROFILES=("${SELECTED_PROFILE}")
fi

# --dry-run: show plan and exit
if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Architecture:      ${ARCH}"
    echo "Profiles to build: ${PROFILES[*]}"
    echo "Output directory:  ${OUTPUT_DIR_ABS}"
    for p in "${PROFILES[@]}"; do
        echo "  -> ${OUTPUT_DIR_ABS}/${p}-preseed-debian-${ARCH}-netinst.iso"
    done
    echo "ISO source:        ${NETINSTISO}"
    echo "ISO will be downloaded if not cached with matching checksum."
    exit 0
fi
for cmd in wget curl sha256sum awk grep gunzip gzip cpio xorriso; do
    if ! command -v "$cmd" &> /dev/null; then
        err "Required tool '$cmd' is not installed!"
    fi
done

if ! command -v gpg &> /dev/null; then
    warn "gpg not found; GPG signature verification skipped (install gnupg for full verification)"
fi

# Find the latest Debian netinstall ISO filename
ISO_FILENAME=$(curl --silent "${NETINSTISO}" | grep -o "debian-[^ ]*-${ARCH}-netinst.iso" | head -n 1)
if [[ -z "$ISO_FILENAME" ]]; then
    err "Could not determine the latest Debian netinstall ISO filename."
fi

# Download SHA256SUMS + signature, verify GPG
SHA256SUMS_FILE=$(mktemp -t sha256sums-XXXXXX)
SHA256SUMS_SIGN_FILE=$(mktemp -t sha256sums-sign-XXXXXX)
trap cleanup EXIT

curl --silent --show-error --fail "${CHECKSUM}" -o "${SHA256SUMS_FILE}" \
    || err "Failed to download SHA256SUMS"
curl --silent --show-error --fail "${CHECKSUM}.sign" -o "${SHA256SUMS_SIGN_FILE}" \
    || err "Failed to download SHA256SUMS.sign"

if command -v gpg &> /dev/null; then
    KEYRING=""
    for candidate in /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/keyrings/debian-role-keys.gpg; do
        if [[ -f "${candidate}" ]]; then
            KEYRING="${candidate}"
            break
        fi
    done

    if [[ -n "${KEYRING}" ]]; then
        if gpg --keyring "${KEYRING}" --verify "${SHA256SUMS_SIGN_FILE}" "${SHA256SUMS_FILE}" 2>/dev/null; then
            log "GPG signature verified for SHA256SUMS"
        else
            warn "GPG verification failed; proceeding with checksum only"
        fi
    else
        if gpg --verify "${SHA256SUMS_SIGN_FILE}" "${SHA256SUMS_FILE}" 2>/dev/null; then
            log "GPG signature verified for SHA256SUMS"
        else
            warn "GPG verification unavailable; install debian-archive-keyring for full verification"
        fi
    fi
fi

# Check if an ISO file already exists and verify checksum
ISO_FILE=$(find . -maxdepth 1 -name "$ISO_FILENAME" -print -quit)
if [[ -n "${ISO_FILE}" ]]; then
    log "Existing ISO found. Verifying checksum..."
    EXPECTED_CHECKSUM=$(grep "${ISO_FILENAME}" "${SHA256SUMS_FILE}" | awk '{print $1}')

    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        err "No matching checksum entry found for ${ISO_FILE}."
    fi

    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    if [[ "${EXPECTED_CHECKSUM}" == "${LOCAL_CHECKSUM}" ]]; then
        log "Checksum matches. No need to download a new ISO."
    else
        warn "Checksum mismatch! Downloading a new ISO..."
        rm --verbose --force "${ISO_FILE}"
        ISO_FILE=""
    fi
fi

# Download ISO if not present or checksum mismatch
if [[ -z "${ISO_FILE}" ]]; then
    log "Downloading latest Debian netinstall ISO: ${ISO_FILENAME}"
    wget --no-parent --show-progress --directory-prefix="./" \
         "${NETINSTISO}${ISO_FILENAME}"

    ISO_FILE=$(find . -maxdepth 1 -name "$ISO_FILENAME" -print -quit)

    log "Verifying downloaded ISO checksum..."
    EXPECTED_CHECKSUM=$(grep "${ISO_FILENAME}" "${SHA256SUMS_FILE}" | awk '{print $1}')
    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        err "No matching checksum entry found for ${ISO_FILE}."
    fi
    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    if [[ "${EXPECTED_CHECKSUM}" != "${LOCAL_CHECKSUM}" ]]; then
        err "Incorrect ISO downloaded."
    fi
fi

for PROFILE in "${PROFILES[@]}"; do
    ISOFILE="${OUTPUT_DIR_ABS}/${PROFILE}-preseed-debian-${ARCH}-netinst.iso"

    if [[ ! -d "${PROFILES_DIR}/${PROFILE}" ]]; then
        err "Directory ${PROFILES_DIR}/${PROFILE} does not exist!"
    fi

    pushd "${PROFILES_DIR}/${PROFILE}" > /dev/null || exit 1

    # Extract ISO contents into a temporary directory
    ISOFILEDIR=$(mktemp -d -t isofiles-XXXXXX)
    CURRENT_ISOFILEDIR="${ISOFILEDIR}"
    xorriso -osirrox on -indev "../../${ISO_FILE}" -extract / "${ISOFILEDIR}" \
        || err "xorriso extraction failed"
    chmod --recursive u+w "${ISOFILEDIR}"

    # Prepare preseed.cfg
    PRESEED_TMPD=$(mktemp -d -t preseed-XXXXXX)
    CURRENT_PRESEED_TMPD="${PRESEED_TMPD}"
    if [[ -f preseed.cfg ]]; then
        cp preseed.cfg "${PRESEED_TMPD}/preseed.cfg"
    else
        CURRENT_PRESEED_TMPD=""
        rm -rf "${PRESEED_TMPD}"
        err "Profile '${PROFILE}' has no preseed.cfg."
    fi

    # Append preseed.cfg into initrd
    INITRD_ABS="${ISOFILEDIR}/${INITRD_DIR}/initrd"
    gunzip "${INITRD_ABS}.gz"
    ( cd "${PRESEED_TMPD}" && echo preseed.cfg | cpio --format=newc --create --append --file="${INITRD_ABS}" )
    gzip "${INITRD_ABS}"
    rm -rf "${PRESEED_TMPD}"
    CURRENT_PRESEED_TMPD=""

    # Generate new md5sum.txt
    ( cd "${ISOFILEDIR}" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt )

    # Create bootable ISO via xorriso
    # amd64/i386: BIOS + UEFI hybrid. arm64: UEFI-only.
    x86_arch=0
    [[ "${ARCH}" == "amd64" || "${ARCH}" == "i386" ]] && x86_arch=1

    if [[ ${x86_arch} -eq 1 ]]; then
        ISOHDPFX=$(find "${ISOFILEDIR}" -name 'isohdpfx.bin' -print -quit)
        if [[ -z "${ISOHDPFX}" ]]; then
            for candidate in /usr/lib/ISOLINUX/isohdpfx.bin \
                             /usr/lib/syslinux/bios/isohdpfx.bin \
                             /usr/lib/syslinux/mbr/isohdpfx.bin \
                             /usr/share/syslinux/isohdpfx.bin; do
                if [[ -f "${candidate}" ]]; then
                    ISOHDPFX="${candidate}"
                    break
                fi
            done
        fi
        if [[ -z "${ISOHDPFX}" ]]; then
            err "isohdpfx.bin not found. Install isolinux (Debian) or syslinux (Arch)."
        fi

        xorriso -as mkisofs \
            -r -V "DEBIAN-PRESEED" \
            -o "${ISOFILE}" \
            -J -joliet-long \
            -isohybrid-mbr "${ISOHDPFX}" \
            -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -boot-load-size 4 -boot-info-table -no-emul-boot \
            -eltorito-alt-boot \
            -e boot/grub/efi.img \
            -no-emul-boot -isohybrid-gpt-basdat \
            "${ISOFILEDIR}" \
            || err "xorriso ISO creation failed"
    else
        xorriso -as mkisofs \
            -r -V "DEBIAN-PRESEED" \
            -o "${ISOFILE}" \
            -J -joliet-long \
            -e boot/grub/efi.img \
            -no-emul-boot \
            "${ISOFILEDIR}" \
            || err "xorriso ISO creation failed"
    fi

    rm --recursive --force "${ISOFILEDIR}"
    CURRENT_ISOFILEDIR=""

    popd > /dev/null || true
done

cd "${_orig_dir}" 2>/dev/null || true
