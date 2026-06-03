#!/usr/bin/env bash
# Generate Debian netinst ISOs with embedded preseed, one per profile.

set -e  # Exit on error
set -u  # Treat unset variables as errors
set -o pipefail  # Fail if a piped command fails

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Define constants
readonly NETINSTISO="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/"
readonly CHECKSUM="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
readonly PROFILES_DIR="profiles"
readonly DEFAULT_OUTPUT_DIR="out"

# Arg parsing
SELECTED_PROFILE=""
LIST_ONLY=0
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
        -o|--output)
            [[ $# -lt 2 ]] && { err "--output requires DIR"; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -p, --profile NAME   build only specified profile
  -l, --list           list available profiles and exit
  -o, --output DIR     output directory (default: ${DEFAULT_OUTPUT_DIR}/)
  -h, --help           show this help

With no options, builds all profiles found in ${PROFILES_DIR}/.
EOF
            exit 0
            ;;
        *)
            err "Unknown argument '$1' (try --help)"
            ;;
    esac
done

# Change to the script directory
BASEDIR=$(dirname "$0")
pushd "${BASEDIR}" > /dev/null || exit 1

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

# Ensure necessary commands are available
for cmd in wget curl sha256sum awk grep gunzip gzip cpio xorriso envsubst gpg; do
    if ! command -v "$cmd" &> /dev/null; then
        err "Required tool '$cmd' is not installed!"
    fi
done

# Find the latest Debian netinstall ISO filename
ISO_FILENAME=$(curl --silent "${NETINSTISO}" | grep -o 'debian-[^ ]*-amd64-netinst.iso' | head -n 1)
if [[ -z "$ISO_FILENAME" ]]; then
    err "Could not determine the latest Debian netinstall ISO filename."
fi

# Download SHA256SUMS + signature, verify GPG
SHA256SUMS_FILE=$(mktemp -t sha256sums-XXXXXX)
SHA256SUMS_SIGN_FILE=$(mktemp -t sha256sums-sign-XXXXXX)
trap 'rm -f "${SHA256SUMS_FILE}" "${SHA256SUMS_SIGN_FILE}"' EXIT

curl --silent --show-error --fail "${CHECKSUM}" -o "${SHA256SUMS_FILE}" \
    || err "Failed to download SHA256SUMS"
curl --silent --show-error --fail "${CHECKSUM}.sign" -o "${SHA256SUMS_SIGN_FILE}" \
    || err "Failed to download SHA256SUMS.sign"

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
    ISOFILE="${OUTPUT_DIR_ABS}/${PROFILE}-preseed-debian-netinst.iso"

    if [[ ! -d "${PROFILES_DIR}/${PROFILE}" ]]; then
        err "Directory ${PROFILES_DIR}/${PROFILE} does not exist!"
    fi

    pushd "${PROFILES_DIR}/${PROFILE}" > /dev/null || exit 1

    # Extract ISO contents into a temporary directory
    ISOFILEDIR=$(mktemp -d -t isofiles-XXXXXX)
    xorriso -osirrox on -indev "../../${ISO_FILE}" -extract / "${ISOFILEDIR}"
    chmod --recursive u+w "${ISOFILEDIR}"

    # Prepare preseed.cfg: raw file wins; otherwise render template from <profile>.env
    PRESEED_TMPD=$(mktemp -d -t preseed-XXXXXX)
    PROFILE_ENV="${PROFILE}.env"
    if [[ -f preseed.cfg ]]; then
        cp preseed.cfg "${PRESEED_TMPD}/preseed.cfg"
    elif [[ -f "${PROFILE_ENV}" ]]; then
        TEMPLATE="../../templates/preseed.cfg.tmpl"
        if [[ ! -f "${TEMPLATE}" ]]; then
            rm -rf "${PRESEED_TMPD}"
            err "Profile '${PROFILE}' uses ${PROFILE_ENV} but ${TEMPLATE} is missing."
        fi
        (
            set -a
            # shellcheck disable=SC1090
            source "${PROFILE_ENV}"
            set +a
            envsubst "\${LOCALE} \${KEYMAP} \${HOSTNAME} \${DOMAIN} \${MIRROR_HOST} \${MIRROR_DIR} \${MIRROR_PROXY} \${ROOT_PASSWORD_HASH} \${USER_FULLNAME} \${USER_NAME} \${USER_PASSWORD_HASH} \${TIMEZONE} \${NTP_SERVER} \${PARTITION_METHOD} \${LVM_SIZE} \${PARTITION_RECIPE} \${APT_NON_FREE_FIRMWARE} \${APT_NON_FREE} \${APT_CONTRIB} \${TASKS} \${PACKAGES} \${UPGRADE_POLICY} \${POPCON} \${GRUB_ONLY_DEBIAN} \${GRUB_WITH_OTHER_OS} \${LATE_COMMAND}" \
                < "${TEMPLATE}" > "${PRESEED_TMPD}/preseed.cfg"
        )
    else
        rm -rf "${PRESEED_TMPD}"
        err "Profile '${PROFILE}' has neither preseed.cfg nor ${PROFILE_ENV}."
    fi

    # Append preseed.cfg into initrd
    INITRD_ABS="$(pwd)/${ISOFILEDIR}/install.amd/initrd"
    gunzip "${INITRD_ABS}.gz"
    ( cd "${PRESEED_TMPD}" && echo preseed.cfg | cpio --format=newc --create --append --file="${INITRD_ABS}" )
    gzip "${INITRD_ABS}"
    rm -rf "${PRESEED_TMPD}"

    # Generate new md5sum.txt
    pushd "${ISOFILEDIR}" > /dev/null
    find . -type f -print0 | xargs -0 md5sum > md5sum.txt
    popd > /dev/null

    # Create bootable hybrid ISO (BIOS + UEFI) via xorriso
    ISOHDPFX=$(find "${ISOFILEDIR}" -name 'isohdpfx.bin' -print -quit)
    [[ -z "${ISOHDPFX}" ]] && ISOHDPFX="/usr/lib/ISOLINUX/isohdpfx.bin"
    if [[ ! -f "${ISOHDPFX}" ]]; then
        err "isohdpfx.bin not found (looked in ISO and /usr/lib/ISOLINUX/)."
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
        "${ISOFILEDIR}"

    # Clean up temporary directory
    rm --recursive --force "${ISOFILEDIR}"

    popd > /dev/null
done

popd > /dev/null

