#!/usr/bin/env bash
#
# PNetLab 27H1 network-install bootstrap.
#
# Fresh-installs PNetLab from a signed release manifest (see
# docs/release-manifest-schema.md) instead of a hardcoded version pin. The
# initial download of this script is unsigned (plain HTTPS + checksum only);
# the embedded manifest fingerprint below is the trust anchor for every
# manifest, apt, and core-assets fetch that follows. Nothing mutates the host
# until the manifest, apt origins, and exact package transaction all verify.
#
# Master profile only configures the web/DB/console stack; satellite profile
# does not. Pass 1 brings up the cloud bridge devices but does not perform the
# ifupdown/uplink/NAT handoff (see the Pass 1 note further down).
#

set -Eeuo pipefail
umask 022

readonly PROGRAM="${0##*/}"

# Trust anchor: the maintainer's OFFLINE master key, not the live signing
# subkey -- gpg VALIDSIG reports the primary key even when a subkey signed, so
# pinning the primary lets the subkey rotate without republishing every
# already-shipped bootstrap. Never overridable by any flag or env var.
readonly PNETLAB_BOOTSTRAP_VERSION='2026.08.26'
readonly PNETLAB_MANIFEST_FPR='158D99DF8D57040AA8E0EDA58F353DF9007A2BB4'
readonly MIN_MANIFEST_SEQUENCE=1
readonly MANIFEST_KEYRING='/usr/share/keyrings/pnetlab-release-manifest.gpg'
readonly DEFAULT_GENERIC_OWNER='netkillui'
readonly DEFAULT_GENERIC_PACKAGE='pnetlab-core-assets'
readonly DEFAULT_POINTER_VERSION='0.channel'
# --- DISTRIBUTION HOST (Phase 1 / R2 track) -------------------------------
# The single place the default distribution host is chosen. Flipping the
# default to R2 is an edit of PNETLAB_DEFAULT_GENERIC_API_BASE alone; the
# Codeberg value below stays valid as the documented env-var fallback:
#   PNETLAB_GENERIC_API_BASE=https://codeberg.org/api/packages
readonly PNETLAB_DEFAULT_GENERIC_API_BASE='https://codeberg.org/api/packages'
# --------------------------------------------------------------------------
readonly POINTER_NAME='pnetlab-latest.json'
readonly PNETLAB_MANIFEST_PUBKEY="$(cat <<'ARMOR'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGqKUBgBEAC56Gd8JpGuNhxAqPleJDGNNhzyH+doBPJXloz6xHCk4b7ozLWv
gZLGOz0p84oqdNiwFpYow1j6foFF+WkKpAutvSAAKxxa6GYbqLBsJL2XmADvAC5a
X6XJ8Y5aEa3k5+s48RxnriUrYUHI9nVADbz5Z4XZBCIu5jx9Q8uPvZ4yTx0aUNEY
kbkj53LbriU1WV83qy4FuZnjwX/tHdR1xTI2k4TVZlMq/k4HYDhw2xQxk3/hlPaz
SkMbRvyvEkXuU0e3i6LZq0eIdjYfrQ9L/EZ/TBjKozy3+AW13b8dXGn9pYQqxvK8
Vd77ndytrWKiWUuhdQu5oGGLE8CkEBVFKDHO2b/dLsNoLiGojYeLb/gQIyvup1Md
Hvrqcrjy9XOlPvJaF8czamdRS0ZWb+UZk5+jt85SQ3NoGpHiKw/xFN8SSq1xPHO0
zPSS7NoWuFuL6ldnTwWOBXbZSpahvc6r6r+u3A8rC3GxfEq2fNNsodzeSwQvPLSz
ciG46+nMVHVZWvT62vbthdpr/KYvOHaH+4KC7Ey0/B7Yeg06vJUi9yUDyEj/x2Wg
Mv+MTx6kvElaVW7g63FgLPOJ5dZdtCg9f4ou4MPWl+uFVYkJJvDLhAG0rlFLmAWp
qM21Ky0Xc4q5PoX+XtzeB80dz9lEXlricKEbxMd9ehuqYK99x8SX4hYppwARAQAB
tCFuZXRraWxsdWkgPG5vcmVwbHlAcG5ldGxhYnY4Lm9yZz6JAlQEEwEKAD4WIQQV
jZnfjVcECqjg7aWPNT35AHortAUCaopQGAIbAQUJA8JnAAULCQgHAgYVCgkICwIE
FgIDAQIeAQIXgAAKCRCPNT35AHortNcjEACe2s118gICY2PbdJLIx1z+ft+htX3g
NMbJzKsLIQ8mQTKZbJQuMwBg89Xro7p1Dfn1py6cJ35blf7k1PuW0yP43CL87sXC
XWceFopZbFHUfngeNiMZ5phKSGdPL4LlzPdh5ydKyFZrbxUixTdNZ1GMODJZOGSS
pSgRoDQ4G902aR/lTvAktRaXbM/1uedbdZ3vGY49nyrAAfP4jOBM1sUDxwB9fNFI
RG81Sbiw8mJoJh1lkydIGfyagmkV9rqUVaLDRfwa/vYLO0bwlGkd/98GUHpszghz
WL6fqr3ZSw5Mh+9jz8Mn+m5Jvo0RSXLaMPZ624bwSmeF56bHDSLjmFspgFVcO6kr
i7K1H9nM9gKzwVfHlpH+b8aGd5GaYwKXsoDZ2DYZUTlufeEiWDqmRTPpBtszdqlC
j/GGUyTpTZAta5HWo+MRd9DeHGXuLxEGeNWTMkIRGtrFSans4EyYcC33k4E3sVq6
gJSMsRlQ0tlIYfBL+95yheD4xGOHpWDa8LN+jUprQfeCbwMdF9Bcb9wvdljfZMWR
syCJ1pqvGoErZq/ROqYBQE7SIquYs58aPVKTwg5wjWVxSr7maVTKTC31zVmNUbua
4zKS2Yv0AqLMQkD3tKdnLwgVFiCGRnFwZzEnQAWmancSDEqvLv/dqaQ9xfjnTc/I
J8Dw+jgR6M5w27kCDQRqilCRARAAusxUWJyaG5/GQWF6SplMHXWdx01OMtvd3HRN
Q4aI3meSrvTEO9QJh7fbLh75oiTethVRFjOLEQP4qN8Ovcp3ajZlzxq3VfDA1QuH
6FxQUaHFlXAC2GwOlZNXjXddj0EoxRC/VDCdshhXhRWhfAzyIa8ittkrI0EsJnzK
vT8F8C4JxOiPBWlCCqdxxmmGOtITZbhwY/O0IqcCgdOrySRcY99cIoxTcT59Wva7
wTwunOFZyl4Dz98p5eUIQfCOa3ZON8KDK32q9vB3G55Rz+0NGYcT1vhCVI+O8vgq
mqDF0SvMa0BxKRrGExb5be0JCYMus5efJQww2rlahRTrGjIEp370EOeaSuTq8r3T
GuqZUwBW5IWw6QAS/+ErUjDdf6X+1kEkw+yphRD8xwD5oO1aw1NonZBa50vt2Bba
Ft0EuWa6CCCQdI4+PZf2yzSk28WgTSIGyPEsQFL4HPxPoiNn2pCwSP7lieRLlf+f
8yxWkv7rb7IY9Ji1beRGP6E8mQB1Exm8+pl1Q6QkKoRIIoMRXOypLJGCOoOh0cXg
dlFzYE++MIS6nCnJ5Ptz3FnSYKFZ9wb1OEyrIufZYUbPqxeXvUkmdJC/dY4WLBjx
qRRMGCwUedOgAxesmWyrSbYnfb9Y5GZSMy4oZBNnwSIfA2tjiLTghR6+U2pFX0j+
63fqPtMAEQEAAYkEcgQYAQoAJhYhBBWNmd+NVwQKqODtpY81PfkAeiu0BQJqilCR
AhsCBQkDwmcAAkAJEI81PfkAeiu0wXQgBBkBCgAdFiEE0hDfePQxaY+j+aYEIVaa
E7M5KzAFAmqKUJEACgkQIVaaE7M5KzCIvRAAo/M9lej7AFk0CF/xNgHv49GezTfe
6esOrOjuNoADu/6UPaqOkOTVYz9zyaVnZ8b7mPFpSk3fhvtQBo2CYekvYOY2De7I
kZX32WgBMkJVcVLB0NNexkg9io8ntUqE9IY46thSKX41cdblN2ruKjt++hrmwTv0
sahbbwGny6aZ56UKgfLOeeE0utm0hWbQdpJUn3oCvLYOiIdGWLRmTgHVqPoV1ny7
P457ovC0+uYxzsi2jwyoqbiLgUHhMsRACJZniJaA2ou4mkDDs97voCmRkboNofVX
2vtBZyQOo7+ZfN/30zIgGUtGr2E4mQCShwFxI+70XoqXgL8LWO2Td7QCPkVSjW6A
4fJ8V9KYNuO2l0Iw6/boQVlIa03+bpR76fVFp3AOCXiJASlrJ2lTIWrJeJzOmOtX
wAROcKKRauKNSf+BOfyngoSRkNW42aXEBfpMpvlN2HWFO4KBGapX3D0siBrcw7gZ
YzgeZdxjjKk9czBVcSsjw5ACFXbapQRP3BpprKJagr7+E4+RHF8dMlfWdlsZnMkY
fq0pPpZw90XYSefKuBo4vi8Nd+smYHBtgVRaOkRdUUZ2ZVn6JkTxXiO/CV5v3gWH
4vCgJB5g8PHzwJM3GmVbHKSN5h/jsSbgRM92iPh7aOZak0gYW9GPO2jld8hUVcUg
f9WW3AuT4yUf2XNgFQ//Q01frZUru0x/8kJ7HXK4qLX83Sj/5DFjWOPMibw3H/gL
ESA0tsAgKYi5vRb9D1ohjKQG/8Xwk7bNWUDBAfIUcUPnkqQ2C9uPYi04RRWg/UtN
HOwQAR1Sv9t/xdKBiYa+GxOhcj0mZIiMgCg7EkPJ9F7RXPpG1cWlzOU5lu7TuSeY
uKE/E4N6HombPy2TbZZblCFj8VjdyOA3eiRu+U3qtzcNVC5GcM53MX4fGKHiltOy
Ura/6X9I6TnEk+/AokIblO4VTfK6swWK4SULaUtD01OFsbdg5lw9M6zs1Hv5M3n/
i78rRWzUmYLX3M4RUB/ZqD6CU6MzAY976cm3Wcr599n9wU5ZpqWMGmS2ZuiBEk21
3AVbAO6f6jS87TWIYMTwcmyzMYM6QIDpeYj3mI0J96sKnwPgo4cOHyMQ2aHUanmx
dHuzTsrk8t8BqkURWXq8ZsQRrKXq571Bkg+Ln8OKeYentofVidB19coiz9FYxVGz
2Wmrip8Wn96zd3nkCylWf3a3bhtIg0UogwF/IXLRVf2laIzSY1xwACKGUuAH2iBn
OZUX+5dVqrFmNTllP+vMig2NMLrOuBCtx0usXPk6nwd+Ht0L4lQ3kdIFLdq1104e
JZfwmNnGhsghB6BszL/EQqM7DDe9BEMfmRVG2vrtGRK8GBJ6kMTE3otupek6jaY=
=r60v
-----END PGP PUBLIC KEY BLOCK-----
ARMOR
)"

# Set from the verified manifest at runtime (main()); not hardcoded, because
# the whole point of the manifest scheme is that the deb source and its
# expected key travel with the signed manifest, not with this script.
CODEBERG_REPOSITORY=''
CODEBERG_KEY_URL=''
readonly CODEBERG_KEYRING='/usr/share/keyrings/pnetlab-netinstall-codeberg.gpg'
readonly CODEBERG_SOURCE='/etc/apt/sources.list.d/pnetlab-netinstall-codeberg.list'
readonly DOCKER_KEY_URL='https://download.docker.com/linux/ubuntu/gpg'
readonly DOCKER_KEYRING='/etc/apt/keyrings/docker.gpg'
readonly DOCKER_SOURCE='/etc/apt/sources.list.d/docker.list'
readonly LOG='/var/log/pnetlab-network-install.log'
readonly HTML='/opt/unetlab/html'
readonly ROOT_PASSWORD='pnet'
readonly MYSQL_ROOT_PASSWORD='pnetlab'
readonly PNETLAB_DEB_CACHE_ROOT="${PNETLAB_DEB_CACHE_ROOT:-/var/cache/pnetlab/debs}"
readonly PNETLAB_DEB_CACHE_LOCK="$PNETLAB_DEB_CACHE_ROOT/.lock"
readonly PNETLAB_DEB_CACHE_LOCK_FD=8   # FD 9 is reserved by pnetlab-update's whole-process lock
readonly APT_CACHE=/var/cache/apt/archives
readonly PNETLAB_CLUSTER_ASSET_CACHE_ROOT="${PNETLAB_CLUSTER_ASSET_CACHE_ROOT:-/var/cache/pnetlab/cluster-assets}"
readonly -a SATELLITE_ZOO_VERSIONS=(2.4.0 2.12.0 4.1.0 5.2.0)
readonly -a SATELLITE_HARD_PACKAGES=(pnetlab-docker pnetlab-qemu pnetlab-satellite pnetlab-vpcs)

readonly -a DOCKER_PACKAGES=(
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
)
readonly -a BASE_PACKAGES=(
    ca-certificates curl gnupg iproute2 mysql-server openssl php8.5-fpm python3-pip uml-utilities
    # inotify-tools: docker_image_watcher.sh (config_scripts) shells out to
    # `inotifywait`, stderr-suppressed, so a missing binary makes
    # pnetlab-docker-image-watcher.service exit clean and silently do nothing
    # rather than fail loudly. The offline bundle installer already pulls this
    # in as part of its own base dependency list; netinstall never did.
    inotify-tools
)

# Populated from the verified manifest's install_profiles selection (main()).
declare -A PROFILE_DEBS=()
declare -A PROFILE_BEST_EFFORT=()
declare -A SATELLITE_PROFILE_DEBS=()
declare -A SATELLITE_PROFILE_BEST_EFFORT=()
declare -a CODEBERG_PACKAGES=()
declare -a CODEBERG_PACKAGE_NAMES=()
declare -a CACHE_PACKAGES=()
MANIFEST_FILE=''
POINTER_TMP_DIR=''
POINTER_RELEASE=''
POINTER_SEQUENCE=''
POINTER_USED=0
DEB_SOURCE=''
DEB_SOURCE_KEY_FPR=''
MANIFEST_RELEASE=''
MANIFEST_SEQUENCE=''
CLUSTER_ASSET_CACHE=''

NO_DOCKER=0
NO_DEB_CACHE=0
YES=0
MANIFEST_SOURCE=''
RELEASE_HINT=''
PROFILE='master'
UPDATE_TMP=''
PNET_SYSROOT="${PNET_SYSROOT:-}"
COOKIE_TMP=''
SESSION_TMP=''

# Pass 2 is deliberately kept in this script rather than a second helper: the
# package transaction and the first-boot handoff have to share one process,
# one log, and (most importantly) the existing EXIT cleanup path below.
P2_NO_CLOUD_UPLINK=0
P2_UPLINK_NIC_OVERRIDE=''
P2_UPLINK_MODE_OVERRIDE=''
P2_UPLINK_ADDRESS_OVERRIDE=''
P2_UPLINK_GATEWAY_OVERRIDE=''
P2_UPLINK_DNS_OVERRIDE=''
P2_ALREADY_PROVISIONED=0
P2_UPLINK_MODE=''
P2_UPLINK_NIC=''
P2_UPLINK_MAC=''
P2_UPLINK_ADDRESS=''
P2_UPLINK_GATEWAY=''
P2_UPLINK_DNS=''
P2_INTERFACES_SNAPSHOT=''
P2_INTERFACES_PRE_KIND='absent'
P2_INTERFACES_PRE_HAS_LO=0
P2_SOURCE_DIRECTIVE=''
P2_BASELINE_TMP=''
P2_TXN=''
P2_TXN_ID=''
P2_TXN_PARENT=''
P2_NETPLAN_TXN_DIR=''
P2_TXN_ACTIVE=0
P2_ROLLING_BACK=0
P2_RECORD_NUMBER=0
P2_PROVISIONED=0
P2_INTERRUPT=0
P2_ROOT="${PNETLAB_PASS2_ROOT:-}"
P2_SYSFS_ROOT="${PNETLAB_SYSFS_ROOT:-/sys}"
P2_PROC_ROOT="${PNETLAB_PROC_ROOT:-/proc}"
declare -A P2_RECORDED=()

mkdir -p "${LOG%/*}"
touch "$LOG"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" | tee -a "$LOG"
}

warn() {
    printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" | tee -a "$LOG" >&2
}

die() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" | tee -a "$LOG" >&2
    exit 1
}

cleanup() {
    [ -z "$UPDATE_TMP" ] || rm -f "$UPDATE_TMP"
    [ -z "$COOKIE_TMP" ] || rm -f "$COOKIE_TMP"
    [ -z "$SESSION_TMP" ] || rm -f "$SESSION_TMP"
    [ -z "$POINTER_TMP_DIR" ] || rm -rf -- "$POINTER_TMP_DIR"
    [ -z "${MANIFEST_FILE:-}" ] || rm -rf -- "$(dirname -- "$MANIFEST_FILE")"
    [ -z "$P2_INTERFACES_SNAPSHOT" ] || rm -f -- "$P2_INTERFACES_SNAPSHOT"
    [ -z "$P2_BASELINE_TMP" ] || rm -f -- "$P2_BASELINE_TMP"
}

on_exit() {
    local rc=$?
    if [ "${P2_TXN_ACTIVE:-0}" -eq 1 ]; then
        p2_rollback || true
    fi
    cleanup
    if [ "$rc" -eq 0 ]; then
        log '=== network install completed ==='
    else
        log "=== network install stopped with exit ${rc} ==="
    fi
    return "$rc"
}
trap on_exit EXIT
trap 'P2_INTERRUPT=1; exit 130' INT
trap 'P2_INTERRUPT=1; exit 143' TERM

usage() {
    cat <<'EOF'
Usage: network-install-pnetlab-27H1.sh --yes [--manifest URL|FILE] [--release VERSION]
                                        [--profile master|satellite] [--no-docker]
                                        [--no-deb-cache] [--no-cloud-uplink]
                                        [--uplink-nic NAME] [--uplink-mode dhcp|static]
                                        [--uplink-address CIDR] [--uplink-gateway IP]
                                        [--uplink-dns IP[,IP...]]

Options:
  --yes         Required for non-interactive use; authorizes package mutation
                after the complete preflight/simulation gate passes.
  --manifest URL|FILE  Signed release manifest source (triplet: FILE, FILE.sha256,
                FILE.sig for a local path; the same three suffixed URLs for an
                https:// URL ending in .json). Defaults to the generic-package
                URL derived from --release when --manifest is omitted.
  --release VERSION    Exact 6.8.<NN>resolute1 release, or latest to resolve
                the signed 0.channel pointer. Ignored if --manifest is given.
  --profile master|satellite  Install profile selected from the manifest's
                install_profiles (default: master).
  --no-docker   Skip Docker repository and pnetlab-docker enrollment/install,
                use --no-install-recommends, and assert docker-ce is absent.
  --no-deb-cache  Opt out of the default local rollback deb cache; this host
                  then has no local rollback material for this release.
  --no-cloud-uplink  Install Pass 1 only; explicitly accept that Pass 2 will
                     not hand the management NIC to pnet0.
  --uplink-nic NAME  Select the sole eligible physical uplink by name.
  --uplink-mode dhcp|static  Override the fail-closed addressing decision.
  --uplink-address CIDR  Override the management IPv4 address.
  --uplink-gateway IP  Override the management default gateway.
  --uplink-dns IP[,IP...]  Override the static-mode DNS servers.
  -h, --help    Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes) YES=1 ;;
        --no-docker) NO_DOCKER=1 ;;
        --no-deb-cache) NO_DEB_CACHE=1 ;;
        --no-cloud-uplink) P2_NO_CLOUD_UPLINK=1 ;;
        --uplink-nic) [ "$#" -ge 2 ] || { echo "ERROR: --uplink-nic requires a name" >&2; exit 1; }; P2_UPLINK_NIC_OVERRIDE="$2"; shift ;;
        --uplink-mode) [ "$#" -ge 2 ] || { echo "ERROR: --uplink-mode requires dhcp or static" >&2; exit 1; }; P2_UPLINK_MODE_OVERRIDE="$2"; shift ;;
        --uplink-address) [ "$#" -ge 2 ] || { echo "ERROR: --uplink-address requires CIDR" >&2; exit 1; }; P2_UPLINK_ADDRESS_OVERRIDE="$2"; shift ;;
        --uplink-gateway) [ "$#" -ge 2 ] || { echo "ERROR: --uplink-gateway requires an IPv4 address" >&2; exit 1; }; P2_UPLINK_GATEWAY_OVERRIDE="$2"; shift ;;
        --uplink-dns) [ "$#" -ge 2 ] || { echo "ERROR: --uplink-dns requires one or more IPv4 addresses" >&2; exit 1; }; P2_UPLINK_DNS_OVERRIDE="$2"; shift ;;
        --manifest) [ "$#" -ge 2 ] || { echo "ERROR: --manifest requires URL or FILE" >&2; exit 1; }; MANIFEST_SOURCE="$2"; shift ;;
        --release) [ "$#" -ge 2 ] || { echo "ERROR: --release requires VERSION" >&2; exit 1; }; RELEASE_HINT="$2"; shift ;;
        --profile) [ "$#" -ge 2 ] || { echo "ERROR: --profile requires master or satellite" >&2; exit 1; }; PROFILE="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
    shift
done

[ "$YES" -eq 1 ] || [ -t 0 ] || die 'non-interactive execution requires --yes'
[[ "$PROFILE" == master || "$PROFILE" == satellite ]] || die "--profile must be master or satellite, got: $PROFILE"
if [ -n "$RELEASE_HINT" ]; then
    [[ "$RELEASE_HINT" == latest || "$RELEASE_HINT" =~ ^6\.8\.[0-9]+resolute1$ ]] \
        || die "--release must be latest or 6.8.<NN>resolute1, got: $RELEASE_HINT"
fi
[ -n "$MANIFEST_SOURCE" ] || [ -n "$RELEASE_HINT" ] || die '--manifest or --release is required'

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

run_logged() {
    log "+ $*"
    "$@" >>"$LOG" 2>&1 || return $?
}

apt_update_checked() {
    UPDATE_TMP=$(mktemp /tmp/pnetlab-netinstall-apt-update.XXXXXX)
    log '+ apt-get update (Codeberg and Docker signatures required)'
    if ! apt-get update 2>&1 | tee -a "$LOG" "$UPDATE_TMP"; then
        die 'apt-get update failed'
    fi
    if grep -Eiq '(^|[^[:alpha:]])(NO_PUBKEY|GPG error|The following signatures were invalid|does not have a Release file|Some index files failed to download)' "$UPDATE_TMP"; then
        die 'apt-get update emitted a signature or index-integrity failure'
    fi
    rm -f "$UPDATE_TMP"
    UPDATE_TMP=''
}

validate_existing_keyring() {
    local keyring="$1" home
    home=$(mktemp -d /tmp/pnetlab-netinstall-gpg.XXXXXX)
    if ! GNUPGHOME="$home" gpg --batch --no-options --show-keys "$keyring" >/dev/null 2>&1; then
        rm -rf "$home"
        die "existing keyring is not valid OpenPGP data: $keyring"
    fi
    rm -rf "$home"
}

enroll_keyring() {
    local url="$1" keyring="$2" parent raw converted home
    parent="${keyring%/*}"
    install -d -m 0755 "$parent"
    if [ -f "$keyring" ]; then
        validate_existing_keyring "$keyring"
        log "reusing valid fresh-install keyring: $keyring"
        return 0
    fi

    raw=$(mktemp /tmp/pnetlab-netinstall-key.XXXXXX)
    converted=$(mktemp /tmp/pnetlab-netinstall-keyring.XXXXXX)
    home=$(mktemp -d /tmp/pnetlab-netinstall-gpg.XXXXXX)
    log "fetching TOFU repository key: $url"
    if ! curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
        --output "$raw" "$url" >>"$LOG" 2>&1; then
        rm -f "$raw" "$converted"
        rm -rf "$home"
        die "could not fetch repository key: $url"
    fi
    if ! GNUPGHOME="$home" gpg --batch --yes --dearmor <"$raw" >"$converted" 2>>"$LOG"; then
        rm -f "$raw" "$converted"
        rm -rf "$home"
        die "downloaded repository key is not valid OpenPGP data: $url"
    fi
    chmod 0644 "$converted"
    mv -f "$converted" "$keyring"
    rm -f "$raw"
    rm -rf "$home"
    validate_existing_keyring "$keyring"
}

enroll_source() {
    local source_file="$1" source_line="$2" temporary
    temporary=$(mktemp /tmp/pnetlab-netinstall-source.XXXXXX)
    printf '%s\n' "$source_line" >"$temporary"
    chmod 0644 "$temporary"
    mv -f "$temporary" "$source_file"
}

# --- Manifest-driven bootstrap ---------------------------------------------
# Verification order: provision the embedded manifest keyring -> fetch ->
# sha256 -> signature/fingerprint -> schema parse -> select profile -> enroll
# apt keyring -> apt simulation. See docs/release-manifest-schema.md.

gpg_key_count() {
    gpg --batch --no-default-keyring --keyring "$1" --with-colons --list-keys 2>/dev/null \
        | awk -F: '$1 == "pub" { n++ } END { print n + 0 }'
}

gpg_primary_fingerprint() {
    gpg --batch --no-default-keyring --keyring "$1" --with-colons --list-keys 2>/dev/null \
        | awk -F: '$1 == "pub" { want=1; next } want && $1 == "fpr" { print $10; exit }'
}

provision_manifest_keyring() {
    local dearmored count fpr
    log '=== provisioning the embedded maintainer manifest keyring ==='
    dearmored=$(mktemp /tmp/pnetlab-netinstall-mkeyring.XXXXXX)
    if ! printf '%s\n' "$PNETLAB_MANIFEST_PUBKEY" | gpg --batch --yes --dearmor >"$dearmored" 2>>"$LOG"; then
        rm -f "$dearmored"
        die 'embedded maintainer public key is not valid OpenPGP data'
    fi
    count=$(gpg_key_count "$dearmored")
    [ "$count" = 1 ] || { rm -f "$dearmored"; die "embedded maintainer keyring must contain exactly one public key (found ${count:-0})"; }
    fpr=$(gpg_primary_fingerprint "$dearmored")
    [ "$fpr" = "$PNETLAB_MANIFEST_FPR" ] \
        || { rm -f "$dearmored"; die "embedded maintainer key fingerprint mismatch: expected $PNETLAB_MANIFEST_FPR, got ${fpr:-none}"; }
    install -d -m 0755 "${MANIFEST_KEYRING%/*}"
    chmod 0644 "$dearmored"
    mv -f "$dearmored" "$MANIFEST_KEYRING"
    log "manifest keyring provisioned and fingerprint-verified: $fpr"
}

fetch_manifest() {
    # The .sha256 sidecar (whether fetched from a URL or copied from a local
    # path) records the manifest's OWN basename inside it -- verify_manifest_
    # signature checks that recorded name against the working copy's basename,
    # so the working copy must keep the source's basename, never a random
    # mktemp name, or that check fails on every real invocation.
    local source="$1" work_dir base
    log "=== fetching release manifest: $source ==="
    work_dir=$(mktemp -d /tmp/pnetlab-netinstall-manifest.XXXXXX)
    if [[ "$source" == http://* || "$source" == https://* ]]; then
        [[ "$source" == *.json ]] || die 'manifest URL must end in .json'
        base="${source##*/}"
        MANIFEST_FILE="$work_dir/$base"
        local suffix
        for suffix in '' .sha256 .sig; do
            curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
                --output "${MANIFEST_FILE}${suffix}" "${source}${suffix}" >>"$LOG" 2>&1 \
                || die "manifest fetch failed: ${source}${suffix}"
        done
    else
        [[ -f "$source" && -f "$source.sha256" && -f "$source.sig" ]] \
            || die "manifest triplet not found at $source (need FILE, FILE.sha256, FILE.sig)"
        base="${source##*/}"
        MANIFEST_FILE="$work_dir/$base"
        cp -- "$source" "$MANIFEST_FILE"
        cp -- "$source.sha256" "${MANIFEST_FILE}.sha256"
        cp -- "$source.sig" "${MANIFEST_FILE}.sig"
    fi
}

assert_detached_signature() { # file signature keyring expected_fpr label
    local file="$1" signature="$2" keyring="$3" expected_fpr="$4" label="$5"
    local gpg_status gpg_error valid_count primary_fpr key_count
    key_count=$(gpg_key_count "$keyring")
    [ "$key_count" = 1 ] \
        || die "$label keyring must contain exactly one public key (found ${key_count:-0})"
    gpg_error=$(mktemp /tmp/pnetlab-netinstall-gpgerr.XXXXXX)
    if ! gpg_status=$(gpg --batch --no-auto-key-retrieve --status-fd 1 --no-default-keyring --keyring "$keyring" \
            --verify "$signature" "$file" 2>"$gpg_error"); then
        cat "$gpg_error" >>"$LOG"
        rm -f "$gpg_error"
        die "$label signature verification failed"
    fi
    rm -f "$gpg_error"
    grep -q '^\[GNUPG:\] GOODSIG ' <<<"$gpg_status" || die "$label GPG status lacks GOODSIG"
    grep -qE '^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|REVKEYSIG|TRUST_NEVER)( |$)' <<<"$gpg_status" \
        && die "$label signature is bad, expired, revoked, or never trusted"
    valid_count=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { n++ } END { print n + 0 }' <<<"$gpg_status")
    [ "$valid_count" = 1 ] || die "$label GPG status must contain exactly one VALIDSIG"
    primary_fpr=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' <<<"$gpg_status")
    [ "$primary_fpr" = "$expected_fpr" ] \
        || die "$label signer fingerprint mismatch: expected $expected_fpr, got ${primary_fpr:-none}"
    log "$label signature OK: signer $primary_fpr"
}

resolve_latest_release() {
    local api_base pointer_base source base suffix checksum_value checksum_name checksum_extra
    local pointer_json pointer_sha pointer_sig
    api_base="${PNETLAB_GENERIC_API_BASE:-$PNETLAB_DEFAULT_GENERIC_API_BASE}"
    api_base="${api_base%/}"
    pointer_base="$api_base/$DEFAULT_GENERIC_OWNER/generic/$DEFAULT_GENERIC_PACKAGE/$DEFAULT_POINTER_VERSION"
    POINTER_TMP_DIR=$(mktemp -d /tmp/pnetlab-netinstall-pointer.XXXXXX)
    pointer_json="$POINTER_TMP_DIR/$POINTER_NAME"
    log "=== resolving signed channel pointer: $pointer_base/$POINTER_NAME ==="
    for suffix in '' .sha256 .sig; do
        curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
            --output "$pointer_json$suffix" "$pointer_base/$POINTER_NAME$suffix" >>"$LOG" 2>&1 \
            || die "channel pointer fetch failed: $pointer_base/$POINTER_NAME$suffix"
    done
    mapfile -t checksum_lines < <(tr -d '\r' <"$pointer_json.sha256")
    [ "${#checksum_lines[@]}" -eq 1 ] || die 'channel pointer checksum file must contain exactly one line'
    read -r checksum_value checksum_name checksum_extra <<<"${checksum_lines[0]}"
    [[ "$checksum_value" =~ ^[0-9a-f]{64}$ && "$checksum_name" == "$POINTER_NAME" && -z "${checksum_extra:-}" ]] \
        || die 'channel pointer checksum file is malformed'
    (cd "$POINTER_TMP_DIR" && sha256sum --check --status -- "$POINTER_NAME.sha256") \
        || die 'channel pointer sha256 verification failed'
    assert_detached_signature "$pointer_json" "$pointer_json.sig" "$MANIFEST_KEYRING" "$PNETLAB_MANIFEST_FPR" 'channel pointer'
    read -r POINTER_RELEASE POINTER_SEQUENCE < <(python3 - "$pointer_json" "$PNETLAB_BOOTSTRAP_VERSION" "$MIN_MANIFEST_SEQUENCE" <<'PY'
import datetime as dt
import json
import re
import sys

path, bootstrap, minimum_sequence = sys.argv[1], sys.argv[2], int(sys.argv[3])
def reject(message):
    raise SystemExit("pointer validation failed: " + message)
try:
    with open(path, encoding="utf-8") as source:
        pointer = json.load(source)
except Exception as exc:
    reject(f"invalid JSON: {exc}")
required = {"generated_utc", "min_bootstrap_version", "not_valid_after", "release", "schema", "sequence", "type"}
if not isinstance(pointer, dict) or set(pointer) != required:
    reject("top-level keys differ from the channel-pointer schema")
if pointer["schema"] != 1 or pointer["type"] != "pnetlab-channel-pointer":
    reject("unknown schema or type")
if not isinstance(pointer["release"], str) or not re.fullmatch(r"6\.8\.[0-9]+resolute1", pointer["release"]):
    reject("invalid release")
if type(pointer["sequence"]) is not int or pointer["sequence"] < minimum_sequence:
    reject("sequence is below the baked-in minimum")
for field in ("generated_utc", "not_valid_after"):
    if not isinstance(pointer[field], str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", pointer[field]):
        reject(f"invalid {field}")
generated = dt.datetime.strptime(pointer["generated_utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
expires = dt.datetime.strptime(pointer["not_valid_after"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
if expires <= generated or dt.datetime.now(dt.timezone.utc) > expires:
    reject("pointer is expired or has an invalid validity interval")
if not isinstance(pointer["min_bootstrap_version"], str) or not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", pointer["min_bootstrap_version"]):
    reject("invalid min_bootstrap_version")
if tuple(map(int, bootstrap.split("."))) < tuple(map(int, pointer["min_bootstrap_version"].split("."))):
    reject("this bootstrap is too old for the channel pointer")
print(pointer["release"], pointer["sequence"])
PY
    ) || die 'channel pointer semantic validation failed'
    [ -n "$POINTER_RELEASE" ] && [ -n "$POINTER_SEQUENCE" ] || die 'channel pointer did not yield release and sequence'
    POINTER_USED=1
    RELEASE_HINT="$POINTER_RELEASE"
    MANIFEST_SOURCE="$api_base/$DEFAULT_GENERIC_OWNER/generic/$DEFAULT_GENERIC_PACKAGE/$POINTER_RELEASE/pnetlab-$POINTER_RELEASE-manifest.json"
    log "channel pointer resolved: release=$POINTER_RELEASE sequence=$POINTER_SEQUENCE"
}

verify_manifest_signature() {
    local name dir checksum_value checksum_name checksum_extra
    log '=== verifying manifest sha256 and detached signature ==='
    name=$(basename -- "$MANIFEST_FILE")
    dir=$(cd -- "$(dirname -- "$MANIFEST_FILE")" && pwd -P)
    mapfile -t checksum_lines < <(tr -d '\r' <"$MANIFEST_FILE.sha256")
    [ "${#checksum_lines[@]}" -eq 1 ] || die 'manifest checksum file must contain exactly one line'
    read -r checksum_value checksum_name checksum_extra <<<"${checksum_lines[0]}"
    [[ "$checksum_value" =~ ^[0-9a-f]{64}$ && "$checksum_name" == "$name" && -z "${checksum_extra:-}" ]] \
        || die 'manifest checksum file is malformed'
    ( cd -- "$dir" && sha256sum --check --status -- "$name.sha256" ) || die 'manifest sha256 verification failed'

    assert_detached_signature "$MANIFEST_FILE" "$MANIFEST_FILE.sig" "$MANIFEST_KEYRING" "$PNETLAB_MANIFEST_FPR" 'manifest'
}

# Strict schema-1 semantic validation, mirroring debs/verify-release-manifest.sh
# exactly (this bootstrap ships standalone and cannot depend on that script
# being present on a fresh host, so the check is duplicated deliberately).
verify_manifest_semantics() {
    log '=== validating manifest schema, freshness, and profile structure ==='
    python3 - "$MANIFEST_FILE" "$PNETLAB_BOOTSTRAP_VERSION" "$MIN_MANIFEST_SEQUENCE" "$PROFILE" <<'PY' >>"$LOG" 2>&1 \
        || die 'manifest semantic validation failed (see log)'
import datetime as dt
import json
import re
import sys

def reject(message):
    raise SystemExit("semantic validation failed: " + message)

path, consumer_version, minimum_sequence, profile = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(path, encoding="utf-8") as source:
    manifest = json.load(source)

required = {
    "arch", "best_effort_debs", "core_assets", "deb_source", "deb_source_key_fpr",
    "debs", "generated_utc", "install_profiles", "min_bootstrap_version",
    "not_valid_after", "oci", "reissue", "release", "schema", "sequence",
}
if not isinstance(manifest, dict) or set(manifest) != required:
    reject("top-level keys differ from schema 1")
if type(manifest["schema"]) is not int or manifest["schema"] != 1:
    reject("unknown schema")
if not re.fullmatch(r"6\.8\.(\d+)resolute1", manifest["release"]):
    reject("invalid release")
if type(manifest["sequence"]) is not int or manifest["sequence"] <= 0:
    reject("invalid sequence")
if manifest["sequence"] < minimum_sequence:
    reject("sequence below the baked-in minimum")
if type(manifest["reissue"]) is not int or manifest["reissue"] < 0:
    reject("invalid reissue")
if manifest["arch"] != "amd64":
    reject("unsupported target architecture")
if not re.fullmatch(r"[0-9A-F]{40}", manifest["deb_source_key_fpr"]):
    reject("invalid deb_source_key_fpr")
if not isinstance(manifest["deb_source"], str) or not manifest["deb_source"].startswith("https://"):
    reject("deb_source must use HTTPS")

for field in ("generated_utc", "not_valid_after"):
    if not isinstance(manifest[field], str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", manifest[field]):
        reject(f"invalid {field}")
generated = dt.datetime.strptime(manifest["generated_utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
expires = dt.datetime.strptime(manifest["not_valid_after"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
if expires <= generated:
    reject("not_valid_after is not later than generated_utc")
if dt.datetime.now(dt.timezone.utc) > expires:
    reject("manifest expired")
if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", manifest["min_bootstrap_version"]):
    reject("invalid min_bootstrap_version")
if tuple(map(int, consumer_version.split("."))) < tuple(map(int, manifest["min_bootstrap_version"].split("."))):
    reject("this bootstrap is too old for this release")

for map_name in ("debs", "best_effort_debs"):
    package_map = manifest[map_name]
    if not isinstance(package_map, dict) or not package_map:
        reject(f"{map_name} must be a non-empty object")
    if any(not isinstance(k, str) or v != manifest["release"] for k, v in package_map.items()):
        reject(f"{map_name} contains invalid package/version")
if set(manifest["best_effort_debs"]) != {"pnetlab-bridge-dkms"}:
    reject("best_effort_debs must contain only pnetlab-bridge-dkms")

profiles = manifest["install_profiles"]
if not isinstance(profiles, dict) or set(profiles) != {"master", "satellite"}:
    reject("install_profiles must contain master and satellite")
if profile not in profiles:
    reject(f"requested profile is not in the manifest: {profile}")
covered_debs, covered_best = set(), set()
for name, prof in profiles.items():
    if not isinstance(prof, dict) or set(prof) != {"debs", "best_effort_debs"}:
        reject(f"invalid {name} profile object")
    for field, package_map in (("debs", manifest["debs"]), ("best_effort_debs", manifest["best_effort_debs"])):
        values = prof[field]
        if not isinstance(values, list) or len(values) != len(set(values)) or values != sorted(values):
            reject(f"{name}.{field} must be a sorted unique string array")
        if any(package not in package_map for package in values):
            reject(f"{name}.{field} names package absent from flat map")
    covered_debs.update(prof["debs"])
    covered_best.update(prof["best_effort_debs"])
if "pnetlab" in profiles["satellite"]["debs"] or "pnetlab-satellite" in profiles["master"]["debs"]:
    reject("conflicting marker package in opposite profile")
if covered_debs != set(manifest["debs"]) or covered_best != set(manifest["best_effort_debs"]):
    reject("profile union does not cover flat package maps")

core = manifest["core_assets"]
if core is not None:
    if not isinstance(core, dict) or set(core) != {"archive", "index", "sha256", "url"}:
        reject("invalid core_assets object")
    if not all(isinstance(core[key], str) and core[key] for key in core):
        reject("empty core_assets field")
    if not re.fullmatch(r"[0-9a-f]{64}", core["sha256"]):
        reject("invalid core_assets sha256")
    if core["index"] != "core-assets.index.json" or not core["url"].startswith("https://"):
        reject("invalid core_assets index or URL")

oci = manifest["oci"]
if oci is not None:
    if not isinstance(oci, dict) or not oci:
        reject("oci must be null or a non-empty object")
    for tag, image in oci.items():
        if not isinstance(image, dict) or set(image) != {"ref", "registry_digest", "image_id"}:
            reject(f"invalid OCI object for {tag}")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", image["registry_digest"]):
            reject(f"OCI entry {tag} lacks registry digest")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", image["image_id"]):
            reject(f"OCI entry {tag} lacks image id")
        if not isinstance(image["ref"], str) or "/" not in image["ref"]:
            reject(f"OCI entry {tag} has invalid ref")

print("manifest OK")
PY
    log 'manifest schema/freshness/profile validation OK'
}

manifest_field() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d[sys.argv[2]]; print(v if v is not None else "")' \
        "$MANIFEST_FILE" "$1" | tr -d '\r'
}

load_profile_selection() {
    local field name version
    for field in debs best_effort_debs; do
        while IFS=$'\t' read -r name version; do
            [ -n "$name" ] || continue
            if [ "$field" = debs ]; then
                PROFILE_DEBS["$name"]="$version"
            else
                PROFILE_BEST_EFFORT["$name"]="$version"
            fi
        done < <(python3 - "$MANIFEST_FILE" "$PROFILE" "$field" <<'PY' | tr -d '\r'
import json, sys
m = json.load(open(sys.argv[1]))
profile, field = sys.argv[2], sys.argv[3]
names = m["install_profiles"][profile][field]
versions = m[field]
for n in names:
    print(f"{n}\t{versions[n]}")
PY
        )
    done
    [ "${#PROFILE_DEBS[@]}" -gt 0 ] || die "profile $PROFILE selected zero fatal-transaction packages"
    DEB_SOURCE=$(manifest_field deb_source)
    DEB_SOURCE_KEY_FPR=$(manifest_field deb_source_key_fpr)
    MANIFEST_RELEASE=$(manifest_field release)
    MANIFEST_SEQUENCE=$(manifest_field sequence)
    # NOTE: "${!array[*]:-default}" is not reliable in bash when the array is
    # non-empty (it can mis-parse as indirection on the joined values rather
    # than "all keys, or default if empty") -- compute the fallback separately.
    local best_effort_list=none
    [ "${#PROFILE_BEST_EFFORT[@]}" -gt 0 ] && best_effort_list="${!PROFILE_BEST_EFFORT[*]}"
    log "profile '$PROFILE' selected: ${!PROFILE_DEBS[*]} (best-effort: $best_effort_list)"
    log "release=$MANIFEST_RELEASE sequence=$MANIFEST_SEQUENCE deb_source=$DEB_SOURCE"
}

load_satellite_profile_selection() {
    local field name version
    SATELLITE_PROFILE_DEBS=()
    SATELLITE_PROFILE_BEST_EFFORT=()
    for field in debs best_effort_debs; do
        while IFS=$'\t' read -r name version; do
            [ -n "$name" ] || continue
            if [ "$field" = debs ]; then
                SATELLITE_PROFILE_DEBS["$name"]="$version"
            else
                SATELLITE_PROFILE_BEST_EFFORT["$name"]="$version"
            fi
        done < <(python3 - "$MANIFEST_FILE" "$field" <<'PY' | tr -d '\r'
import json, sys
m = json.load(open(sys.argv[1]))
field = sys.argv[2]
for name in m['install_profiles']['satellite'][field]:
    print(f"{name}\t{m[field][name]}")
PY
        )
    done
    [ "${#SATELLITE_PROFILE_DEBS[@]}" -gt 0 ] || return 1
    for name in "${SATELLITE_HARD_PACKAGES[@]}"; do
        [ -n "${SATELLITE_PROFILE_DEBS[$name]:-}" ] \
            || return 1
    done
}

assert_apt_keyring_fpr() {
    local keyring="$1" expected="$2" count fpr
    count=$(gpg_key_count "$keyring")
    [ "$count" = 1 ] || die "apt keyring must contain exactly one public key (found ${count:-0}): $keyring"
    fpr=$(gpg_primary_fingerprint "$keyring")
    [ "$fpr" = "$expected" ] \
        || die "apt key fingerprint mismatch: manifest says $expected, keyring has ${fpr:-none}"
    log "apt keyring fingerprint matches signed deb_source_key_fpr: $fpr"
}

core_assets_present() {
    [ -n "$(manifest_field core_assets)" ] && python3 -c \
        'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["core_assets"] is not None else 1)' \
        "$MANIFEST_FILE"
}

fetch_core_assets() {
    log '=== core-assets: checking manifest closure ==='
    if ! core_assets_present; then
        log 'manifest declares core_assets: null; nothing to fetch'
        return 0
    fi
    local url sha archive_name work id file member_sha extract_to asset_name asset_size
    local cluster_stage='' cluster_cache='' cluster_cache_ok=1
    url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["core_assets"]["url"])' "$MANIFEST_FILE" | tr -d '\r')
    sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["core_assets"]["sha256"])' "$MANIFEST_FILE" | tr -d '\r')
    archive_name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["core_assets"]["archive"])' "$MANIFEST_FILE" | tr -d '\r')
    work=$(mktemp -d /tmp/pnetlab-netinstall-coreassets.XXXXXX)
    if [ "$PROFILE" = master ] && [ "${PNET_NO_CLUSTER_BUNDLE:-0}" != 1 ]; then
        if ! install -d -o root -g root -m 0755 "$PNETLAB_CLUSTER_ASSET_CACHE_ROOT"; then
            warn 'could not create the root-only satellite asset cache; continuing without bundle staging'
        elif ! cluster_stage=$(mktemp -d "$PNETLAB_CLUSTER_ASSET_CACHE_ROOT/$MANIFEST_RELEASE.staging.XXXXXX"); then
            warn 'could not create a release-scoped satellite asset cache; continuing without bundle staging'
        elif ! chown root:root "$cluster_stage" || ! chmod 0700 "$cluster_stage"; then
            warn 'could not secure the release-scoped satellite asset cache; continuing without bundle staging'
            rm -rf -- "$cluster_stage" || true
            cluster_stage=''
        elif ! printf 'asset\tsha256\tsize\tpath\n' >"$cluster_stage/asset-inventory.tsv"; then
            warn 'could not initialize the satellite asset inventory; continuing without bundle staging'
            rm -rf -- "$cluster_stage" || true
            cluster_stage=''
        else
            :
        fi
    fi
    log "downloading core-assets archive: $url"
    curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
        --output "$work/$archive_name" "$url" >>"$LOG" 2>&1 || { rm -rf "$work"; die "core-assets download failed: $url"; }
    printf '%s  %s\n' "$sha" "$archive_name" >"$work/$archive_name.sha256"
    if ! ( cd "$work" && sha256sum --check --status -- "$archive_name.sha256" ); then
        rm -rf "$work"
        die 'core-assets archive sha256 mismatch against signed manifest'
    fi
    tar --zstd -xf "$work/$archive_name" -C "$work" || { rm -rf "$work"; die 'core-assets archive extraction failed'; }
    [ -f "$work/core-assets.index.json" ] || { rm -rf "$work"; die 'core-assets archive is missing core-assets.index.json'; }

    while IFS=$'\t' read -r id file member_sha extract_to; do
        [ -n "$id" ] || continue
        [ -f "$work/$file" ] || { rm -rf "$work"; die "core-assets index entry $id names a missing member: $file"; }
        printf '%s  %s\n' "$member_sha" "$file" >"$work/$file.sha256"
        if ! ( cd "$work" && sha256sum --check --status -- "$file.sha256" ); then
            rm -rf "$work"
            die "core-assets member sha256 mismatch: $id ($file)"
        fi
        install -d -m 0755 "$extract_to"
        tar xzf "$work/$file" -C "$extract_to" || { rm -rf "$work"; die "core-assets extraction failed for $id -> $extract_to"; }
        log "core-assets extracted: $id -> $extract_to"
        if [ "$id" = qemu-compat-libs ]; then
            printf '%s\n' "$extract_to" >/etc/ld.so.conf.d/pnetlab-qemu-compat.conf
            ldconfig || { rm -rf "$work"; die 'ldconfig failed after qemu-compat-libs extraction'; }
        fi
        if [ -n "$cluster_stage" ]; then
            case "$id" in
                qemu-zoo-*-net)
                    asset_name="$(basename "$file")"
                    if ! asset_size=$(stat -c '%s' "$work/$file") \
                        || ! install -d -m 0755 "$cluster_stage/qemu-zoo" \
                        || ! install -m 0644 "$work/$file" "$cluster_stage/qemu-zoo/$asset_name" \
                        || ! printf '%s\t%s\t%s\tqemu-zoo/%s\n' "$asset_name" "$member_sha" "$asset_size" "$asset_name" \
                            >>"$cluster_stage/asset-inventory.tsv"; then
                        warn "could not cache verified satellite asset $id; bundle staging will be skipped"
                        cluster_cache_ok=0
                    fi
                    ;;
                qemu-compat-libs)
                    if ! asset_size=$(stat -c '%s' "$work/$file") \
                        || ! install -d -m 0755 "$cluster_stage/deps" \
                        || ! install -m 0644 "$work/$file" "$cluster_stage/deps/qemu-compat-libs.tgz" \
                        || ! printf 'qemu-compat-libs.tgz\t%s\t%s\tdeps/qemu-compat-libs.tgz\n' "$member_sha" "$asset_size" \
                            >>"$cluster_stage/asset-inventory.tsv"; then
                        warn 'could not cache verified qemu-compat-libs.tgz; bundle staging will be skipped'
                        cluster_cache_ok=0
                    fi
                    ;;
            esac
        fi
    done < <(python3 - "$work/core-assets.index.json" <<'PY' | tr -d '\r'
import json, sys
for e in json.load(open(sys.argv[1])):
    print(f"{e['id']}\t{e['file']}\t{e['sha256']}\t{e['extract_to']}")
PY
    )
    if [ -n "$cluster_stage" ]; then
        for version in "${SATELLITE_ZOO_VERSIONS[@]}"; do
            [ -f "$cluster_stage/qemu-zoo/qemu-zoo-$version-net.tgz" ] || cluster_cache_ok=0
        done
        [ -f "$cluster_stage/deps/qemu-compat-libs.tgz" ] || cluster_cache_ok=0
        [ -f "$cluster_stage/asset-inventory.tsv" ] || cluster_cache_ok=0
        if [ "$cluster_cache_ok" -eq 1 ]; then
            cluster_cache="$PNETLAB_CLUSTER_ASSET_CACHE_ROOT/$MANIFEST_RELEASE"
            if ! rm -rf -- "$cluster_cache"; then
                warn "could not replace release-scoped satellite asset cache $cluster_cache"
                rm -rf -- "$cluster_stage" || true
                cluster_cache_ok=0
            fi
            if [ "$cluster_cache_ok" -eq 1 ] && ! mv -T -- "$cluster_stage" "$cluster_cache"; then
                warn "could not publish release-scoped satellite asset cache $cluster_cache"
                rm -rf -- "$cluster_stage" || true
                cluster_cache_ok=0
            elif [ "$cluster_cache_ok" -eq 1 ]; then
                if ! chown -R root:root "$cluster_cache"; then
                    warn "could not finalize ownership of satellite asset cache $cluster_cache"
                    rm -rf -- "$cluster_cache" || true
                    cluster_cache_ok=0
                fi
            fi
            if [ "$cluster_cache_ok" -eq 1 ]; then
                CLUSTER_ASSET_CACHE="$cluster_cache"
            fi
        else
            rm -rf -- "$cluster_stage" || true
            warn 'satellite asset cache is incomplete; bundle staging will be skipped'
        fi
    fi
    rm -rf "$work"
    log 'core-assets: all indexed members verified and extracted'
}

reap_satellite_tombstones() {
    local releases="$1" tombstone
    [ -d "$releases" ] || return 0
    while IFS= read -r -d '' tombstone; do
        if ! rm -rf -- "$tombstone"; then
            log "could not reap superseded satellite tombstone $tombstone; will retry on next publish"
        fi
    done < <(find "$releases" -mindepth 1 -maxdepth 1 -name '*.superseded.*' -print0 2>/dev/null)
}

stage_satellite_bundle() {
    # Master-only convenience: pre-stage the satellite deb + installer script
    # at /opt/unetlab/cluster-bundle/ (the exact layout System -> Cluster ->
    # "Deploy a satellite" push-deploy expects, normally only populated by
    # the offline bundle installer) so push-deploy works immediately on a
    # network-installed master without requiring an offline bundle tgz to
    # already be sitting on the host. Best-effort and non-fatal: a network
    # install must succeed even if this convenience step cannot.
    log '=== staging satellite bundle for Cluster push-deploy (best effort) ==='
    if [ "${PNET_NO_CLUSTER_BUNDLE:-0}" = 1 ]; then
        log 'satellite bundle staging skipped by PNET_NO_CLUSTER_BUNDLE=1'
        return 0
    fi
    if ! load_satellite_profile_selection; then
        warn 'signed satellite profile is empty or missing a required package; leaving current bundle unchanged'
        return 1
    fi
    if [ -z "$CLUSTER_ASSET_CACHE" ]; then
        warn 'verified core-assets did not produce a satellite asset cache; leaving current bundle unchanged'
        return 0
    fi
    local api_base script_name work deb_dir staging releases destination current pointer_tmp tombstone publish_lock_file publish_status
    local script_sha inventory_sha asset_inventory_sha package_list optional_list optional_deb satellite_deb bridge_deb deb package arch version sha size filename
    local -a staged_debs=()
    api_base="${PNETLAB_GENERIC_API_BASE:-$PNETLAB_DEFAULT_GENERIC_API_BASE}"
    api_base="${api_base%/}"
    script_name="pnetlab-install-resolute-satellite-$MANIFEST_RELEASE.sh"
    releases=/opt/unetlab/cluster-bundle/releases
    destination="$releases/$MANIFEST_RELEASE"
    current=/opt/unetlab/cluster-bundle/current
    if ! install -d -o root -g root -m 0755 /opt/unetlab/cluster-bundle \
        || ! install -d -o root -g root -m 0755 "$releases"; then
        warn 'could not create the root-only release staging directory; leaving current bundle unchanged'
        return 0
    fi
    if ! staging=$(mktemp -d "$releases/.${MANIFEST_RELEASE}.staging.XXXXXX") \
        || ! chmod 0700 "$staging"; then
        warn 'could not create the unique root-only release staging directory; leaving current bundle unchanged'
        [ -n "$staging" ] && rm -rf -- "$staging"
        return 0
    fi
    if ! curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
            --output "$staging/$script_name" \
            "$api_base/$DEFAULT_GENERIC_OWNER/generic/$DEFAULT_GENERIC_PACKAGE/$MANIFEST_RELEASE/$script_name" \
            >>"$LOG" 2>&1 \
        || ! curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
            --output "$staging/$script_name.sha256" \
            "$api_base/$DEFAULT_GENERIC_OWNER/generic/$DEFAULT_GENERIC_PACKAGE/$MANIFEST_RELEASE/$script_name.sha256" \
            >>"$LOG" 2>&1; then
        warn "satellite installer unavailable for $MANIFEST_RELEASE; leaving current bundle unchanged"
        rm -rf -- "$staging"
        return 0
    fi
    script_sha=$(awk 'NR == 1 {print $1}' "$staging/$script_name.sha256")
    if ! [[ "$script_sha" =~ ^[0-9a-fA-F]{64}$ ]] \
        || ! printf '%s  %s\n' "$script_sha" "$script_name" >"$staging/.script.sha256" \
        || ! ( cd "$staging" && sha256sum --check --status -- .script.sha256 ); then
        warn 'satellite installer checksum verification failed; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    rm -f -- "$staging/$script_name.sha256" "$staging/.script.sha256"
    if ! install -m 0755 "$staging/$script_name" "$staging/install-resolute-satellite.sh" \
        || ! rm -f -- "$staging/$script_name"; then
        warn 'could not normalize the satellite installer in the release staging directory'
        rm -rf -- "$staging"
        return 0
    fi
    deb_dir="$staging/pnetlab-debs"
    if ! install -d -m 0755 "$deb_dir"; then
        warn 'could not create the satellite deb staging directory; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    for package in "${!SATELLITE_PROFILE_DEBS[@]}"; do
        if ! stage_satellite_deb "$package" "${SATELLITE_PROFILE_DEBS[$package]}" "$deb_dir"; then
            warn "required satellite package $package could not be staged; leaving current bundle unchanged"
            rm -rf -- "$staging"
            return 0
        fi
    done
    for package in "${!SATELLITE_PROFILE_BEST_EFFORT[@]}"; do
        if stage_satellite_deb "$package" "${SATELLITE_PROFILE_BEST_EFFORT[$package]}" "$deb_dir"; then
            log "optional satellite package staged: $package"
        else
            warn "optional satellite package $package was not staged"
        fi
    done
    if ! install -d -m 0755 "$staging/qemu-zoo" "$staging/deps"; then
        warn 'could not create the satellite asset staging directories; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    for version in "${SATELLITE_ZOO_VERSIONS[@]}"; do
        if ! install -m 0644 "$CLUSTER_ASSET_CACHE/qemu-zoo/qemu-zoo-$version-net.tgz" \
            "$staging/qemu-zoo/qemu-zoo-$version-net.tgz"; then
            warn "required QEMU zoo asset $version could not be staged; leaving current bundle unchanged"
            rm -rf -- "$staging"
            return 0
        fi
    done
    if ! install -m 0644 "$CLUSTER_ASSET_CACHE/deps/qemu-compat-libs.tgz" "$staging/deps/"; then
        warn 'required qemu-compat-libs.tgz could not be staged; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    if ! install -m 0644 "$CLUSTER_ASSET_CACHE/asset-inventory.tsv" "$staging/asset-inventory.tsv"; then
        warn 'required satellite asset inventory could not be staged; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    package_list=$(printf '%s\n' "${!SATELLITE_PROFILE_DEBS[@]}" | sort | while IFS= read -r package; do
        [ -n "$package" ] && printf '%s=%s,' "$package" "${SATELLITE_PROFILE_DEBS[$package]}"
    done)
    package_list="${package_list%,}"
    optional_list=$(printf '%s\n' "${!SATELLITE_PROFILE_BEST_EFFORT[@]}" | sort | while IFS= read -r package; do
        [ -n "$package" ] || continue
        optional_deb=$(find "$deb_dir" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit || true)
        [ -n "$optional_deb" ] || continue
        printf '%s=%s,' "$package" "${SATELLITE_PROFILE_BEST_EFFORT[$package]}"
    done)
    optional_list="${optional_list%,}"
    {
        printf 'package\tarchitecture\tversion\tsha256\tsize\tfilename\n'
        mapfile -t staged_debs < <(find "$deb_dir" -maxdepth 1 -type f -name '*.deb' -printf '%p\n' | sort)
        for deb in "${staged_debs[@]}"; do
            package=$(dpkg-deb -f "$deb" Package)
            arch=$(dpkg-deb -f "$deb" Architecture)
            version=$(dpkg-deb -f "$deb" Version)
            sha=$(sha256sum "$deb" | awk '{print $1}')
            size=$(stat -c '%s' "$deb")
            filename=$(basename "$deb")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$package" "$arch" "$version" "$sha" "$size" "$filename"
        done
    } >"$staging/inventory.tsv" || {
        warn 'could not write the satellite package inventory; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    }
    inventory_sha=$(sha256sum "$staging/inventory.tsv" | awk '{print $1}')
    asset_inventory_sha=$(sha256sum "$staging/asset-inventory.tsv" | awk '{print $1}')
    {
        printf 'format=1\nrelease=%s\npackages=%s\noptional_packages=%s\n' "$MANIFEST_RELEASE" "$package_list" "$optional_list"
        printf 'assets=qemu-compat-libs.tgz,qemu-zoo-2.4.0-net.tgz,qemu-zoo-2.12.0-net.tgz,qemu-zoo-4.1.0-net.tgz,qemu-zoo-5.2.0-net.tgz\n'
        printf 'inventory_sha256=%s\nasset_inventory_sha256=%s\n' "$inventory_sha" "$asset_inventory_sha"
    } >"$staging/COMPLETE" || {
        warn 'could not write the satellite COMPLETE marker; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    }
    {
        printf 'release=%s\n' "$MANIFEST_RELEASE"
        printf 'manifest_sha256=%s\n' "$(sha256sum "$MANIFEST_FILE" | awk '{print $1}')"
        printf 'manifest_sequence=%s\n' "$MANIFEST_SEQUENCE"
        printf 'staged_utc=%s\nsource=netinstall\nprofile=satellite\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$staging/provenance" || {
        warn 'could not write satellite bundle provenance; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    }
    if ! chown -R root:root "$staging" \
        || ! find "$staging" -type d -exec chmod 0755 {} + \
        || ! find "$staging" -type f -exec chmod 0644 {} + \
        || ! chmod 0755 "$staging/install-resolute-satellite.sh"; then
        warn 'could not finalize root-only satellite bundle permissions; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    if ! satellite_bundle_complete_for_release "$staging" "$MANIFEST_RELEASE"; then
        warn 'assembled satellite release failed digest/completeness validation; leaving current bundle unchanged'
        rm -rf -- "$staging"
        return 0
    fi
    # Shared with pnet-satdeploy.sh: only one publisher may mutate this
    # release tree or reap its rollback tombstones at a time.
    publish_lock_file="$releases/.publish.lock"
    if ! exec 7>"$publish_lock_file"; then
        warn "could not open satellite release publish lock $publish_lock_file; leaving current bundle unchanged"
        rm -rf -- "$staging"
        return 0
    fi
    if ! flock -x -w 600 7; then
        warn "another satellite release publisher holds $publish_lock_file; leaving current bundle unchanged"
        exec 7>&-
        rm -rf -- "$staging"
        return 0
    fi
    if (
        reap_satellite_tombstones "$releases"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if satellite_bundle_complete_for_release "$destination" "$MANIFEST_RELEASE"; then
            rm -rf -- "$staging"
        else
            if [ ! -d "$destination" ] || [ -L "$destination" ]; then
                warn "release directory already exists but is not repairable; leaving current bundle unchanged"
                rm -rf -- "$staging"
                return 0
            fi
            tombstone="$releases/$MANIFEST_RELEASE.superseded.$$.$RANDOM"
            if [ -e "$tombstone" ] || [ -L "$tombstone" ] \
                || ! mv -T -- "$destination" "$tombstone"; then
                warn "could not replace incomplete satellite release $destination; leaving current bundle unchanged"
                rm -rf -- "$staging"
                return 0
            fi
            if ! mv -T -- "$staging" "$destination"; then
                warn "could not publish replacement satellite release $destination; restoring the previous release"
                if ! mv -T -- "$tombstone" "$destination"; then
                    warn "could not restore the previous satellite release $destination"
                fi
                rm -rf -- "$staging"
                return 0
            fi
            if ! rm -rf -- "$tombstone"; then
                warn "published satellite release $destination but could not remove superseded tombstone $tombstone"
            fi
        fi
    elif ! mv -T -- "$staging" "$destination"; then
        warn "could not publish satellite release directory $destination; leaving current bundle unchanged"
        rm -rf -- "$staging"
        return 0
    fi
    if ! satellite_bundle_complete_for_release "$destination" "$MANIFEST_RELEASE"; then
        warn "assembled satellite release $destination failed completeness validation; leaving current bundle unchanged"
        return 0
    fi
    pointer_tmp="/opt/unetlab/cluster-bundle/.current.$$"
    rm -f -- "$pointer_tmp"
    if [ -e "$current" ] || [ -L "$current" ]; then
        if [ ! -L "$current" ]; then
            warn 'existing cluster-bundle/current is not a symlink; leaving current bundle unchanged'
            return 0
        fi
    fi
    if ! ln -s "releases/$MANIFEST_RELEASE" "$pointer_tmp" \
        || ! chown -h root:root "$pointer_tmp" \
        || ! mv -Tf -- "$pointer_tmp" "$current"; then
        warn 'could not switch the root-owned current satellite bundle pointer; leaving the previous pointer unchanged'
        rm -f -- "$pointer_tmp"
        return 0
    fi
    mapfile -t old_releases < <(find "$releases" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^6\.8\.[0-9]+resolute1$' | grep -v -F -- "$MANIFEST_RELEASE" | sort -V -r || true)
    if [ "${#old_releases[@]}" -gt 1 ]; then
        for release in "${old_releases[@]:1}"; do
            rm -rf -- "$releases/$release" || warn "could not reap superseded satellite release $release"
        done
    fi
    reap_satellite_tombstones "$releases"
    satellite_deb=$(find "$destination/pnetlab-debs" -maxdepth 1 -type f -name 'pnetlab-satellite_*.deb' -print -quit || true)
    bridge_deb=$(find "$destination/pnetlab-debs" -maxdepth 1 -type f -name 'pnetlab-bridge-dkms_*.deb' -print -quit || true)
    if [ -z "$satellite_deb" ] \
        || ! install -d -o root -g root -m 0755 /opt/unetlab/data/satellite \
        || ! install -m 0644 "$satellite_deb" /opt/unetlab/data/satellite/; then
        warn 'satellite deb staging to data/satellite failed; continuing'
    fi
    # Sync Satellite needs the matching DKMS package as well.  The bundle
    # completeness gate has already verified the optional package identity and
    # version; keep this copy independently guarded so a missing optional
    # package never turns a successful network install into a hard failure.
    if [ -n "$bridge_deb" ] && [ -n "$satellite_deb" ] \
        && [ "$(dpkg-deb -f "$bridge_deb" Version 2>/dev/null || true)" = \
             "$(dpkg-deb -f "$satellite_deb" Version 2>/dev/null || true)" ] \
        && install -d -o root -g root -m 0755 /opt/unetlab/data/satellite \
        && install -m 0644 "$bridge_deb" /opt/unetlab/data/satellite/; then
        log 'matching pnetlab-bridge-dkms deb staged for Sync Satellite'
    else
        warn 'matching pnetlab-bridge-dkms deb unavailable; Sync Satellite will remain disabled until it is staged'
    fi
    log "satellite bundle published atomically: $destination (current -> $MANIFEST_RELEASE)"
    ); then
        publish_status=0
    else
        publish_status=$?
    fi
    flock -u 7 || true
    exec 7>&-
    return "$publish_status"
}

p2_path() {
    local path="$1"
    if [ -n "$P2_ROOT" ]; then
        printf '%s%s\n' "${P2_ROOT%/}" "$path"
    else
        printf '%s\n' "$path"
    fi
}

p2_read_trimmed() {
    local file="$1" value=''
    [ -f "$file" ] || return 1
    IFS= read -r value <"$file" || true
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s\n' "$value"
}

p2_valid_ipv4() {
    local value="$1" part
    local -a octets=()
    IFS=. read -r -a octets <<<"$value"
    [ "${#octets[@]}" -eq 4 ] || return 1
    for part in "${octets[@]}"; do
        [[ "$part" =~ ^[0-9]{1,3}$ ]] || return 1
        [ "$part" -le 255 ] || return 1
    done
}

p2_valid_cidr() {
    local cidr="$1" address prefix
    [[ "$cidr" == */* ]] || return 1
    address="${cidr%%/*}"
    prefix="${cidr##*/}"
    p2_valid_ipv4 "$address" || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] && [ "$prefix" -ge 1 ] && [ "$prefix" -le 32 ]
}

p2_valid_dns_csv() {
    local csv="$1" dns
    local -a servers=()
    [ -n "$csv" ] || return 1
    IFS=',' read -r -a servers <<<"$csv"
    [ "${#servers[@]}" -gt 0 ] || return 1
    for dns in "${servers[@]}"; do
        p2_valid_ipv4 "${dns// /}" || return 1
    done
}

p2_check_interfaces_a() {
    local interfaces
    interfaces="$(p2_path /etc/network/interfaces)"
    if [ ! -e "$interfaces" ] && [ ! -L "$interfaces" ]; then
        P2_INTERFACES_PRE_KIND=absent
        P2_INTERFACES_PRE_HAS_LO=0
        return 0
    fi
    [ ! -L "$interfaces" ] || die 'preflight Check A refuses a symlinked /etc/network/interfaces; use --no-cloud-uplink'
    P2_INTERFACES_SNAPSHOT=$(mktemp /tmp/pnetlab-pass2-interfaces.XXXXXX)
    cp -a -- "$interfaces" "$P2_INTERFACES_SNAPSHOT"
    if [ ! -s "$interfaces" ]; then
        P2_INTERFACES_PRE_KIND=empty
        P2_INTERFACES_PRE_HAS_LO=0
        return 0
    fi
    # Accept either a pristine pre-install file (empty / lo-only -- the state
    # on a genuinely fresh host before pnetlab is ever installed) OR the
    # EXACT postinst-authored natmac/nat0 baseline that Check B (below, run
    # after package installation) already recognizes. The second shape is
    # not "administrator content": it is pnetlab.postinst's own
    # unconditional nat0 bridge stanza (build-stage.sh / pnetlab.postinst
    # "nat0 bridge in /etc/network/interfaces"), written during package
    # configuration -- which happens BEFORE Pass 2 discovery on a host that
    # is resuming after a prior run installed packages but never reached the
    # Pass 2 mutation step (the documented repair/re-run path
    # p2_nic_is_already_provisioned() already anticipates). Refusing that
    # exact, known-safe shape made every such resume die here with "refuses
    # administrator content", even though nothing an administrator wrote is
    # actually present.
    local check_a_result
    if check_a_result="$(python3 - "$interfaces" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    raw = source.readlines()

source_lines = []
content = []
for line in raw:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    match = re.fullmatch(r"(source|source-directory)\s+(.+)", stripped)
    if match:
        directive, value = match.groups()
        if (directive == "source" and value != "/etc/network/interfaces.d/*") or (directive == "source-directory" and value != "/etc/network/interfaces.d"):
            raise SystemExit(1)
        if source_lines:
            raise SystemExit(1)
        source_lines.append(stripped)
        continue
    content.append(stripped)

lo = ["auto lo", "iface lo inet loopback"]
nat = [
    "auto natmac",
    "iface natmac inet manual",
    "pre-up ip link add natmac address 00:01:01:01:01:01 type dummy",
    "auto nat0",
    "iface nat0 inet static",
    "bridge_ports natmac",
    "bridge_stp off",
    "address 10.0.137.254",
    "netmask 255.255.255.0",
    "up systemctl --no-block restart udhcpd",
]
if content not in ([], lo, nat, lo + nat):
    raise SystemExit(1)
has_lo = content[:len(lo)] == lo
is_baseline = content in (nat, lo + nat)
print(("baseline" if is_baseline else "lo") + "\t" + ("1" if has_lo else "0"))
PY
    )"; then
        P2_INTERFACES_PRE_KIND="${check_a_result%%$'\t'*}"
        P2_INTERFACES_PRE_HAS_LO="${check_a_result##*$'\t'}"
        return 0
    fi
    die 'preflight Check A refuses administrator content in /etc/network/interfaces; use --no-cloud-uplink'
}

p2_check_interfaces_b() {
    local interfaces
    interfaces="$(p2_path /etc/network/interfaces)"
    [ -f "$interfaces" ] || die 'Pass 2 Check B: ifupdown did not create /etc/network/interfaces'
    P2_BASELINE_TMP=$(mktemp /tmp/pnetlab-pass2-baseline.XXXXXX)
    if ! python3 - "$interfaces" "$(p2_path /etc/network/interfaces.d)" >"$P2_BASELINE_TMP" <<'PY'
import os
import re
import sys

path, interfaces_d = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    raw = source.readlines()

source_lines = []
content = []
for line in raw:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    match = re.fullmatch(r"(source|source-directory)\s+(.+)", stripped)
    if match:
        directive, value = match.groups()
        if (directive == "source" and value != "/etc/network/interfaces.d/*") or (directive == "source-directory" and value != "/etc/network/interfaces.d"):
            raise SystemExit("unsupported interfaces.d directive")
        source_lines.append(stripped)
        continue
    content.append(stripped)

if len(source_lines) > 1:
    raise SystemExit("multiple interfaces.d directives")
if source_lines:
    if os.path.isdir(interfaces_d) and any(os.scandir(interfaces_d)):
        raise SystemExit("interfaces.d is populated")

lo = ["auto lo", "iface lo inet loopback"]
nat = [
    "auto natmac",
    "iface natmac inet manual",
    "pre-up ip link add natmac address 00:01:01:01:01:01 type dummy",
    "auto nat0",
    "iface nat0 inet static",
    "bridge_ports natmac",
    "bridge_stp off",
    "address 10.0.137.254",
    "netmask 255.255.255.0",
    "up systemctl --no-block restart udhcpd",
]
if content == nat:
    has_lo = 0
elif content == lo + nat:
    has_lo = 1
else:
    raise SystemExit("interfaces file is not the postinst natmac/nat0 baseline")

if source_lines:
    print("source\t" + source_lines[0])
print("lo\t" + str(has_lo))
PY
    then
        rm -f -- "$P2_BASELINE_TMP"
        P2_BASELINE_TMP=''
        die 'Pass 2 Check B refuses unexpected post-package content in /etc/network/interfaces'
    fi
    P2_SOURCE_DIRECTIVE="$(awk -F '	' '$1 == "source" {print substr($0, index($0, FS) + 1); exit}' "$P2_BASELINE_TMP")"
    P2_POST_HAS_LO="$(awk -F '	' '$1 == "lo" {print $2; exit}' "$P2_BASELINE_TMP")"
    [ "$P2_INTERFACES_PRE_HAS_LO" -eq 1 ] && [ "$P2_POST_HAS_LO" = 1 ] || \
        [ "$P2_INTERFACES_PRE_HAS_LO" -eq 0 ] || \
        die 'Pass 2 Check B lost the host original lo stanza'
    log "Pass 2 Check B accepted postinst baseline (source=${P2_SOURCE_DIRECTIVE:-none}, lo=${P2_POST_HAS_LO:-0})"
}

p2_nic_is_already_provisioned() {
    local interfaces pnet0 brif
    interfaces="$(p2_path /etc/network/interfaces)"
    pnet0="$P2_SYSFS_ROOT/class/net/pnet0"
    brif="$pnet0/brif"
    [ -f "$interfaces" ] || return 1
    grep -Fq '# BEGIN pnetlab-netcfg pnet0' "$interfaces" || return 1
    [ -d "$pnet0" ] || return 1
    shopt -s nullglob
    local ports=("$brif"/*)
    shopt -u nullglob
    [ "${#ports[@]}" -gt 0 ]
}

p2_route_details() {
    local -n route_lines_ref="$1"
    local route
    mapfile -t route_lines_ref < <(ip -4 route show default)
    [ "${#route_lines_ref[@]}" -eq 1 ] || \
        die "uplink discovery requires exactly one IPv4 default route (found ${#route_lines_ref[@]}); use --no-cloud-uplink"
    route="${route_lines_ref[0]}"
    [[ "$route" != *nexthop* ]] || die 'uplink discovery refuses a multipath default route; use --no-cloud-uplink'
    [[ "$route" != *onlink* ]] || die 'uplink discovery refuses an onlink gateway; use --no-cloud-uplink'
}

p2_check_policy_routing() {
    local -a rules=() expected=(
        '0: from all lookup local'
        '32766: from all lookup main'
        '32767: from all lookup default'
    )
    mapfile -t rules < <(ip -4 rule show | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
    [ "${#rules[@]}" -eq 3 ] || die 'uplink discovery refuses policy routing; ip -4 rule show is not the stock three-rule set; use --no-cloud-uplink'
    local index
    for index in 0 1 2; do
        [ "${rules[$index]}" = "${expected[$index]}" ] || \
            die "uplink discovery refuses policy routing: offending rule '${rules[$index]}'; use --no-cloud-uplink"
    done
    local line table
    while IFS= read -r line; do
        [[ "$line" == default* ]] || continue
        table="$(awk '{for (i=1; i<NF; i++) if ($i == "table") {print $(i+1); exit}}' <<<"$line")"
        if [ -n "$table" ] && [ "$table" != main ] && [ "$table" != 254 ]; then
            die "uplink discovery refuses a non-main default route: $line; use --no-cloud-uplink"
        fi
    done < <(ip -4 route show table all)
}

p2_netplan_mode() {
    local nic="$1" mac="$2" netplan_dir
    netplan_dir="$(p2_path /etc/netplan)"
    [ -d "$netplan_dir" ] || die "uplink addressing is ambiguous: no netplan YAML mentions $nic; use --uplink-mode/--uplink-address/--uplink-gateway/--uplink-dns"
    mapfile -t P2_NETPLAN_FILES < <(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -print | sort)
    [ "${#P2_NETPLAN_FILES[@]}" -gt 0 ] || \
        die "uplink addressing is ambiguous: no netplan YAML mentions $nic; use --uplink-mode/--uplink-address/--uplink-gateway/--uplink-dns"
    python3 - "$nic" "$mac" "${P2_NETPLAN_FILES[@]}" <<'PY'
import fnmatch
import re
import sys

nic, mac, *paths = sys.argv[1:]
mac = mac.lower()

def stanza_matches(s):
    if s["name"] == nic or s["mac"] == mac:
        return True
    return bool(s["match_name"]) and fnmatch.fnmatchcase(nic, s["match_name"])

matches = []
for path in paths:
    with open(path, encoding="utf-8") as source:
        lines = source.readlines()
    ethernets_indent = None
    ethernets_child_indent = None
    current = None
    current_indent = None
    current_child_indent = None
    stanza = None
    block = None
    block_indent = None
    block_child_indent = None
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        text = raw.strip()
        if text == "ethernets:":
            ethernets_indent = indent
            ethernets_child_indent = None
            current = None
            current_indent = None
            current_child_indent = None
            stanza = None
            block = None
            block_indent = None
            block_child_indent = None
            continue
        if ethernets_indent is None:
            continue
        if indent <= ethernets_indent:
            current = None
            current_indent = None
            current_child_indent = None
            block = None
            block_indent = None
            block_child_indent = None
            continue
        if ethernets_child_indent is None:
            ethernets_child_indent = indent
        if indent == ethernets_child_indent and text.endswith(":"):
            if stanza is not None and stanza_matches(stanza):
                matches.append(stanza)
            current = text[:-1].strip("'\"")
            current_indent = indent
            current_child_indent = None
            stanza = {"name": current, "mac": "", "dhcp4": None, "addresses": False, "match_name": None}
            block = None
            block_indent = None
            block_child_indent = None
            continue
        if current is None or stanza is None or indent <= current_indent:
            continue
        # Only attributes that are DIRECT children of the interface stanza
        # (indent == current_child_indent, the indentation of the first line
        # seen under this stanza) describe the interface itself. Deeper lines
        # belong to a nested mapping (match:, nameservers:,
        # routes:, ...) and must never be mistaken for the interface's own
        # dhcp4/addresses/macaddress -- e.g. `nameservers: / addresses:`
        # nests a DNS server list one level deeper and is not a static IP
        # assignment for the interface.
        if current_child_indent is None:
            current_child_indent = indent
        if block is not None and indent <= block_indent:
            block = None
            block_indent = None
            block_child_indent = None
        if indent == current_child_indent:
            if text.endswith(":") and not re.match(r"(dhcp4|addresses|macaddress)\s*:\s*\S", text, re.I):
                block = text.split(":", 1)[0].strip().strip("'\"")
                block_indent = indent
                block_child_indent = None
            else:
                block = None
                block_indent = None
                block_child_indent = None
            match = re.match(r"macaddress:\s*['\"]?([^'\"\s]+)", text, re.I)
            if match:
                stanza["mac"] = match.group(1).lower()
            match = re.match(r"dhcp4:\s*(true|false)\b", text, re.I)
            if match:
                stanza["dhcp4"] = match.group(1).lower() == "true"
            if re.match(r"addresses\s*:", text):
                stanza["addresses"] = True
            continue
        if block is not None and block_child_indent is None and indent > block_indent:
            block_child_indent = indent
        if block == "match" and indent == block_child_indent:
            match = re.match(r"macaddress:\s*['\"]?([^'\"\s]+)", text, re.I)
            if match:
                stanza["mac"] = match.group(1).lower()
            match = re.match(r"name:\s*['\"]?([^'\"\s]+)", text)
            if match:
                stanza["match_name"] = match.group(1)
    if stanza is not None and stanza_matches(stanza):
        matches.append(stanza)

if len(matches) != 1:
    raise SystemExit(f"expected one netplan stanza for {nic}, found {len(matches)}")
stanza = matches[0]
if stanza["dhcp4"] is True and stanza["addresses"]:
    raise SystemExit("netplan stanza declares both dhcp4 and addresses")
if stanza["dhcp4"] is True:
    print("dhcp")
elif stanza["addresses"]:
    print("static")
else:
    raise SystemExit("netplan stanza has neither dhcp4 nor addresses")
PY
}

detect_uplink_nic() {
    local entry nic type devtype phys_name phys_switch mac first_octet
    local route gateway_route uplink_route active_address active_dynamic
    local netplan_mode resolved_dns
    local -a eligible=() route_lines=() addr_lines=()
    if [ "$PROFILE" = satellite ]; then
        log 'Pass 2: satellite profile is master-only; discovery and handoff are skipped'
        return 0
    fi
    if [ "$P2_NO_CLOUD_UPLINK" -eq 1 ]; then
        log 'Pass 2: --no-cloud-uplink explicitly selected; discovery and handoff are skipped'
        return 0
    fi
    if p2_nic_is_already_provisioned; then
        # Clean skip of PASS 2 ONLY -- never of the install. Re-running the
        # bootstrap on a provisioned host is the documented maintenance path
        # (repair, upgrade, re-assert), so packages must still be installed and
        # configured exactly as on any other run. Setting the same flag that
        # --no-cloud-uplink sets makes the mutation phase and summary() take
        # the identical skip path, with nothing else in main() short-circuited.
        P2_ALREADY_PROVISIONED=1
        P2_NO_CLOUD_UPLINK=1
        log 'Pass 2: existing pnetlab-netcfg pnet0 with bridge ports detected; skipping Pass 2 (install continues)'
        return 0
    fi
    p2_check_interfaces_a

    shopt -s nullglob
    local -a net_entries=("$P2_SYSFS_ROOT/class/net"/*)
    shopt -u nullglob
    for entry in "${net_entries[@]}"; do
        [ -d "$entry" ] || continue
        nic="${entry##*/}"
        [ -f "$entry/type" ] || continue
        type="$(p2_read_trimmed "$entry/type")"
        [ "$type" = 1 ] || continue
        [ -e "$entry/device" ] || [ -L "$entry/device" ] || continue
        [ ! -e "$entry/wireless" ] || continue
        [ ! -e "$entry/master" ] || continue
        [ ! -e "$entry/bridge" ] || continue
        [ ! -e "$entry/bonding" ] || continue
        [ ! -e "$entry/bonding_slave" ] || continue
        [ ! -e "$entry/device/physfn" ] || continue
        devtype="$(awk -F= '$1 == "DEVTYPE" {print $2; exit}' "$entry/uevent" 2>/dev/null || true)"
        [ -z "$devtype" ] || continue
        phys_name="$(p2_read_trimmed "$entry/phys_port_name" 2>/dev/null || true)"
        [[ ! "$phys_name" =~ ^(p[0-9]+)?(pf[0-9]+)?vf[0-9]+$ ]] || continue
        [[ ! "$phys_name" =~ ^(p[0-9]+)?(pf[0-9]+)?sf[0-9]+$ ]] || continue
        phys_switch="$(p2_read_trimmed "$entry/phys_switch_id" 2>/dev/null || true)"
        if [ -n "$phys_switch" ] && [ -e "$entry/device/physfn" ]; then
            continue
        fi
        mac="$(p2_read_trimmed "$entry/address" 2>/dev/null || true)"
        [[ "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] || continue
        first_octet="${mac%%:*}"
        [ "$mac" != 00:00:00:00:00:00 ] || continue
        (( (16#$first_octet & 1) == 0 )) || continue
        eligible+=("$nic")
    done

    [ "${#eligible[@]}" -ge 1 ] || \
        die 'uplink discovery found no eligible physical Ethernet NIC; use --no-cloud-uplink'

    # PNetLab/EVE-NG's long-standing multi-NIC convention: the first physical
    # NIC is the management/uplink interface (and, per D-existing behavior,
    # doubles as pnet0's bridge port); any additional NICs are left completely
    # untouched here for the operator to map to pnet1..9 via the normal
    # PNetLab bridge-port tooling, outside Pass 2's scope. "First" is ordered
    # by PCI bus/device/function address (stable across reboots, independent
    # of whichever interface-naming scheme is active at detection time), not
    # by interface name -- refusing outright on 2+ NICs (the pre-2026-08-25
    # behavior) made Pass 2 unusable on exactly this common topology.
    local -a eligible_sorted=() pci
    local nic_i pci_path
    for nic_i in "${eligible[@]}"; do
        pci_path="$(readlink -f -- "$P2_SYSFS_ROOT/class/net/$nic_i/device" 2>/dev/null || true)"
        pci+=("${pci_path##*/}"$'\t'"$nic_i")
    done
    mapfile -t pci < <(printf '%s\n' "${pci[@]}" | sort)
    for entry in "${pci[@]}"; do
        eligible_sorted+=("${entry#*$'\t'}")
    done

    if [ -n "$P2_UPLINK_NIC_OVERRIDE" ]; then
        nic=''
        for nic_i in "${eligible[@]}"; do
            [ "$nic_i" = "$P2_UPLINK_NIC_OVERRIDE" ] && nic="$nic_i" && break
        done
        [ -n "$nic" ] || \
            die "--uplink-nic '$P2_UPLINK_NIC_OVERRIDE' is not an eligible physical Ethernet NIC (eligible: ${eligible_sorted[*]})"
        P2_UPLINK_NIC="$nic"
    else
        P2_UPLINK_NIC="${eligible_sorted[0]}"
    fi
    if [ "${#eligible_sorted[@]}" -gt 1 ]; then
        log "uplink discovery: ${#eligible_sorted[@]} eligible NICs (${eligible_sorted[*]}, PCI order); selected $P2_UPLINK_NIC as management/uplink; the rest are left untouched for pnet1..9 mapping"
    fi
    P2_UPLINK_MAC="$(p2_read_trimmed "$P2_SYSFS_ROOT/class/net/$P2_UPLINK_NIC/address")"

    p2_route_details route_lines
    route="${route_lines[0]}"
    uplink_route="$(awk '{for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit}}' <<<"$route")"
    [ "$uplink_route" = "$P2_UPLINK_NIC" ] || \
        die "uplink discovery found the default route on '$uplink_route', not $P2_UPLINK_NIC; use --no-cloud-uplink"
    gateway_route="$(awk '{for (i=1; i<NF; i++) if ($i == "via") {print $(i+1); exit}}' <<<"$route")"
    { [ -n "$gateway_route" ] && p2_valid_ipv4 "$gateway_route"; } || \
        [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ] || \
        die 'uplink discovery requires a default route with an IPv4 gateway; use --uplink-gateway or --no-cloud-uplink'
    p2_check_policy_routing

    mapfile -t addr_lines < <(ip -o -4 addr show dev "$P2_UPLINK_NIC" scope global)
    active_address=''
    active_dynamic=0
    if [ "${#addr_lines[@]}" -eq 1 ]; then
        active_address="$(awk '{print $4}' <<<"${addr_lines[0]}")"
        [[ " ${addr_lines[0]} " == *' dynamic '* ]] && active_dynamic=1
    fi

    if [ -n "$P2_UPLINK_MODE_OVERRIDE" ]; then
        [[ "$P2_UPLINK_MODE_OVERRIDE" == dhcp || "$P2_UPLINK_MODE_OVERRIDE" == static ]] || \
            die '--uplink-mode must be dhcp or static'
        P2_UPLINK_MODE="$P2_UPLINK_MODE_OVERRIDE"
        if [ "$P2_UPLINK_MODE" = static ]; then
            [ -n "$P2_UPLINK_ADDRESS_OVERRIDE" ] && [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ] && [ -n "$P2_UPLINK_DNS_OVERRIDE" ] || \
                die '--uplink-mode static requires --uplink-address, --uplink-gateway, and --uplink-dns'
        elif [ -n "$P2_UPLINK_ADDRESS_OVERRIDE" ] || [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ] || [ -n "$P2_UPLINK_DNS_OVERRIDE" ]; then
            die '--uplink-mode dhcp cannot be combined with static addressing overrides'
        fi
    elif [ -n "$P2_UPLINK_ADDRESS_OVERRIDE" ] || [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ] || [ -n "$P2_UPLINK_DNS_OVERRIDE" ]; then
        [ -n "$P2_UPLINK_ADDRESS_OVERRIDE" ] && [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ] && [ -n "$P2_UPLINK_DNS_OVERRIDE" ] || \
            die 'addressing overrides require --uplink-address, --uplink-gateway, and --uplink-dns together; use --uplink-mode static'
        P2_UPLINK_MODE=static
    else
        [ "${#addr_lines[@]}" -eq 1 ] || \
            die "uplink addressing is ambiguous: $P2_UPLINK_NIC has ${#addr_lines[@]} global IPv4 addresses; use --uplink-mode/--uplink-address/--uplink-gateway/--uplink-dns"
        netplan_mode="$(p2_netplan_mode "$P2_UPLINK_NIC" "$P2_UPLINK_MAC")" || \
            die 'uplink addressing is ambiguous: netplan/live state disagrees; use --uplink-mode/--uplink-address/--uplink-gateway/--uplink-dns'
        if [ "$active_dynamic" -eq 1 ] && [ "$netplan_mode" = dhcp ]; then
            P2_UPLINK_MODE=dhcp
        elif [ "$active_dynamic" -eq 0 ] && [ "$netplan_mode" = static ]; then
            P2_UPLINK_MODE=static
        else
            die "uplink addressing is ambiguous: live address and netplan disagree ($P2_UPLINK_NIC); use --uplink-mode/--uplink-address/--uplink-gateway/--uplink-dns"
        fi
    fi

    if [ -n "$P2_UPLINK_ADDRESS_OVERRIDE" ]; then
        p2_valid_cidr "$P2_UPLINK_ADDRESS_OVERRIDE" || die "invalid --uplink-address: $P2_UPLINK_ADDRESS_OVERRIDE"
        P2_UPLINK_ADDRESS="$P2_UPLINK_ADDRESS_OVERRIDE"
    elif [ "${#addr_lines[@]}" -eq 1 ]; then
        P2_UPLINK_ADDRESS="$active_address"
    elif [ "$P2_UPLINK_MODE" = static ]; then
        die 'static uplink requires --uplink-address when live address discovery is ambiguous'
    fi

    if [ -n "$P2_UPLINK_GATEWAY_OVERRIDE" ]; then
        p2_valid_ipv4 "$P2_UPLINK_GATEWAY_OVERRIDE" || die "invalid --uplink-gateway: $P2_UPLINK_GATEWAY_OVERRIDE"
        P2_UPLINK_GATEWAY="$P2_UPLINK_GATEWAY_OVERRIDE"
    else
        P2_UPLINK_GATEWAY="$gateway_route"
    fi

    if [ -n "$P2_UPLINK_DNS_OVERRIDE" ]; then
        p2_valid_dns_csv "$P2_UPLINK_DNS_OVERRIDE" || die "invalid --uplink-dns: $P2_UPLINK_DNS_OVERRIDE"
        P2_UPLINK_DNS="${P2_UPLINK_DNS_OVERRIDE// /}"
    elif [ "$P2_UPLINK_MODE" = static ]; then
        resolved_dns="$(resolvectl dns "$P2_UPLINK_NIC" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | paste -sd, - || true)"
        p2_valid_dns_csv "$resolved_dns" || \
            die "static uplink has no DNS from resolvectl dns $P2_UPLINK_NIC; use --uplink-dns"
        P2_UPLINK_DNS="$resolved_dns"
    else
        P2_UPLINK_DNS=''
    fi
    log "uplink discovery: nic=$P2_UPLINK_NIC mac=$P2_UPLINK_MAC mode=$P2_UPLINK_MODE address=${P2_UPLINK_ADDRESS:-none} gateway=$P2_UPLINK_GATEWAY dns=${P2_UPLINK_DNS:-none}"
}

p2_recover_pending_transactions() {
    local parent txn state helper
    parent="$(p2_path /var/lib/pnetlab-pass2)"
    [ -d "$parent" ] || return 0
    # The deb-shipped recovery unit handles power-loss recovery before normal
    # boot. Re-run the same recovery before discovery as a guard for a manual
    # installer invocation that races the unit or follows a crashed install.
    [ -z "$P2_ROOT" ] || return 0
    helper=/opt/ovf/pnetlab-pass2-recover.sh
    shopt -s nullglob
    local -a pending=("$parent"/txn.*/state)
    shopt -u nullglob
    for txn in "${pending[@]}"; do
        state="$(cat "$txn" 2>/dev/null || true)"
        case "$state" in
            armed|verified)
                [ -x "$helper" ] || die "abandoned Pass 2 transaction found but recovery helper is missing: $helper"
                PNETLAB_PASS2_RECOVERY_LOG="$LOG" "$helper" || \
                    die "abandoned Pass 2 transaction could not be recovered: ${txn%/state}"
                ;;
        esac
    done
}

preflight_host() {
    local version_id available_kb
    log '=== preflight: host checks (no package/system configuration mutation) ==='
    [ "$(id -u)" -eq 0 ] || die 'must run as root'
    [ -r /etc/os-release ] || die 'missing /etc/os-release'
    # shellcheck disable=SC1091
    . /etc/os-release
    version_id="${VERSION_ID:-}"
    [ "$version_id" = '26.04' ] || die "requires Ubuntu 26.04; detected ${version_id:-unknown}"
    [ "$(dpkg --print-architecture 2>/dev/null)" = 'amd64' ] || die 'requires amd64'
    available_kb=$(df -Pk / | awk 'NR==2 {print $4}')
    [ "${available_kb:-0}" -ge 20971520 ] || die "requires at least 20 GiB free on /; detected ${available_kb:-0} KiB"
    [ -c /dev/kvm ] || die 'requires /dev/kvm for the network-install preflight'
    for command_name in apt-cache apt-get curl dpkg find getent gpg install ip openssl python3 systemctl; do
        require_command "$command_name"
    done
    log "host=$(hostname) release=$version_id arch=$(dpkg --print-architecture) free_kib=$available_kb kvm=/dev/kvm"
    # Discovery is intentionally the final preflight action: it reads sysfs,
    # routes, addresses, policy rules, and the original interfaces file before
    # the manifest keyring, apt sources, cache, or packages can mutate a host.
    p2_recover_pending_transactions
    detect_uplink_nic
}

policy_for() {
    local package="$1"
    apt-cache policy "$package" 2>&1 | tee -a "$LOG"
}

require_codeberg_candidate() {
    local package="$1" expected policy candidate
    expected="${PROFILE_DEBS[$package]:-${PROFILE_BEST_EFFORT[$package]:-}}"
    [ -n "$expected" ] || die "package is not in the selected profile's manifest selection: $package"
    policy=$(apt-cache policy "$package" 2>&1 | tee -a "$LOG")
    candidate=$(printf '%s\n' "$policy" | awk '/^[[:space:]]*Candidate:/ {print $2; exit}')
    [ "$candidate" = "$expected" ] || die "Codeberg candidate mismatch for $package: expected $expected, found ${candidate:-none}"
    printf '%s\n' "$policy" | grep -Fq "$CODEBERG_REPOSITORY" || \
        die "Codeberg origin missing from apt-cache policy for $package"
}

require_docker_candidate() {
    local policy candidate
    policy=$(apt-cache policy docker-ce 2>&1 | tee -a "$LOG")
    candidate=$(printf '%s\n' "$policy" | awk '/^[[:space:]]*Candidate:/ {print $2; exit}')
    [ -n "$candidate" ] && [ "$candidate" != '(none)' ] || die 'docker-ce has no apt candidate'
    printf '%s\n' "$policy" | grep -Fq 'download.docker.com/linux/ubuntu' || \
        die 'docker-ce candidate is not from download.docker.com'
    apt-cache show docker-ce 2>/dev/null | grep -Eq '^Architecture: amd64$' || \
        die 'docker-ce does not expose an amd64 package'
}

build_transaction() {
    local name
    CODEBERG_PACKAGES=()
    CODEBERG_PACKAGE_NAMES=()
    for name in $(printf '%s\n' "${!PROFILE_DEBS[@]}" | sort); do
        CODEBERG_PACKAGES+=("${name}=${PROFILE_DEBS[$name]}")
        CODEBERG_PACKAGE_NAMES+=("$name")
    done

    TRANSACTION=()
    CACHE_PACKAGES=()
    TRANSACTION+=("${BASE_PACKAGES[@]}")
    local package
    for package in "${CODEBERG_PACKAGES[@]}"; do
        [ "$NO_DOCKER" -eq 1 ] && [[ "$package" == pnetlab-docker=* ]] && continue
        TRANSACTION+=("$package")
        CACHE_PACKAGES+=("$package")
    done
    if [ "$NO_DOCKER" -eq 0 ]; then
        TRANSACTION+=("${DOCKER_PACKAGES[@]}")
    fi
}

cache_metadata_record() { # package version architecture -> sha<TAB>size<TAB>filename
    local package="$1" version="$2" architecture="$3"
    apt-cache show "$package=$version" 2>/dev/null | awk -v p="$package" -v v="$version" -v a="$architecture" '
        BEGIN { RS=""; FS="\n"; OFS="\t" }
        { delete x; for (i=1;i<=NF;i++) { n=index($i,":"); if (n) { k=substr($i,1,n-1); z=substr($i,n+1); sub(/^[[:space:]]+/,"",z); x[k]=z } }
          if (x["Package"]==p && x["Version"]==v && (x["Architecture"]==a || x["Architecture"]=="all"))
             if (x["SHA256"] ~ /^[[:xdigit:]]{64}$/ && x["Size"] ~ /^[0-9]+$/ && x["Filename"] != "") { print tolower(x["SHA256"]),x["Size"],x["Filename"]; exit } }'
}

cache_verify_deb() { # file package version architecture sha size
    local deb="$1" package="$2" version="$3" architecture="$4" expected_sha="$5" expected_size="$6" actual_arch
    [ -f "$deb" ] || return 1
    [ "$(dpkg-deb -f "$deb" Package 2>/dev/null)" = "$package" ] || return 1
    [ "$(dpkg-deb -f "$deb" Version 2>/dev/null)" = "$version" ] || return 1
    actual_arch="$(dpkg-deb -f "$deb" Architecture 2>/dev/null)"
    [ "$actual_arch" = "$architecture" ] || [ "$actual_arch" = all ] || return 1
    [ "$(sha256sum "$deb" | awk '{print tolower($1)}')" = "${expected_sha,,}" ] || return 1
    [ "$(stat -c '%s' "$deb")" = "$expected_size" ]
}

satellite_deb_origin_ok() {
    local package="$1" version="$2" madison
    madison=$(apt-cache madison "$package" 2>&1 | tee -a "$LOG") || return 1
    printf '%s\n' "$madison" | awk -F'|' -v expected="$version" -v origin="$DEB_SOURCE" '
        { candidate=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate); source=$3 }
        candidate == expected && index(source, origin) { found=1 }
        END { exit(found ? 0 : 1) }'
}

stage_satellite_deb() {
    local package="$1" version="$2" destination_dir="$3"
    local record expected_sha expected_size filename source_deb download_dir candidate
    satellite_deb_origin_ok "$package" "$version" || {
        warn "signed deb_source origin is not available for $package=$version"
        return 1
    }
    record=$(cache_metadata_record "$package" "$version" amd64)
    [ -n "$record" ] || {
        warn "signed apt metadata is missing for satellite package $package=$version"
        return 1
    }
    IFS=$'\t' read -r expected_sha expected_size filename <<<"$record"
    filename="${filename##*/}"
    source_deb="$APT_CACHE/$filename"
    if [ -f "$source_deb" ] && cache_verify_deb "$source_deb" "$package" "$version" amd64 "$expected_sha" "$expected_size"; then
        install -m 0644 "$source_deb" "$destination_dir/$filename" || return 1
    else
        download_dir=$(mktemp -d "$destination_dir/.download.XXXXXX") || return 1
        if ! ( cd "$download_dir" && apt-get download "$package=$version" ) >>"$LOG" 2>&1; then
            rm -rf -- "$download_dir"
            return 1
        fi
        candidate=$(find "$download_dir" -maxdepth 1 -type f -name '*.deb' -print -quit)
        if [ -z "$candidate" ]; then
            rm -rf -- "$download_dir"
            return 1
        fi
        install -m 0644 "$candidate" "$destination_dir/$filename" || {
            rm -rf -- "$download_dir"
            return 1
        }
        rm -rf -- "$download_dir"
    fi
    cache_verify_deb "$destination_dir/$filename" "$package" "$version" amd64 "$expected_sha" "$expected_size"
}

complete_marker_value() {
    local key="$1" marker="$2"
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$marker"
}

satellite_bundle_complete_for_release() {
    local bundle="$1" release="$2" marker_packages marker_optional marker_assets inventory_sha asset_inventory_sha
    local asset expected_sha expected_size asset_path actual_sha actual_size package version deb
    local -a expected_asset_names=(qemu-compat-libs.tgz)
    local expected_packages="pnetlab-docker=$release,pnetlab-qemu=$release,pnetlab-satellite=$release,pnetlab-vpcs=$release"
    local expected_assets='qemu-compat-libs.tgz,qemu-zoo-2.4.0-net.tgz,qemu-zoo-2.12.0-net.tgz,qemu-zoo-4.1.0-net.tgz,qemu-zoo-5.2.0-net.tgz'
    for version in "${SATELLITE_ZOO_VERSIONS[@]}"; do
        expected_asset_names+=("qemu-zoo-$version-net.tgz")
    done
    [ -d "$bundle" ] && [ ! -L "$bundle" ] || return 1
    [ "$(stat -c '%U:%G %a' "$bundle" 2>/dev/null)" = 'root:root 755' ] || return 1
    [ -f "$bundle/COMPLETE" ] || return 1
    marker_packages=$(complete_marker_value packages "$bundle/COMPLETE")
    marker_optional=$(complete_marker_value optional_packages "$bundle/COMPLETE")
    marker_assets=$(complete_marker_value assets "$bundle/COMPLETE")
    [ "$(complete_marker_value format "$bundle/COMPLETE")" = 1 ] || return 1
    [ "$(complete_marker_value release "$bundle/COMPLETE")" = "$release" ] || return 1
    [ "$marker_packages" = "$expected_packages" ] || return 1
    [ -z "$marker_optional" ] || [ "$marker_optional" = "pnetlab-bridge-dkms=$release" ] || return 1
    [ "$marker_assets" = "$expected_assets" ] || return 1
    [ -f "$bundle/inventory.tsv" ] || return 1
    inventory_sha=$(complete_marker_value inventory_sha256 "$bundle/COMPLETE")
    [ -n "$inventory_sha" ] && [ "$(sha256sum "$bundle/inventory.tsv" | awk '{print $1}')" = "$inventory_sha" ] || return 1
    [ -f "$bundle/asset-inventory.tsv" ] || return 1
    asset_inventory_sha=$(complete_marker_value asset_inventory_sha256 "$bundle/COMPLETE")
    [[ "$asset_inventory_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    [ "$(sha256sum "$bundle/asset-inventory.tsv" | awk '{print $1}')" = "$asset_inventory_sha" ] || return 1
    [ "$(sed -n '1p' "$bundle/asset-inventory.tsv")" = $'asset\tsha256\tsize\tpath' ] || return 1
    [ "$(wc -l <"$bundle/asset-inventory.tsv")" -eq 6 ] || return 1
    [ -x "$bundle/install-resolute-satellite.sh" ] || return 1
    [ "$(stat -c '%U:%G %a' "$bundle/install-resolute-satellite.sh" 2>/dev/null)" = 'root:root 755' ] || return 1
    for package in "${SATELLITE_HARD_PACKAGES[@]}"; do
        deb=$(find "$bundle/pnetlab-debs" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit 2>/dev/null || true)
        [ -n "$deb" ] || return 1
        [ "$(dpkg-deb -f "$deb" Package 2>/dev/null)" = "$package" ] || return 1
        [ "$(dpkg-deb -f "$deb" Version 2>/dev/null)" = "$release" ] || return 1
        [ "$(dpkg-deb -f "$deb" Architecture 2>/dev/null)" = amd64 ] || return 1
    done
    for version in "${SATELLITE_ZOO_VERSIONS[@]}"; do
        [ -f "$bundle/qemu-zoo/qemu-zoo-$version-net.tgz" ] || return 1
    done
    [ -f "$bundle/deps/qemu-compat-libs.tgz" ] || return 1
    for asset in "${expected_asset_names[@]}"; do
        if [ "$asset" = qemu-compat-libs.tgz ]; then
            asset_path="deps/$asset"
        else
            asset_path="qemu-zoo/$asset"
        fi
        IFS=$'\t' read -r expected_sha expected_size actual_sha <<<"$(awk -F'\t' -v a="$asset" '$1 == a {print $2 "\t" $3 "\t" $4; exit}' "$bundle/asset-inventory.tsv")"
        [ "$actual_sha" = "$asset_path" ] || return 1
        [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$expected_size" =~ ^[0-9]+$ ]] || return 1
        actual_sha="$(sha256sum "$bundle/$asset_path" | awk '{print $1}')"
        actual_size="$(stat -c '%s' "$bundle/$asset_path")"
        [ "$actual_sha" = "$expected_sha" ] && [ "$actual_size" = "$expected_size" ] || return 1
    done
    return 0
}

cache_reap_staging() {
    local dir
    shopt -s nullglob
    for dir in "$PNETLAB_DEB_CACHE_ROOT"/.staging-*; do
        case "$dir" in
            "$PNETLAB_DEB_CACHE_ROOT"/.staging-*) rm -rf --one-file-system -- "$dir" ;;
            *) die "refusing to reap unexpected cache path: $dir" ;;
        esac
    done
    shopt -u nullglob
}

cache_compare_committed() { # destination staging release; 0 equal, 10 differs, 20 corrupt
    local destination="$1" staging="$2" release="$3"
    python3 - "$destination" "$staging" "$release" <<'PY'
import hashlib, pathlib, re, sys
old, new = map(pathlib.Path, sys.argv[1:3])
release = sys.argv[3]
header = "package\tarchitecture\tversion\tsha256\tsize\tfilename"
def state(directory):
    if not directory.is_dir() or directory.is_symlink():
        raise ValueError(f"{directory}: committed cache path is not a real directory")
    for required in ("COMPLETE", "provenance", "cache.tsv"):
        child = directory / required
        if not child.is_file() or child.is_symlink():
            raise ValueError(f"{directory}: {required} is not a regular file")
    complete = (directory / "COMPLETE").read_text().splitlines()
    if len(complete) != 2 or complete[0] != "format=1" or not re.fullmatch(r"committed_utc=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", complete[1]):
        raise ValueError(f"{directory}: invalid COMPLETE")
    values = {}
    for line in (directory / "provenance").read_text().splitlines():
        if line.count("=") != 1: raise ValueError(f"{directory}: invalid provenance")
        key, value = line.split("=", 1)
        if key in values: raise ValueError(f"{directory}: duplicate provenance key {key}")
        values[key] = value
    for key in ("release", "manifest_sequence", "profile", "no_docker"):
        if key not in values: raise ValueError(f"{directory}: missing provenance {key}")
    if values["release"] != release or not re.fullmatch(r"[0-9]+", values["manifest_sequence"]): raise ValueError(f"{directory}: invalid identity provenance")
    if values["no_docker"] not in ("0", "1"): raise ValueError(f"{directory}: invalid no_docker")
    lines = (directory / "cache.tsv").read_text().splitlines()
    if len(lines) < 2 or lines[0] != header: raise ValueError(f"{directory}: invalid cache.tsv header/rows")
    rows = {}
    for number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")
        if len(fields) != 6: raise ValueError(f"{directory}: invalid cache.tsv line {number}")
        package, arch, version, sha, size, filename = fields
        if not re.fullmatch(r"pnetlab(?:-[a-z0-9][a-z0-9+.-]*)?", package) or arch not in ("amd64", "all") or not re.fullmatch(r"[A-Za-z0-9.+:~_-]+", version) or not re.fullmatch(r"[0-9a-f]{64}", sha) or not re.fullmatch(r"[0-9]+", size) or "/" in filename or not filename.endswith(".deb") or filename in rows:
            raise ValueError(f"{directory}: invalid cache.tsv line {number}")
        rows[filename] = (package, arch, version, sha, int(size), filename)
    actual = {p.name for p in directory.iterdir() if p.name.endswith(".deb")}
    if actual != set(rows): raise ValueError(f"{directory}: actual .deb set differs from cache.tsv")
    for filename, row in rows.items():
        item = directory / filename
        if item.is_symlink() or not item.is_file() or item.stat().st_size != row[4] or hashlib.sha256(item.read_bytes()).hexdigest() != row[3]: raise ValueError(f"{directory}: deb digest/size mismatch for {filename}")
    return values, rows
try:
    old_prov, old_rows = state(old)
except (OSError, ValueError) as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(21)  # existing committed directory is corrupt -- safe to quarantine and replace
try:
    new_prov, new_rows = state(new)
except (OSError, ValueError) as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(22)  # our own freshly-staged directory is corrupt -- never touch the existing one
# manifest_sha256, manifest_reissue, and source may legitimately differ
# between honest re-stagings (for example netinstall then update), so they are
# explicitly excluded. release and manifest_sequence are explicitly included
# and must agree with both the destination and the new staging directory.
if old_rows == new_rows and old_prov["profile"] == new_prov["profile"] and old_prov["no_docker"] == new_prov["no_docker"] and old_prov["release"] == new_prov["release"] and old_prov["manifest_sequence"] == new_prov["manifest_sequence"]:
    raise SystemExit(0)
raise SystemExit(10)
PY
}

stage_deb_cache() {
    local staging destination release manifest_sha manifest_sequence manifest_reissue package version architecture record sha size filename deb
    [ "$NO_DEB_CACHE" -eq 0 ] || { log 'WARNING: --no-deb-cache opted this host out of local rollback material and the retention guarantee'; return 0; }
    [ "$(id -u)" -eq 0 ] || die 'deb-cache staging must run as root'
    [ "${#CACHE_PACKAGES[@]}" -gt 0 ] || die 'deb-cache staging received an empty Codeberg package set'
    release="$MANIFEST_RELEASE"
    install -d -m 0755 "$PNETLAB_DEB_CACHE_ROOT"
    exec 8>"$PNETLAB_DEB_CACHE_LOCK"
    flock -w 600 8 || die 'another process holds the pnetlab deb-cache lock'
    cache_reap_staging
    staging="$(mktemp -d "$PNETLAB_DEB_CACHE_ROOT/.staging-$$-XXXXXX")"
    chmod 0755 "$staging"
    apt-get install -y --download-only --allow-change-held-packages "${CACHE_PACKAGES[@]}" >>"$LOG" 2>&1 || die 'deb-cache download preflight failed; no package mutation was attempted'
    printf 'package\tarchitecture\tversion\tsha256\tsize\tfilename\n' >"$staging/cache.tsv"
    for package_version in "${CACHE_PACKAGES[@]}"; do
        package="${package_version%%=*}"
        version="${package_version#*=}"
        architecture=amd64
        record="$(cache_metadata_record "$package" "$version" "$architecture")"
        IFS=$'\t' read -r sha size filename <<<"$record"
        [ -n "${sha:-}" ] || die "signed apt metadata is missing for $package=$version"
        filename="${filename##*/}"
        deb=""
        if [ -f "$APT_CACHE/$filename" ] && cache_verify_deb "$APT_CACHE/$filename" "$package" "$version" "$architecture" "$sha" "$size"; then
            ln -- "$APT_CACHE/$filename" "$staging/$filename" 2>/dev/null || cp --reflink=auto -- "$APT_CACHE/$filename" "$staging/$filename" || die "could not stage $filename"
            deb="$staging/$filename"
        else
            (cd "$staging" && apt-get download "$package=$version") >>"$LOG" 2>&1 || die "could not download $package=$version into cache staging"
            deb="$staging/$filename"
        fi
        cache_verify_deb "$deb" "$package" "$version" "$architecture" "$sha" "$size" || die "staged deb failed verification: $filename"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$package" "$architecture" "$version" "$sha" "$size" "$filename" >>"$staging/cache.tsv"
    done
    manifest_sha="$(sha256sum "$MANIFEST_FILE" | awk '{print $1}')"
    manifest_sequence="$MANIFEST_SEQUENCE"
    manifest_reissue="$(manifest_field reissue)"
    {
        printf 'release=%s\n' "$release"
        printf 'manifest_sha256=%s\nmanifest_sequence=%s\nmanifest_reissue=%s\n' "$manifest_sha" "$manifest_sequence" "$manifest_reissue"
        printf 'staged_utc=%s\nsource=netinstall\nprofile=%s\nno_docker=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROFILE" "$NO_DOCKER"
    } >"$staging/provenance"
    printf 'format=1\ncommitted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$staging/COMPLETE"
    find "$staging" -maxdepth 1 -type f -exec sync -f {} \; 2>/dev/null || sync
    sync -f "$staging" 2>/dev/null || sync
    destination="$PNETLAB_DEB_CACHE_ROOT/$release"
    if [ -e "$destination" ]; then
        if cache_compare_committed "$destination" "$staging" "$release"; then
            rm -rf --one-file-system -- "$staging"
        else
            rc=$?
            case "$rc" in
                10) die "cache directory for $release already exists with different content" ;;
                21) corrupt="$destination.corrupt-$(date -u +%Y%m%dT%H%M%SZ)"; mv -T -- "$destination" "$corrupt" || die "could not quarantine corrupt cache directory: $destination"; mv -T -- "$staging" "$destination" || die "could not commit replacement cache directory: $destination" ;;
                22) die "freshly staged cache directory for $release failed self-validation; leaving the existing committed directory untouched" ;;
                *) die "cache comparison failed for $release" ;;
            esac
        fi
    else
        mv -T -- "$staging" "$destination" || die "could not commit cache directory: $destination"
    fi
    sync -f "$PNETLAB_DEB_CACHE_ROOT" 2>/dev/null || sync
    exec 8>&-
    log "local deb cache committed: $destination"
}

simulate_exact_transaction() {
    local -a options=()
    [ "$NO_DOCKER" -eq 1 ] && options+=(--no-install-recommends)
    log '=== preflight: exact transaction simulation (last gate before mutation) ==='
    log "+ apt-get install --simulate -y ${options[*]} ${TRANSACTION[*]}"
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install --simulate -y "${options[@]}" \
        -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' \
        "${TRANSACTION[@]}" >>"$LOG" 2>&1 || die 'exact apt transaction simulation failed; no package mutation was attempted'
}

confirm_mutation() {
    [ "$YES" -eq 1 ] && return 0
    printf 'The preflight passed. Install PNetLab and Docker now? [y/N] ' >&2
    local answer=''
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) die 'installation declined' ;;
    esac
}

install_transaction() {
    local -a options=()
    [ "$NO_DOCKER" -eq 1 ] && options+=(--no-install-recommends)
    log '=== installing exact pinned transaction ==='
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y "${options[@]}" \
        -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' \
        "${TRANSACTION[@]}" >>"$LOG" 2>&1 || die 'pinned package transaction failed; inspect the installer log'
}

configure_host_basics() {
    log '[2/14 minimal] configuring SSH, systemd timeout, and root password'
    sed -i 's/^[#[:space:]]*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/^[#[:space:]]*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf 2>/dev/null || true
    systemctl daemon-reload >>"$LOG" 2>&1 || true
    systemctl restart ssh >>"$LOG" 2>&1 || die 'could not restart ssh after host-basics configuration'
    printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd >>"$LOG" 2>&1 || die 'could not set root password'
}

configure_database() {
    local mysql_admin mysql tables guac_tables schema guac_schema password_hash plugin_status
    mysql_admin=(mysql --defaults-file=/etc/mysql/debian.cnf)
    mysql=(mysql -uroot -p"$MYSQL_ROOT_PASSWORD")
    log '[14 minimal] configuring MySQL users, databases, schemas, and admin seed'
    for _ in $(seq 1 60); do
        "${mysql_admin[@]}" -N -e 'SELECT 1' >/dev/null 2>&1 && break
        sleep 1
    done
    "${mysql_admin[@]}" -N -e 'SELECT 1' >/dev/null 2>&1 || die 'mysqld did not accept connections'
    plugin_status=$("${mysql_admin[@]}" -N -e "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='mysql_native_password';" 2>/dev/null || true)
    if ! printf '%s\n' "$plugin_status" | grep -qi '^ACTIVE$'; then
        log '[14 minimal] enabling MySQL 8.4 mysql_native_password compatibility'
        printf '[mysqld]\nmysql_native_password=ON\n' >/etc/mysql/mysql.conf.d/zz-pnetlab-native-pw.cnf
        systemctl restart mysql >>"$LOG" 2>&1 || die 'could not restart MySQL after enabling mysql_native_password'
        for _ in $(seq 1 60); do
            "${mysql_admin[@]}" -N -e 'SELECT 1' >/dev/null 2>&1 && break
            sleep 1
        done
        plugin_status=$("${mysql_admin[@]}" -N -e "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='mysql_native_password';" 2>/dev/null || true)
        printf '%s\n' "$plugin_status" | grep -qi '^ACTIVE$' || die 'mysql_native_password did not become active'
    fi
    "${mysql_admin[@]}" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" >>"$LOG" 2>&1 || die 'could not configure MySQL root authentication'
    printf '[client]\nuser=root\npassword=%s\n' "$MYSQL_ROOT_PASSWORD" >/root/.my.cnf
    chmod 0600 /root/.my.cnf

    "${mysql_admin[@]}" >>"$LOG" 2>&1 <<'SQL_USERS'
CREATE DATABASE IF NOT EXISTS pnetlab_db CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS guacdb CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'pnetlab'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
CREATE USER IF NOT EXISTS 'guacuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
ALTER USER 'pnetlab'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
ALTER USER 'guacuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'localhost';
GRANT ALL PRIVILEGES ON guacdb.* TO 'guacuser'@'localhost';
FLUSH PRIVILEGES;
SQL_USERS

    tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pnetlab_db';")
    schema='/opt/unetlab/schema/pnetlab_db-schema.sql'
    [ -f "$schema" ] || schema='/opt/unetlab/schema/pnetlab_db.sql'
    [ -f "$schema" ] || die 'pnetlab schema payload is missing'
    if [ "${tables:-0}" -eq 0 ]; then
        "${mysql[@]}" pnetlab_db <"$schema" >>"$LOG" 2>&1 || die 'pnetlab schema import failed'
    fi

    guac_tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='guacdb';")
    guac_schema='/opt/unetlab/schema/guacdb-1.6.0-schema.sql'
    [ -f "$guac_schema" ] || die 'guacamole schema payload is missing'
    if [ "${guac_tables:-0}" -eq 0 ]; then
        "${mysql[@]}" guacdb <"$guac_schema" >>"$LOG" 2>&1 || die 'guacamole schema import failed'
    fi

    password_hash=$(printf '%s' pnet | sha256sum | awk '{print $1}')
    "${mysql[@]}" pnetlab_db >>"$LOG" 2>&1 <<SQL_ADMIN
INSERT INTO control (control_name, control_value) VALUES
  ('ctrl_offline_mode','0'), ('ctrl_online_mode','1'),
  ('ctrl_default_mode','online'), ('ctrl_captcha','0'),
  ('ctrl_version','8.2.0')
ON DUPLICATE KEY UPDATE control_value = VALUES(control_value);
INSERT INTO users (username,password,role,offline,user_status,online_time)
  SELECT 'admin','$password_hash','0',0,1,UNIX_TIMESTAMP()
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE username='admin');
UPDATE users SET password='$password_hash', role='0', offline=0,
  user_status=1, online_time=UNIX_TIMESTAMP(), active_time=NULL, expired_time=NULL
  WHERE username='admin';
DELETE u FROM users u,
  (SELECT MIN(pod) AS keep FROM users WHERE username='admin') m
  WHERE u.username='admin' AND u.pod <> m.keep;
SQL_ADMIN
}

configure_apache() {
    log '[11/14 minimal] writing Apache HTTP/HTTPS vhosts and reverse-proxy routes'
    install -d -m 0755 /etc/apache2/sites-available /etc/apache2/sites-enabled
    cat >/etc/apache2/sites-available/pnetlab.conf <<'APACHE_HTTP'
<VirtualHost *:80>
    DocumentRoot /opt/unetlab/html
    RewriteEngine On
    RewriteCond %{REMOTE_ADDR} !^127\.
    RewriteCond %{REMOTE_ADDR} !^::1$
    RewriteRule ^/?(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
    <Directory /opt/unetlab/html/>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ProxyPass /telnet/ ws://127.0.0.1:8022/ upgrade=websocket
    ProxyPassReverse /telnet/ ws://127.0.0.1:8022/
    ProxyPass /vnc/ ws://127.0.0.1:6080/ upgrade=websocket
    ProxyPassReverse /vnc/ ws://127.0.0.1:6080/
    ProxyPass /guac/ ws://127.0.0.1:8081/ upgrade=websocket
    ProxyPassReverse /guac/ ws://127.0.0.1:8081/
    ProxyPass /shell/ ws://127.0.0.1:8023/ upgrade=websocket
    ProxyPassReverse /shell/ ws://127.0.0.1:8023/
    ProxyPass /labstate/ ws://127.0.0.1:8024/ upgrade=websocket
    ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
    ProxyPass /console/http/ http://127.0.0.1:8025/ upgrade=websocket
    ProxyPassReverse /console/http/ http://127.0.0.1:8025/
</VirtualHost>
APACHE_HTTP

    if [ ! -f /etc/ssl/certs/pnetlab-selfsigned.crt ] || [ ! -f /etc/ssl/private/pnetlab-selfsigned.key ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
            -keyout /etc/ssl/private/pnetlab-selfsigned.key \
            -out /etc/ssl/certs/pnetlab-selfsigned.crt \
            -subj '/CN=pnetlab' \
            -addext 'subjectAltName=DNS:pnetlab,DNS:localhost,IP:127.0.0.1' >>"$LOG" 2>&1 || die 'self-signed HTTPS certificate generation failed'
        chmod 0600 /etc/ssl/private/pnetlab-selfsigned.key
    fi
    cat >/etc/apache2/sites-available/pnetlab-ssl.conf <<'APACHE_SSL'
<IfModule mod_ssl.c>
<VirtualHost *:443>
    DocumentRoot /opt/unetlab/html
    <Directory /opt/unetlab/html/>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
    <Directory /opt/unetlab/data/Exports/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/pnetlab-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/pnetlab-selfsigned.key
    ProxyPass /telnet/ ws://127.0.0.1:8022/ upgrade=websocket
    ProxyPassReverse /telnet/ ws://127.0.0.1:8022/
    ProxyPass /vnc/ ws://127.0.0.1:6080/ upgrade=websocket
    ProxyPassReverse /vnc/ ws://127.0.0.1:6080/
    ProxyPass /guac/ ws://127.0.0.1:8081/ upgrade=websocket
    ProxyPassReverse /guac/ ws://127.0.0.1:8081/
    ProxyPass /shell/ ws://127.0.0.1:8023/ upgrade=websocket
    ProxyPassReverse /shell/ ws://127.0.0.1:8023/
    ProxyPass /labstate/ ws://127.0.0.1:8024/ upgrade=websocket
    ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
    ProxyPass /console/http/ http://127.0.0.1:8025/ upgrade=websocket
    ProxyPassReverse /console/http/ http://127.0.0.1:8025/
</VirtualHost>
</IfModule>
APACHE_SSL

    a2enmod rewrite ssl proxy_http proxy_wstunnel headers http2 >>"$LOG" 2>&1 || die 'Apache module enablement failed'
    a2dissite 000-default default-ssl pnetlabs >>"$LOG" 2>&1 || true
    a2ensite pnetlab pnetlab-ssl >>"$LOG" 2>&1 || die 'Apache vhost enablement failed'
    sed -i '/^PrivateTmp[[:space:]]*=/d' /lib/systemd/system/apache2.service 2>/dev/null || true
}

configure_php_fpm() {
    log '[11e minimal] wiring Apache to php8.5-fpm'
    for service_name in apache2 php8.5-fpm; do
        install -d -m 0755 "/etc/systemd/system/${service_name}.service.d"
        cat >"/etc/systemd/system/${service_name}.service.d/zz-pnetlab-procnet.conf" <<'PROCNET'
[Service]
ProtectProc=default
ProcSubset=all
PROCNET
    done
    if [ -x /opt/unetlab/scripts/enable-php-fpm.sh ]; then
        bash /opt/unetlab/scripts/enable-php-fpm.sh >>"$LOG" 2>&1 || die 'packaged php-fpm switcher failed'
    else
        a2dismod php8.5 >>"$LOG" 2>&1 || true
        a2enmod mpm_event proxy_fcgi setenvif >>"$LOG" 2>&1 || die 'Apache FPM module enablement failed'
        a2enconf php8.5-fpm >>"$LOG" 2>&1 || die 'php8.5-fpm Apache config is missing'
        systemctl enable --now php8.5-fpm >>"$LOG" 2>&1 || die 'php8.5-fpm did not start'
    fi
    systemctl daemon-reload >>"$LOG" 2>&1 || die 'systemd reload failed after PHP-FPM wiring'
}

configure_web_hardening() {
    local hardening_script=/opt/unetlab/scripts/enable-web-hardening.sh
    log '=== applying final web hardening and export aliases ==='
    [ -x "$hardening_script" ] || die "missing web hardening script: $hardening_script"
    bash "$hardening_script" >>"$LOG" 2>&1 || \
        die 'web hardening/export alias activation failed'
}

configure_guac_key() {
    local env_file=/etc/pnet-webconsole/guac.env config_file=/etc/pnet-webconsole/console_config.php key
    log '[11d minimal] creating per-install GUAC_CRYPT_KEY'
    install -d -m 0755 /etc/pnet-webconsole
    key=''
    [ -f "$env_file" ] && key=$(sed -n 's/^GUAC_CRYPT_KEY=//p' "$env_file" | head -n1)
    [ "${#key}" -eq 32 ] || key=$(head -c 24 /dev/urandom | base64 | tr -d '\n')
    [ "${#key}" -eq 32 ] || die 'generated GUAC_CRYPT_KEY is not 32 bytes of base64 text'
    printf 'GUAC_CRYPT_KEY=%s\n' "$key" >"$env_file"
    chown root:root "$env_file"
    chmod 0600 "$env_file"
    [ -f "$config_file" ] || die 'packaged console_config.php is missing'
    sed -i "s|define('GUAC_CRYPT_KEY', '[^']*');|define('GUAC_CRYPT_KEY', '$key');|" "$config_file"
    systemctl enable --now guacd.service >>"$LOG" 2>&1 || die 'guacd did not start after GUAC_CRYPT_KEY setup'
    systemctl enable --now pnet-guac-lite.service >>"$LOG" 2>&1 || die 'pnet-guac-lite did not start after guac.env setup'
}

install_telnetlib3() {
    log '[11c minimal] installing telnetlib3 from the network and verifying import'
    require_command pip3
    pip3 install --break-system-packages telnetlib3 >>"$LOG" 2>&1 || die 'telnetlib3 installation failed'
    python3 -c 'import telnetlib3' >>"$LOG" 2>&1 || die 'telnetlib3 import verification failed'
    log '[11c minimal] retrying the postinst-owned console mux after its dependency is present'
    systemctl unmask pnet-console-mux.service >>"$LOG" 2>&1 || die 'could not unmask pnet-console-mux.service'
    systemctl daemon-reload >>"$LOG" 2>&1 || die 'systemd reload failed before console mux cutover'
    systemctl stop pnet-telnet-bridge.service pnet-websockify.service >>"$LOG" 2>&1 || true
    if systemctl enable --now pnet-console-mux.service >>"$LOG" 2>&1; then
        systemctl disable pnet-telnet-bridge.service pnet-websockify.service >>"$LOG" 2>&1 || true
    else
        systemctl restart pnet-telnet-bridge.service pnet-websockify.service >>"$LOG" 2>&1 || true
        die 'pnet-console-mux did not start after telnetlib3 installation'
    fi
}

verify_postinst_permissions() {
    log '[12/14 + 13/14] verifying postinst-owned sudoers cleanup and fixpermissions result'
    [ ! -e /etc/sudoers.d/unetlab ] || die 'pnetlab.postinst left the retired www-data sudoers grant in place'
    [ -x /opt/unetlab/wrappers/unl_wrapper ] || die 'unl_wrapper is missing from the pnetlab payload'
    [ -d /opt/unetlab/tmp ] || die 'pnetlab.postinst/payload did not create /opt/unetlab/tmp'
    getent group unl >/dev/null 2>&1 || die 'pnetlab.postinst did not create group unl'
    [ "$(stat -c '%G' /opt/unetlab/tmp 2>/dev/null)" = 'unl' ] || die '/opt/unetlab/tmp is not group-owned by unl'
    [ -d /opt/unetlab/data/Exports ] || die 'pnetlab.postinst did not create data/Exports'
    [ -d /opt/unetlab/data/Logs ] || die 'pnetlab.postinst did not create data/Logs'
    sudo -u www-data php -r 'require "/etc/pnet-webconsole/console_config.php";' >>"$LOG" 2>&1 || \
        die 'www-data cannot read /etc/pnet-webconsole/console_config.php'
}

verify_no_retired_console_units() {
    log '=== verifying the retired console units are absent from the installed payload ==='
    local dead
    for dead in pnet-websockify pnet-telnet-bridge; do
        [ ! -e "${PNET_SYSROOT}/lib/systemd/system/${dead}.service" ] || \
            die "retired unit shipped by the pnetlab deb: /lib/systemd/system/${dead}.service (stale builder input; see debs/pnetlab/build-stage.sh allowlist)"
        [ ! -e "${PNET_SYSROOT}/etc/systemd/system/${dead}.service" ] || \
            warn "stale ${dead}.service left in /etc from a pre-6.8.67 install; remove it"
    done
    [ ! -e "${PNET_SYSROOT}/opt/pnet-webconsole/backend/telnet_ws_bridge_telnetlib3.py" ] || \
        die 'retired backend shipped: /opt/pnet-webconsole/backend/telnet_ws_bridge_telnetlib3.py'
}

verify_cloud_bridges() {
    local i state=''
    log '=== verifying the cloud bridge devices (pnet0-9 + nat0) ==='
    [ "$(systemctl is-enabled pnetlab-pnet-bridges.service 2>/dev/null)" = 'enabled' ] || \
        die 'pnetlab-pnet-bridges.service is not enabled (deb did not ship/enable it)'
    # oneshot + RemainAfterExit: poll, do not sample once -- dpkg may still be
    # mid-transaction when this runs.
    for _ in $(seq 1 15); do
        state="$(systemctl is-active pnetlab-pnet-bridges.service 2>/dev/null || true)"
        [ "$state" = 'active' ] && break
        [ "$state" = 'failed' ] && break
        sleep 1
    done
    if [ "$state" != 'active' ]; then
        systemctl status pnetlab-pnet-bridges.service >>"$LOG" 2>&1 || true
        journalctl -u pnetlab-pnet-bridges.service -n 40 --no-pager >>"$LOG" 2>&1 || true
        die "pnetlab-pnet-bridges.service did not become active (state=${state:-unknown})"
    fi
    for i in 0 1 2 3 4 5 6 7 8 9; do
        ip link show "pnet$i" >/dev/null 2>&1 || die "cloud bridge device missing: pnet$i"
    done
    ip link show nat0 >/dev/null 2>&1 || die 'cloud bridge device missing: nat0'
    [ -x "${PNET_SYSROOT}/opt/ovf/pnet-bridges.sh" ] || \
        die '/opt/ovf/pnet-bridges.sh is not executable; ovfstartup.sh reassert will silently no-op'
    # DELIBERATELY NOT ASSERTED (Pass 1 scope): pnet0 carrying an address, eth0
    # enslaved into pnet0, nat0 carrying an address, udhcpd active, or any NAT rule.
    # Those need the ifupdown handoff, which this bootstrap does not perform.
    # Do not "fix" this by adding assertions -- add the handoff first (Pass 2).
    log 'cloud bridge devices present: pnet0-9 + nat0 (uplink/NAT are NOT provisioned; see summary)'
}

p2_fail_at() {
    local step="$1"
    [ "${PNETLAB_PASS2_FAIL_AT:-}" = "$step" ] || return 0
    die "PNETLAB_PASS2_FAIL_AT requested failure after $step"
}

p2_state() {
    local value="$1" temporary="${P2_TXN}/.state.$$.tmp"
    printf '%s\n' "$value" >"$temporary"
    mv -f -- "$temporary" "${P2_TXN}/state"
}

p2_remove_destination() {
    local path="$1"
    if [ -L "$path" ] || [ -f "$path" ]; then
        rm -f -- "$path"
    elif [ -d "$path" ]; then
        rmdir -- "$path"
    elif [ -e "$path" ]; then
        rm -f -- "$path"
    fi
}

p2_record_path() {
    local path="$1" forced_stash="${2:-}" kind mode uid gid linktarget='-' sha256='-' stash='-'
    local key="$path" parent
    [ "${P2_RECORDED[$key]+yes}" = yes ] && return 0
    P2_RECORDED["$key"]=1
    P2_RECORD_NUMBER=$((P2_RECORD_NUMBER + 1))
    if [ -L "$path" ]; then
        kind=symlink
        mode="$(stat -c '%a' -- "$path")"
        uid="$(stat -c '%u' -- "$path")"
        gid="$(stat -c '%g' -- "$path")"
        linktarget="$(readlink -- "$path")"
    elif [ -f "$path" ]; then
        kind=file
        mode="$(stat -c '%a' -- "$path")"
        uid="$(stat -c '%u' -- "$path")"
        gid="$(stat -c '%g' -- "$path")"
        sha256="$(sha256sum -- "$path" | awk '{print $1}')"
        if [ -n "$forced_stash" ]; then
            stash="$forced_stash"
        else
            stash="${P2_TXN}/stash/$(printf '%03d' "$P2_RECORD_NUMBER")"
            cp -a -- "$path" "$stash"
        fi
    elif [ -d "$path" ]; then
        kind=dir
        mode="$(stat -c '%a' -- "$path")"
        uid="$(stat -c '%u' -- "$path")"
        gid="$(stat -c '%g' -- "$path")"
    else
        kind=absent
        mode='-'
        uid='-'
        gid='-'
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$path" "$kind" "$mode" "$uid" "$gid" "$linktarget" "$sha256" "$stash" \
        >>"${P2_TXN}/manifest.tsv"
}

p2_atomic_write() {
    local destination="$1" mode="$2" parent temporary
    parent="$(dirname -- "$destination")"
    [ -d "$parent" ] || die "Pass 2 destination directory is missing: $parent"
    temporary="$(mktemp "$parent/.pass2.$$.XXXXXX")"
    cat >"$temporary"
    chmod "$mode" -- "$temporary"
    chown root:root -- "$temporary"
    mv -f -- "$temporary" "$destination"
}

p2_ensure_dir() {
    local directory="$1" mode="${2:-0755}"
    if [ ! -d "$directory" ]; then
        p2_record_path "$directory"
        install -d -m "$mode" -o root -g root -- "$directory"
    fi
}

p2_record_unit() {
    # The manifest also retains the raw UnitFileState/UnitFilePreset comment;
    # path records below preserve persistent and runtime topology.
    local unit_state
    unit_state="$(systemctl show -p UnitFileState --value "$1" 2>/dev/null || true)"
    local unit="$1" state active unit_state preset path wants_dir
    local key="unit:$unit"
    [ "${P2_RECORDED[$key]+yes}" = yes ] && return 0
    P2_RECORDED["$key"]=1
    state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    active="$(systemctl is-active "$unit" 2>/dev/null || true)"
    unit_state="$(systemctl show -p UnitFileState --value "$unit" 2>/dev/null || true)"
    preset="$(systemctl show -p UnitFilePreset --value "$unit" 2>/dev/null || true)"
    for path in \
        "$(p2_path "/etc/systemd/system/$unit")" \
        "$(p2_path "/run/systemd/system/$unit")"; do
        p2_record_path "$path"
    done
    wants_dir="$(p2_path /etc/systemd/system)"
    for wants in multi-user.target.wants sockets.target.wants network-pre.target.wants; do
        p2_record_path "$wants_dir/$wants/$unit"
    done
    if [ -d "$wants_dir" ]; then
        while IFS= read -r -d '' path; do
            p2_record_path "$path"
        done < <(find "$wants_dir" -type l -name "$unit" -print0)
    fi
    # Restore the unit operation first, then the exact /etc and /run topology.
    printf '# unit %s state=%s active=%s unit_file_state=%s preset=%s\n' \
        "$unit" "${state:-not-found}" "${active:-inactive}" "${unit_state:-unknown}" "${preset:-unknown}" >>"${P2_TXN}/manifest.tsv"
    printf '%s\tunit\t%s\t%s\t-\t-\t-\t-\n' \
        "$unit" "${state:-not-found}" "${active:-inactive}" >>"${P2_TXN}/manifest.tsv"
}

p2_restore_record() {
    local path="$1" kind="$2" mode="$3" uid="$4" gid="$5" linktarget="$6" sha256="$7" stash="$8"
    case "$kind" in
        absent)
            p2_remove_destination "$path"
            ;;
        file)
            [ -f "$stash" ] || { warn "Pass 2 rollback missing stash for $path: $stash"; return 1; }
            p2_remove_destination "$path"
            install -d -- "$(dirname -- "$path")"
            if [[ "$stash" == */netplan.pass2-txn/* ]]; then
                mv -f -- "$stash" "$path"
            else
                cp -a -- "$stash" "$path"
            fi
            chmod "$mode" -- "$path"
            chown "$uid:$gid" -- "$path"
            ;;
        symlink)
            p2_remove_destination "$path"
            install -d -- "$(dirname -- "$path")"
            ln -sfn -- "$linktarget" "$path"
            ;;
        dir)
            [ ! -e "$path" ] || rmdir -- "$path"
            ;;
        unit)
            case "$mode" in
                masked) systemctl unmask "$path" >/dev/null 2>&1 || true; systemctl mask "$path" >/dev/null 2>&1 || return 1 ;;
                enabled) systemctl unmask "$path" >/dev/null 2>&1 || true; systemctl enable "$path" >/dev/null 2>&1 || return 1 ;;
                disabled) systemctl unmask "$path" >/dev/null 2>&1 || true; systemctl disable "$path" >/dev/null 2>&1 || return 1 ;;
                static|alias|not-found|'') ;;
                *) warn "Pass 2 rollback unknown unit state for $path: $mode"; return 1 ;;
            esac
            case "$uid" in
                active) systemctl start "$path" >/dev/null 2>&1 || return 1 ;;
                inactive|dead|failed) systemctl stop "$path" >/dev/null 2>&1 || true ;;
            esac
            ;;
        *)
            warn "Pass 2 rollback unknown manifest kind for $path: $kind"
            return 1
            ;;
    esac
}

p2_rollback() {
    local line path kind mode uid gid linktarget sha256 stash
    local -a records=()
    local index failed=0 failed_paths=''
    [ "${P2_TXN_ACTIVE:-0}" -eq 1 ] || return 0
    [ "${P2_ROLLING_BACK:-0}" -eq 0 ] || return 0
    P2_ROLLING_BACK=1
    [ -f "${P2_TXN}/manifest.tsv" ] || {
        warn "Pass 2 rollback has no manifest: ${P2_TXN}"
        P2_ROLLING_BACK=0
        return 1
    }
    while IFS= read -r line || [ -n "$line" ]; do
        records+=("$line")
    done <"${P2_TXN}/manifest.tsv"
    set +e
    for ((index=${#records[@]} - 1; index >= 0; index--)); do
        line="${records[$index]}"
        [ -n "$line" ] || continue
        [[ "$line" == \#* ]] && continue
        IFS=$'\t' read -r path kind mode uid gid linktarget sha256 stash <<<"$line"
        [ -n "$path" ] || { failed=1; continue; }
        if ! p2_restore_record "$path" "$kind" "$mode" "$uid" "$gid" "$linktarget" "$sha256" "$stash"; then
            failed=1
            failed_paths+=" $path (stash=$stash)"
        fi
    done
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ "$failed" -eq 0 ]; then
        p2_state committed
        P2_TXN_ACTIVE=0
        log "Pass 2 transaction rolled back: ${P2_TXN}"
    else
        warn "Pass 2 rollback incomplete; recovery unit will retry: ${P2_TXN}; paths:${failed_paths:- none}"
    fi
    set -e
    P2_ROLLING_BACK=0
    [ "$failed" -eq 0 ]
}

p2_prune_committed() {
    local parent txn state txn_id stash_dir
    parent="${P2_TXN_PARENT:-$(p2_path /var/lib/pnetlab-pass2)}"
    [ -d "$parent" ] || return 0
    shopt -s nullglob
    local -a old_txns=("$parent"/txn.*)
    shopt -u nullglob
    for txn in "${old_txns[@]}"; do
        [ -d "$txn" ] || continue
        state="$(cat "$txn/state" 2>/dev/null || true)"
        [ "$state" = committed ] || continue
        txn_id="${txn##*/}"
        stash_dir="$(p2_path "/etc/netplan.pass2-txn/$txn_id")"
        [ ! -d "$stash_dir" ] || rm -rf -- "$stash_dir"
        rm -rf -- "$txn"
    done
}

p2_begin_transaction() {
    local parent
    p2_check_interfaces_b
    P2_TXN_PARENT="$(p2_path /var/lib/pnetlab-pass2)"
    if [ ! -d "$P2_TXN_PARENT" ]; then
        install -d -m 0700 -o root -g root -- "$P2_TXN_PARENT"
    else
        chmod 0700 -- "$P2_TXN_PARENT"
        chown root:root -- "$P2_TXN_PARENT"
    fi
    p2_prune_committed
    P2_TXN="$(mktemp -d "$P2_TXN_PARENT/txn.XXXXXX")"
    P2_TXN_ID="${P2_TXN##*/}"
    chmod 0700 -- "$P2_TXN"
    chown root:root -- "$P2_TXN"
    install -d -m 0700 -o root -g root -- "${P2_TXN}/stash"
    : >"${P2_TXN}/manifest.tsv"
    p2_state armed
    P2_TXN_ACTIVE=1
    P2_RECORDED=()
    P2_RECORD_NUMBER=0
    log "Pass 2 transaction armed: ${P2_TXN}"
}

p2_fault_boundary() {
    local step="$1"
    p2_fail_at "$step"
}

p2_build_pnet0_stanza() {
    if [ "$P2_UPLINK_MODE" = dhcp ]; then
        cat <<STANZA
# BEGIN pnetlab-netcfg pnet0
# Managed by pnetlab-netcfg. Mode: DHCP (stock non-blocking design).
# \`inet manual\` + a BACKGROUNDED dhcpcd (NOT \`inet dhcp\`, which blocks ifup and
# stretches boot to ~1m41s). allow-hotplug (NOT auto) lets the pnet0 bridge come
# up via the udev hotplug event without ifup -a blocking on it -> ~10s boot.
allow-hotplug pnet0
iface pnet0 inet manual
    up dhcpcd -b pnet0
    down dhcpcd -k pnet0 || true
    pre-up ip link set dev eth0 up
    bridge_ports eth0
    bridge_stp off
# END pnetlab-netcfg pnet0
STANZA
    else
        cat <<STANZA
# BEGIN pnetlab-netcfg pnet0
# Managed by pnetlab-netcfg. Mode: STATIC. Kept under allow-hotplug (NOT auto) so
# udev applies \`inet static\` non-blocking, preserving the ~10s boot. Change with:
#   pnetlab-netcfg           (interactive)   or   pnetlab-netcfg dhcp
allow-hotplug pnet0
iface pnet0 inet static
    address $P2_UPLINK_ADDRESS
    gateway $P2_UPLINK_GATEWAY
    pre-up ip link set dev eth0 up
    bridge_ports eth0
    bridge_stp off
# END pnetlab-netcfg pnet0
STANZA
    fi
}

p2_render_interfaces() {
    [ -z "$P2_SOURCE_DIRECTIVE" ] || printf '%s\n' "$P2_SOURCE_DIRECTIVE"
    if [ "$P2_POST_HAS_LO" = 1 ]; then
        printf 'auto lo\niface lo inet loopback\n\n'
    fi
    p2_build_pnet0_stanza
    for _i in $(seq 1 9); do
        cat <<IFACES

auto pnet${_i}
iface pnet${_i} inet manual
    bridge_ports none
    bridge_stp off
    post-up [ -e /sys/class/net/eth${_i} ] && ip link set dev eth${_i} master pnet${_i} up || true
IFACES
    done
    cat <<'IFACES'

# NAT cloud
auto natmac
iface natmac inet manual
    pre-up ip link add natmac address 00:01:01:01:01:01 type dummy
auto nat0
iface nat0 inet static
    bridge_ports natmac
    bridge_stp off
    address 10.0.137.254
    netmask 255.255.255.0
    up systemctl --no-block restart udhcpd
IFACES
}

p2_move_netplan() {
    local netplan_dir stash_root file target
    netplan_dir="$(p2_path /etc/netplan)"
    [ -d "$netplan_dir" ] || return 0
    mapfile -t P2_NETPLAN_FILES < <(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -print | sort)
    [ "${#P2_NETPLAN_FILES[@]}" -gt 0 ] || return 0
    p2_ensure_dir "$(p2_path /etc/netplan.pass2-txn)" 0700
    stash_root="$(p2_path "/etc/netplan.pass2-txn/$P2_TXN_ID")"
    p2_ensure_dir "$stash_root" 0700
    for file in "${P2_NETPLAN_FILES[@]}"; do
        target="$stash_root/${file##*/}"
        p2_record_path "$file" "$target"
        mv -f -- "$file" "$target"
    done
    P2_NETPLAN_TXN_DIR="$stash_root"
}

p2_write_file_from() {
    local source="$1" destination="$2" mode="$3"
    p2_atomic_write "$destination" "$mode" <"$source"
}

p2_selfcheck_script() {
    cat <<'SELFHECK'
#!/bin/bash
set -u

LOG=/var/log/pnetlab-network-install.log
PENDING=/opt/unetlab/.uplink-selfcheck-pending
RESULT=/opt/unetlab/.uplink-selfcheck-result
MODE=${P2_EXPECTED_MODE:-dhcp}
EXPECTED=${P2_EXPECTED_ADDRESS:-}
deadline=$(( $(date +%s) + 120 ))
first_failure=''

mark_failure() {
    [ -n "$first_failure" ] || first_failure="$1"
}

while :; do
    first_failure=''
    [ -e /sys/class/net/pnet0/brif/eth0 ] || mark_failure 'pnet0 does not contain eth0'
    [ "$(cat /sys/class/net/pnet0/carrier 2>/dev/null || true)" = 1 ] || mark_failure 'pnet0 carrier is not up'
    addresses="$(ip -o -4 addr show dev pnet0 scope global 2>/dev/null || true)"
    if [ "$MODE" = static ]; then
        grep -Eq "(^|[[:space:]])$EXPECTED([[:space:]]|$)" <<<"$addresses" || mark_failure "pnet0 lacks expected address $EXPECTED"
    else
        [ -n "$addresses" ] || mark_failure 'pnet0 has no global IPv4 address'
    fi
    ip -4 route show default dev pnet0 2>/dev/null | grep -q '^default' || mark_failure 'no default route via pnet0'
    ip -o -4 addr show dev nat0 2>/dev/null | awk '$4 == "10.0.137.254/24" {found=1} END {exit(found ? 0 : 1)}' || mark_failure 'nat0 lacks 10.0.137.254/24'
    ss -lunp 2>/dev/null | grep -Eq '(^|[[:space:]])[^[:space:]]*:67[[:space:]]' || mark_failure 'udhcpd is not listening on UDP port 67'
    [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true)" = 1 ] || mark_failure 'net.ipv4.ip_forward is not 1'
    masq_count="$(iptables -t nat -S POSTROUTING 2>/dev/null | awk '$0 == "-A POSTROUTING -s 10.0.137.0/24 -o pnet0 -j MASQUERADE" {n++} END {print n+0}')"
    [ "$masq_count" = 1 ] || mark_failure "expected one PNetLab MASQUERADE rule, found ${masq_count:-0}"
    fwd_rules="$(iptables -S PNETLAB-FWD 2>/dev/null || true)"
    grep -Fqx -- '-A PNETLAB-FWD -s 10.0.137.0/24 -o pnet0 -j ACCEPT' <<<"$fwd_rules" || mark_failure 'PNETLAB-FWD source rule is missing'
    grep -Fqx -- '-A PNETLAB-FWD -d 10.0.137.0/24 -i pnet0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT' <<<"$fwd_rules" || mark_failure 'PNETLAB-FWD return rule is missing'

    [ -z "$first_failure" ] && break
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 2
done

status=PASS
[ -z "$first_failure" ] || status="FAIL: $first_failure"
{
    printf '%s\n' "$status"
    printf 'observed mode=%s expected=%s\n' "$MODE" "${EXPECTED:-any-global-ipv4}"
    printf 'pnet0 addresses:\n%s\n' "${addresses:-<none>}"
    printf 'pnet0 default route:\n%s\n' "$(ip -4 route show default dev pnet0 2>/dev/null || true)"
    printf 'nat0 addresses:\n%s\n' "$(ip -o -4 addr show dev nat0 2>/dev/null || true)"
    printf 'udp listeners:\n%s\n' "$(ss -lunp 2>/dev/null || true)"
    printf 'ip_forward=%s\n' "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true)"
    printf 'POSTROUTING:\n%s\n' "$(iptables -t nat -S POSTROUTING 2>/dev/null || true)"
    printf 'PNETLAB-FWD:\n%s\n' "$(iptables -S PNETLAB-FWD 2>/dev/null || true)"
} | tee -a "$LOG" >"$RESULT"
rm -f -- "$PENDING"
[ "$status" = PASS ]
SELFHECK
}

p2_write_service_units() {
    local selfcheck="$1"
    cat <<UNIT
[Unit]
Description=PNetLab cloud-uplink post-reboot self-check
ConditionPathExists=/opt/unetlab/.uplink-selfcheck-pending
After=pnetlab-ovfstartup.service network-online.target

[Service]
Type=oneshot
Environment=P2_EXPECTED_MODE=$P2_UPLINK_MODE
Environment=P2_EXPECTED_ADDRESS=$P2_UPLINK_ADDRESS
ExecStart=/bin/bash $selfcheck
TimeoutStartSec=125

[Install]
WantedBy=multi-user.target
UNIT
}

p2_rewrite_udhcp_restart() {
    local path="$1"
    [ -f "$path" ] || return 0
    grep -Fq 'up service udhcpd restart' "$path" || return 0
    p2_record_path "$path"
    sed 's#up service udhcpd restart#up systemctl --no-block restart udhcpd#g' "$path" | \
        p2_atomic_write "$path" 0644
}

p2_unit_is_present() {
    local unit="$1"
    if systemctl list-unit-files "$unit" 2>/dev/null | awk -v u="$unit" '$1 == u {found=1} END {exit(found ? 0 : 1)}'; then
        return 0
    fi
    [ -f "$(p2_path "/lib/systemd/system/$unit")" ] || \
        [ -f "$(p2_path "/usr/lib/systemd/system/$unit")" ] || \
        [ -f "$(p2_path "/etc/systemd/system/$unit")" ]
}

p2_commit() {
    [ "$P2_TXN_ACTIVE" -eq 1 ] || die 'Pass 2 commit requested without an armed transaction'
    [ -f "${P2_TXN}/state" ] && [ "$(<"${P2_TXN}/state")" = verified ] || \
        die 'Pass 2 commit requested before the transaction reached verified state'
    p2_state committed
    P2_TXN_ACTIVE=0
    P2_PROVISIONED=1
    log "Pass 2 transaction committed: ${P2_TXN}"
}

p2_provision_cloud_uplink() {
    local interfaces link_file cloud_cfg timeout_dropin ovf_conf configured resolv selfcheck selfcheck_unit
    p2_begin_transaction

    # P2-a: the only safe full rewrite is one whose pre- and post-package
    # baselines were both proven before this transaction was armed.
    interfaces="$(p2_path /etc/network/interfaces)"
    p2_record_path "$interfaces"
    p2_render_interfaces | p2_atomic_write "$interfaces" 0644
    p2_fault_boundary P2-a

    # P2-b: let pnet0 adopt the detected NIC's MAC at the next reboot.
    p2_ensure_dir "$(p2_path /etc/systemd/network)" 0755
    link_file="$(p2_path /etc/systemd/network/98-pnet0-mac.link)"
    p2_record_path "$link_file"
    cat <<'LINK' | p2_atomic_write "$link_file" 0644
[Match]
OriginalName=pnet0

[Link]
MACAddressPolicy=none
LINK
    p2_fault_boundary P2-b

    # P2-c was deliberately dropped: a .link Name=eth0 rule cannot safely
    # resolve collisions and is the reason discovery refuses multi-NIC hosts.

    # P2-d: move netplan within /etc, disable cloud-init's network owner, then
    # make ifupdown the durable owner. Never --now: the reboot performs it.
    p2_move_netplan
    cloud_cfg="$(p2_path /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg)"
    p2_ensure_dir "$(dirname -- "$cloud_cfg")" 0755
    p2_record_path "$cloud_cfg"
    printf 'network: {config: disabled}\n' | p2_atomic_write "$cloud_cfg" 0644
    p2_record_unit networking.service
    p2_record_unit systemd-networkd.socket
    p2_record_unit systemd-networkd-varlink.socket
    p2_record_unit systemd-networkd-resolve-hook.socket
    p2_record_unit systemd-networkd.service
    systemctl unmask networking.service >>"$LOG" 2>&1 || die 'Pass 2 could not unmask networking.service'
    systemctl enable networking.service >>"$LOG" 2>&1 || die 'Pass 2 could not enable networking.service'
    # Mask ALL of systemd-networkd's triggering sockets, not just its own
    # socket -- systemd itself warns that systemd-networkd-varlink.socket and
    # systemd-networkd-resolve-hook.socket independently trigger the service
    # and are untouched by masking .socket/.service alone. Leaving them
    # active caused a real, reproduced systemd job-queue deadlock during
    # pnetlab-pass2-recover.sh's restart of systemd-networkd.service after an
    # abandoned transaction (2026-08-24 gate, step 19). Sockets are masked
    # before the service they trigger, matching systemd's own warning order.
    systemctl disable systemd-networkd.socket systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket systemd-networkd.service >>"$LOG" 2>&1 || die 'Pass 2 could not disable systemd-networkd'
    systemctl mask systemd-networkd.socket systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket systemd-networkd.service >>"$LOG" 2>&1 || die 'Pass 2 could not mask systemd-networkd'
    p2_fault_boundary P2-d

    # P2-e: bound networking.service startup and repair the old blocking
    # udhcpd spelling wherever the deb or an upgrade left it.
    timeout_dropin="$(p2_path /etc/systemd/system/networking.service.d/10-timeout.conf)"
    p2_ensure_dir "$(dirname -- "$timeout_dropin")" 0755
    p2_record_path "$timeout_dropin"
    printf '[Service]\nTimeoutStartSec=90\n' | p2_atomic_write "$timeout_dropin" 0644
    p2_rewrite_udhcp_restart "$interfaces"
    p2_rewrite_udhcp_restart "$(p2_path /opt/ovf/ovfconfig.sh)"
    p2_fault_boundary P2-e

    # P2-f: the unit is package-owned in Slice 2. Enabling an absent unit
    # would create a false success that fails only after the reboot.
    p2_unit_is_present pnetlab-ovfstartup.service || \
        die 'this build predates the deb-shipped ovfstartup unit; install the Slice 2 pnetlab deb before Pass 2'
    ovf_conf="$(p2_path /opt/ovf/ovfstartup.conf)"
    p2_ensure_dir "$(dirname -- "$ovf_conf")" 0755
    p2_record_path "$ovf_conf"
    cat <<'CONF' | p2_atomic_write "$ovf_conf" 0644
OVFSTARTUP_APT_AUTOREMOVE=0
OVFSTARTUP_PURGE_LOGS=0
OVFSTARTUP_LVM_AUTOEXTEND=0
OVFSTARTUP_EBTABLES_FLUSH=0
OVFSTARTUP_FORWARD_POLICY_ACCEPT=0
CONF
    p2_record_unit pnetlab-ovfstartup.service
    systemctl enable pnetlab-ovfstartup.service >>"$LOG" 2>&1 || die 'Pass 2 could not enable the deb-shipped pnetlab-ovfstartup.service'
    configured="$(p2_path /opt/ovf/.configured)"
    p2_record_path "$configured"
    if command -v dmidecode >/dev/null 2>&1; then
        dmidecode --string system-uuid 2>/dev/null | p2_atomic_write "$configured" 0644
    else
        printf '\n' | p2_atomic_write "$configured" 0644
    fi
    p2_fault_boundary P2-f

    # P2-g: static DNS is the one live write in Pass 2. It runs after the
    # satellite bundle's last network call and is immediately tested.
    if [ "$P2_UPLINK_MODE" = static ]; then
        resolv="$(p2_path /etc/resolv.conf)"
        p2_record_path "$resolv"
        {
            echo '# Written by pnetlab-netcfg (static mode). Edit with: pnetlab-netcfg'
            IFS=',' read -ra _dns_servers <<<"$P2_UPLINK_DNS"
            for _dns in "${_dns_servers[@]}"; do
                _dns="${_dns// /}"
                [ -n "$_dns" ] && printf 'nameserver %s\n' "$_dns"
            done
        } | p2_atomic_write "$resolv" 0644
        _dist_host="${PNETLAB_GENERIC_API_BASE:-$PNETLAB_DEFAULT_GENERIC_API_BASE}"
        _dist_host="${_dist_host#https://}"
        _dist_host="${_dist_host#http://}"
        _dist_host="${_dist_host%%/*}"
        getent hosts "$_dist_host" >/dev/null 2>&1 || die 'static DNS resolution check failed after writing /etc/resolv.conf'
    fi
    p2_fault_boundary P2-g

    # P2-h: the helper waits for all eight boot-time signals; only enablement
    # is performed now.
    selfcheck="$(p2_path /opt/ovf/pnetlab-uplink-selfcheck.sh)"
    p2_ensure_dir "$(dirname -- "$selfcheck")" 0755
    p2_record_path "$selfcheck"
    p2_selfcheck_script | p2_atomic_write "$selfcheck" 0755
    selfcheck_unit="$(p2_path /etc/systemd/system/pnetlab-uplink-selfcheck.service)"
    p2_ensure_dir "$(dirname -- "$selfcheck_unit")" 0755
    p2_record_path "$selfcheck_unit"
    p2_write_service_units "$selfcheck" | p2_atomic_write "$selfcheck_unit" 0644
    p2_record_path "$(p2_path /opt/unetlab/.uplink-selfcheck-pending)"
    printf '\n' | p2_atomic_write "$(p2_path /opt/unetlab/.uplink-selfcheck-pending)" 0644
    p2_record_unit pnetlab-uplink-selfcheck.service
    systemctl enable pnetlab-uplink-selfcheck.service >>"$LOG" 2>&1 || die 'Pass 2 could not enable the uplink self-check unit'
    p2_fault_boundary P2-h

    # P2-i: refresh systemd's view after all unit and drop-in writes.
    systemctl daemon-reload >>"$LOG" 2>&1 || die 'Pass 2 systemd daemon-reload failed'
    p2_fault_boundary P2-i
}

p2_extract_marker_block() {
    local file="$1" output="$2"
    awk '
        /# BEGIN pnetlab-netcfg pnet0/ {inside=1}
        inside {print}
        /# END pnetlab-netcfg pnet0/ {exit}
    ' "$file" >"$output"
}

p2_verify_interfaces_structure() {
    local interfaces expected marker
    interfaces="$(p2_path /etc/network/interfaces)"
    expected="$(mktemp /tmp/pnetlab-pass2-expected-stanza.XXXXXX)"
    marker="$(mktemp /tmp/pnetlab-pass2-actual-stanza.XXXXXX)"
    p2_build_pnet0_stanza >"$expected"
    p2_extract_marker_block "$interfaces" "$marker"
    cmp -s "$expected" "$marker" || {
        rm -f "$expected" "$marker"
        die 'Pass 2 verification: pnet0 marker stanza is not byte-identical to the pnetlab-netcfg builder'
    }
    rm -f "$expected" "$marker"
    python3 - "$interfaces" "$(p2_path /etc/network/interfaces.d)" "$P2_SOURCE_DIRECTIVE" <<'PY'
import os
import re
import sys

path, interfaces_d, expected_source = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    raw = source.readlines()

sources = []
stanzas = {}
current = None
for raw_line in raw:
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if re.fullmatch(r"(source|source-directory)\s+.+", stripped):
        sources.append(stripped)
        continue
    if re.match(r"^(auto|allow-hotplug)\s+.+$", stripped):
        continue
    iface = re.match(r"^iface\s+(\S+)\s+(\S+)\s+(\S+)$", stripped)
    if iface:
        current = iface.group(1)
        if current in stanzas:
            raise SystemExit(f"duplicate stanza: {current}")
        stanzas[current] = {"header": stripped, "options": []}
        continue
    if current is None or not raw_line.startswith((" ", "\t")):
        raise SystemExit(f"unexpected interfaces line: {stripped}")
    stanzas[current]["options"].append(stripped)

if expected_source:
    if sources != [expected_source]:
        raise SystemExit("interfaces.d source directive changed")
    if os.path.isdir(interfaces_d) and any(os.scandir(interfaces_d)):
        raise SystemExit("interfaces.d is populated")
elif sources:
    raise SystemExit("unexpected interfaces.d source directive")

required = {"pnet0", *[f"pnet{i}" for i in range(1, 10)], "natmac", "nat0"}
if set(stanzas) not in (required, required | {"lo"}):
    raise SystemExit(f"unexpected interface stanzas: {sorted(set(stanzas) - required)}")
if "lo" in stanzas and stanzas["lo"]["header"] != "iface lo inet loopback":
    raise SystemExit("lo stanza header changed")
pnet0_header = stanzas["pnet0"]["header"]
if pnet0_header not in ("iface pnet0 inet manual", "iface pnet0 inet static"):
    raise SystemExit("pnet0 stanza has the wrong method")
for i in range(1, 10):
    stanza = stanzas[f"pnet{i}"]
    if stanza["header"] != f"iface pnet{i} inet manual":
        raise SystemExit(f"pnet{i} is not manual")
    if stanza["options"].count("bridge_ports none") != 1:
        raise SystemExit(f"pnet{i} bridge_ports assertion failed")
    if stanza["options"].count("bridge_stp off") != 1:
        raise SystemExit(f"pnet{i} bridge_stp assertion failed")
    expected_guard = f"post-up [ -e /sys/class/net/eth{i} ] && ip link set dev eth{i} master pnet{i} up || true"
    if stanza["options"].count(expected_guard) != 1:
        raise SystemExit(f"pnet{i} master guard assertion failed")
if stanzas["natmac"]["header"] != "iface natmac inet manual":
    raise SystemExit("natmac stanza header failed")
if stanzas["nat0"]["header"] != "iface nat0 inet static":
    raise SystemExit("nat0 stanza header failed")
nat_options = stanzas["nat0"]["options"]
for option in ("bridge_ports natmac", "bridge_stp off", "address 10.0.137.254", "netmask 255.255.255.0"):
    if nat_options.count(option) != 1:
        raise SystemExit(f"nat0 option failed: {option}")
if nat_options.count("up systemctl --no-block restart udhcpd") != 1:
    raise SystemExit("nat0 udhcpd restart assertion failed")
PY
    if command -v ifquery >/dev/null 2>&1; then
        ifquery --list -a >/dev/null 2>&1 || die 'Pass 2 verification: ifquery --list -a failed'
    else
        die 'Pass 2 verification cannot run: ifquery is missing'
    fi
}

p2_verify_rule_once() {
    local table="$1" chain="$2" expected="$3" count
    count="$(iptables -t "$table" -S "$chain" 2>/dev/null | awk -v rule="$expected" '$0 == rule {n++} END {print n+0}')"
    [ "$count" = 1 ] || die "Pass 2 verification: expected exactly one '$expected', found ${count:-0}"
}

verify_cloud_uplink_config() {
    local conf apt_conf line
    log '=== verifying Pass 2 cloud uplink/NAT configuration (transaction still armed) ==='
    p2_verify_interfaces_structure
    grep -Fq 'MACAddressPolicy=none' "$(p2_path /etc/systemd/network/98-pnet0-mac.link)" || \
        die 'Pass 2 verification: MACAddressPolicy=none is missing'
    shopt -s nullglob
    local -a yaml_files=($(p2_path /etc/netplan)/*.yaml)
    shopt -u nullglob
    [ "${#yaml_files[@]}" -eq 0 ] || die 'Pass 2 verification: netplan YAML remains active'
    [ "$(systemctl is-enabled pnetlab-ovfstartup.service 2>/dev/null || true)" = enabled ] || \
        die 'Pass 2 verification: pnetlab-ovfstartup.service is not enabled'
    [ "$(systemctl is-enabled ovfstartup.service 2>/dev/null || true)" = masked ] || \
        die 'Pass 2 verification: legacy ovfstartup.service is not masked'
    [ "$(systemctl is-enabled networking.service 2>/dev/null || true)" = enabled ] || \
        die 'Pass 2 verification: networking.service is not enabled'
    [ "$(systemctl is-enabled systemd-networkd.service 2>/dev/null || true)" = masked ] || \
        die 'Pass 2 verification: systemd-networkd.service is not masked'
    [ "$(systemctl is-enabled systemd-networkd.socket 2>/dev/null || true)" = masked ] || \
        die 'Pass 2 verification: systemd-networkd.socket is not masked'
    [ "$(systemctl is-enabled systemd-networkd-varlink.socket 2>/dev/null || true)" = masked ] || \
        die 'Pass 2 verification: systemd-networkd-varlink.socket is not masked'
    [ "$(systemctl is-enabled systemd-networkd-resolve-hook.socket 2>/dev/null || true)" = masked ] || \
        die 'Pass 2 verification: systemd-networkd-resolve-hook.socket is not masked'
    grep -Fqx 'network: {config: disabled}' "$(p2_path /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg)" || \
        die 'Pass 2 verification: cloud-init network config is not disabled'
    grep -Fq 'net.ifnames=0' "$(p2_path /etc/default/grub)" || \
        die 'Pass 2 verification: net.ifnames=0 is missing from /etc/default/grub'
    conf="$(p2_path /opt/ovf/ovfstartup.conf)"
    python3 - "$conf" <<'PY'
import sys
expected = {
    "OVFSTARTUP_APT_AUTOREMOVE": "0",
    "OVFSTARTUP_PURGE_LOGS": "0",
    "OVFSTARTUP_LVM_AUTOEXTEND": "0",
    "OVFSTARTUP_EBTABLES_FLUSH": "0",
    "OVFSTARTUP_FORWARD_POLICY_ACCEPT": "0",
}
values = {}
with open(sys.argv[1], encoding="utf-8") as source:
    for line in source:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or key in values:
            raise SystemExit("malformed or duplicate ovfstartup toggle")
        values[key] = value
if values != expected:
    raise SystemExit("ovfstartup toggles are not exactly the five zero values")
PY
    # MASQUERADE and PNETLAB-FWD rule checks deliberately do NOT belong here.
    # Both only exist once ovfstartup.sh has actually run, which never happens
    # in this install-time session by design (D2: pnetlab-ovfstartup.service is
    # `enable`d, never `--now`-started, at install/package time). The identical
    # assertions already run post-boot in pnetlab-uplink-selfcheck.sh (see
    # p2_selfcheck_script()), whose PASS/FAIL result gate step 3 of
    # docs/pass2-design/03-revised-plan.md already checks. Asserting them here
    # guaranteed rollback on every fresh install; see the 2026-08-24 gate run.
    for unit in apt-daily.timer apt-daily-upgrade.timer motd-news.timer unattended-upgrades.service; do
        [ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" = masked ] || \
            die "Pass 2 verification: $unit is not masked"
    done
    apt_conf="$(p2_path /etc/apt/apt.conf.d/99pnetlab-no-auto-upgrade)"
    for line in \
        'APT::Periodic::Update-Package-Lists "0";' \
        'APT::Periodic::Unattended-Upgrade "0";' \
        'APT::Periodic::Download-Upgradeable-Packages "0";' \
        'APT::Periodic::AutocleanInterval "0";'; do
        grep -Fqx "$line" "$apt_conf" || die "Pass 2 verification: missing unattended-upgrade setting: $line"
    done
    log 'Pass 2 verification passed: structural interfaces, handoff ownership, deny-list, NAT, and unattended-upgrade state'
}

ensure_runtime_tmp() {
    log '[13 minimal] creating the engine runtime tmp directory omitted by pnetlab.postinst'
    getent group unl >/dev/null 2>&1 || die 'unl group is missing before runtime tmp setup'
    install -d -o root -g unl -m 2777 /opt/unetlab/tmp
}

recover_dkms() {
    local dkms_status journal_status purge_status configure_status check_status
    warn 'pnetlab-bridge-dkms failed; starting mandatory recovery'
    {
        echo '--- dkms status ---'
        dkms status || true
        echo '--- kernel journal ---'
        journalctl -k -n 150 --no-pager || true
        echo '--- dpkg audit before purge ---'
        dpkg --audit || true
    } >>"$LOG" 2>&1
    set +e
    apt-get purge -y pnetlab-bridge-dkms >>"$LOG" 2>&1
    purge_status=$?
    dpkg --configure -a >>"$LOG" 2>&1
    configure_status=$?
    apt-get check >>"$LOG" 2>&1
    check_status=$?
    set -e
    [ "$configure_status" -eq 0 ] || die 'DKMS recovery dpkg --configure -a failed'
    [ "$check_status" -eq 0 ] || die 'DKMS recovery left apt-get check unclean'
    warn "pnetlab-bridge-dkms unavailable/failed and was purged (purge rc=$purge_status); continuing without patched bridge module"
}

install_dkms_best_effort() {
    local version="${PROFILE_BEST_EFFORT[pnetlab-bridge-dkms]:-}"
    [ -n "$version" ] || { log '[post-step-5] pnetlab-bridge-dkms not in this profile selection; skipping'; return 0; }
    log "[post-step-5] installing pnetlab-bridge-dkms=$version as isolated best effort"
    if apt-get install -y "pnetlab-bridge-dkms=${version}" >>"$LOG" 2>&1; then
        log 'pnetlab-bridge-dkms installed; recording DKMS state'
        dkms status >>"$LOG" 2>&1 || true
    else
        recover_dkms
    fi
}

assert_restart_clean() {
    local unit="$1" restarts
    restarts=$(systemctl show -p NRestarts --value "$unit" 2>/dev/null || echo unavailable)
    [ "$restarts" = '0' ] || die "$unit restart-loop evidence: NRestarts=${restarts:-empty}"
}

wait_socket() {
    local label="$1" expression="$2" unit="$3" command_text
    for _ in $(seq 1 30); do
        if eval "$expression" >/dev/null 2>&1; then
            assert_restart_clean "$unit"
            log "socket OK: $label ($unit; NRestarts=$(systemctl show -p NRestarts --value "$unit" 2>/dev/null))"
            return 0
        fi
        sleep 1
    done
    command_text="systemctl status $unit; journalctl -u $unit -n 80 --no-pager"
    eval "$command_text" >>"$LOG" 2>&1 || true
    die "socket did not become ready: $label"
}

verify_services() {
    log '=== socket-level service verification (restart-loop proof) ==='
    wait_socket 'broker unix socket' '[ -S /run/pnetlab/broker.sock ]' pnetlab-brokerd.service
    wait_socket 'HTTP bridge 127.0.0.1:8025' "ss -ltnH 'sport = :8025' | grep -Eq '127\\.0\\.0\\.1:8025|\\[::1\\]:8025'" pnet-http-bridge.service
    wait_socket 'console mux telnet :8022 and VNC :6080' "ss -ltnH 'sport = :8022' | grep -Eq '127\\.0\\.0\\.1:8022|\\[::1\\]:8022' && ss -ltnH 'sport = :6080' | grep -Eq '127\\.0\\.0\\.1:6080|\\[::1\\]:6080'" pnet-console-mux.service
    wait_socket 'shell bridge :8023' "ss -ltnH 'sport = :8023' | grep -Eq '127\\.0\\.0\\.1:8023|\\[::1\\]:8023'" pnet-shell-bridge.service
    wait_socket 'guac-lite :8081' "ss -ltnH 'sport = :8081' | grep -Eq '127\\.0\\.0\\.1:8081|\\[::1\\]:8081'" pnet-guac-lite.service
    wait_socket 'labstated :8024' "ss -ltnH 'sport = :8024' | grep -Eq '127\\.0\\.0\\.1:8024|\\[::1\\]:8024'" pnetlab-labstated.service
}

verify_broker_only() {
    log '=== satellite profile: broker-only socket verification ==='
    wait_socket 'broker unix socket' '[ -S /run/pnetlab/broker.sock ]' pnetlab-brokerd.service
}

verify_schema() {
    local query result
    log '=== schema verification against shipped 6.8.64 schema shape ==='
    query="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pnetlab_db' AND table_name IN ('control','users','node_sessions');"
    result=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$query")
    [ "$result" = '3' ] || die "schema table verification failed: expected 3 core tables, got ${result:-empty}"
    for column in user_max_cpu user_max_ram access_days ext_auth; do
        query="SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='pnetlab_db' AND table_name='users' AND column_name='$column';"
        result=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$query")
        [ "$result" = '1' ] || die "schema column verification failed: users.$column"
    done
    query="SELECT username FROM pnetlab_db.users WHERE username='admin';"
    [ "$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$query")" = 'admin' ] || die 'admin seed verification failed'
}

verify_web_and_login() {
    local login_code api_code api_body session_body
    log '=== HTTPS login and API login verification ==='
    login_code=$(curl -k -sS -o /dev/null -w '%{http_code}' https://127.0.0.1/login/)
    [ "$login_code" = '200' ] || die "HTTPS login page returned HTTP $login_code"
    COOKIE_TMP=$(mktemp /tmp/pnetlab-netinstall-cookie.XXXXXX)
    api_body=$(mktemp /tmp/pnetlab-netinstall-api.XXXXXX)
    api_code=$(curl -k -sS -c "$COOKIE_TMP" -o "$api_body" -w '%{http_code}' \
        -X POST https://127.0.0.1/api/auth \
        -H 'Content-Type: application/json' \
        --data '{"username":"admin","password":"pnet"}')
    [ "$api_code" = '200' ] || { cat "$api_body" >>"$LOG"; die "HTTPS API login returned HTTP $api_code"; }
    SESSION_TMP=$(mktemp /tmp/pnetlab-netinstall-session.XXXXXX)
    curl -k -sS -b "$COOKIE_TMP" -o "$SESSION_TMP" https://127.0.0.1/api/auth >>"$LOG" 2>&1 || true
    cat "$SESSION_TMP" >>"$LOG"
    grep -Eiq 'admin|User has been loaded' "$api_body" "$SESSION_TMP" || {
        die 'API login response did not identify the admin user'
    }
    rm -f "$api_body"
    rm -f "$SESSION_TMP"
    SESSION_TMP=''
}

verify_docker() {
    if [ "$NO_DOCKER" -eq 1 ]; then
        log '=== --no-docker negative postcondition ==='
        if dpkg-query -W -f='${db:Status-Status}\n' docker-ce 2>/dev/null | grep -qx installed; then
            die '--no-docker postcondition failed: docker-ce is installed'
        fi
        if dpkg-query -W -f='${db:Status-Status}\n' pnetlab-docker 2>/dev/null | grep -qx installed; then
            die '--no-docker postcondition failed: pnetlab-docker is installed'
        fi
        log 'negative postcondition OK: docker-ce and pnetlab-docker are not installed'
        return 0
    fi
    log '=== Docker runtime verification ==='
    systemctl enable --now docker >>"$LOG" 2>&1 || die 'Docker service did not start'
    docker info >>"$LOG" 2>&1 || die 'docker info failed'
    docker run --rm hello-world >>"$LOG" 2>&1 || die 'docker run --rm hello-world failed'
    log '=== required Docker-backed node smoke through the PNetLab broker ==='
    python3 - <<'PY' >>"$LOG" 2>&1 || die 'brokered Docker node smoke failed'
import json
import socket
import time

SOCK = '/run/pnetlab/broker.sock'
SESSION = 970001


def call(verb, args):
    request = (json.dumps({'verb': verb, 'args': args}) + '\n').encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(180)
        sock.connect(SOCK)
        sock.sendall(request)
        data = b''
        while not data.endswith(b'\n'):
            chunk = sock.recv(1048576)
            if not chunk:
                raise RuntimeError('broker closed without a response')
            data += chunk
    return json.loads(data.decode())


created = False
try:
    create = call('docker_create', {
        'family': 'docker',
        'session': SESSION,
        'lab_session': SESSION,
        'template': 'docker',
        'name': 'netinstall-docker-smoke',
        'image': 'hello-world',
        'ram': 64,
        'cpu': 1,
        'publish': [],
    })
    print('docker_create:', json.dumps(create, sort_keys=True))
    if create.get('rc') != 0:
        raise RuntimeError('docker_create returned rc=%s' % create.get('rc'))
    created = True

    start = call('docker_start', {'node_session': SESSION})
    print('docker_start:', json.dumps(start, sort_keys=True))
    if start.get('rc') != 0:
        raise RuntimeError('docker_start returned rc=%s' % start.get('rc'))
    time.sleep(1)

    inspect = call('docker_inspect', {
        'kind': 'node',
        'node_session': SESSION,
        'format': '{{json .State}}',
    })
    print('docker_inspect:', json.dumps(inspect, sort_keys=True))
    if inspect.get('rc') != 0 or not inspect.get('out'):
        raise RuntimeError('docker_inspect did not return container state')
    state = json.loads(inspect['out'][0])
    if state.get('Status') not in ('running', 'exited'):
        raise RuntimeError('unexpected Docker node state: %s' % state.get('Status'))
    if state.get('Status') == 'exited' and state.get('ExitCode') != 0:
        raise RuntimeError('Docker node exited with code %s' % state.get('ExitCode'))
finally:
    if created:
        removed = call('docker_rm', {'node_session': SESSION, 'force': True})
        print('docker_rm:', json.dumps(removed, sort_keys=True))
        if removed.get('rc') != 0:
            raise RuntimeError('docker_rm returned rc=%s' % removed.get('rc'))
PY
    log 'Docker apt/runtime smoke and brokered Docker node smoke OK'
}

# pnet-capture-web:1.0 -- the html5 web packet-capture image the link Capture
# action invokes. Never bundled offline on any install path (Docker Hub pull
# only); the ISO installer pre-pulls it during install so it's warm for the
# first Capture click, this bootstrap did not. Best-effort: a failed pull just
# means the GUI's own on-demand pull runs on first use instead.
CAPWEB_PRELOADED=0
preload_capture_web() {
    log '=== preloading pnet-capture-web (html5 packet capture) ==='
    if docker pull rspnet/pnet-capture-web:latest >>"$LOG" 2>&1; then
        docker tag rspnet/pnet-capture-web:latest pnet-capture-web:1.0 >>"$LOG" 2>&1 || true
        log 'pulled + tagged pnet-capture-web:1.0 from Docker Hub (rspnet/)'
        CAPWEB_PRELOADED=1
    else
        warn 'pnet-capture-web pull failed -- html5 packet capture will pull on first use from Dashboard > Docker Devices'
    fi
}

summary() {
    log '=== installed package/origin summary ==='
    dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' \
        "${CODEBERG_PACKAGE_NAMES[@]}" \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
        mysql-server php8.5-fpm 2>&1 | tee -a "$LOG" || true
    for package in "${CODEBERG_PACKAGE_NAMES[@]}"; do
        apt-cache policy "$package" >>"$LOG" 2>&1 || true
    done
    for package in "${DOCKER_PACKAGES[@]}"; do
        apt-cache policy "$package" >>"$LOG" 2>&1 || true
    done
    log "Manifest consumed: release=$MANIFEST_RELEASE sequence=$MANIFEST_SEQUENCE profile=$PROFILE"
    log 'Not available on network installs (offline bundle only): pnet-wireshark, pnet-wifi-spike.'
    if [ "$PROFILE" = master ] && [ "$NO_DOCKER" -eq 0 ]; then
        if [ "$CAPWEB_PRELOADED" -eq 1 ]; then
            log 'html5 packet capture : pnet-capture-web:1.0 preloaded, ready for the link Capture action.'
        else
            log 'html5 packet capture : pnet-capture-web NOT preloaded (pull failed) -- will pull on first use from Dashboard > Docker Devices.'
        fi
    fi
    log 'Pointer only: future update operations remain owned by pnetlab-update; this bootstrap does not invoke it.'
    log 'cloud bridges     : pnet0-9 + nat0 devices present (GUI cloud list populated)'
    if [ "$PROFILE" = satellite ]; then
        log 'cloud uplink/NAT  : SKIPPED -- satellite profile is Pass 2 master-only.'
        log 'management NIC    : Pass 2 skipped; the satellite profile keeps its existing networking.'
    elif [ "$P2_ALREADY_PROVISIONED" -eq 1 ]; then
        log 'cloud uplink/NAT  : already provisioned by an earlier run; Pass 2 skipped, networking untouched.'
        log 'management NIC    : unchanged. Packages were still installed/upgraded normally by this run.'
    elif [ "$P2_NO_CLOUD_UPLINK" -eq 1 ]; then
        log 'cloud uplink/NAT  : SKIPPED by --no-cloud-uplink.'
        log 'WARNING           : net.ifnames=0 remains armed by the deb; confirm your own boot-time networking survives the rename.'
    elif [ "$P2_PROVISIONED" -eq 1 ]; then
        log "cloud uplink/NAT  : provisioned (pnet0 mgmt bridge over $P2_UPLINK_NIC, $P2_UPLINK_MODE; nat0 10.0.137.254/24 + udhcpd + MASQUERADE)"
        log 'ovfstartup        : enabled (deb unit) with deny-list: no apt-autoremove, no log purge, no LVM auto-extend, no ebtables flush, scoped FORWARD rules'
        log "management NIC    : $P2_UPLINK_NIC (MAC $P2_UPLINK_MAC) becomes eth0 inside pnet0 AT THE NEXT REBOOT."
        log 'IP AFTER REBOOT   : the same address is EXPECTED but NOT GUARANTEED. The DHCP client changes from systemd-networkd to dhcpcd, and a DHCP server keying on DUID/client-id rather than MAC may issue a different lease.'
        log "Find the host after reboot by MAC $P2_UPLINK_MAC."
        log 'Recovery from console: pnetlab-netcfg'
        log 'REBOOT REQUIRED   : networking is NOT yet handed over.'
        log 'SELF-CHECK        : result will be written to /opt/unetlab/.uplink-selfcheck-result after reboot.'
    fi
}

main() {
    log "=== ${PROGRAM}: Ubuntu 26.04 manifest-driven network install (profile=${PROFILE}, no-docker=${NO_DOCKER}) ==="
    preflight_host

    provision_manifest_keyring
    if [ -z "$MANIFEST_SOURCE" ]; then
        if [ "$RELEASE_HINT" = latest ]; then
            resolve_latest_release
        else
            MANIFEST_SOURCE="${PNETLAB_GENERIC_API_BASE:-$PNETLAB_DEFAULT_GENERIC_API_BASE}"
            MANIFEST_SOURCE="${MANIFEST_SOURCE%/}/${DEFAULT_GENERIC_OWNER}/generic/${DEFAULT_GENERIC_PACKAGE}/${RELEASE_HINT}/pnetlab-${RELEASE_HINT}-manifest.json"
        fi
    fi
    fetch_manifest "$MANIFEST_SOURCE"
    verify_manifest_signature
    verify_manifest_semantics
    load_profile_selection
    if [ "$POINTER_USED" -eq 1 ]; then
        [ "$MANIFEST_RELEASE" = "$POINTER_RELEASE" ] \
            && [ "$MANIFEST_SEQUENCE" = "$POINTER_SEQUENCE" ] \
            || die "channel pointer/manifest identity mismatch: pointer=${POINTER_RELEASE}/${POINTER_SEQUENCE}, manifest=${MANIFEST_RELEASE}/${MANIFEST_SEQUENCE}"
        log "channel pointer/manifest identity matches: release=$MANIFEST_RELEASE sequence=$MANIFEST_SEQUENCE"
    fi
    CODEBERG_REPOSITORY="$DEB_SOURCE"
    CODEBERG_KEY_URL="${CODEBERG_REPOSITORY}/repository.key"

    log '=== enrolling fresh-install-scoped Codeberg apt source ==='
    enroll_keyring "$CODEBERG_KEY_URL" "$CODEBERG_KEYRING"
    assert_apt_keyring_fpr "$CODEBERG_KEYRING" "$DEB_SOURCE_KEY_FPR"
    enroll_source "$CODEBERG_SOURCE" "deb [arch=amd64 signed-by=$CODEBERG_KEYRING] $CODEBERG_REPOSITORY resolute main"

    if [ "$NO_DOCKER" -eq 0 ]; then
        log '=== enrolling Docker apt source ==='
        enroll_keyring "$DOCKER_KEY_URL" "$DOCKER_KEYRING"
        enroll_source "$DOCKER_SOURCE" "deb [arch=amd64 signed-by=$DOCKER_KEYRING] https://download.docker.com/linux/ubuntu resolute stable"
    else
        log '=== --no-docker: Docker source enrollment skipped ==='
    fi

    apt_update_checked
    log '=== verifying signed apt origins and exact manifest-pinned candidates ==='
    build_transaction
    for package in "${CODEBERG_PACKAGE_NAMES[@]}"; do
        [ "$NO_DOCKER" -eq 1 ] && [ "$package" = 'pnetlab-docker' ] && continue
        require_codeberg_candidate "$package"
    done
    if [ "$NO_DOCKER" -eq 0 ]; then
        require_docker_candidate
    fi
    simulate_exact_transaction
    confirm_mutation
    stage_deb_cache
    install_transaction
    install_dkms_best_effort
    fetch_core_assets

    ensure_runtime_tmp
    verify_postinst_permissions
    verify_no_retired_console_units

    if [ "$PROFILE" = master ]; then
        configure_host_basics
        configure_database
        configure_apache
        configure_php_fpm
        configure_guac_key
        install_telnetlib3
        systemctl daemon-reload >>"$LOG" 2>&1 || die 'systemd daemon-reload failed'

        # The pnetlab postinst runs this once, but configure_apache() writes the
        # final netinstall vhosts afterwards. Re-run it only after Apache/PHP are
        # configured so /Exports and the other hardened aliases survive.
        configure_web_hardening

        verify_docker
        [ "$NO_DOCKER" -eq 0 ] && preload_capture_web
        verify_services
        verify_cloud_bridges
        verify_schema
        verify_web_and_login
        if ! stage_satellite_bundle; then
            warn 'satellite bundle staging failed; continuing network install'
        fi
        if [ "$P2_NO_CLOUD_UPLINK" -eq 0 ]; then
            p2_provision_cloud_uplink
            verify_cloud_uplink_config
            p2_state verified
            p2_commit
        else
            log '=== Pass 2: --no-cloud-uplink selected; mutation phase skipped ==='
        fi
    else
        log '=== satellite profile: skipping master-only web/DB/console configuration ==='
        systemctl daemon-reload >>"$LOG" 2>&1 || die 'systemd daemon-reload failed'
        verify_docker
        verify_broker_only
        verify_cloud_bridges
    fi
    summary
}

main "$@"
