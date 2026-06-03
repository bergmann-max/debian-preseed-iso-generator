#!/usr/bin/env bash
# Generate Debian netinst ISOs with embedded preseed, one per preseed.
#
# Preseeds are directories under preseeds/ containing a preseed.cfg.
# Drop a new directory with a preseed.cfg, it builds.

set -u  # Treat unset variables as errors
set -o pipefail  # Fail if a piped command fails
# NOTE: set -e is NOT used because bash 5.x has edge-case issues with pushd/popd + set -e

VERSION="0.3.0"

_COLOR=1
[[ -n "${NO_COLOR:-}" ]] && _COLOR=0

log()  { printf "${GREEN}[%s] %s${NC}\n" "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf "${ORANGE}[%s] WARN: %s${NC}\n" "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf "${RED}[%s] ERROR: %s${NC}\n" "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Spinner

_spinner() {
    local chars=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local msg="$1"
    while true; do
        for c in "${chars[@]}"; do
            printf '\r %s %s' "$c" "$msg" >&2
            sleep .2
        done
    done
}

spinner_start() {
    _spinner "$1" &
    _SPINNER_PID=$!
}

spinner_stop() {
    if [[ -n ${_SPINNER_PID:-} ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf '\r\033[K' >&2
    fi
}

# Define constants
readonly PRESEEDS_DIR="preseeds"
readonly DEFAULT_OUTPUT_DIR="out"
readonly DEFAULT_ARCH="amd64"

# Global temp dirs for cleanup trap
CURRENT_ISOFILEDIR=""
CURRENT_PRESEED_TMPD=""

cleanup() {
    spinner_stop
    rm -f "${SHA256SUMS_FILE:-}" "${SHA256SUMS_SIGN_FILE:-}"
    [[ -n "${CURRENT_ISOFILEDIR:-}" && -d "${CURRENT_ISOFILEDIR}" ]] && rm -rf "${CURRENT_ISOFILEDIR}"
    [[ -n "${CURRENT_PRESEED_TMPD:-}" && -d "${CURRENT_PRESEED_TMPD}" ]] && rm -rf "${CURRENT_PRESEED_TMPD}"
}

# Arg parsing
SELECTED_PRESEED=""
LIST_ONLY=0
DRY_RUN=0
ARCH="${DEFAULT_ARCH}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--preseed)
            [[ $# -lt 2 ]] && { err "--preseed requires NAME"; }
            SELECTED_PRESEED="$2"
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
        --no-color)
            _COLOR=0
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
  -p, --preseed NAME   build only specified preseed
  -l, --list           list available preseeds and exit
  -o, --output DIR     output directory (default: ${DEFAULT_OUTPUT_DIR}/)
  -a, --arch ARCH      target architecture (default: ${DEFAULT_ARCH})
                       supported: amd64, arm64, i386
  -n, --dry-run        show what would be done without executing
  -h, --help           show this help
  -V, --version        print version and exit
      --no-color       disable colored output (or set NO_COLOR=1)

With no options, builds all preseeds found in ${PRESEEDS_DIR}/.
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

[[ $_COLOR -eq 1 ]] && {
    GREEN=$'\033[0;32m'
    ORANGE=$'\033[0;33m'
    RED=$'\033[0;31m'
    NC=$'\033[0m'
} || {
    GREEN=''
    ORANGE=''
    RED=''
    NC=''
}

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

# Discover preseeds
if [[ ! -d "${PRESEEDS_DIR}" ]]; then
    err "Preseeds directory '${PRESEEDS_DIR}/' not found."
fi
mapfile -t PRESEEDS < <(find "${PRESEEDS_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if [[ ${#PRESEEDS[@]} -eq 0 ]]; then
    err "No preseeds found in ${PRESEEDS_DIR}/"
fi

# --list: print preseeds and exit
if [[ ${LIST_ONLY} -eq 1 ]]; then
    printf '%s\n' "${PRESEEDS[@]}"
    exit 0
fi

# --preseed NAME: filter to single preseed
if [[ -n "${SELECTED_PRESEED}" ]]; then
    found=0
    for p in "${PRESEEDS[@]}"; do
        [[ "$p" == "${SELECTED_PRESEED}" ]] && found=1
    done
    if [[ ${found} -eq 0 ]]; then
        err "Preseed '${SELECTED_PRESEED}' not found. Available: ${PRESEEDS[*]}"
    fi
    PRESEEDS=("${SELECTED_PRESEED}")
fi

# --dry-run: show plan and exit
if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Architecture:      ${ARCH}"
    echo "Preseeds to build: ${PRESEEDS[*]}"
    echo "Output directory:  ${OUTPUT_DIR_ABS}"
    for p in "${PRESEEDS[@]}"; do
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
trap cleanup EXIT INT TERM

spinner_start "Downloading SHA256SUMS..."
curl --silent --show-error --fail "${CHECKSUM}" -o "${SHA256SUMS_FILE}" \
    || { spinner_stop; err "Failed to download SHA256SUMS"; }
spinner_stop

spinner_start "Downloading SHA256SUMS signature..."
curl --silent --show-error --fail "${CHECKSUM}.sign" -o "${SHA256SUMS_SIGN_FILE}" \
    || { spinner_stop; err "Failed to download SHA256SUMS.sign"; }
spinner_stop

if command -v gpg &> /dev/null; then
    KEYRING=""
    for candidate in /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/keyrings/debian-role-keys.gpg; do
        if [[ -f "${candidate}" ]]; then
            KEYRING="${candidate}"
            break
        fi
    done

    spinner_start "Verifying GPG signature..."
    if [[ -n "${KEYRING}" ]]; then
        if gpg --keyring "${KEYRING}" --verify "${SHA256SUMS_SIGN_FILE}" "${SHA256SUMS_FILE}" 2>/dev/null; then
            spinner_stop
            log "GPG signature verified for SHA256SUMS"
        else
            spinner_stop
            warn "GPG verification failed; proceeding with checksum only"
        fi
    else
        if gpg --verify "${SHA256SUMS_SIGN_FILE}" "${SHA256SUMS_FILE}" 2>/dev/null; then
            spinner_stop
            log "GPG signature verified for SHA256SUMS"
        else
            spinner_stop
            warn "GPG verification unavailable; install debian-archive-keyring for full verification"
        fi
    fi
fi

# Check if an ISO file already exists and verify checksum
ISO_FILE=$(find . -maxdepth 1 -name "$ISO_FILENAME" -print -quit)
if [[ -n "${ISO_FILE}" ]]; then
    log "Existing ISO found."
    spinner_start "Verifying ISO checksum..."
    EXPECTED_CHECKSUM=$(grep "${ISO_FILENAME}" "${SHA256SUMS_FILE}" | awk '{print $1}')

    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        spinner_stop
        err "No matching checksum entry found for ${ISO_FILE}."
    fi

    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    if [[ "${EXPECTED_CHECKSUM}" == "${LOCAL_CHECKSUM}" ]]; then
        spinner_stop
        log "Checksum matches. No need to download a new ISO."
    else
        spinner_stop
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

    spinner_start "Verifying downloaded ISO checksum..."
    EXPECTED_CHECKSUM=$(grep "${ISO_FILENAME}" "${SHA256SUMS_FILE}" | awk '{print $1}')
    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        spinner_stop
        err "No matching checksum entry found for ${ISO_FILE}."
    fi
    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    spinner_stop
    if [[ "${EXPECTED_CHECKSUM}" != "${LOCAL_CHECKSUM}" ]]; then
        err "Incorrect ISO downloaded."
    fi
fi

for PRESEED in "${PRESEEDS[@]}"; do
    ISOFILE="${OUTPUT_DIR_ABS}/${PRESEED}-preseed-debian-${ARCH}-netinst.iso"

    if [[ ! -d "${PRESEEDS_DIR}/${PRESEED}" ]]; then
        err "Directory ${PRESEEDS_DIR}/${PRESEED} does not exist!"
    fi

    pushd "${PRESEEDS_DIR}/${PRESEED}" > /dev/null || exit 1

    # Extract ISO contents into a temporary directory
    ISOFILEDIR=$(mktemp -d -t isofiles-XXXXXX)
    CURRENT_ISOFILEDIR="${ISOFILEDIR}"
    spinner_start "Extracting ISO contents..."
    xorriso -osirrox on -indev "../../${ISO_FILE}" -extract / "${ISOFILEDIR}" \
        || { spinner_stop; err "xorriso extraction failed"; }
    spinner_stop
    chmod --recursive u+w "${ISOFILEDIR}"

    # Prepare preseed.cfg
    PRESEED_TMPD=$(mktemp -d -t preseed-XXXXXX)
    CURRENT_PRESEED_TMPD="${PRESEED_TMPD}"
    if [[ -f preseed.cfg ]]; then
        cp preseed.cfg "${PRESEED_TMPD}/preseed.cfg"
    else
        CURRENT_PRESEED_TMPD=""
        rm -rf "${PRESEED_TMPD}"
        err "Preseed '${PRESEED}' has no preseed.cfg."
    fi

    # Append preseed.cfg into initrd
    spinner_start "Appending preseed to initrd..."
    INITRD_ABS="${ISOFILEDIR}/${INITRD_DIR}/initrd"
    gunzip "${INITRD_ABS}.gz"
    ( cd "${PRESEED_TMPD}" && echo preseed.cfg | cpio --format=newc --create --append --file="${INITRD_ABS}" )
    gzip "${INITRD_ABS}"
    spinner_stop
    rm -rf "${PRESEED_TMPD}"
    CURRENT_PRESEED_TMPD=""

    # Generate new md5sum.txt
    spinner_start "Generating checksums..."
    ( cd "${ISOFILEDIR}" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt )
    spinner_stop

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

        spinner_start "Creating bootable ISO (BIOS+UEFI)..."
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
            || { spinner_stop; err "xorriso ISO creation failed"; }
        spinner_stop
    else
        spinner_start "Creating bootable ISO (UEFI)..."
        xorriso -as mkisofs \
            -r -V "DEBIAN-PRESEED" \
            -o "${ISOFILE}" \
            -J -joliet-long \
            -e boot/grub/efi.img \
            -no-emul-boot \
            "${ISOFILEDIR}" \
            || { spinner_stop; err "xorriso ISO creation failed"; }
        spinner_stop
    fi
    log "Built ${ISOFILE}"

    rm --recursive --force "${ISOFILEDIR}"
    CURRENT_ISOFILEDIR=""

    popd > /dev/null || true
done

log "Done. ${#PRESEEDS[@]} ISO(s) built:"
for output_iso in "${OUTPUT_DIR_ABS}"/*-preseed-debian-${ARCH}-netinst.iso; do
    log "  ${output_iso}"
done
cd "${_orig_dir}" 2>/dev/null || true
