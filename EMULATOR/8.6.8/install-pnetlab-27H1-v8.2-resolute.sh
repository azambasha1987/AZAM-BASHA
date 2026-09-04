#!/bin/bash
# install-pnetlab-27H1-v8.2-resolute.sh — PNetLab v8/27H1 (Ubuntu 26.04 target), Laravel store.
#
# Derived from the jammy installer. PORT STATUS (2026-06-08):
#   - QEMU rebuilt for Noble: 9.2.4 default + Noble-Depends legacy zoo deb — DONE & verified.
#   - v8 env wired: 26.04 preflight, PHP 8.5 stack, docker.com 'resolute' apt repo,
#     self-contained Noble main/store/webconsole debs — DONE.
#   - STILL JAMMY carry-overs (file-only, OK on Noble): libssl1.1/lib32gcc1 compat debs,
#     qemu-compat-libs focal .so set, and the version label (seeds '6.7.11 Noble' as of the apt-repo branch).
# Idempotent: safe to re-run.
#
#   Run on a FRESH Ubuntu 26.04 machine (no PNetLab installed yet):
#       sudo bash install-pnetlab-27H1-v8.2-resolute.sh
#
# Internet is required for the Ubuntu apt mirrors and (optionally) the docker.com repo.
# Every PNetLab-specific artifact is installed from the local bundle — no labhub.eu.org.
#
# Bundle layout (must sit next to this script):
#   pnetlab-debs/
#       pnetlab_kernel.zip                  KSM kernel 6.12.92-pnetlab-ksm-1 (linux-image/headers/libc-dev)
#       pnetlab-docker_*.deb                base payload debs (focal-built, file-only — OK on Noble)
#       pnetlab-dynamips_*.deb
#       pnetlab-schema_*.deb
#       pnetlab-vpcs_*.deb
#       pnetlab_6.0.0-103_*.deb             main package
#       pnetlab-qemu_6.0.0-30noble1_amd64.deb  REPACKAGED with Noble Depends (drops libxen*/capstone/brlapi -> compat-libs)
#       pnetlab-guacamole_jammy.deb         REPACKAGED with jammy Depends (libwebp7/libnettle8/...)
#   deps/
#       libssl1.1_*.deb                     focal compat deb (side-load for focal-linked binaries)
#       lib32gcc1_jammy-compat.deb          transitional dummy (Depends lib32gcc-s1; no jammy candidate)
#       qemu-compat-libs.tgz                focal .so set so legacy /opt/qemu-* binaries load on Noble
#                                           (jammy set + libaio.so.1 + libnfs.so.13)
#   (v8: no qemu92/ — modern default is the distro's stock QEMU 10.2.1; see [8/14])
#   guac/
#       guacd-1.6.0-jammy-bin.tgz           guacd 1.6.0 staged tree (extract to /)
#       guacamole-1.6.0.war                 client webapp
#       guacamole-auth-jdbc-mysql-1.6.0.jar JDBC MySQL auth extension
#       mysql-connector-java-8.0.24.jar     Connector/J
#   schema/
#       pnetlab_db-schema.sql               working pnetlab_db structure (incl. ALTER columns)
#       guacdb-1.6.0-schema.sql             guacamole 1.6.0 schema structure
#   web/
#       customizations-6.5.tgz              248-file golden customization set -> /opt/unetlab/html
#       api_login_route.php                 plaintext POST /api/auth login route (injected into api.php)
#   store/
#       store-l10-jammy.tgz                 Laravel 10 store (M2 menu), full tree incl vendor/public/.env
#                                           -> /opt/unetlab/html/store (offline-custom Default/Devices
#                                           controllers, app/Services/Auth JWT, Console/Commands 8 cmds
#                                           + 2 ionCube stubs; advisory-bundled composer deps)
#
# What this installer bakes that the stock deb path does NOT:
#   - php8.5 everywhere (apache mod_php8.5, php default = 8.3)
#   - qemu deb repackaged with Noble-correct Depends (guacamole deb still jammy — pending)
#   - QEMU 9.2.4 (/opt/qemu-9.2.4 + ld.so.conf + ldconfig; /opt/qemu default symlink -> 9.2.4)
#   - Guacamole 1.6.0 (guacd from source, war + jdbc 1.6.0 on tomcat9)
#   - 248 baked customizations + 2 php8.1 brace fixes + injected plaintext login route
#   - adminLTE menu plugins recreated from themes/default (no menu 404s)
#   - apache vhost (DocumentRoot /opt/unetlab/html, AllowOverride All)
#   - Laravel 10 store (M2 menu) -> /opt/unetlab/html/store + apache /html5->guac proxy
#   - 3 permission fixes + FULL-root www-data sudoers (stock PNetLab; runs docker/qemu/wrappers)
#   - /etc/hosts FQDN entries to kill the 15s www-data sudo DNS-canonicalization hang (offline box)
#   - DB: app users pnetlab/guacuser, schema import, admin + ctrl_* offline SQL (version 6.5)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBS_DIR="$SCRIPT_DIR/pnetlab-debs"
DEPS_DIR="$SCRIPT_DIR/deps"
# QEMU_DIR removed for v8 — modern QEMU is the distro's stock 10.2.1 (no custom build)
GUAC_DIR="$SCRIPT_DIR/guac"
SCHEMA_DIR="$SCRIPT_DIR/schema"
WEB_DIR="$SCRIPT_DIR/web"
STORE_DIR="$SCRIPT_DIR/store"
ENGINE_DIR="$SCRIPT_DIR/engine-custom"   # tracked-source overlay: config_scripts/addons not in the html golden set
WEBCONSOLE_DIR="$SCRIPT_DIR/web-console" # web-console backend/units/wheels (frontend rides the engine overlay)
BUNDLE_DOCKER_STORE="$SCRIPT_DIR/docker-store" # bundle.manifest-declared offline Docker images (pnet-wireshark, pnet-wifi-spike)
LOG="/var/log/install-pnetlab-noble.log"
HTML="/opt/unetlab/html"

DO_REBOOT=1
UPDATE_ENROLLMENT=unspecified
for arg in "$@"; do
    case $arg in
        --no-reboot) DO_REBOOT=0 ;;
        --enable-updates)
            if [ "$UPDATE_ENROLLMENT" = disable ]; then
                echo "ERROR: --enable-updates and --no-updates cannot be used together" >&2
                exit 2
            fi
            UPDATE_ENROLLMENT=enable
            ;;
        --no-updates)
            if [ "$UPDATE_ENROLLMENT" = enable ]; then
                echo "ERROR: --enable-updates and --no-updates cannot be used together" >&2
                exit 2
            fi
            UPDATE_ENROLLMENT=disable
            ;;
        *)
            echo "ERROR: unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
    local resume=0
    if [ "${IS_TTY:-0}" -eq 1 ] && [ -n "${SPINNER_PID:-}" ]; then
        stop_spinner
        resume=1
    fi
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
    if [ "$resume" -eq 1 ]; then
        start_spinner
    fi
}
IS_TTY=0
[ -t 1 ] && IS_TTY=1
TOTAL_STEPS=14
# Relative wall-clock weights for the real step bodies below.  Apt/package and
# image-loading steps dominate; quick file/configuration steps stay light.
STEP_WEIGHTS=(0 3 1 7 25 5 15 20 2 2 10 3 1 2 4)
TOTAL_WEIGHT=100
INSTALL_T0=$SECONDS
CUR_STEP=0
CUR_STEP_LABEL=
STEP_T0=$SECONDS
WARN_COUNT=0
SPINNER_FLAG="/tmp/pnetlab-installer-spinner.$$"
SPINNER_PID=
BUILD_TMP=

format_elapsed() {
    local total=$1
    printf '%dm%02ds' "$((total / 60))" "$((total % 60))"
}

weighted_percent() {
    local current=$1 i done=0
    i=1
    while [ "$i" -lt "$current" ]; do
        done=$((done + STEP_WEIGHTS[$i]))
        i=$((i + 1))
    done
    printf '%d' "$((done * 100 / TOTAL_WEIGHT))"
}

spinner_loop() {
    local frames='|/-\\' frame=0 now step_elapsed total_elapsed
    while [ -f "$SPINNER_FLAG" ]; do
        now=$SECONDS
        step_elapsed=$((now - STEP_T0))
        total_elapsed=$((now - INSTALL_T0))
        printf '\r\033[2K  %s step %d/%d  %3d%% weighted  %s  (step %s; total %s)' \
            "${frames:frame:1}" "$CUR_STEP" "$TOTAL_STEPS" \
            "$(weighted_percent "$CUR_STEP")" "$CUR_STEP_LABEL" \
            "$(format_elapsed "$step_elapsed")" "$(format_elapsed "$total_elapsed")"
        frame=$(( (frame + 1) % 4 ))
        sleep 1
    done
}

stop_spinner() {
    rm -f "$SPINNER_FLAG"
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=
        printf '\r\033[2K'
    fi
}

start_spinner() {
    [ "$IS_TTY" -eq 1 ] || return 0
    : > "$SPINNER_FLAG"
    spinner_loop &
    SPINNER_PID=$!
}

cleanup_progress() {
    stop_spinner
    rm -f "$SPINNER_FLAG"
    [ -z "$BUILD_TMP" ] || rm -rf "$BUILD_TMP"
}
trap cleanup_progress EXIT

step() {
    local number=$1 label=$2 percent elapsed
    stop_spinner
    CUR_STEP=$number
    CUR_STEP_LABEL=$label
    STEP_T0=$SECONDS
    log "[$number/$TOTAL_STEPS] $label"
    if [ "$IS_TTY" -eq 1 ]; then
        percent=$(weighted_percent "$number")
        elapsed=$(format_elapsed "$((SECONDS - INSTALL_T0))")
        printf '\033[36m-- step %d/%d -- %s\033[0m  \033[90m(weighted %d%% complete; elapsed %s)\033[0m\n' \
            "$number" "$TOTAL_STEPS" "$label" "$percent" "$elapsed"
        start_spinner
    fi
}

warn() {
    local line resume=0
    WARN_COUNT=$((WARN_COUNT + 1))
    if [ "$IS_TTY" -eq 1 ] && [ -n "$SPINNER_PID" ]; then
        stop_spinner
        resume=1
    fi
    line="[$(date '+%H:%M:%S')] WARNING: $*"
    if [ "$IS_TTY" -eq 1 ]; then
        printf '%s\n' "$line" >> "$LOG"
        printf '\033[33m%s\033[0m\n' "$line" >&2
    else
        printf '%s\n' "$line" | tee -a "$LOG" >&2
    fi
    if [ "$resume" -eq 1 ]; then
        start_spinner
    fi
}
finish_progress() {
    local elapsed
    stop_spinner
    # A piped/headless install is a compatibility surface: keep its logfile
    # byte-shaped like today's output.  Interactive runs get the additive
    # summary in both the terminal and the same logfile.
    [ "$IS_TTY" -eq 1 ] || return 0
    elapsed=$(format_elapsed "$((SECONDS - INSTALL_T0))")
    log "=== Installer progress: 100% weighted complete; elapsed $elapsed; warnings $WARN_COUNT ==="
    log "Log: $LOG"
}
die() {
    stop_spinner
    echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "$LOG" >&2
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

: > "$LOG"
log "=== PNetLab v8/27H1 Installer (26.04 / php8.5) ==="
log "Log: $LOG ; bundle: $SCRIPT_DIR"

# ── Preflight ─────────────────────────────────────────────────────────────────
[ "$(id -u)" = "0" ] || die "Must run as root (sudo bash install-noble.sh)"
lsb_release -r -s 2>/dev/null | grep -q '26.04' || \
    die "Requires Ubuntu 26.04. Detected: $(lsb_release -r -s 2>/dev/null || echo unknown)"
[ -d "$DEBS_DIR" ]   || die "pnetlab-debs/ not found in $SCRIPT_DIR"
[ -d "$GUAC_DIR" ]   || die "guac/ not found in $SCRIPT_DIR"
[ -d "$SCHEMA_DIR" ] || die "schema/ not found in $SCRIPT_DIR"
[ -d "$WEB_DIR" ]    || die "web/ not found in $SCRIPT_DIR"
# Satellite deb: warn now so the operator can abort/re-bundle before the long install.
ls "$DEBS_DIR"/pnetlab-satellite_*.deb >/dev/null 2>&1 \
    || warn "PREFLIGHT: pnetlab-satellite_*.deb absent from pnetlab-debs/ — the 'Sync satellites' feature will be unavailable. Bundles MUST include the satellite deb (see scripts/sync-builder.sh --deploy)."

# ── [1/14] DPKG cleanup ───────────────────────────────────────────────────────
step 1 "Cleaning dpkg locks / configuring pending packages..."
rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock 2>/dev/null || true
dpkg --configure -a >> "$LOG" 2>&1 || true

# ── [2/14] SSH / systemd / root password ──────────────────────────────────────
step 2 "Configuring SSH, systemd timeout, root password..."
sed -i 's/.*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/.*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf 2>/dev/null || true
systemctl restart ssh >> "$LOG" 2>&1 || true
echo 'root:pnet' | chpasswd >> "$LOG" 2>&1 || warn "Could not set root password"

# ── [3/14] APT update + remove conflicting docker ─────────────────────────────
step 3 "apt update; removing distro docker.io/containerd if present..."
# NOTE: do NOT purge php8* — php8.5 is exactly what we want.
apt-get purge -y docker.io containerd runc >> "$LOG" 2>&1 || true
apt-get update -q >> "$LOG" 2>&1 || die "apt-get update failed (need internet to Ubuntu mirrors)"

# ── [4/14] Base apt dependencies (noble / php8.5) ─────────────────────────────
# Derived from the focal list with the verified jammy + Noble substitutions:
#   php7.4*->php8.5*  libwebp6->libwebp7  libnettle7->libnettle8
#   libwebsockets15->libwebsockets19  libcapstone3->libcapstone4
#   libbrlapi0.7->libbrlapi0.8  libxen* DROPPED  ; libssl1.1 side-loaded (step 5).
# Noble (24.04) re-pins on top of jammy — apt installs atomically, so ONE stale name
# aborts the whole set (incl. mysql-server) -> caught on the .11 gate:
#   t64 transition:  libaio1->libaio1t64   libasound2->libasound2t64
#   ffmpeg 6:        libavcodec58->60  libavformat58->60  libavutil56->58  libswscale5->7
#   soname bumps:    libnfs13->libnfs14   libwebsockets16->libwebsockets19
#   DROPPED on Noble: tomcat9* (Tomcat webapp retired -> guacd is its own deb),
#                     python2 (gone; the Noble pnetlab deb no longer Depends on it),
#                     libtinfo5/libncurses5/libncursesw5 (ncurses5 compat dropped).
#   exact-name dep:   the MAIN deb Depends on `libsdl1.2-compat` (transitional symlink pkg);
#                     `libsdl1.2debian` only Provides libsdl1.2-compat-shim, so the exact name
#                     MUST also be installed or the deb stays unconfigured (clean re-gate catch).
# TODO(legacy-IOL): the dropped ncurses5/tinfo5 32-bit set is needed by OLD IOU/IOL
#   binaries. Side-load focal compat debs (like libssl1.1) when legacy-IOL is back in scope.
# The MAIN pnetlab deb uses stable package names, so we also install the
# php-* meta packages + busybox-static (which Provides busybox).
# lib32gcc1 has no Noble candidate -> satisfied by a tiny transitional dummy (step 5).
# Without these the main deb stays half-configured (hU) and poisons every apt run.
step 4 "Installing base apt dependencies (php8.5 stack + noble libs)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    ifupdown unzip \
    php8.5 php8.5-yaml php8.5-common php8.5-cli php8.5-curl php8.5-gd \
    php8.5-mbstring php8.5-mysql php8.5-sqlite3 php8.5-xml php8.5-zip \
    php8.5-bcmath php8.5-imagick libapache2-mod-php8.5 \
    libncurses6 libncursesw6 libtinfo6 vim dos2unix apache2 \
    bridge-utils build-essential debconf-utils dialog dmidecode \
    genisoimage iptables lib32gcc-s1 lib32z1 \
    libc6 libc6-i386 libelf1t64 libpcap0.8t64 libsdl1.2debian logrotate \
    lsb-release lvm2 chrony rsync sshpass \
    plymouth-label python3-pexpect python3-pip python3-websockets sqlite3 tcpdump telnet uml-utilities zip \
    python3-ldap \
    python3-httpx \
    nodejs \
    cgroup-tools \
    net-tools mysql-server \
    libavcodec62 libavformat62 libavutil60 libswscale9 \
    libfreerdp-client3-3 libfreerdp-server3-3 libfreerdp-shadow-subsystem3-3 \
    libfreerdp-shadow3-3 libfreerdp3-3 libwinpr3-3 winpr-utils \
    gir1.2-pango-1.0 libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 \
    libpangoxft-1.0-0 pango1.0-tools pkg-config \
    libssh2-1t64 libtelnet2 libvncclient1 libvncserver1 libwebsockets19t64 \
    libpulse0 libpulse-mainloop-glib0 \
    libvorbis0a libvorbisenc2 libvorbisfile3 \
    libwebp7 libwebpmux3 libwebpdemux2 \
    libcairo2 libcairo-gobject2 libcairo-script-interpreter2 \
    libjpeg62 libjpeg-turbo8 libpng16-16t64 libtool libuuid1 libossp-uuid16 \
    default-jdk default-jdk-headless \
    libaio1t64 libasound2t64 libbrlapi0.8 libcacard0 libepoxy0 libfdt1 libgbm1 \
    libgcc-s1 libglib2.0-0t64 libgnutls30t64 libibverbs1 libjpeg8 \
    libnettle8t64 libnuma1 libpixman-1-0 libpmem1 librdmacm1t64 libsasl2-2 \
    libseccomp2 libslirp0 libspice-server1 libusb-1.0-0 \
    libusbredirparser1t64 libvirglrenderer1 zlib1g qemu-system-common qemu-system-x86 qemu-utils \
    libcapstone5 libvdeplug2t64 libnfs14 udhcpd libxss1 \
    libsdl2-2.0-0 inotify-tools curl ca-certificates gnupg \
    lsof busybox-static \
    php php-cli php-mysql php-gd php-curl php-mbstring php-sqlite3 php-zip php-xml php-imagick libapache2-mod-php \
    >> "$LOG" 2>&1 || {
        warn "Base dependency install had errors — attempting apt-get -f install"
        DEBIAN_FRONTEND=noninteractive apt-get install -f -y >> "$LOG" 2>&1 || true
    }

# php default = 8.3; switch apache to prefork+mod_php8.5 (mod_php needs prefork, not event)
update-alternatives --set php /usr/bin/php8.5 >> "$LOG" 2>&1 || true
a2dismod php8.1 php7.4 php7.0 >> "$LOG" 2>&1 || true      # harmless if not present
a2dismod mpm_event >> "$LOG" 2>&1 || true                # mpm_event is incompatible with mod_php
a2enmod mpm_prefork php8.5 rewrite >> "$LOG" 2>&1 || true

# ── [5/14] Side-load compat debs (libssl1.1 + lib32gcc1 transitional dummy) ───
step 5 "Side-loading libssl1.1 + lib32gcc1 transitional dummy..."
if ls "$DEPS_DIR"/libssl1.1_*.deb >/dev/null 2>&1; then
    dpkg -i "$DEPS_DIR"/libssl1.1_*.deb >> "$LOG" 2>&1 || warn "libssl1.1 install warning"
else
    warn "deps/libssl1.1_*.deb missing — focal-linked bundled binaries may fail to load"
fi
# lib32gcc1 has no jammy candidate; the main pnetlab deb hard-Depends on it. The dummy
# (Depends: lib32gcc-s1, which provides the actual 32-bit libgcc) satisfies the name.
if ls "$DEPS_DIR"/lib32gcc1_*.deb >/dev/null 2>&1; then
    dpkg -i "$DEPS_DIR"/lib32gcc1_*.deb >> "$LOG" 2>&1 || warn "lib32gcc1 dummy install warning"
else
    warn "deps/lib32gcc1_*.deb missing — pnetlab main deb will not configure (lib32gcc1 dep)"
fi

# ── [6/14] Docker CE from docker.com (resolute) ───────────────────────────────
step 6 "Installing Docker CE (docker.com resolute repo)..."
if have docker && docker --version >/dev/null 2>&1; then
    log "  Docker already present ($(docker --version)) — skipping repo setup"
else
    install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>>"$LOG" || warn "docker gpg fetch failed"
        chmod a+r /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    fi
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -q >> "$LOG" 2>&1 || warn "docker repo apt update failed"
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
        >> "$LOG" 2>&1 || warn "docker-ce install failed — install manually later"
fi

# ── [7/14] Install PNetLab packages from local files ──────────────────────────
step 7 "Installing PNetLab packages from local files..."
BUILD_TMP="$(mktemp -d /tmp/pnet_install.XXXXXX)"

install_zip() {
    local zipfile="$1" label="$2" path="$DEBS_DIR/$1"
    [ -f "$path" ] || { warn "Missing $path — skipping $label"; return 0; }
    log "  Installing $label ($zipfile)..."
    cp "$path" "$BUILD_TMP/"
    ( cd "$BUILD_TMP" && unzip -o "$zipfile" >> "$LOG" 2>&1 ) || die "Failed to unzip $zipfile"
    local dir="${zipfile%.zip}"
    dpkg -i "$BUILD_TMP/$dir"/*.deb >> "$LOG" 2>&1 || warn "dpkg warnings installing $zipfile"
}
install_deb() {
    local glob="$1" label="$2" found
    found="$(ls "$DEBS_DIR"/$glob 2>/dev/null | head -1)"
    [ -n "$found" ] || { warn "Missing $DEBS_DIR/$glob — skipping $label"; return 0; }
    log "  Installing $label ($(basename "$found"))..."
    dpkg -i "$found" >> "$LOG" 2>&1 || warn "dpkg warnings installing $found"
}

install_pkgs() {
    # apt path: install from the bundle's flat repo. apt resolves Depends and
    # versions; --reinstall keeps the legacy `dpkg -i` re-run semantics on an
    # idempotent re-install; --allow-downgrades lets a bundle roll a box back.
    apt-get install -y --reinstall --allow-downgrades \
        -o DPkg::Lock::Timeout=120 \
        -o Dpkg::Options::=--force-confold "$@" >> "$LOG" 2>&1 \
        || warn "apt install warnings: $*"
}

# v8/27H1: NO custom kernel. Ubuntu 26.04 ships stock Linux 7.0, which already
# carries the modern in-tree KSM (advisor/smart_scan/prctl) the 6.12 build existed
# to provide. KSM tuning ships as userspace (pnetlab-ksm.service) in the engine deb.
# (Was: install_zip "pnetlab_kernel.zip" "KSM kernel 6.12.92-pnetlab-ksm-1".)

# NOTE: pnetlab-wireshark deb intentionally dropped. Its only real action was
# `docker pull` of the original xrdp capture image. The web console now captures
# into the slim pnet-wireshark:1.0 (TigerVNC/VNC, rendered via guacamole-lite),
# loaded OFFLINE from the bundled docker-store in the docker section below. Docker
# enable/start + the daemon.json (unix-socket-only) are owned by pnetlab-docker, so removing this deb
# changes nothing else.
#
# Self-contained Noble debs: the main package bakes in the customizations +
# engine-custom overlay and the install-time source-fixes; store + web console are
# split out. This retires the install-time overlay steps below (customizations bake,
# engine-custom cp -a, store extract, guacd tar, web-console copies) — see debs/README.md.
if [ -f "$DEBS_DIR/Packages.gz" ]; then
    # ── apt path: the bundle ships a flat repo index (gen-apt-index.sh) ──
    # Same stage order as the legacy dpkg path: payload debs -> qemu -> core.
    log "  Bundle repo index found — installing via apt (file:$DEBS_DIR)"
    APT_BUNDLE_LIST=/etc/apt/sources.list.d/pnetlab-bundle.list
    echo "deb [trusted=yes] file:$DEBS_DIR ./" > "$APT_BUNDLE_LIST"
    apt-get update >> "$LOG" 2>&1 || warn "apt update (bundle repo) warnings"
    # A previous run's apt-mark holds (set below) would make apt refuse the
    # upgrade on an idempotent re-run — lift them for the install, re-held after.
    # pnetlab-webconsole is RETIRED (item E, foldin @ 6.8.31) — the pnetlab deb
    # Provides/Replaces/Conflicts it, so it is no longer listed here; an
    # existing box with the old package still installed gets it removed by
    # apt when pnetlab is upgraded (Replaces+Conflicts), no explicit unhold needed.
    # pnetlab-store is RETIRED (item C6, store decommission) — it is no longer
    # built/bundled, so it is dropped from this list too.
    apt-mark unhold pnetlab pnetlab-docker pnetlab-dynamips \
        pnetlab-guacd pnetlab-qemu pnetlab-schema pnetlab-vpcs >> "$LOG" 2>&1 || true
    install_pkgs pnetlab-docker pnetlab-schema pnetlab-guacd pnetlab-vpcs pnetlab-dynamips
    install_pkgs pnetlab-qemu
    # pnetlab-qemu SHIPS /opt/qemu as a packaged symlink -> qemu-2.4.0; installing it
    # clobbers the modern default. Step [8] re-points /opt/qemu at the stock-qemu compat
    # tree on fresh installs; re-assert here so an idempotent RE-run is never left on 2.4.0
    # mid-script (ovfstartup also guards at boot). Glob the newest /opt/qemu-1X.* tree.
    # `|| true`: at this point (step 7) the stock-qemu compat tree does not exist
    # yet (step 8 builds it), so the glob matches nothing and `ls` exits non-zero.
    # Under `set -euo pipefail` an unguarded failing command substitution aborts
    # the whole installer right before the main pnetlab package — guard it.
    _modern=$(ls -d /opt/qemu-1[0-9].* 2>/dev/null | sort -V | tail -1 || true)
    { [ -n "$_modern" ] && ln -sfn "$(basename "$_modern")" /opt/qemu; } || true
    install_pkgs pnetlab
    # pnetlab-webconsole is RETIRED (item E, foldin @ 6.8.31) — its payload
    # (frontend + backend bridges + units) ships inside the pnetlab deb now;
    # the deb's Provides/Replaces/Conflicts pnetlab-webconsole handles removal
    # of any leftover old package on upgrade.
    # pnetlab-store is RETIRED (item C6, store decommission) — the Laravel
    # store is gone; the engine-native /login/ replaces it. Nothing to install.
    # Patched bridge.ko via DKMS (LACP/pause group-MAC forwarding); optional —
    # the engine writes group_fwd_mask 65535 with a 65528 fallback, so labs work
    # whether or not it is present. Built against the KSM kernel headers.
    install_pkgs pnetlab-bridge-dkms || warn "pnetlab-bridge-dkms not installed (LACP labs unavailable)"
    # The bundle dir rarely survives on the installed box — drop the source so a
    # later `apt-get update` never errors on a vanished file: repo.
    rm -f "$APT_BUNDLE_LIST"
    apt-get update >> "$LOG" 2>&1 || true
else
    # ── legacy path: ordered dpkg -i (bundle without Packages.gz) ──
    log "  No Packages.gz in pnetlab-debs/ — legacy ordered dpkg path"
    install_deb "pnetlab-docker_*.deb"      "pnetlab-docker"
    install_deb "pnetlab-schema_*.deb"      "pnetlab-schema"
    install_deb "pnetlab-guacd_*.deb"       "pnetlab-guacd (guacd 1.6 from Noble source)"
    install_deb "pnetlab-vpcs_*.deb"        "pnetlab-vpcs"
    install_deb "pnetlab-dynamips_*.deb"    "pnetlab-dynamips"
    install_deb "pnetlab-qemu_*noble*_amd64.deb"     "pnetlab-qemu (REPACKAGED Noble deps)"
    # Version-agnostic globs: deb versions bump per milestone now (6.7.2noble1+).
    # 'pnetlab_*.deb' only matches the main deb — subpackages are 'pnetlab-*'.
    # pnetlab-webconsole is RETIRED (item E, foldin @ 6.8.31) — console +
    # bridges now ship inside the pnetlab deb itself (its Provides/Replaces/
    # Conflicts pnetlab-webconsole removes any leftover old package via dpkg).
    install_deb "pnetlab_*.deb"                      "pnetlab (self-contained Noble main, incl. web console)"
    # pnetlab-store is RETIRED (item C6, store decommission) — no longer built/bundled.
    install_deb "pnetlab-bridge-dkms_*.deb"          "pnetlab-bridge-dkms (LACP/pause bridge fwd)" || true
fi

# ── Stage the satellite push-deploy bundle ────────────────────────────────────
# System ▸ Cluster "Deploy & Join" rsyncs /opt/unetlab/cluster-bundle/ to the
# target and runs install-resolute-satellite.sh there; without staging, the GUI
# deploy fails with "satellite bundle missing on the master". Stage it at
# install time while the bundle is still on disk (~700 MB; set
# PNET_NO_CLUSTER_BUNDLE=1 to skip on space-constrained masters).
if [ "${PNET_NO_CLUSTER_BUNDLE:-0}" != "1" ] && [ -f "$SCRIPT_DIR/install-resolute-satellite.sh" ]; then
    log "  staging satellite push-deploy bundle -> /opt/unetlab/cluster-bundle"
    mkdir -p /opt/unetlab/cluster-bundle
    cp -a "$SCRIPT_DIR/install-resolute-satellite.sh" /opt/unetlab/cluster-bundle/
    for d in pnetlab-debs deps; do
        rm -rf "/opt/unetlab/cluster-bundle/$d"
        cp -a "$SCRIPT_DIR/$d" /opt/unetlab/cluster-bundle/ >> "$LOG" 2>&1 || warn "cluster-bundle: $d copy failed"
    done
    rm -rf /opt/unetlab/cluster-bundle/pnetlab-debs/superseded-bak 2>/dev/null
    find /opt/unetlab/cluster-bundle -maxdepth 1 -name "*.md" -delete 2>/dev/null
else
    log "  satellite bundle staging skipped (no satellite installer in bundle or PNET_NO_CLUSTER_BUNDLE=1)"
fi

# ── Stage the satellite deb to the persistent lookup path ────────────────────
# The "Sync satellites" feature (cluster/api.php + broker cluster_sync_satellite)
# reads the NEWEST pnetlab-satellite_*.deb from /opt/unetlab/data/satellite/ to
# push to joined satellites.  Every bundle MUST include pnetlab-satellite_*.deb in
# pnetlab-debs/; warn loudly here on fresh install so a missing deb is not silent.
_sat_deb="$(ls -t "$DEBS_DIR"/pnetlab-satellite_*.deb 2>/dev/null | head -1)"
if [ -n "$_sat_deb" ]; then
    log "  staging satellite deb -> /opt/unetlab/data/satellite/"
    mkdir -p /opt/unetlab/data/satellite
    cp -f "$_sat_deb" /opt/unetlab/data/satellite/
    chmod 0644 "/opt/unetlab/data/satellite/$(basename "$_sat_deb")"
    log "    staged: $(basename "$_sat_deb")"
else
    warn "pnetlab-satellite_*.deb not found in $DEBS_DIR — the 'Sync satellites' feature will be unavailable until the deb is placed at /opt/unetlab/data/satellite/. Bundles MUST include the satellite deb."
fi

# Neuter the xml.cisco.com phone-home null-route injector at its SOURCE. The pnetlab postinst
# (line ~79) does `fgrep xml.cisco.com /etc/hosts || echo 127.0.0.127 xml.cisco.com >> /etc/hosts`.
# That martian null-route makes the new x86_64 IOS-XE IOL (L2/L3) ABORT at boot in BinOS
# smart-licensing (gethostbyname succeeds -> bogus addr -> __crb_runtime_event abort). The deb
# re-fires its postinst on every `dpkg --configure`/reconfigure (incl. the configure -a below), so
# the one-shot /etc/hosts removal in [13/14] loses the race. Disable it at the source + strip now.
PNINFO=/var/lib/dpkg/info/pnetlab.postinst
if [ -f "$PNINFO" ] && grep -q '^fgrep "xml.cisco.com" /etc/hosts' "$PNINFO"; then
    sed -i '/^fgrep "xml.cisco.com" \/etc\/hosts/ s|^|# DISABLED (breaks IOS-XE IOL smart-licensing; stripped at boot by ovfstartup): |' "$PNINFO"
    log "  neutered xml.cisco.com null-route injector in pnetlab.postinst"
fi
sed -i '/[[:space:]]xml\.cisco\.com/d' /etc/hosts 2>/dev/null || true

# Neuter the postinst's ctrl_version reset (same re-fire race as the xml.cisco.com injector above).
# The pnetlab postinst does `replace control ... ('ctrl_version', $(cat /opt/unetlab/version))` =
# "6.0.0-103" on EVERY dpkg --configure/reconfigure, clobbering the "6.7.11 Noble" box name we seed in
# the store DB step below. A one-time DB set loses that race (it silently regressed a live gate back
# to "6.0.0-103"). Disable it at the source so our version label is durable across future reconfigures.
if [ -f "$PNINFO" ] && grep -qE "^mysql .*replace control .*'ctrl_version'" "$PNINFO"; then
    sed -i "/^mysql .*replace control .*'ctrl_version'/ s|^|# DISABLED (resets ctrl_version to the deb version on reconfigure; we seed the release label in the store DB step): |" "$PNINFO"
    log "  neutered ctrl_version reset in pnetlab.postinst"
fi
# The Noble-rebuilt deb reformatted that postinst block (mysql -uroot ... -e \ on one
# line, the replace on a continuation line), so the legacy ^mysql regex above no longer
# matches and ctrl_version regressed to the deb version on every reconfigure. Neuter
# the rebuilt form too: comment the whole version-stamp if-block.
if [ -f "$PNINFO" ] && grep -q "replace control (control_name, control_value) values ('ctrl_version'" "$PNINFO" \
        && ! grep -q "DISABLED-ctrl-version-stamp" "$PNINFO"; then
    sed -i "/^if \[ -e \/opt\/unetlab\/version \]; then/,/^fi/ s|^|# DISABLED-ctrl-version-stamp: |" "$PNINFO"
    log "  neutered ctrl_version reset in pnetlab.postinst (Noble rebuilt form)"
fi

# Settle dpkg WITHOUT 'apt-get -f install' (which would try to pull focal libs and
# re-break the apt state the repackaged debs just fixed). The repackaged qemu/guac
# the qemu deb carries Noble-correct Depends, so configure-a is enough.
dpkg --configure -a >> "$LOG" 2>&1 || true
# Lock timeout: the post-install `apt-get update` can leave apt's background
# triggers holding the dpkg frontend lock for a moment (seen on the fresh-VM
# gate); don't let a transient lock turn into a spurious warning.
apt-get -o DPkg::Lock::Timeout=120 check >> "$LOG" 2>&1 && log "  apt-get check clean" || warn "apt-get check reported issues (see log)"

# Hold PNetLab + kernel so Ubuntu upgrades never clobber them. pnetlab-webconsole
# is RETIRED (item E, foldin @ 6.8.31) — no separate package to hold; it ships
# inside pnetlab, which is already held below. pnetlab-store is RETIRED (item
# C6, store decommission) — no longer built/bundled, so also dropped here.
apt-mark hold pnetlab pnetlab-docker pnetlab-dynamips pnetlab-guacd \
    pnetlab-qemu pnetlab-schema pnetlab-vpcs \
    $(dpkg-query -W -f='${Package}\n' 'linux-image-*pnetlab*' 'linux-headers-*pnetlab*' 2>/dev/null) \
    >> "$LOG" 2>&1 || warn "Some apt-mark holds failed"

# ── [8/14] QEMU modern default = STOCK qemu (v8/27H1) ─────────────────────────
# v8: Ubuntu 26.04 ships stock QEMU 10.2.1, which links liburing (io_uring) and has
# correct sonames natively — so we DROP the custom-built QEMU 9.2.4 entirely and point
# /opt/qemu at the system binaries via a thin compat tree. device_qemu.php still resolves
# /opt/qemu/bin/qemu-system-* and /opt/qemu/share/qemu/*; readlink('/opt/qemu') ->
# "qemu-<ver>" -> the engine str_replace('qemu-','') yields the version (>=8 => io_uring).
# Stock-arg compatibility (pc/q35, smm=off, cpu host, aio=io_uring, virtio/e1000, OVMF)
# was verified on a 26.04 box. Version-pinned legacy nodes still use /opt/qemu-<ver> ([8b]).
QV=$(/usr/bin/qemu-system-x86_64 --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -1 || true)
QV=${QV:-10.2.1}
step 8 "Wiring /opt/qemu -> stock QEMU $QV (modern default)..."
if [ -x /usr/bin/qemu-system-x86_64 ]; then
    QT="/opt/qemu-$QV"
    mkdir -p "$QT/bin" "$QT/share/qemu"
    for b in qemu-system-x86_64 qemu-system-i386 qemu-img; do
        [ -x "/usr/bin/$b" ] && ln -sfn "/usr/bin/$b" "$QT/bin/$b"
    done
    # stock data files (seabios/vgabios/keymaps) — mirror the system share dir
    if [ -d /usr/share/qemu ]; then
        for f in /usr/share/qemu/*; do ln -sfn "$f" "$QT/share/qemu/$(basename "$f")"; done
    fi
    # flat OVMF.fd (legacy -bios style device_qemu.php uses) from the ovmf package
    [ -f /usr/share/ovmf/OVMF.fd ] && ln -sfn /usr/share/ovmf/OVMF.fd "$QT/share/qemu/OVMF.fd"
    ln -sfn "qemu-$QV" /opt/qemu                           # RELATIVE target — engine str_replace('qemu-','',readlink) -> version
    # PNetLab add-on firmware/floppies that are in NO Ubuntu package: the Windows
    # virtio-win drivers floppy and the NX-OS 9000v OVMF-sata.fd. The pnetlab deb
    # ([7/14]) ships virtio-win-drivers.img under /opt/unetlab/scripts; OVMF-sata.fd
    # rides in the legacy /opt/qemu-2.4.0 from the pnetlab-qemu deb. Seed both as real
    # copies into the modern default's share dir.
    _vwd="$QT/share/qemu/virtio-win-drivers.img"
    if [ ! -e "$_vwd" ]; then
        for _src in /opt/unetlab/scripts/virtio-win-drivers.img \
                    /opt/qemu-2.4.0/share/qemu/virtio-win-drivers.img; do
            [ -f "$_src" ] && { cp "$_src" "$_vwd"; chmod 644 "$_vwd"; log "  seeded virtio-win-drivers.img (Windows node floppy)"; break; }
        done
        [ -e "$_vwd" ] || warn "virtio-win-drivers.img not found — Windows nodes will fail until placed in /opt/qemu/share/qemu/"
    fi
    _ovmfs="$QT/share/qemu/OVMF-sata.fd"
    if [ ! -e "$_ovmfs" ] && [ -f /opt/qemu-2.4.0/share/qemu/OVMF-sata.fd ]; then
        cp /opt/qemu-2.4.0/share/qemu/OVMF-sata.fd "$_ovmfs"; chmod 644 "$_ovmfs"; log "  seeded OVMF-sata.fd (NX-OS 9000v boot firmware)"
    fi
    if /opt/qemu/bin/qemu-system-x86_64 --version >/dev/null 2>&1; then
        log "  $(/opt/qemu/bin/qemu-system-x86_64 --version | head -1) (default -> /opt/qemu)"
    else
        warn "stock qemu did not run from /opt/qemu (check qemu-system-x86 install)"
    fi
else
    warn "stock qemu-system-x86_64 missing — was qemu-system-x86 installed in [4/14]?"
fi

# ── [8b/14] Legacy QEMU focal compat libs ─────────────────────────────────────
# The pnetlab-qemu deb ships focal-built /opt/qemu-1.3.1 .. 7.2.0 binaries that link
# sonames ABSENT on Noble (libbrlapi.so.0.7, libnettle.so.7, libhogweed.so.5,
# libcapstone.so.3, the libxen 4.11 set, PLUS libaio.so.1 [Noble has .so.1t64] and
# libnfs.so.13 [Noble has .so.14]). Without these EVERY legacy qemu fails to load
# (only the freshly-built qemu-9.2.4 runs) — i.e. no version-pinned QEMU node could boot.
# The repackaged deb only fixed Depends METADATA, not the binaries. Side-load the focal
# .so files; sonames differ from Noble's -> NO conflict. Verified on Noble 2026-06-08.
if [ -f "$DEPS_DIR/qemu-compat-libs.tgz" ]; then
    log "  Installing focal QEMU compat libs to /opt/qemu-compat-libs..."
    mkdir -p /opt/qemu-compat-libs
    tar xzf "$DEPS_DIR/qemu-compat-libs.tgz" -C /opt/qemu-compat-libs >> "$LOG" 2>&1 || warn "qemu-compat-libs extract warning"
    echo '/opt/qemu-compat-libs' > /etc/ld.so.conf.d/pnetlab-qemu-compat.conf
    ldconfig
    if /opt/qemu-6.0.0/bin/qemu-system-x86_64 --version >/dev/null 2>&1; then
        log "  Legacy QEMU now loads ($(/opt/qemu-6.0.0/bin/qemu-system-x86_64 --version | head -1))"
    else
        warn "legacy qemu still not loading (check /opt/qemu-compat-libs / ldconfig)"
    fi
else
    warn "deps/qemu-compat-libs.tgz missing — legacy QEMU node binaries will NOT load on jammy"
fi

# ── [9/14] Guacamole — guacd from the pnetlab-guacd deb (NO Tomcat webapp) ─────
# guacd 1.6 is now its own deb (debs/pnetlab-guacd, built from source on Noble): it
# ships /usr/local/{sbin,lib} + the guacd.service unit and enables+starts it via its
# postinst. The Tomcat Guacamole WEBAPP stays retired (the built-in web console +
# guacamole-lite replaced it), so the old war/jdbc/properties staging is gone.
step 9 "guacd provided by pnetlab-guacd deb; verifying it is active..."
ldconfig
systemctl enable guacd >> "$LOG" 2>&1 || true
systemctl restart guacd >> "$LOG" 2>&1 || warn "guacd did not start (pnetlab-guacd deb installed?)"

# ── [10/14] Runtime content: docker node images + bundle config_scripts ───────
# The 248-file customizations, the engine-custom overlay, the adminLTE menu plugins,
# the php8.1 brace fixes, the /api/auth login route, the VPCS icon and the China-pack
# removal are now BAKED into the pnetlab deb (debs/pnetlab/build-stage.sh). Nothing is
# tar-baked / cp -a'd / sed'd into $HTML here anymore — the deb owns it.
step 10 "Loading pre-staged docker node images + merging bundle config_scripts ..."
[ -d "$HTML" ] || die "$HTML missing — pnetlab main package did not install"

# Pre-load docker node images staged in the bundle. The engine-custom overlay (XRd
# worker config_scripts, device_docker/ceos/srlinux php) + the docker-image-watcher
# systemd unit are shipped by the pnetlab deb now; the watcher (enabled by the deb's
# postinst) handles archives dropped in later. Here we just provision ones present
# at install time: XRd .tar(.gz) -> docker load; cEOS flat tars -> ceos_provision.sh;
# the wireshark capture image -> docker pull.
if have docker; then
    # Ensure dockerd is up (unix:///var/run/docker.sock) before any image step.
    # ROOT CAUSE (found on the fresh-VM regate, 2026-06-10): docker-ce starts in
    # step [6] with its stock unit (`-H fd://`); pnetlab-docker (step [7]) then
    # writes daemon.json + the ExecStart drop-in but never reloads or restarts
    # docker, so the OLD dockerd keeps running until the end-of-install reboot —
    # and every image step below was silently skipped on a fresh install (0
    # images; the wireshark pull warning was the only symptom). No amount of
    # polling fixes that — restart docker so the drop-in + daemon.json take
    # effect NOW, then poll. Since pnetlab-docker 6.0.0-31 the daemon binds ONLY
    # the unix socket (the root-equivalent tcp://127.0.0.1:4243 API is retired),
    # so the poll uses the default unix socket.
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart docker 2>/dev/null || warn "    docker restart failed"
    systemctl start pnetlab-docker.service 2>/dev/null || true
    for _i in $(seq 1 90); do
        docker version >/dev/null 2>&1 && break
        sleep 2
    done
    if docker version >/dev/null 2>&1; then
        log "    engine docker endpoint (unix socket) ready"
    else
        warn "    engine docker endpoint not ready after 180s — docker image steps may be skipped"
    fi

    for arch in /opt/unetlab/addons/docker/XRD/*.tar.gz /opt/unetlab/addons/docker/XRD/*.tar; do
        [ -f "$arch" ] || continue
        if docker load -i "$arch" >>"$LOG" 2>&1; then log "    docker load: $(basename "$arch")"; else warn "    docker load failed: $arch"; fi
    done
    for arch in /opt/unetlab/addons/docker/*[cC][eE][oO][sS]*.tar /opt/unetlab/addons/docker/*[cC][eE][oO][sS]*.tar.xz; do
        [ -f "$arch" ] || continue
        if /opt/unetlab/config_scripts/ceos_provision.sh "$arch" >>"$LOG" 2>&1; then log "    cEOS provisioned: $(basename "$arch")"; else warn "    cEOS provision failed: $arch"; fi
    done
    # Stage + load whatever pnet-*.tar.gz node images the bundle ships in its
    # docker-store/ sibling directory. These were formerly embedded in the engine deb
    # (~900 MB); staging is a HARDLINK into /opt/unetlab/addons/docker-store/ (the bundle
    # extracts onto the same root fs, so cp -l is instant + avoids a 900 MB copy; cp -n
    # fallback covers the cross-filesystem case), then every staged tarball is docker-loaded
    # IN PARALLEL. This eliminates the double I/O (no dpkg-unpack of 900 MB + no slow copy)
    # and pre-loads the set so there is no first-use stall.
    #
    # The loop is a GLOB, not a named set — it loads exactly what the bundle shipped. As of
    # 6.8.63 debs/bundle.manifest ships two:
    #   * pnet-wireshark-1-0.tar.gz  -> pnet-wireshark:1.0   — ACTIVE, not retired. The VNC
    #     Capture node still uses it and includes/doctor.php health-checks for it; the html5
    #     Capture lane's pnet-capture-web (pulled below) is a SECOND lane, not a replacement.
    #     pnet-wireshark:1.0 MUST match includes/functions.php (addWiresharkSystem).
    #   * pnet-wifi-spike-1-0.tar.gz -> pnet-wifi-spike:1.0  — the vwifi RF medium, run by the
    #     broker verb vwifi_server_ensure. Older bundles' tarballs carry the legacy tag
    #     wifi-spike:latest; the verb retags legacy -> canonical on first use.
    # pnet-aaa / pnet-browser are NOT in bundle.manifest and are therefore never staged here:
    # they are network-installed (digest-pinned, see debs/oci-images.lock) or offline-installed
    # from Dashboard > Docker Devices, which is what templates/{intel,amd}/{aaa,browser}.yml say.
    # Falls back gracefully if the bundle docker-store/ is absent (e.g. a lite ISO).
    DS_DEST="/opt/unetlab/addons/docker-store"
    mkdir -p "$DS_DEST"
    if [ -d "$BUNDLE_DOCKER_STORE" ] && ls "$BUNDLE_DOCKER_STORE"/*.tar.gz >/dev/null 2>&1; then
        log "    staging offline Docker images from bundle docker-store/ -> $DS_DEST (hardlink) ..."
        cp -l "$BUNDLE_DOCKER_STORE/"*.tar.gz "$DS_DEST/" 2>>"$LOG" \
            || cp -n "$BUNDLE_DOCKER_STORE/"*.tar.gz "$DS_DEST/" 2>>"$LOG" || true
    fi
    if ls "$DS_DEST"/pnet-*.tar.gz >/dev/null 2>&1; then
        log "    loading bundled node docker images IN PARALLEL ($(cd "$DS_DEST" && echo pnet-*.tar.gz)) ..."
        _ds_pids=()
        for _img in "$DS_DEST"/pnet-*.tar.gz; do
            [ -f "$_img" ] || continue
            ( if docker load -i "$_img" >>"$LOG" 2>&1; then
                  log "    docker load OK: $(basename "$_img")"
              else
                  warn "    docker load FAILED: $_img"
              fi ) &
            _ds_pids+=($!)
        done
        for _p in "${_ds_pids[@]}"; do wait "$_p" || true; done
        log "    parallel docker load complete"
    else
        warn "    no bundled node docker images found in $DS_DEST or $BUNDLE_DOCKER_STORE — install pnet-wireshark / pnet-wifi-spike (and pnet-aaa / pnet-browser, which are never bundled) via Dashboard > Docker Devices"
    fi

    # pnet-capture-web:1.0 — the html5 WEB packet-capture image (live packet table
    # + .pcap download) that replaced the VNC pnet-wireshark on the http console
    # lane. PULLED FROM DOCKER HUB (rspnet/pnet-capture-web) rather than bundled in
    # docker-store/, with a local tarball fallback for airgapped installs. MUST
    # match includes/functions.php addWiresharkSystem (pnet-capture-web:1.0).
    CAPWEB_TAR="$DS_DEST/pnet-capture-web-1-0.tar.gz"
    if docker pull rspnet/pnet-capture-web:latest >>"$LOG" 2>&1; then
        docker tag rspnet/pnet-capture-web:latest pnet-capture-web:1.0 >>"$LOG" 2>&1 || true
        log "    pulled + tagged pnet-capture-web:1.0 from Docker Hub (rspnet/)"
    elif [ -f "$CAPWEB_TAR" ]; then
        log "    Hub pull unavailable; loading pnet-capture-web:1.0 from local image store ..."
        docker load -i "$CAPWEB_TAR" >>"$LOG" 2>&1 \
            && log "    docker load OK: pnet-capture-web:1.0" \
            || warn "    docker load FAILED: pnet-capture-web"
    else
        warn "    pnet-capture-web:1.0 not fetched (no internet + no local tarball) — install via Dashboard > Docker Devices"
    fi
    docker image inspect pnet-capture-web:1.0 >/dev/null 2>&1 \
        || warn "    pnet-capture-web:1.0 absent — html5 packet capture will not start until installed"
fi

# Merge the curated content folders from pnetlab-custom_1.1 (the offline bundle's customization
# deb) that the base deb + engine-custom don't already provide — notably config_scripts for newer
# devices (cEOS, SR Linux, Juniper vEX, C8000v, Ruijie Router). NO-CLOBBER (cp -n): existing files
# always win, so local edits + engine-custom (e.g. docker.yml ram=1024, the XRd scripts) are never
# overwritten. The deb is staged in pnetlab-debs/ but is NOT dpkg-installed (only its 3 folders are
# merged) — installing the whole custom deb is intentionally avoided (the golden tgz owns the rest).
CONTENT_DEB="$(ls "$DEBS_DIR"/pnetlab-custom_*.deb 2>/dev/null | head -1)"
if [ -n "$CONTENT_DEB" ] && [ -f "$CONTENT_DEB" ]; then
    log "  Merging bundle content folders from $(basename "$CONTENT_DEB") (no-clobber)..."
    CTMP="$(mktemp -d)"
    if dpkg-deb -x "$CONTENT_DEB" "$CTMP" >>"$LOG" 2>&1; then
        for sub in config_scripts html/templates html/images/icons; do
            [ -d "$CTMP/opt/unetlab/$sub" ] || continue
            mkdir -p "/opt/unetlab/$sub"
            cp -rn "$CTMP/opt/unetlab/$sub/." "/opt/unetlab/$sub/" 2>>"$LOG" || true
        done
        chmod 0755 /opt/unetlab/config_scripts/*.py 2>/dev/null || true
        chown -R root:root /opt/unetlab/config_scripts 2>/dev/null || true
        log "    merged config_scripts/templates/icons (existing files preserved)"
    else
        warn "  pnetlab-custom content extract failed — newer device config_scripts may be absent"
    fi
    rm -rf "$CTMP"
else
    warn "  pnetlab-custom_*.deb not staged in pnetlab-debs/ — skipping content merge (cEOS/SRL/etc config_scripts absent)"
fi

# (VPCS icon -> SVG, Chinese-language-pack removal, php8.1 brace fixes, and the
#  /api/auth login-route injection are baked into the pnetlab deb now —
#  debs/pnetlab/build-stage.sh steps 5b-5f — no longer applied at install time.)

# ── [11/14] Apache vhost ──────────────────────────────────────────────────────
step 11 "Writing apache vhost (DocumentRoot $HTML, AllowOverride All)..."
cat > /etc/apache2/sites-available/pnetlab.conf <<APACHECONF
<VirtualHost *:80>
    DocumentRoot $HTML
    # http -> https redirect for EXTERNAL clients (login-loop fix). The session
    # token cookie is Secure-flagged (auth hardening 6.8.36), so serving the app
    # over plain http let a user submit admin/pnet "successfully" while the
    # browser silently dropped the cookie -> /main/ 401 -> bounced back to the
    # login form with no error ("admin/pnet does not work"). Loopback is exempt:
    # localhost health checks (enable-php-fpm.sh), the ishare2 catalog probe and
    # the MCP bridge (pnetlab-mcp.py -> http://127.0.0.1/mcp/bridge.php) POST
    # over plain http and must not be bounced by a 301.
    RewriteEngine On
    RewriteCond %{REMOTE_ADDR} !^127\.
    RewriteCond %{REMOTE_ADDR} !^::1\$
    RewriteRule ^/?(.*)\$ https://%{HTTP_HOST}/\$1 [R=301,L]
    <Directory $HTML/>
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
    AddType application/x-httpd-php .php
    # PNET web-console: wss -> console_mux.py :8022/:6080 [S1/S2] + guacamole-lite :8081 [S3] + shell pty :8023 [admin]
    <IfModule mod_proxy_wstunnel.c>
        ProxyPass        /telnet/  ws://127.0.0.1:8022/  upgrade=websocket
        ProxyPassReverse /telnet/  ws://127.0.0.1:8022/
        ProxyPass        /vnc/     ws://127.0.0.1:6080/  upgrade=websocket
        ProxyPassReverse /vnc/     ws://127.0.0.1:6080/
        ProxyPass        /guac/    ws://127.0.0.1:8081/  upgrade=websocket
        ProxyPassReverse /guac/    ws://127.0.0.1:8081/
        ProxyPass        /shell/   ws://127.0.0.1:8023/  upgrade=websocket
        ProxyPassReverse /shell/   ws://127.0.0.1:8023/
        # lab-state push fan-out (pnetlab-labstated) — live topology node/link status
        ProxyPass        /labstate/ ws://127.0.0.1:8024/  upgrade=websocket
        ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
        # node http/https web console -> http_ws_bridge.py :8025 (iframe reverse-proxy)
        ProxyPass        /console/http/ http://127.0.0.1:8025/ upgrade=websocket
        ProxyPassReverse /console/http/ http://127.0.0.1:8025/
    </IfModule>
    # Strip the engine's strict global CSP/XFO (pnet-hardening.conf) for the
    # PROXIED node app, which serves its own inline scripts/styles/assets; keep it
    # same-origin-framable only. mod_headers is enabled by enable-web-hardening.sh.
    <Location "/console/http/">
        Header always unset Content-Security-Policy
        Header always unset Content-Security-Policy-Report-Only
        Header always unset X-Frame-Options
        Header always set Content-Security-Policy "frame-ancestors 'self'"
    </Location>
    ErrorLog \${APACHE_LOG_DIR}/pnetlab_error.log
    CustomLog \${APACHE_LOG_DIR}/pnetlab_access.log combined
</VirtualHost>
APACHECONF
a2enmod rewrite >> "$LOG" 2>&1 || true
a2dissite 000-default default-ssl pnetlabs >> "$LOG" 2>&1 || true
a2ensite pnetlab >> "$LOG" 2>&1 || true
# strip PrivateTmp from apache unit (PNetLab needs shared /tmp for sockets/consoles)
sed -i -e '/^PrivateTmp/d' /lib/systemd/system/apache2.service 2>/dev/null || true
systemctl daemon-reload >> "$LOG" 2>&1 || true

# ── [11b] HTTPS (self-signed) — secure context for the Guacamole clipboard ─────
# Browsers only expose the async Clipboard API in a secure context (HTTPS/localhost), so
# Guacamole HTML5 copy/paste sync requires TLS. Give apache a self-signed cert + a :443
# vhost mirroring the :80 one. The guac /html5 reverse-proxy (conf-available, server scope)
# applies here too; a wss:// client connection is terminated by mod_ssl and forwarded to
# tomcat as ws:// by mod_proxy_wstunnel. This also replaces the prior ':443 plain-HTTP' state.
log "[11b] Enabling HTTPS (self-signed TLS) for the secure-context clipboard..."
a2enmod ssl proxy_wstunnel >> "$LOG" 2>&1 || true
if [ ! -f /etc/ssl/certs/pnetlab-selfsigned.crt ] || [ ! -f /etc/ssl/private/pnetlab-selfsigned.key ]; then
    if openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
            -keyout /etc/ssl/private/pnetlab-selfsigned.key \
            -out /etc/ssl/certs/pnetlab-selfsigned.crt \
            -subj '/CN=pnetlab' \
            -addext 'subjectAltName=DNS:pnetlab,DNS:localhost,IP:127.0.0.1' >> "$LOG" 2>&1; then
        chmod 600 /etc/ssl/private/pnetlab-selfsigned.key
    else
        warn "self-signed cert generation failed — HTTPS clipboard will not work"
    fi
fi
cat > /etc/apache2/sites-available/pnetlab-ssl.conf <<APACHESSL
<IfModule mod_ssl.c>
<VirtualHost *:443>
    DocumentRoot $HTML
    <Directory $HTML/>
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
    AddType application/x-httpd-php .php

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/pnetlab-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/pnetlab-selfsigned.key

    # PNET web-console: wss -> console_mux.py :8022/:6080 [S1/S2] + guacamole-lite :8081 [S3] + shell pty :8023 [admin]
    <IfModule mod_proxy_wstunnel.c>
        ProxyPass        /telnet/  ws://127.0.0.1:8022/  upgrade=websocket
        ProxyPassReverse /telnet/  ws://127.0.0.1:8022/
        ProxyPass        /vnc/     ws://127.0.0.1:6080/  upgrade=websocket
        ProxyPassReverse /vnc/     ws://127.0.0.1:6080/
        ProxyPass        /guac/    ws://127.0.0.1:8081/  upgrade=websocket
        ProxyPassReverse /guac/    ws://127.0.0.1:8081/
        ProxyPass        /shell/   ws://127.0.0.1:8023/  upgrade=websocket
        ProxyPassReverse /shell/   ws://127.0.0.1:8023/
        # lab-state push fan-out (pnetlab-labstated) — live topology node/link status
        ProxyPass        /labstate/ ws://127.0.0.1:8024/  upgrade=websocket
        ProxyPassReverse /labstate/ ws://127.0.0.1:8024/
        # node http/https web console -> http_ws_bridge.py :8025 (iframe reverse-proxy)
        ProxyPass        /console/http/ http://127.0.0.1:8025/ upgrade=websocket
        ProxyPassReverse /console/http/ http://127.0.0.1:8025/
    </IfModule>

    # Strip the engine's strict global CSP/XFO (pnet-hardening.conf) for the
    # PROXIED node app, which serves its own inline scripts/styles/assets; keep it
    # same-origin-framable only. mod_headers is enabled by enable-web-hardening.sh.
    <Location "/console/http/">
        Header always unset Content-Security-Policy
        Header always unset Content-Security-Policy-Report-Only
        Header always unset X-Frame-Options
        Header always set Content-Security-Policy "frame-ancestors 'self'"
    </Location>

    ErrorLog \${APACHE_LOG_DIR}/pnetlab_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/pnetlab_ssl_access.log combined
</VirtualHost>
</IfModule>
APACHESSL
a2ensite pnetlab-ssl >> "$LOG" 2>&1 || true
# The pnetlab deb ships its OWN _default_:443 SSL vhost (sites-available/pnetlabs.conf, enabled
# by its postinst) that points SSLCertificateFile at /etc/ssl/certs/apache-selfsigned.crt — a cert
# the stock PNetLab firstboot generates but we never do. It's inert while mod_ssl is off, but the
# `a2enmod ssl` above activates it -> apache fails configtest ("SSLCertificateFile ... does not
# exist") and won't start (esp. after a reboot). We ship our own :443 vhost (pnetlab-ssl.conf), so
# disable the deb's. Found by the M8 fresh-VM gate (surfaced once the deb actually configured).
a2dissite pnetlabs >> "$LOG" 2>&1 || true

# ── [store] Laravel store — RETIRED (item C6, store decommission) ────────────
# The Laravel store (formerly the pnetlab-store deb) is gone: the engine-
# native /login/ replaces it, and /opt/unetlab/html/store does not exist on
# fresh installs. The retired Tomcat guacamole /html5 reverse-proxy was
# already dropped — the web console replaced it and updateUserToken() is a
# no-op. Nothing to extract or install here.
log "[store] Laravel store retired — nothing to do."

# ── [11c] Web console runtime deps (frontend/bridges/units are the deb) ───────
# The frontend (html/console), backend bridges (/opt/pnet-webconsole), the systemd
# units, the tmpfiles token store and /etc/pnet-webconsole are the pnetlab deb now
# (folded in @ 6.8.31, item E — was the separate pnetlab-webconsole deb; the
# pnetlab postinst enables the units + tmpfiles). What stays here is genuinely
# install-time: the console mux's two Python deps.
#   * websockets  — apt `python3-websockets` (installed above). On 26.04/Python 3.14 the old
#     pinned `websockets==12.0` pip wheel is cp312-only and has NO sdist build that compiles on
#     3.14, so a pip install fails and (because it shared one invocation) took telnetlib3 down
#     with it → telnet console blank. The distro package (15.x) is built for the system Python
#     and the bridge is already version-agnostic (handle(ws,*args) + request_path()).
#   * telnetlib3 — still PyPI-only (no clean apt dep), pure-python (py3-none-any), so the
#     bundled wheel installs on ANY Python. Installed in its OWN pip call so nothing can block it.
# PEP 668 (externally-managed-environment) → --break-system-packages to land in the system
# site-packages the unit's /usr/bin/python3 imports from.
log "[11c] Installing web-console console-mux python deps + (re)starting units..."
if python3 -c 'import websockets' >/dev/null 2>&1; then
    log "  websockets present ($(python3 -c 'import websockets;print(websockets.__version__)' 2>/dev/null)) via apt"
else
    warn "python3-websockets missing (apt) — telnet console may not start"
fi
if ls "$WEBCONSOLE_DIR"/wheels/telnetlib3*.whl >/dev/null 2>&1; then
    pip3 install --break-system-packages --no-index --find-links "$WEBCONSOLE_DIR/wheels" telnetlib3 >> "$LOG" 2>&1 \
        && log "  telnetlib3 installed from bundled wheel" \
        || warn "telnetlib3 install from bundled wheel failed — telnet console may not start"
else
    pip3 install --break-system-packages telnetlib3 >> "$LOG" 2>&1 \
        && log "  telnetlib3 installed from PyPI" \
        || warn "telnetlib3 install failed — telnet console will not start"
fi
# proxy_http + proxy_wstunnel (already listed) cover the http-console bridge too:
# it proxies plain HTTP and upgrades to ws on demand. NO proxy_html — the bridge
# rewrites node-app URLs itself, in Python; Apache just forwards bytes.
a2enmod proxy proxy_http proxy_wstunnel rewrite >> "$LOG" 2>&1 || true
systemctl daemon-reload >> "$LOG" 2>&1 || true
# pnetlab.postinst's own console-mux preflight runs during package configuration
# (step [7/14] above), before telnetlib3 (just installed, above) exists on disk —
# it always fails that preflight on a fresh install and masks the unit as its safe
# fallback (no legacy units to restore since 6.8.67). Undo that mask now that the
# real dependency is actually present, or enable/restart below are silent no-ops.
systemctl unmask pnet-console-mux.service >> "$LOG" 2>&1 || true
systemctl enable pnet-console-mux.service >> "$LOG" 2>&1 || true
systemctl restart pnet-console-mux.service >> "$LOG" 2>&1 || warn "pnet-console-mux failed to start"
sleep 1
if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8022' && \
   ss -ltn 2>/dev/null | grep -q '127.0.0.1:6080'; then
    log "  pnet-console-mux listening on 127.0.0.1:8022 and :6080"
else
    warn "pnet-console-mux is NOT listening on both :8022 and :6080"
fi
systemctl restart pnet-shell-bridge.service pnet-token-janitor.timer >> "$LOG" 2>&1 || true
# http node web-console bridge (:8025 — NOT :8024, that's labstated). The unit
# ships in the pnetlab deb; enable so it survives reboot, then (re)start it.
#
# Its runtime deps are python3-websockets AND **python3-httpx** — http_ws_bridge.py:121
# does `import httpx`. httpx was previously undeclared here and in the deb Depends, and
# only arrived incidentally via the OPTIONAL AI/MCP pip step at [11d]; on any install
# where [11d] was skipped or failed, this unit crash-looped on ModuleNotFoundError
# forever while `systemctl is-active` still read "active" (Restart= keeps re-arming it).
# Apache then had no proxy backend and every node web console AND every Wireshark
# capture iframe rendered Apache's "Service Unavailable" page. Observed on the .222
# gate 2026-08-05 at restart counter 601. Prefer the apt package over pip: [11d]'s own
# comment records that pip installs under /usr/local SHADOW apt modules.
if python3 -c 'import httpx' >/dev/null 2>&1; then
    log "  httpx present ($(python3 -c 'import httpx;print(httpx.__version__)' 2>/dev/null)) via apt"
else
    warn "python3-httpx missing — pnet-http-bridge will crash-loop; node web consoles AND Wireshark captures will show Apache 503"
fi
systemctl enable pnet-http-bridge.service >> "$LOG" 2>&1 || true
systemctl restart pnet-http-bridge.service >> "$LOG" 2>&1 || warn "pnet-http-bridge failed to start"
# `is-active` is NOT sufficient here: a Restart=-armed unit that dies on import reads
# "active" between respawns. Assert the socket is actually bound.
sleep 2
if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8025'; then
    log "  pnet-http-bridge listening on 127.0.0.1:8025"
else
    warn "pnet-http-bridge is NOT listening on :8025 — check 'journalctl -u pnet-http-bridge'"
fi
log "  web-console deps ready (mux=$(systemctl is-active pnet-console-mux.service 2>/dev/null) shell=$(systemctl is-active pnet-shell-bridge.service 2>/dev/null) http=$(systemctl is-active pnet-http-bridge.service 2>/dev/null))"

# ── airduct RF position feed (opt-in Tier-1 distance-loss) ───────────────────
# airduct-pos-sync.py writes each OPTED-IN lab session's node canvas coords to
# /opt/unetlab/tmp/<session>/airduct-pos.json for the airhandler's Tier-1 model.
# Opt-in = the Wi-Fi Painter "Distance roaming (RF)" toggle (pnq-wifi.php drops the
# airduct-rf marker). Un-opted labs get no pos file -> airhandler fails open. The
# unit ships as a data file in the engine overlay; enable so RF-opted labs work.
if [ -f /opt/unetlab/scripts/airduct-pos-sync.service ]; then
    cp -f /opt/unetlab/scripts/airduct-pos-sync.service /etc/systemd/system/airduct-pos-sync.service
    systemctl daemon-reload >> "$LOG" 2>&1 || true
    systemctl enable --now airduct-pos-sync.service >> "$LOG" 2>&1 || warn "airduct-pos-sync failed to start"
    log "  airduct-pos-sync = $(systemctl is-active airduct-pos-sync.service 2>/dev/null)"
fi

# Telemetry collector (pnq-telemetryd): host + per-node CPU/RAM history into a
# root-owned SQLite store, read by the dashboard History view and the per-node
# graph panel. The deb postinst also enables this; the explicit fresh-install
# path here guarantees the data dirs + unit on the ISO build. Idempotent.
mkdir -p /opt/unetlab/data/telemetry /opt/unetlab/data/extauth /opt/unetlab/data/backups 2>/dev/null || true
chmod 0755 /opt/unetlab/data/telemetry /opt/unetlab/data/backups 2>/dev/null || true
chmod 0700 /opt/unetlab/data/extauth 2>/dev/null || true
if [ -f /opt/unetlab/scripts/pnq-telemetryd.service ]; then
    cp -f /opt/unetlab/scripts/pnq-telemetryd.service /etc/systemd/system/pnq-telemetryd.service
    systemctl daemon-reload >> "$LOG" 2>&1 || true
    systemctl enable --now pnq-telemetryd.service >> "$LOG" 2>&1 || warn "pnq-telemetryd failed to start"
    log "  pnq-telemetryd = $(systemctl is-active pnq-telemetryd.service 2>/dev/null)"
fi

# ── [11d] AI Lab Builder / MCP server python deps (best-effort, needs egress) ─
# The toggleable pnetlab-mcp.service (scripts/mcp/pnetlab-mcp.py) needs the
# official `mcp` SDK + uvicorn/httpx for the Streamable-HTTP transport, and the
# `anthropic`/`openai` SDKs for the (P3) in-app agent. The service ships DISABLED
# by default and is only turned on from the main dashboard, so a failed install
# here (airgapped site with no provider yet) is non-fatal — the dashboard surfaces
# "MCP unavailable" until the deps + a provider are configured.
log "[11d] Installing AI/MCP python deps (mcp, uvicorn, httpx, anthropic, openai)..."
# Two steps, deliberately NOT a blanket --ignore-installed:
#   1. The apt-installed `jsonschema` (an mcp dep) on 26.04/Py3.14 ships with no
#      RECORD file, so pip refuses to manage it; force just that one package with
#      fresh wheels (the original Py3.14 breakage this step was added for).
#   2. Install the rest normally, under a constraint. A blanket --ignore-installed
#      reinstalls the whole dependency closure and drags in cryptography>=47, which
#      SHADOWS the apt python3-cryptography (46.x) under /usr/local and BREAKS
#      pyOpenSSL (it pins cryptography<47) — taking the Lab PKI + SD-WAN cert paths
#      down with it. mcp itself needs no cryptography, so the constraint keeps any
#      transitive pull apt-compatible and pyOpenSSL intact.
MCP_PIP_CONSTRAINT="$(mktemp)"; echo 'cryptography<47' > "$MCP_PIP_CONSTRAINT"
MCP_DEPS_OK=0
# (1) Prefer the bundled offline wheels (airgapped sites get the agent too). The
#     web-console/wheels/ dir carries the full mcp/uvicorn/httpx/anthropic/openai
#     closure resolved under cryptography<47 — note it deliberately ships NO
#     cryptography wheel, so the apt python3-cryptography (46.x) is never shadowed
#     and pyOpenSSL / Lab PKI stay intact. Mirrors the telnetlib3 offline path.
if ls "$WEBCONSOLE_DIR"/wheels/mcp-*.whl >/dev/null 2>&1; then
    pip3 install --break-system-packages --no-index --find-links "$WEBCONSOLE_DIR/wheels" --ignore-installed jsonschema >> "$LOG" 2>&1 || true
    if pip3 install --break-system-packages --no-index --find-links "$WEBCONSOLE_DIR/wheels" -c "$MCP_PIP_CONSTRAINT" mcp uvicorn httpx anthropic openai >> "$LOG" 2>&1; then
        log "  AI/MCP deps installed from bundled wheels ($(python3 -c 'import mcp,uvicorn,httpx;print(\"mcp+uvicorn+httpx ok\")' 2>/dev/null))"
        MCP_DEPS_OK=1
    else
        warn "AI/MCP bundled-wheel install failed — trying online"
    fi
fi
# (2) Online fallback (or if no wheels bundled). Two steps, deliberately NOT a
#     blanket --ignore-installed:
#       1. The apt-installed `jsonschema` (an mcp dep) on 26.04/Py3.14 ships with no
#          RECORD file, so pip refuses to manage it; force just that one package.
#       2. Install the rest under the constraint. A blanket --ignore-installed drags
#          in cryptography>=47, which shadows apt's 46.x and breaks pyOpenSSL (Lab
#          PKI / SD-WAN cert paths); the constraint keeps any transitive pull
#          apt-compatible.
if [ "$MCP_DEPS_OK" != 1 ]; then
    pip3 install --break-system-packages --ignore-installed jsonschema >> "$LOG" 2>&1 || true
    if pip3 install --break-system-packages -c "$MCP_PIP_CONSTRAINT" mcp uvicorn httpx anthropic openai >> "$LOG" 2>&1; then
        log "  AI/MCP deps installed from PyPI ($(python3 -c 'import mcp,uvicorn,httpx;print(\"mcp+uvicorn+httpx ok\")' 2>/dev/null))"
    else
        warn "AI/MCP python deps not installed (no egress + no bundled wheels?) — enable the MCP server from the dashboard after installing: pip3 install --break-system-packages -c <(echo 'cryptography<47') --ignore-installed jsonschema mcp uvicorn httpx anthropic openai"
    fi
fi
rm -f "$MCP_PIP_CONSTRAINT"

# ── [11d] Web console RDP lane: per-install GUAC_CRYPT_KEY ─────────────────────
# guacamole-lite (the Node service + vendored node_modules + its unit) ships in the
# pnetlab deb now (folded in @ 6.8.31, item E — was the separate pnetlab-webconsole
# deb). The ONE install-time bit is the per-install GUAC_CRYPT_KEY, shared
# byte-identical between the Node side (guac.env, the unit's EnvironmentFile)
# and the PHP side (console_config.php, a deb conffile) so token_mint's AES blob
# decrypts. Generate once, reuse on re-install, then restart the deb-enabled unit.
log "[11d] Configuring web-console RDP lane crypto key..."
# Some nodejs packages ship only /usr/bin/nodejs; the unit calls /usr/bin/node.
[ -x /usr/bin/node ] || { [ -x /usr/bin/nodejs ] && ln -sf /usr/bin/nodejs /usr/bin/node; }

GUAC_ENV=/etc/pnet-webconsole/guac.env
GUAC_KEY=""
[ -f "$GUAC_ENV" ] && GUAC_KEY=$(sed -n 's/^GUAC_CRYPT_KEY=//p' "$GUAC_ENV" | head -1)
if [ "${#GUAC_KEY}" -ne 32 ]; then
    GUAC_KEY=$(head -c 24 /dev/urandom | base64 | tr -d '\n')
fi
printf 'GUAC_CRYPT_KEY=%s\n' "$GUAC_KEY" > "$GUAC_ENV"
chown root:root "$GUAC_ENV"; chmod 600 "$GUAC_ENV"
if [ -f /etc/pnet-webconsole/console_config.php ]; then
    sed -i "s|define('GUAC_CRYPT_KEY', '[^']*');|define('GUAC_CRYPT_KEY', '$GUAC_KEY');|" /etc/pnet-webconsole/console_config.php
else
    warn "/etc/pnet-webconsole/console_config.php missing (pnetlab deb installed? web console is folded into it since 6.8.31)"
fi

systemctl daemon-reload >> "$LOG" 2>&1 || true
if [ -x /usr/bin/node ] && [ -d /opt/pnet-webconsole/backend/node_modules/guacamole-lite ]; then
    systemctl restart pnet-guac-lite.service >> "$LOG" 2>&1 || warn "pnet-guac-lite failed to start"
else
    warn "node or vendored guacamole-lite missing — rdp console (pnet-guac-lite) not started"
fi
log "  web-console rdp key set (guac-lite=$(systemctl is-active pnet-guac-lite.service 2>/dev/null), node=$(command -v node || echo none))"

# ── [11e] B2: Apache event MPM + php8.5-fpm ────────────────────────────────────
# prefork+mod_php (bootstrapped in [4]) ties a full Apache process to every
# idle WS console tunnel. Switch to mpm_event + fpm via the deb-shipped,
# idempotent switcher (it also mirrors the .htaccess php_* limits into the
# fpm pool). Revert path: /opt/unetlab/scripts/enable-php-fpm.sh --revert
log "[11e] Switching Apache to mpm_event + php8.5-fpm..."
# v8/27H1: the engine's node-status detection runs `netstat`/reads /proc/net/tcp
# (functions.php getNodeStatus -> "is the console port LISTENing?") from the web
# process. Ubuntu 26.04's stock apache2 unit ships ProtectProc=invisible +
# ProcSubset=pid, which HIDE /proc/net/* from the service — so under mod_php
# netstat fails ("no support for AF INET (tcp)") and EVERY node shows stopped in
# the GUI even while its process + console port are up. (php-fpm ships
# ProcSubset=all, so the fpm path is unaffected, but the mod_php fallback below is
# not.) Restore /proc visibility for both SAPIs via drop-ins before the restart.
for _svc in apache2 php8.5-fpm; do
    mkdir -p "/etc/systemd/system/${_svc}.service.d"
    cat > "/etc/systemd/system/${_svc}.service.d/zz-pnetlab-procnet.conf" <<'PROCNET'
[Service]
# PNetLab node-status detection needs to read /proc/net/tcp (netstat); the stock
# 26.04 unit hides it (ProtectProc=invisible/ProcSubset=pid) -> nodes show stopped.
ProtectProc=default
ProcSubset=all
PROCNET
done
systemctl daemon-reload >> "$LOG" 2>&1 || true
if ! dpkg -s php8.5-fpm >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y php8.5-fpm >> "$LOG" 2>&1 \
        || dpkg -i "$DEBS_DIR"/php8.5-fpm_*.deb >> "$LOG" 2>&1 \
        || warn "php8.5-fpm install failed — staying on prefork+mod_php"
fi
if dpkg -s php8.5-fpm >/dev/null 2>&1 && [ -x /opt/unetlab/scripts/enable-php-fpm.sh ]; then
    bash /opt/unetlab/scripts/enable-php-fpm.sh >> "$LOG" 2>&1 \
        && log "  mpm_event + php8.5-fpm active" \
        || { warn "php-fpm switch failed — reverting to mod_php"; bash /opt/unetlab/scripts/enable-php-fpm.sh --revert >> "$LOG" 2>&1 || true; }
else
    warn "php8.5-fpm or switcher missing — staying on prefork+mod_php"
fi

# ── [11f] Web-tier hardening + asset delivery ─────────────────────────────────
# Historically closed a real secret-disclosure hole: the Laravel store's
# framework root (.env with APP_KEY + DB creds, vendor/, storage/logs,
# composer.json) was served as static files because the whole html/ tree is
# the DocumentRoot. The store is now retired (item C6, store decommission) —
# the deb-shipped switcher denies EVERYTHING under /store/ outright (no more
# /store/public/ exception) as belt-and-braces for an upgraded box where the
# old store tree might still exist on disk. It also turns off directory
# listing, adds baseline security headers, and — now that B2 gave us
# mpm_event+fpm — enables HTTP/2 and static-asset caching. Idempotent;
# revert: enable-web-hardening.sh --revert.
log "[11f] Applying web-tier hardening (store lockdown + h2 + caching)..."
if [ -x /opt/unetlab/scripts/enable-web-hardening.sh ]; then
    bash /opt/unetlab/scripts/enable-web-hardening.sh >> "$LOG" 2>&1 \
        && log "  web hardening active" \
        || warn "web hardening failed — store framework paths may be exposed; check $LOG"
else
    warn "enable-web-hardening.sh missing — store framework paths remain web-exposed"
fi

# ── [12/14] sudoers — RETIRED (B7): the privilege broker handles root ops ──────
step 12 "sudoers: removing any legacy www-data grant (pnetlab-brokerd took over)..."
# Stock PNetLab granted www-data full passwordless root. Every engine and store
# call site now rides pnetlab-brokerd (allowlisted, argument-validated verbs on
# /run/pnetlab/broker.sock); the 6.7.10+ pnetlab deb no longer ships
# /etc/sudoers.d/unetlab. Remove leftovers from older installs (dpkg keeps
# obsolete conffiles on disk across upgrades). Known-dead without the grant:
# the stock online-upgrade flow (undesirable on this build — it would clobber
# the custom debs) and the uncalled Scand* artisan commands.
rm -f /etc/sudoers.d/unetlab

# ── [13/14] Permission fixes (node boot through orchestration) ────────────────
step 13 "Applying permission fixes..."

# Default KSM ON for fresh installs (parity with the old UKSM kernel, which
# auto-enabled itself). The in-tree 6.12 KSM boots with run=0; ovfstartup replays
# /opt/unetlab/ksm at every boot and the System Status toggle rewrites that file.
# A fresh install never seeded it, so KSM silently stayed off (found by the
# fresh-VM gate). Seed once — never overwrite a user's later choice.
if [ ! -f /opt/unetlab/ksm ]; then
    echo 1 > /opt/unetlab/ksm
    log "  seeded /opt/unetlab/ksm = 1 (KSM on by default)"
fi
if [ -e /sys/kernel/mm/ksm/run ]; then
    cat /opt/unetlab/ksm > /sys/kernel/mm/ksm/run 2>/dev/null || true
fi

# baking the customs as a non-root user can leave html unreadable to www-data
chmod -R a+rX "$HTML" 2>/dev/null || true
chmod -R a+rX "$HTML/templates" 2>/dev/null || true
# web server writes its own logs here -> must be www-data-owned
mkdir -p /opt/unetlab/data/Logs
chown -R www-data:www-data /opt/unetlab/data/Logs 2>/dev/null || true
chmod -R 775 /opt/unetlab/data/Logs 2>/dev/null || true
# lab export API (apiExportLabs) zips into here -> must be www-data-owned, or
# every export fails with "Cannot ZIP file (80073)" (zip can't write into a
# missing dir); Apache's "Alias /Exports" also assumes it exists
mkdir -p /opt/unetlab/data/Exports
chown -R www-data:www-data /opt/unetlab/data/Exports 2>/dev/null || true
chmod -R 775 /opt/unetlab/data/Exports 2>/dev/null || true
# runtime dirs the engine writes
for d in /opt/unetlab/labs /opt/unetlab/data; do
    mkdir -p "$d"; chown www-data:www-data "$d" 2>/dev/null || true
done
# /opt/unetlab/tmp MUST stay group 'unl' + setgid (the deb default = root:unl 2777). Node run
# dirs are created here and, for node types that drop to the per-tenant user (IOL runs as
# unl<tid>), must be writable by that user. The setgid makes children inherit group 'unl' so
# the tenant user can write its run dir; chowning tmp to www-data:www-data (as a generic
# "runtime dir") BREAKS IOL ("Cannot open AF_UNIX sockets", wrapper "Child is no more running").
mkdir -p /opt/unetlab/tmp
if getent group unl >/dev/null 2>&1; then chown root:unl /opt/unetlab/tmp 2>/dev/null || true; fi
chmod 2777 /opt/unetlab/tmp 2>/dev/null || true

# Belt-and-suspenders strip of the xml.cisco.com null-route (`127.0.0.127 xml.cisco.com`). The
# SOURCE injector in pnetlab.postinst is already neutered in [7/14] and a boot-time strip is baked
# into ovfstartup.sh, so this is just a final build-time cleanup. It "disables phone-home" for OLD
# IOU images, but the new x86_64 IOS-XE IOL images FAIL to come up with it null-routed (BinOS
# smart-licensing). (Verified: with it removed, L2 `Switch>` and L3 `Router>` both boot.)
sed -i "/[[:space:]]xml\.cisco\.com/d" /etc/hosts 2>/dev/null || true

# ── [14/14] Database: users, schema, offline admin ────────────────────────────
step 14 "Configuring database (app users, schema, offline admin)..."
systemctl enable mysql >> "$LOG" 2>&1 || true
systemctl start  mysql >> "$LOG" 2>&1 || true
for _i in $(seq 1 60); do mysqladmin ping --silent 2>/dev/null && break; sleep 2; done
if ! mysqladmin ping --silent 2>/dev/null; then
    warn "MySQL not responding — DB setup skipped. Re-run installer after MySQL is up."
else
    # Ubuntu 26.04 ships MySQL 8.4, which DISABLES the built-in mysql_native_password
    # auth plugin by default. PNetLab's app (php8.5 mysqlnd) + guacamole (Connector/J)
    # DB users authenticate WITH mysql_native_password, and the deb postinsts ALTER root
    # with it too — all fail with "ERROR 1524: Plugin 'mysql_native_password' is not
    # loaded" until it is re-enabled. It is still present in 8.4 LTS (removed only in
    # 9.x), so flip it back on BEFORE any IDENTIFIED WITH mysql_native_password SQL.
    if ! mysql --defaults-file=/etc/mysql/debian.cnf -N \
         -e "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='mysql_native_password';" 2>/dev/null | grep -qi active; then
        printf '[mysqld]\nmysql_native_password=ON\n' > /etc/mysql/mysql.conf.d/zz-pnetlab-native-pw.cnf
        systemctl restart mysql >> "$LOG" 2>&1 || warn "mysql restart (native_password enable) warning"
        for _i in $(seq 1 60); do mysqladmin ping --silent 2>/dev/null && break; sleep 2; done
        log "  enabled mysql_native_password (MySQL 8.4 disables it by default)"
    fi
    # Noble MySQL 8.0 makes root@localhost caching_sha2_password (NOT auth_socket as on
    # focal/jammy), so a bare `mysql` as root is denied. Drive admin via the always-present
    # debian-sys-maint account (full privs), and set root's password to 'pnetlab' so the
    # pnetlab deb postinst (`mysql -uroot -ppnetlab ...`) also works on every reconfigure.
    MYSQL="mysql --defaults-file=/etc/mysql/debian.cnf"
    $MYSQL -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab'; FLUSH PRIVILEGES;" >> "$LOG" 2>&1 || warn "root pw set warning"
    # Bare credential-less `mysql` as root is used by the ishare2 docker-device scripts
    # (ishare2/devices.json: `mysql pnetlab_db -e "DELETE FROM process_device …"`) and by
    # includes/doctor.php — those run AS ROOT and would be denied on Noble (root@localhost
    # now needs a password). Drop a root client config so a bare `mysql` authenticates as
    # root/pnetlab. Without this a docker image pulls fine but the install never clears its
    # process_device row, so the Docker-devices page sticks on "not installed".
    printf '[client]\nuser=root\npassword=pnetlab\n' > /root/.my.cnf
    chmod 600 /root/.my.cnf
    log "  wrote /root/.my.cnf (credential-less root mysql for ishare2/doctor)"
    # Create the app users the engine actually uses (functions.php PDO):
    #   pnetlab_db  <- 'pnetlab'/'pnetlab'   ;  guacdb <- 'guacuser'/'pnetlab'
    $MYSQL >> "$LOG" 2>&1 <<'SQLUSERS' || warn "user/db creation had warnings"
CREATE DATABASE IF NOT EXISTS pnetlab_db CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS guacdb     CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'pnetlab'@'localhost'  IDENTIFIED WITH mysql_native_password BY 'pnetlab';
CREATE USER IF NOT EXISTS 'guacuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
ALTER USER 'pnetlab'@'localhost'  IDENTIFIED WITH mysql_native_password BY 'pnetlab';
ALTER USER 'guacuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'pnetlab';
GRANT ALL PRIVILEGES ON pnetlab_db.* TO 'pnetlab'@'localhost';
GRANT ALL PRIVILEGES ON guacdb.*     TO 'guacuser'@'localhost';
FLUSH PRIVILEGES;
SQLUSERS

    # Import schema ONLY when the DB is empty (NEVER re-import — that wipes admin/control).
    PNET_TABLES=$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='pnetlab_db';" 2>/dev/null || echo 0)
    if [ "${PNET_TABLES:-0}" -eq 0 ]; then
        SRC="$SCHEMA_DIR/pnetlab_db-schema.sql"
        [ -f "$SRC" ] || SRC="/opt/unetlab/schema/pnetlab_db.sql"
        log "  pnetlab_db empty -> importing $SRC"
        $MYSQL pnetlab_db < "$SRC" >> "$LOG" 2>&1 || warn "pnetlab_db import warning"
    else
        log "  pnetlab_db already has $PNET_TABLES tables -> NOT re-importing (preserves data)"
    fi

    GUAC_TABLES=$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='guacdb';" 2>/dev/null || echo 0)
    if [ "${GUAC_TABLES:-0}" -eq 0 ]; then
        SRC="$SCHEMA_DIR/guacdb-1.6.0-schema.sql"
        log "  guacdb empty -> importing $SRC"
        $MYSQL guacdb < "$SRC" >> "$LOG" 2>&1 || warn "guacdb import warning"
    else
        log "  guacdb already has $GUAC_TABLES tables -> NOT re-importing"
    fi

    # Schema ledger for existing databases. Fresh databases already receive the
    # final schema and literal ledger rows from pnetlab_db-schema.sql.
    DBMYSQL="$MYSQL pnetlab_db"
    if $DBMYSQL -e "CREATE TABLE IF NOT EXISTS schema_version (version INT PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, description TEXT)" >> "$LOG" 2>&1; then
        migration_001() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='user_max_cpu'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE users ADD COLUMN user_max_cpu INT DEFAULT NULL" >> "$LOG" 2>&1; }
        migration_002() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='user_max_ram'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE users ADD COLUMN user_max_ram INT DEFAULT NULL" >> "$LOG" 2>&1; }
        migration_003() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='access_days'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE users ADD COLUMN access_days VARCHAR(16) DEFAULT NULL" >> "$LOG" 2>&1; }
        migration_004() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='ext_auth'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE users ADD COLUMN ext_auth VARCHAR(8) DEFAULT NULL" >> "$LOG" 2>&1; }
        migration_005() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_cpu'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE node_sessions ADD COLUMN node_cpu FLOAT DEFAULT 0" >> "$LOG" 2>&1; }
        migration_006() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_ram'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE node_sessions ADD COLUMN node_ram INT DEFAULT 0" >> "$LOG" 2>&1; }
        migration_007() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_session_port_2nd'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE node_sessions ADD COLUMN node_session_port_2nd INT(11) DEFAULT NULL" >> "$LOG" 2>&1; }
        migration_008() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='node_sessions' AND COLUMN_NAME='node_session_host'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "ALTER TABLE node_sessions ADD COLUMN node_session_host TINYINT NOT NULL DEFAULT 0" >> "$LOG" 2>&1; }
        migration_009() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cluster_hosts'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "CREATE TABLE cluster_hosts (host_id TINYINT NOT NULL PRIMARY KEY, host_name VARCHAR(64) NOT NULL, host_ip VARCHAR(45) NOT NULL, host_status TINYINT NOT NULL DEFAULT 0, host_last_seen INT DEFAULT NULL, host_version VARCHAR(48) DEFAULT NULL, host_joined INT DEFAULT NULL) ENGINE=InnoDB" >> "$LOG" 2>&1; }
        migration_010() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cluster_placements'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "CREATE TABLE cluster_placements (placement_lab CHAR(36) NOT NULL, placement_nid INT NOT NULL, placement_host TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (placement_lab, placement_nid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" >> "$LOG" 2>&1; }
        migration_011() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='activity_log'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "CREATE TABLE activity_log (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, created_at INT UNSIGNED NOT NULL, pod INT DEFAULT NULL, username VARCHAR(150) NOT NULL, ip VARCHAR(45) DEFAULT NULL, category VARCHAR(16) NOT NULL, action VARCHAR(32) NOT NULL, lab_path VARCHAR(1024) DEFAULT NULL, lab_name VARCHAR(255) DEFAULT NULL, node_name VARCHAR(255) DEFAULT NULL, node_template VARCHAR(64) DEFAULT NULL, detail TEXT DEFAULT NULL, session_id CHAR(64) DEFAULT NULL, duration_seconds INT UNSIGNED DEFAULT NULL, PRIMARY KEY (id), KEY activity_category_time (category, created_at), KEY activity_session (session_id, action, created_at), KEY activity_created_at (created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" >> "$LOG" 2>&1; }
        migration_012() { local n; n=$($DBMYSQL -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='password_resets'" 2>/dev/null) || return 1; [ "$n" != 0 ] || $DBMYSQL -e "CREATE TABLE password_resets (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, token_hash CHAR(64) NOT NULL, pod INT NOT NULL, created_at INT UNSIGNED NOT NULL, expires_at INT UNSIGNED NOT NULL, used_at INT UNSIGNED DEFAULT NULL, PRIMARY KEY (id), UNIQUE KEY password_resets_token (token_hash), KEY password_resets_pod (pod, used_at), KEY password_resets_expires (expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" >> "$LOG" 2>&1; }
        migrations=(migration_001 migration_002 migration_003 migration_004 migration_005 migration_006 migration_007 migration_008 migration_009 migration_010 migration_011 migration_012)
        descriptions=("users.user_max_cpu" "users.user_max_ram" "users.access_days" "users.ext_auth" "node_sessions.node_cpu" "node_sessions.node_ram" "node_sessions.node_session_port_2nd" "node_sessions.node_session_host" "cluster_hosts" "cluster_placements" "activity_log" "password_resets")
        for i in "${!migrations[@]}"; do
            version=$((i + 1))
            done_row=$($DBMYSQL -N -e "SELECT COUNT(*) FROM schema_version WHERE version=$version" 2>/dev/null) || { warn "could not inspect schema_version $version"; break; }
            [ "$done_row" != 0 ] && continue
            "${migrations[$i]}" || { warn "schema migration $version failed"; break; }
            $DBMYSQL -e "INSERT INTO schema_version (version, description) VALUES ($version, '${descriptions[$i]}')" >> "$LOG" 2>&1 || { warn "could not record schema migration $version"; break; }
        done
    else
        warn "could not bootstrap schema_version; schema migrations skipped"
    fi

    # Offline mode, no captcha, version 6.5, and the offline admin user (idempotent).
    _PASS=$(printf '%s' 'pnet' | sha256sum | cut -d' ' -f1)
    $MYSQL pnetlab_db >> "$LOG" 2>&1 <<SQLADMIN || warn "admin/ctrl SQL warning"
INSERT INTO control (control_name, control_value) VALUES
  ('ctrl_offline_mode','1'),
  ('ctrl_online_mode','0'),
  ('ctrl_default_mode','offline'),
  ('ctrl_captcha','0'),
  ('ctrl_version','8.2.0')
ON DUPLICATE KEY UPDATE control_value = VALUES(control_value);

INSERT INTO users (username,password,role,offline,user_status,online_time)
  SELECT 'admin','$_PASS','0',1,1,UNIX_TIMESTAMP()
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE username='admin');
UPDATE users SET password='$_PASS', role='0', offline=1, user_status=1,
  online_time=UNIX_TIMESTAMP(), active_time=NULL, expired_time=NULL
  WHERE username='admin';
DELETE u FROM users u,
  (SELECT MIN(pod) AS keep FROM users WHERE username='admin') m
  WHERE u.username='admin' AND u.pod <> m.keep;
SQLADMIN
    log "  Offline mode set, captcha off, version 6.7.11 Noble, admin user: admin / pnet"
fi

# ── Networking: prevent the one-time PRE-WIZARD boot hang ─────────────────────
# On a freshly-installed (not-yet-wizard-configured) jammy box, netplan/systemd-networkd
# still own eth0 while ifupdown's networking.service is enabled with only the deb's partial
# nat0 stanza. `ifup -a` then deadlocks ~5 min on nat0's BLOCKING `up service udhcpd restart`
# — on jammy `service` maps to a synchronous `systemctl restart`, whose job can't run until
# networking.service finishes, while networking.service waits on that restart. The first-boot
# wizard (ovfconfig.sh) cures the disease (removes netplan -> makes ifupdown the single owner;
# the 6.5 ref boots in ~7 s post-wizard). Until then, harden two ways — both safe and a no-op
# once the system is configured:
#   1) make the udhcpd restart NON-BLOCKING so the deadlock can't form (live file + wizard tmpl);
#   2) cap networking.service's start timeout so any residual stall is bounded, not 5 min.
log "Hardening networking against the pre-wizard ifup hang..."
for f in /etc/network/interfaces /opt/ovf/ovfconfig.sh; do
    [ -f "$f" ] && sed -i 's#service udhcpd restart#systemctl --no-block restart udhcpd#g' "$f"
done
mkdir -p /etc/systemd/system/networking.service.d
cat > /etc/systemd/system/networking.service.d/10-timeout.conf <<'NETTMO'
# Bound ifupdown's start time. Healthy (post-wizard) boots finish in <1s; this only caps a
# pathological pre-wizard stall so the box reaches multi-user in ~90s instead of ~5min.
[Service]
TimeoutStartSec=90
NETTMO
systemctl daemon-reload >> "$LOG" 2>&1 || true

# ── OVF-on-boot (jammy): replace the dead Upstart trigger with systemd + build the bridges ────
# PNetLab's first-boot wizard ran from Upstart (/etc/init/ovfconfig.conf) — DEAD on jammy systemd,
# so the bridges (pnet0..9, nat0) were never built and ovfstartup.sh never ran. Wire it the jammy way:
#   - net.ifnames=0 (grub) so the primary NIC is eth0 (the wizard/cloud model hardcodes eth0..eth9);
#   - a deterministic /etc/network/interfaces (no interactive dialog): pnet0 mgmt-bridge (DHCP over
#     eth0), pnet1..9 cloud bridges, nat0 NAT cloud (10.0.137.254/24 + udhcpd + MASQUERADE out pnet0);
#   - hand the NIC to ifupdown (remove netplan, disable systemd-networkd);
#   - a systemd oneshot (pnetlab-ovfstartup.service) running /opt/ovf/ovfstartup.sh every boot.
# Effective after the post-install reboot (NIC renames to eth0 + ifupdown brings the bridges up).
log "Wiring OVF-on-boot (systemd ovfstartup + bridges; net.ifnames=0)..."
if ! grep -q 'net.ifnames=0' /etc/default/grub 2>/dev/null; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0 /' /etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="net.ifnames=0 /' /etc/default/grub
fi

# ── Reclaim the kdump crashkernel reservation (~1 GiB) ────────────────────────
# A lab appliance never kernel-dumps, yet Ubuntu's kdump-tools ships
# /etc/default/grub.d/kdump-tools.cfg which appends crashkernel=<size> to the
# cmdline (~512M-1024M reserved, RAM that could hold another vIOS-class node).
# Robust removal against the grub.d drop-in re-adding it:
#   1) purge kdump-tools + crash (removes the grub.d/kdump-tools.cfg source), and
#   2) drop a LATE grub.d override (99-*, sorts AFTER kdump-tools.cfg) that strips
#      any crashkernel= from the cmdline at every grub-mkconfig — so even a future
#      kdump-tools reinstall can't re-arm the reservation.
apt-get purge -y kdump-tools crash >> "$LOG" 2>&1 || true
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-pnetlab-no-crashkernel.cfg <<'NOCK'
# PNetLab: strip crashkernel= (lab appliance never kdumps; reclaim ~1 GiB).
# Sorts after grub.d/kdump-tools.cfg so it removes the reservation even if that
# package is ever reinstalled. Also neutralises crashkernel= baked into
# GRUB_CMDLINE_LINUX / _DEFAULT by /etc/default/grub.
GRUB_CMDLINE_LINUX_DEFAULT="$(echo "$GRUB_CMDLINE_LINUX_DEFAULT" | sed -e 's/crashkernel=[^ ]*//g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
GRUB_CMDLINE_LINUX="$(echo "$GRUB_CMDLINE_LINUX" | sed -e 's/crashkernel=[^ ]*//g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
NOCK

update-grub >> "$LOG" 2>&1 || warn "update-grub failed"

# Fix the PNetLab Plymouth boot splash. The stock theme (from the base pnetlab deb)
# draws a STATIC logo sprite AND, on every boot-progress tick, a brand-new Sprite()
# for the animation frame at the same centre — so you see two overlapping/ghosted
# logos ("two logos buffered"). Replace it with a single sprite that animates in
# place (SetImage on the one logo sprite; no per-frame Sprite(), no static base
# underneath), then rebuild the initramfs (the theme is baked into it) so it takes
# effect at next boot. Best-effort/cosmetic.
PLY_SCRIPT=/usr/share/plymouth/themes/pnetlab/pnetlab.script
if [ -f "$PLY_SCRIPT" ]; then
    log "Fixing Plymouth boot splash (single animated logo)..."
    cat > "$PLY_SCRIPT" <<'PLYEOF'
# PNetLab Plymouth boot splash — single animated sprite (no double/ghosted logo).
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

logo.image = Image("logo.png");
if (Window.GetWidth() > logo.image.GetWidth() && Window.GetHeight() > logo.image.GetHeight()) {
    scale = 1;
} else {
    scale_x = Window.GetWidth() / logo.image.GetWidth();
    scale_y = Window.GetHeight() / logo.image.GetHeight();
    scale = Math.Min(scale_x, scale_y) * 0.95;
}
logo.width = logo.image.GetWidth() * scale;
logo.height = logo.image.GetHeight() * scale;
logo.scaled = logo.image.Scale(logo.width, logo.height);
logo.x = Window.GetX() + Window.GetWidth() / 2 - logo.width / 2;
logo.y = Window.GetY() + Window.GetHeight() / 2 - logo.height / 2;

# ONE sprite, reused for every frame.
logo.sprite = Sprite();
logo.sprite.SetImage(logo.scaled);
logo.sprite.SetX(logo.x);
logo.sprite.SetY(logo.y);
logo.sprite.SetZ(0);
logo.sprite.SetOpacity(1);

fun refresh_callback () { }
Plymouth.SetRefreshFunction(refresh_callback);

checkpoint = 0;
logo_count = 1;
increasing = 1;
fun progress_callback (duration, progress) {
    if (checkpoint != progress) {
        checkpoint = progress;
        if (logo_count == 12 && increasing == 1) { logo_count = 11; increasing = 0; }
        else if (logo_count == 1 && increasing == 0) { logo_count = 2; increasing = 1; }
        else if (increasing == 1) { logo_count = logo_count + 1; }
        else { logo_count = logo_count - 1; }

        frame.image = Image("logo_" + logo_count + ".png");
        frame.width = frame.image.GetWidth() * scale;
        frame.height = frame.image.GetHeight() * scale;
        frame.scaled = frame.image.Scale(frame.width, frame.height);

        # Animate the SINGLE logo sprite in place — no new Sprite() (old frames
        # were left buffered) and no separate static logo, so only one shows.
        logo.sprite.SetImage(frame.scaled);
        logo.sprite.SetX(Window.GetX() + Window.GetWidth() / 2 - frame.width / 2);
        logo.sprite.SetY(Window.GetY() + Window.GetHeight() / 2 - frame.height / 2);
    }
}
Plymouth.SetBootProgressFunction(progress_callback);

fun quit_callback () {
    Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
    Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);
    logo.sprite.SetOpacity(0);
}
Plymouth.SetQuitFunction(quit_callback);

message_sprite = Sprite();
message_sprite.SetPosition(10, 10, 10000);
fun message_callback (text) {
    my_image = Image.Text(text, 1, 1, 1);
    message_sprite.SetImage(my_image);
}
Plymouth.SetMessageFunction(message_callback);
PLYEOF
    update-initramfs -u >> "$LOG" 2>&1 || warn "update-initramfs failed — Plymouth splash fix applies after the next initramfs rebuild"
fi

cat > /etc/network/interfaces <<'IFACES'
# PNetLab bridges (jammy OVF-on-boot). eth0 == primary NIC after net.ifnames=0.
auto lo
iface lo inet loopback

iface eth0 inet manual
# pnet0 is mgmt DHCP but configured `inet manual` + a BACKGROUNDED dhcpcd, NOT
# `inet dhcp`. ifupdown's `inet dhcp` method invokes dhcpcd and BLOCKS waiting for
# it to return; dhcpcd 10.x stays a persistent foreground-attached daemon and
# never hands control back, so `ifup -a` hangs until networking.service's 90s
# timeout kills it → service "failed" + ~1m41s boot (the IPv4 lease itself takes
# ~9s). `dhcpcd -b` forks to the background immediately, so `ifup` returns at once:
# networking.service succeeds and the box boots in ~10s, with dhcpcd leasing +
# renewing pnet0 in the background. (`down dhcpcd -k` stops it on ifdown.)
# allow-hotplug (NOT auto): the early pnet-bridges oneshot creates the pnet0
# bridge DEVICE before networking.service, and that device-add fires a udev event
# that brings pnet0 up via hotplug — so `ifup -a` never blocks on it. This removes
# the ~90s "raise network interfaces" boot wait (seen on static / slow-carrier
# configs) while pnet0 still comes up (eth0 enslaved + leased/addressed) right
# after boot. (auto would make networking.service wait on the bridge synchronously.)
allow-hotplug pnet0
iface pnet0 inet manual
    up dhcpcd -b pnet0
    down dhcpcd -k pnet0 || true
    pre-up ip link set dev eth0 up
    bridge_ports eth0
    bridge_stp off
IFACES
# Cloud N -> (N+1)th VM NIC mapping (backlog #7): pnetN bridges to ethN when that NIC exists
# (Cloud1->eth1 = 2nd VM NIC, Cloud2->eth2 = 3rd, ...). bridge_ports stays 'none' so `ifup` never
# fails on a 1-NIC box; a guarded post-up enslaves ethN only when present (absent NIC -> no-op).
for _i in $(seq 1 9); do
cat >> /etc/network/interfaces <<IFACES

auto pnet${_i}
iface pnet${_i} inet manual
    bridge_ports none
    bridge_stp off
    post-up [ -e /sys/class/net/eth${_i} ] && ip link set dev eth${_i} master pnet${_i} up || true
IFACES
done
cat >> /etc/network/interfaces <<'IFACES'

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
    postup ip link set nat0 address 00:aa:aa:aa:aa:aa
    up systemctl --no-block restart udhcpd
IFACES
# Mgmt bridge MAC = the physical NIC (eth0) MAC, not systemd's machine-id-derived one.
# jammy's /usr/lib/systemd/network/99-default.link sets MACAddressPolicy=persistent, which
# gives the pnet0 bridge its OWN stable MAC derived from /etc/machine-id instead of eth0's.
# Consequence: at install, DHCP runs on eth0 (NIC MAC) -> lease X; after the first reboot
# DHCP runs on the pnet0 bridge with the machine-id MAC -> the DHCP server sees a brand-new
# client -> the mgmt IP changes (the one-time .NNN -> .NNN+1 jump users hit post-install).
# Override the policy for pnet0 (sorts before 99-default, so it wins): MACAddressPolicy=none
# leaves the MAC unset, so the kernel ADOPTS eth0's MAC when eth0 is enslaved -> the bridged
# DHCP client presents the SAME MAC the installer used -> same lease/IP. Verified on the UKSM
# kernel (a policy=none bridge adopts its port's MAC; a default bridge does not). .link files
# are applied by systemd-udevd, so this works even though systemd-networkd is disabled below.
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/98-pnet0-mac.link <<'LINK'
[Match]
OriginalName=pnet0

[Link]
MACAddressPolicy=none
LINK
mkdir -p /etc/netplan.disabled
mv -f /etc/netplan/*.yaml /etc/netplan.disabled/ 2>/dev/null || true
# Make the handoff DURABLE: tell cloud-init to stop managing the network, otherwise it regenerates
# /etc/netplan/50-cloud-init.yaml on the next boot and fights ifupdown for eth0 (the pnet0 bridge
# port). With this, ifupdown is the single, deterministic owner across reboots (matches real PNetLab).
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'CICFG'
network: {config: disabled}
CICFG
rm -f /etc/netplan/*.yaml 2>/dev/null || true
# MASK (not just disable) systemd-networkd so a cloud-init-regenerated netplan
# can't socket-activate it and steal eth0 back from ifupdown on a later boot
# (the usual cause of "pnet0 + all clouds vanished from the modal").
systemctl disable systemd-networkd.socket systemd-networkd >> "$LOG" 2>&1 || true
systemctl mask systemd-networkd.socket systemd-networkd >> "$LOG" 2>&1 || true
systemctl unmask networking >> "$LOG" 2>&1 || true
systemctl enable networking >> "$LOG" 2>&1 || true
cat > /etc/systemd/system/pnetlab-ovfstartup.service <<'UNIT'
[Unit]
Description=PNetLab OVF startup (bridge tuning, NAT, setcap, ebtables) - replaces the dead Upstart job
After=network-online.target mysql.service docker.service
Wants=network-online.target
ConditionPathExists=/opt/ovf/ovfstartup.sh

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/bin/bash /opt/ovf/ovfstartup.sh
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
UNIT
# MASK (not just disable) the legacy vendor ovfstartup.service so it cannot
# run /opt/ovf/ovfstartup.sh alongside our correctly-ordered replacement;
# systemd cannot mask a regular unit file, so park it with a visible non-unit
# suffix first. Keep an existing /dev/null mask and backup untouched on reruns.
systemctl disable ovfstartup.service >> "$LOG" 2>&1 || true
_OVF_UNIT=/etc/systemd/system/ovfstartup.service
_OVF_BACKUP="${_OVF_UNIT}.disabled-by-pnetlab-installer"
_OVF_TARGET="$(readlink "$_OVF_UNIT" 2>/dev/null || true)"
if [ -L "$_OVF_UNIT" ] && [ "$_OVF_TARGET" = "/dev/null" ]; then
    : # Already masked; never move the mask or overwrite its preserved backup.
elif [ -e "$_OVF_UNIT" ] || [ -L "$_OVF_UNIT" ]; then
    if [ -e "$_OVF_BACKUP" ] || [ -L "$_OVF_BACKUP" ]; then
        _OVF_STAMP="$(date +%s 2>/dev/null || true)"
        if [ -z "$_OVF_STAMP" ]; then
            _OVF_STAMP=fallback
        fi
        _OVF_BACKUP="${_OVF_BACKUP}.${_OVF_STAMP}"
        while [ -e "$_OVF_BACKUP" ] || [ -L "$_OVF_BACKUP" ]; do
            _OVF_BACKUP="${_OVF_BACKUP}.1"
        done
    fi
    mv "$_OVF_UNIT" "$_OVF_BACKUP" >> "$LOG" 2>&1 || true
fi
if [ ! -L "$_OVF_UNIT" ] || [ "$_OVF_TARGET" != "/dev/null" ]; then
    systemctl mask ovfstartup.service >> "$LOG" 2>&1 || true
fi
systemctl daemon-reload >> "$LOG" 2>&1 || true
systemctl enable pnetlab-ovfstartup.service >> "$LOG" 2>&1 || true
echo "$(dmidecode --string system-uuid 2>/dev/null)" > /opt/ovf/.configured 2>/dev/null || true

# Cloud bridge DEVICES (pnet0..9 + nat0) — created BEFORE ifupdown so the GUI's
# listNetworkTypes() sysfs scan always finds them and the modal always lists the
# clouds, even if the eth0/netplan handoff later fails to address/enslave them.
# Deb ships /opt/ovf/pnet-bridges.sh; this oneshot just runs it early. ovfstartup
# also calls it (belt-and-suspenders for boxes predating this unit).
cat > /etc/systemd/system/pnetlab-pnet-bridges.service <<'UNIT'
[Unit]
Description=PNetLab cloud bridge devices (pnet0-9 + nat0) — exist regardless of ifupdown
DefaultDependencies=no
After=systemd-udev-settle.service
Before=networking.service network-pre.target
Wants=network-pre.target
ConditionPathExists=/opt/ovf/pnet-bridges.sh

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /opt/ovf/pnet-bridges.sh

[Install]
WantedBy=multi-user.target
UNIT
chmod +x /opt/ovf/pnet-bridges.sh 2>/dev/null || true
systemctl daemon-reload >> "$LOG" 2>&1 || true
systemctl enable pnetlab-pnet-bridges.service >> "$LOG" 2>&1 || true

# Bake a boot-time strip of the xml.cisco.com null-route into the deb-provided ovfstartup.sh
# (runs every boot via pnetlab-ovfstartup.service). Belt-and-suspenders with the postinst neuter
# in [7/14]: even if some future dpkg op re-arms or re-adds the line, it is removed on every boot
# before any IOL node can start. See the IOS-XE IOL note in [7/14].
OVF=/opt/ovf/ovfstartup.sh
if [ -f "$OVF" ] && ! grep -q 'IOS-XE IOL fix: keep xml.cisco.com OUT' "$OVF"; then
    cat >> "$OVF" <<'OVFEOF'

# IOS-XE IOL fix: keep xml.cisco.com OUT of /etc/hosts. The pnetlab deb postinst null-routes it
# (127.0.0.127) to 'disable phone-home' for OLD IOU, but that martian makes NEW x86_64 IOS-XE IOL
# (L2/L3) ABORT at boot in BinOS smart-licensing. Strip it every boot so it can never persist.
sed -i '/[[:space:]]xml\.cisco\.com/d' /etc/hosts 2>/dev/null || true
OVFEOF
    log "  baked xml.cisco.com boot-strip into ovfstartup.sh"
fi

# ── Backend tuning (OPcache, InnoDB, sysctl, apache worker recycling, XRd inotify) ────────────
log "Applying backend tuning (opcache/innodb/sysctl/apache/xrd-inotify)..."
# OPcache for the SAPI that actually serves the engine on 26.04 = php8.5-fpm (mpm_event;
# mod_php is inactive). The old hardcoded /etc/php/8.3/apache2 path no longer exists on 26.04
# (php 8.5, fpm) → the cat failed and opcache was never configured. Write to every present
# php8.5 conf.d dir and reload fpm so it takes effect.
for _phpd in /etc/php/8.5/fpm/conf.d /etc/php/8.5/apache2/conf.d /etc/php/8.5/cli/conf.d; do
    [ -d "$_phpd" ] || continue
    cat > "$_phpd/99-pnetlab-opcache.ini" <<'OPC'
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
opcache.revalidate_freq=60
OPC
done
systemctl reload php8.5-fpm >> "$LOG" 2>&1 || systemctl restart php8.5-fpm >> "$LOG" 2>&1 || true
cat > /etc/mysql/mysql.conf.d/99-pnetlab.cnf <<'MYC'
[mysqld]
innodb_buffer_pool_size=512M
innodb_flush_log_at_trx_commit=2
MYC
cat > /etc/sysctl.d/99-pnetlab-tuning.conf <<'SYS'
vm.swappiness=10
# Dirty page-cache caps (absolute bytes, not ratio). The default ratio caps let
# ~20% of a 48 GiB box (~9 GiB) go dirty before a forced writeback — several
# qcow2 guests using cache=writeback can then trigger a multi-second flush storm
# that stalls all node I/O. 256 MiB background-flush threshold / 1 GiB hard
# ceiling smooths I/O under many-node boot/install bursts. Setting *_bytes
# supersedes the corresponding *_ratio.
vm.dirty_background_bytes=268435456
vm.dirty_bytes=1073741824
SYS
# Cisco XRd host requirements (inotify) — needed by xrd-control-plane / xrd-vrouter containers
cat > /etc/sysctl.d/99-xrd.conf <<'SYX'
fs.inotify.max_user_instances=64000
fs.inotify.max_user_watches=65536
SYX
sysctl --system >> "$LOG" 2>&1 || true

# ── I/O scheduler: 'none' for virtual/flash-backed disks ─────────────────────
# The appliance's disk is a hypervisor vdisk (virtio-blk / VMware vSCSI) or NVMe,
# where the host/controller already schedules I/O — an in-guest elevator
# (mq-deadline) only adds latency and CPU. Discriminate the SCSI case by VENDOR
# (VMware/QEMU/Hyper-V), NOT by rotational: VMware vdisks report rotational=1, so
# a rotational guard would both misfire here AND is the wrong signal. Vendor match
# leaves bare-metal SATA/SAS (incl. spinning disks) on mq-deadline. virtio-blk is
# always virtual; NVMe already defaults to none (set explicitly for clarity).
cat > /etc/udev/rules.d/60-pnetlab-ioscheduler.rules <<'IOSCHED'
# PNetLab: no-op I/O scheduler for hypervisor/flash-backed virtual disks.
ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{vendor}=="VMware*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{vendor}=="QEMU*",   ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{vendor}=="Msft*",   ATTR{queue/scheduler}="none"
IOSCHED
udevadm control --reload >> "$LOG" 2>&1 || true
udevadm trigger --subsystem-match=block --action=change >> "$LOG" 2>&1 || true

sed -i 's/MaxConnectionsPerChild[[:space:]]*0/MaxConnectionsPerChild   1000/' /etc/apache2/mods-available/mpm_prefork.conf 2>/dev/null || true
systemctl restart mysql >> "$LOG" 2>&1 || warn "mysql restart (innodb tuning) failed"

# ── Restart web stack ─────────────────────────────────────────────────────────
# Slice-5 cutover: the web console is the default in-browser console, so Tomcat is
# stripped — stop + disable + mask tomcat9 (frees :8080). guacd + pnet-guac-lite
# (the RDP lane) stay up. Reversible: `systemctl unmask --now tomcat9` + move the
# parked war from webapps.disabled/ back into webapps/.
log "Restarting apache2; masking tomcat9 (web console default, Tomcat stripped)..."
systemctl restart apache2 >> "$LOG" 2>&1 || warn "apache2 restart failed"
systemctl stop tomcat9 >> "$LOG" 2>&1 || true
systemctl disable tomcat9 >> "$LOG" 2>&1 || true
systemctl mask tomcat9 >> "$LOG" 2>&1 || warn "tomcat9 mask failed"

# ── Prune desktop/hardware daemons unused by a headless lab appliance ─────────
# Reclaims ~150-250 MB idle RAM + trims boot time (apt-daily-upgrade alone was
# ~49 s of boot blame on the gate). MASK the clearly-inapplicable ones so nothing
# can dbus/socket-activate them back:
#   fwupd         — firmware updater; airgapped VM, no firmware to flash
#   packagekit    — background package mgmt D-Bus service; pnetlab uses apt/dpkg directly
#   ModemManager  — cellular modem manager; no WWAN hardware
#   multipathd    — dm-multipath for SAN; single-vdisk appliance never uses it
# udisks2 is only DISABLED (not masked): pnetlab manages images via qemu-img, not
# udisks, but it is D-Bus-activatable, so disabling stops the boot autostart while
# leaving an on-demand safety valve if some flow ever invokes it.
log "Masking unused desktop/hardware daemons (fwupd/packagekit/ModemManager/multipathd; udisks2 disabled)..."
for _svc in fwupd packagekit ModemManager multipathd; do
    systemctl disable --now "$_svc" >> "$LOG" 2>&1 || true
    systemctl mask "$_svc" >> "$LOG" 2>&1 || true
done
systemctl disable --now udisks2 >> "$LOG" 2>&1 || true
# Disable periodic apt work + MOTD phone-home: an airgapped appliance must never
# auto-upgrade under itself, and these timers add boot/wakeup cost for no benefit.
#
# MASK, not just disable: a dpkg upgrade of apt / unattended-upgrades re-runs
# deb-systemd-helper in its postinst, which happily re-ENABLES a merely-disabled
# timer. Masking is the only state that survives a package upgrade.
#
# This matters beyond boot cost. An unattended upgrade that restarts a service
# can take running labs down with it: older boxes put QEMU in the legacy shared
# /cpulimit cgroup and the unit used KillMode=control-group. The new per-node
# transient scopes are independent of broker/service restarts; the upgrade
# migration moves legacy guests uncapped before removing that shared group.
log "Masking periodic apt work + MOTD phone-home (an appliance must not auto-upgrade under itself)..."
for _tmr in apt-daily.timer apt-daily-upgrade.timer motd-news.timer; do
    systemctl disable --now "$_tmr" >> "$LOG" 2>&1 || true
    systemctl mask "$_tmr" >> "$LOG" 2>&1 || true
done
# unattended-upgrades.service is a SEPARATE unit from the timers above and ships
# enabled; disabling the timers alone leaves it active (it also runs on shutdown).
systemctl disable --now unattended-upgrades.service >> "$LOG" 2>&1 || true
systemctl mask unattended-upgrades.service >> "$LOG" 2>&1 || true
# Belt-and-braces at the config layer, in case a timer is ever unmasked by hand:
# apt.systemd.daily reads APT::Periodic::*. Ship our OWN file rather than editing
# /etc/apt/apt.conf.d/{10periodic,20auto-upgrades} — those are conffiles of the
# unattended-upgrades package, so editing them invites a dpkg conffile prompt on
# upgrade. apt reads apt.conf.d in lexical order and last wins, so 99- beats both.
cat > /etc/apt/apt.conf.d/99pnetlab-no-auto-upgrade <<'APTEOF'
// PNetLab appliance: never auto-update or auto-upgrade under a running lab.
// An unattended upgrade that restarts a service can kill every running qemu node
// (legacy guests were in cpulimit.service's shared cgroup; current guests use
// independent pnetlab-qemu-*.scope units). Operators apply updates deliberately,
// via the bundle's patch script.
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APTEOF
chmod 0644 /etc/apt/apt.conf.d/99pnetlab-no-auto-upgrade

# ── Silence systemd 259 OSC 3008 "context" prompt markers ─────────────────────
# Ubuntu 26.04 ships systemd 259, whose /usr/lib/systemd/profile.d/80-systemd-osc-
# context.sh makes bash emit OSC 3008 "Hierarchical Context Signalling" escapes at
# every prompt (session machineid/user/host/bootid/pid/cwd + per-command exit).
# Terminals that don't implement OSC 3008 — SecureCRT, older PuTTY, serial/console
# scrapes, xterm.js — render them as literal garbage on the shell line, e.g.
#   ...;end=<uuid>;exit=failure;status=108;start=<uuid>;...;type=shell;cwd=/root
# Divert the emitter out of the profile.d *.sh glob so no login sources it. Using
# dpkg-divert (not rm/blank) keeps it disabled across any future systemd reinstall.
# Reversible: dpkg-divert --rename --remove /usr/lib/systemd/profile.d/80-systemd-osc-context.sh
_OSC=/usr/lib/systemd/profile.d/80-systemd-osc-context.sh
if [ -e "$_OSC" ] && ! dpkg-divert --list "$_OSC" 2>/dev/null | grep -q .; then
    log "Diverting systemd OSC 3008 context prompt emitter (garbles non-OSC-3008 terminals)..."
    dpkg-divert --quiet --rename --divert "${_OSC}.disabled" "$_OSC" >> "$LOG" 2>&1 \
        || warn "osc-context divert failed"
fi

# ── Hostname + FQDN (kills the 15s www-data sudo DNS hang) ─────────────────────
echo 'pnetlab' > /etc/hostname
hostname pnetlab 2>/dev/null || true
# sudo canonicalizes the hostname via getaddrinfo(AI_CANONNAME). With a `search <domain>` in
# resolv.conf (VMware-NAT pushes `localdomain`) glibc tries `<host>.<domain>` FIRST; on an
# OFFLINE box that lookup hits systemd-resolved (127.0.0.53) and BLOCKS 3x5s = 15s before
# falling back to the bare name. EVERY www-data `sudo` (node boot, docker, scand) then paid
# 15s. Make the FQDN resolve from FILES (no DNS) for localdomain + any current search domains.
HN=pnetlab
for d in localdomain $(sed -n 's/^search[[:space:]]*//p' /etc/resolv.conf 2>/dev/null); do
    grep -qiE "[[:space:]]${HN}\.${d}([[:space:]]|\$)" /etc/hosts || \
        echo "127.0.1.1 ${HN}.${d} ${HN}" >> /etc/hosts
done

# Belt-and-suspenders for the store's phone-home removal: null-route the (now-disabled) pnetlab.com
# center/telemetry hosts server-side. The store already refuses them at Query::make() + points all
# APP_* at disabled.invalid; this catches any server-side literal reference too.
for _h in user.pnetlab.com authen.pnetlab.com uploader.pnetlab.com admin.pnetlab.com cloud.pnetlab.com; do
    grep -qiE "[[:space:]]${_h}([[:space:]]|\$)" /etc/hosts || echo "127.0.0.1 ${_h}" >> /etc/hosts
done

# ── Cisco IOU license (iourc) ─────────────────────────────────────────────────
# IOU is host-locked to hostid+hostname, so a fixed/shipped iourc is wrong on every other box ->
# IOL nodes fail the license check and die at boot. Generate the correct iourc for THIS host with
# the py3 keygen (stock CiscoIOUKeygen.py is python2 and crashes on python3). It deliberately does
# NOT add the xml.cisco.com phone-home null-route.
# ORDER MATTERS: run this AFTER the /etc/hosts FQDN block above. The keygen's hostid is IP-derived
# (glibc gethostid -> gethostbyname(hostname)); without the `127.0.1.1 pnetlab` line the bare
# hostname resolves to the transient DHCP mgmt IP, baking a key tied to an address that changes on
# the first ovf boot -> the stable runtime hostid (127.0.1.1) never matches. With the line present,
# hostid is the permanent 127.0.1.1 regardless of the mgmt IP, so the key stays valid after reboot.
if [ -f /opt/unetlab/addons/iol/bin/CiscoIOUKeygen3.py ]; then
    chmod 0755 /opt/unetlab/addons/iol/bin/CiscoIOUKeygen3.py 2>/dev/null || true
    if python3 /opt/unetlab/addons/iol/bin/CiscoIOUKeygen3.py >>"$LOG" 2>&1; then
        chmod 0644 /opt/unetlab/addons/iol/bin/iourc 2>/dev/null || true
        log "  Generated Cisco IOU license (iourc) for host '$(hostname)' (hostid $(hostid))"
    else
        warn "  CiscoIOUKeygen3.py failed — IOL nodes will not be licensed"
    fi
fi

# ── Verification ──────────────────────────────────────────────────────────────
log ""
log "=== Verification ==="
check() { local d="$1" c="$2" e="$3" r; r=$(eval "$c" 2>/dev/null || true)
    echo "$r" | grep -q "$e" && log "  OK  $d" || warn "FAIL $d (got: ${r:0:60})"; }
check "php default 8.3"        "php -v | head -1"                              "PHP 8.3"
check "php8.5-fpm active (B2)" "systemctl is-active php8.5-fpm"                "active"
check "mod_php absent (B2)"    "apache2ctl -M 2>/dev/null | grep -q php8 && echo loaded || echo absent" "absent"
# Store is retired (item C6, store decommission): /store/ must be denied in
# its entirety (no more /store/public/ exception) and /login/ (the engine-
# native login) is the thing that must serve now.
check "store .env blocked"     "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/store/.env" "40"
check "store/ denied"          "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/store/" "40"
check "login/ serves"          "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/login/" "200"
check "dir listing off"        "curl -sk https://127.0.0.1/themes/ | grep -qi 'Index of' && echo on || echo off" "off"
check "nosniff header"         "curl -sk -D - -o /dev/null https://127.0.0.1/login/ | tr -d '\r'" "X-Content-Type-Options: nosniff"
check "http2 enabled"          "apache2ctl -M 2>/dev/null | grep -o http2_module" "http2_module"
check "apache2 running"        "systemctl is-active apache2"                   "active"
check "mysql running"          "systemctl is-active mysql"                     "active"
check "guacd 1.6.0"            "/usr/local/sbin/guacd -v 2>&1 | head -1"       "1.6.0"
check "qemu 9.2 runs"          "/opt/qemu-9.2.4/bin/qemu-system-x86_64 --version" "9.2"
check "qemu default is 9.2"    "readlink /opt/qemu"                                "qemu-9.2.4"
check "legacy qemu loads"      "/opt/qemu-5.2.0/bin/qemu-system-x86_64 --version" "5.2"
check "sudoers grant retired (B7)" "test -f /etc/sudoers.d/unetlab && echo present || echo absent" "absent"
check "templates a+rX"         "stat -c '%A' $HTML/templates"                  "r-x"
check "login route present"    "grep -c 'post(\"/api/auth\"' $HTML/api.php"    "1"
# DB checks: Noble root@localhost is NOT auth_socket (it's password auth after step 14 set
# root's pw to 'pnetlab'), so a bare `mysql` as root is denied -> pass -uroot -ppnetlab.
check "admin user exists"      "mysql -uroot -ppnetlab -N -e \"SELECT username FROM pnetlab_db.users WHERE username='admin'\"" "admin"
check "ctrl_version 8.2.0"     "mysql -uroot -ppnetlab -N -e \"SELECT control_value FROM pnetlab_db.control WHERE control_name='ctrl_version'\"" "8.2.0"
check "pnetlab configured"     "dpkg -s pnetlab 2>/dev/null | grep Status"     "ok installed"
check "users.user_max_cpu col" "mysql -uroot -ppnetlab -N -e \"SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='pnetlab_db' AND table_name='users' AND column_name='user_max_cpu'\"" "1"
check "www-data sudo revoked (B7)" "sudo -ln -U www-data 2>&1 | grep -q 'not allowed' && echo revoked || echo granted" "revoked"
check "sudo FQDN (no DNS hang)" "grep -c 'pnetlab.localdomain' /etc/hosts"      "1"
check "top works (procps)"     "top -bn1 -w512 >/dev/null 2>&1 && echo ok"     "ok"
check "login->whoami 200"      "curl -s -c /tmp/_vrf -X POST http://127.0.0.1/api/auth -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"pnet\"}' >/dev/null; curl -s -b /tmp/_vrf http://127.0.0.1/api/auth" "User has been loaded"
# Store is retired (item C6, store decommission): the store deployment/
# runtime-dir/scand/login/menu/devices checks above (Laravel-specific) are
# obsolete and removed. The bare-host redirect now lands on /main/, not the
# store menu.
check "/ routes to main"       "curl -s -o /dev/null -w '%{url_effective}' -L http://127.0.0.1/" "main/"
check "net hang hardening"     "test -f /etc/systemd/system/networking.service.d/10-timeout.conf && grep -c 'systemctl --no-block restart udhcpd' /etc/network/interfaces" "1"
check "iol tmp group unl"      "stat -c '%G' /opt/unetlab/tmp"                 "unl"
check "no xml.cisco.com route" "grep -c 'xml.cisco.com' /etc/hosts || echo 0"  "0"
check "xml injector neutered"  "grep -cE '(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+xml\.cisco\.com' /var/lib/dpkg/info/pnetlab.postinst || echo 0" "0"
check "xml boot-strip baked"   "grep -c 'IOS-XE IOL fix: keep xml.cisco.com OUT' /opt/ovf/ovfstartup.sh" "1"
check "apt state clean"        "apt-get check 2>&1 && echo clean"              "clean"
# session-4 bakes: theme, ovf-on-boot, backend tuning. The store's phone-home
# guards (domain.php/Query.php), .env APP_DEBUG, green-theme-wired-into-blade,
# and "Download Labs hidden" checks are all Laravel-store-specific and are
# now obsolete — the store is retired (item C6, store decommission).
check "chinese lang removed"    "test ! -d $HTML/language/China && ls $HTML/language" "English"
check "ishare2 www-data owned"  "stat -c '%U' $HTML/ishare2"                    "www-data"
check "image store catalog 200" "curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1/ishare2/api.php?action=catalog'" "200"
check "iol iourc valid for host" "python3 $HTML/../addons/iol/bin/CiscoIOUKeygen3.py --print 2>/dev/null | grep -oE '[0-9a-f]{16}' | grep -qFf - /opt/unetlab/addons/iol/bin/iourc && echo ok" "ok"
check "https (clipboard ctx)"   "test -f /etc/ssl/certs/pnetlab-selfsigned.crt && a2query -s pnetlab-ssl >/dev/null 2>&1 && curl -k -s -o /dev/null -w '%{http_code}' https://127.0.0.1/ | grep -qE '200|301|302' && echo ok" "ok"
check "deb :443 vhost off"      "test ! -e /etc/apache2/sites-enabled/pnetlabs.conf && echo ok" "ok"
check "http ext->https redirect" "a2query -m rewrite >/dev/null 2>&1 && grep -q 'RewriteRule .*https://%{HTTP_HOST}' /etc/apache2/sites-available/pnetlab.conf && echo ok" "ok"
check "docker tmpl ram 1024"     "grep -hE '^ram:' $HTML/templates/intel/docker.yml $HTML/templates/amd/docker.yml | grep -c 1024" "2"
check "merged device cfg scripts" "ls $HTML/../config_scripts/config_srlinux.py $HTML/../config_scripts/config_ceos.py >/dev/null 2>&1 && echo ok" "ok"
check "ceos provisioner ready"   "test -x $HTML/../config_scripts/ceos_provision.sh && grep -q 'ceos_provision.sh' $HTML/../config_scripts/docker_image_watcher.sh && echo ok" "ok"
check "ceos console bridged"     "grep -c 'wrappers/docker_console.sh' $HTML/devices/docker/device_ceos.php" "4"
check "iou_import present"       "test -x $HTML/../scripts/iou_import && echo ok" "ok"
check "iol nvram pre-bake"       "grep -c 'this->pnqBakeNvram' $HTML/devices/iol/device_iol.php" "3"
check "iol initial-config = 1"   "grep -A2 '^Initial_startup_config:' $HTML/templates/device/iol.yml | grep -c 'value: 1'" "1"
check "srlinux img-ref strip"    "grep -c 'dockerImage' $HTML/devices/docker/device_srlinux.php" "2"
check "ceos img-ref strip"       "grep -c 'dockerImage' $HTML/devices/docker/device_ceos.php" "2"
check "c8000vcm deps complete"   "test -f $HTML/templates/intel/c8000vcm.yml -a -f $HTML/../config_scripts/config_c8000vcm.py -a -f $HTML/../config_scripts/prep_c8000vcm.sh -a -d /opt/qemu-4.1.0 && command -v mkisofs >/dev/null && python3 -c 'import pexpect' && echo ok" "ok"
check "ovfstartup svc enabled"  "systemctl is-enabled pnetlab-ovfstartup.service 2>/dev/null" "enabled"
check "legacy ovf svc masked"   "systemctl is-enabled ovfstartup.service 2>/dev/null" "masked"
check "net.ifnames=0 (grub)"    "grep -q 'net.ifnames=0' /etc/default/grub && echo ok" "ok"
check "nat0 + pnet0 in ifaces"  "grep -cE '^auto nat0|^allow-hotplug pnet0' /etc/network/interfaces" "2"
check "pnet0 mac=NIC (.link)"   "grep -q 'MACAddressPolicy=none' /etc/systemd/network/98-pnet0-mac.link 2>/dev/null && echo ok" "ok"
check "cloud NIC enslave (9)"   "grep -c 'master pnet' /etc/network/interfaces"                "9"
check "netplan handed off"      "ls /etc/netplan/*.yaml 2>/dev/null | wc -l"    "0"
check "cloud-init net disabled" "grep -hq 'config: disabled' /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg && echo ok" "ok"
check "networkd masked"         "systemctl is-enabled systemd-networkd 2>/dev/null" "masked"
check "pnet-bridges script"     "test -x /opt/ovf/pnet-bridges.sh && echo ok" "ok"
check "pnet-bridges svc enabled" "systemctl is-enabled pnetlab-pnet-bridges.service 2>/dev/null" "enabled"
check "ovfstartup calls bridges" "grep -c 'pnet-bridges.sh' /opt/ovf/ovfstartup.sh" "1"
check "net.ifnames=0 (grub.cfg)" "grep -q 'net.ifnames=0' /boot/grub/grub.cfg && echo ok" "ok"
check "opcache tuned"           "test -f /etc/php/8.5/fpm/conf.d/99-pnetlab-opcache.ini && echo ok" "ok"
check "innodb buffer 512M"      "mysql -uroot -ppnetlab -N -e 'SELECT @@innodb_buffer_pool_size/1024/1024'" "512"
check "xrd inotify tuned"       "sysctl -n fs.inotify.max_user_instances"       "64000"
check "xrd config_script"       "test -x /opt/unetlab/config_scripts/config_xrd.py && echo ok" "ok"
check "xrd prep_script"         "test -x /opt/unetlab/config_scripts/prep_xrd.sh && echo ok"   "ok"
check "xrd firstboot.cfg"       "test -f /opt/unetlab/addons/docker/XRD/firstboot.cfg && echo ok" "ok"
check "docker-img watcher svc"  "systemctl is-enabled pnetlab-docker-image-watcher.service"   "enabled"
check "docker console bridge"   "test -x /opt/unetlab/wrappers/docker_console.sh -a -f /opt/unetlab/wrappers/docker_console.py && echo ok" "ok"
check "vios cfg-export hardened" "grep -c 'ANY exec prompt' /opt/unetlab/config_scripts/config_vios.py" "1"
check "vpcs icon = svg"         "grep -h '^icon:' /opt/unetlab/html/templates/intel/vpcs.yml" "icon: PC-2D-Desktop-Generic-S.svg"
check "pnetlab.com null-route"  "grep -c 'user.pnetlab.com' /etc/hosts"         "1"
# web-console (Slice 1 telnet + Slice 2 vnc; opt-in alongside Guacamole)
check "webconsole frontend"     "test -f $HTML/console/console.html -a -f $HTML/console/token_mint.php && echo ok" "ok"
check "captures aggregator"     "test -f $HTML/console/captures.html && echo ok" "ok"
check "webconsole xterm vendored" "test -f $HTML/console/vendor/xterm.js && echo ok" "ok"
check "webconsole novnc vendored" "test -f $HTML/console/vendor/novnc/core/rfb.js && echo ok" "ok"
check "webconsole bridge deps"  "python3 -c 'import websockets,telnetlib3' 2>/dev/null && echo ok" "ok"
check "console mux active"      "systemctl is-active pnet-console-mux.service" "active"
check "console mux on 8022"     "ss -ltn 2>/dev/null | grep 127.0.0.1:8022 || echo none" "8022"
check "shell bridge present"    "test -f /opt/pnet-webconsole/backend/shell_ws_bridge.py && echo ok" "ok"
check "shell bridge active"     "systemctl is-active pnet-shell-bridge.service" "active"
check "shell bridge on 8023"    "ss -ltn 2>/dev/null | grep 127.0.0.1:8023 || echo none" "8023"
check "shell wss route (ssl)"   "grep -o '127.0.0.1:8023' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:8023"
check "http bridge present"     "test -f /opt/pnet-webconsole/backend/http_ws_bridge.py && echo ok" "ok"
check "http bridge active"      "systemctl is-active pnet-http-bridge.service" "active"
check "http bridge on 8025"     "ss -ltn 2>/dev/null | grep 127.0.0.1:8025 || echo none" "8025"
check "http console route (ssl)" "grep -o '127.0.0.1:8025' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:8025"
check "http grant store dir"    "test -d /dev/shm/pnet-http-tokens && echo ok" "ok"
check "console mux on 6080"     "ss -ltn 2>/dev/null | grep 127.0.0.1:6080 || echo none" "6080"
check "token janitor timer"     "systemctl is-active pnet-token-janitor.timer"  "active"
check "telnet wss route (ssl)"  "grep -o '127.0.0.1:8022' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:8022"
check "vnc wss route (ssl)"     "grep -o '127.0.0.1:6080' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:6080"
check "webconsole quickbar"     "grep -c 'action-openconsole-all' $HTML/themes/default/index.html" "1"
check "console_config out of webroot" "test -f /etc/pnet-webconsole/console_config.php && echo ok" "ok"
# web-console Slice 3 (rdp lane: guacamole-lite -> guacd, no Tomcat)
check "webconsole guac vendored"  "test -f $HTML/console/vendor/guacamole/guacamole-common.min.js && echo ok" "ok"
check "rdp lane enabled (html)"   "grep -c 'guacamole-common.min.js' $HTML/console/console.html" "1"
check "guac-lite deps vendored"   "test -d /opt/pnet-webconsole/backend/node_modules/guacamole-lite && echo ok" "ok"
check "node runtime present"      "command -v node >/dev/null && echo ok" "ok"
check "guac.env key 32 bytes"     "awk -F= '/^GUAC_CRYPT_KEY=/{print length(\$2)}' /etc/pnet-webconsole/guac.env" "32"
check "console_config readable by www-data" "sudo -u www-data php -r \"require '/etc/pnet-webconsole/console_config.php'; echo 'readable';\"" "readable"
check "guac key php==env (www-data)" "[ \"\$(. /etc/pnet-webconsole/guac.env; echo \$GUAC_CRYPT_KEY)\" = \"\$(sudo -u www-data php -r \"require '/etc/pnet-webconsole/console_config.php'; echo GUAC_CRYPT_KEY;\")\" ] && echo match" "match"
check "guac-lite active"          "systemctl is-active pnet-guac-lite.service" "active"
check "guac-lite on 8081"         "ss -ltn 2>/dev/null | grep 127.0.0.1:8081 || echo none" "8081"
check "guac wss route (ssl)"      "grep -o '127.0.0.1:8081' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:8081"
# lab-state push server (Phase 1: live topology node status over wss /labstate/)
check "labstated active"          "systemctl is-active pnetlab-labstated.service" "active"
check "labstated on 8024"         "ss -ltn 2>/dev/null | grep 127.0.0.1:8024 || echo none" "8024"
check "labstate wss route (ssl)"  "grep -o '127.0.0.1:8024' /etc/apache2/sites-available/pnetlab-ssl.conf | head -1" "127.0.0.1:8024"
check "labstate token mint"       "test -f $HTML/pnq-labstate-token.php && echo ok" "ok"
check "labstate producer (cli)"   "test -f $HTML/pnq-nodestate.php && echo ok" "ok"
check "labstate client wired"     "grep -c 'pnetlab-labstate-client.js' $HTML/themes/default/index.html" "1"

UPDATE_ENROLLMENT_STATUS=disabled
if [ "$UPDATE_ENROLLMENT" = unspecified ] && [ -t 0 ]; then
    # stop_spinner first: the step-14 spinner_loop background process redraws
    # its `\r`-anchored progress line once a second, which otherwise erases
    # this prompt within ~1s of it being printed -- the operator then sees
    # what looks like a frozen "step 14/14" progress bar while the script is
    # actually blocked on a read() for a prompt they never saw (observed
    # hanging 2+ hours on an unattended console before this fix).
    stop_spinner
    printf 'Enable online update checks from codeberg.org? [y/N] '
    # Bounded: an attended console gets a real prompt; an unattended one
    # (console left running, nobody watching stdin) times out to the same
    # safe default as non-interactive instead of hanging indefinitely.
    if IFS= read -r -t 30 update_answer; then
        :
    else
        update_answer=
        printf '\n(no input after 30s, defaulting to No)\n'
    fi
    case $update_answer in
        y|Y) UPDATE_ENROLLMENT=enable ;;
        *)   UPDATE_ENROLLMENT=disable ;;
    esac
elif [ "$UPDATE_ENROLLMENT" = unspecified ]; then
    UPDATE_ENROLLMENT=disable
fi

if [ "$UPDATE_ENROLLMENT" = enable ]; then
    log "Enrolling in online update checks from codeberg.org..."
    if [ -x /usr/sbin/pnetlab-update ] && \
       /usr/sbin/pnetlab-update enroll >> "$LOG" 2>&1; then
        UPDATE_ENROLLMENT_STATUS=enrolled
        log "Online update enrollment completed."
    else
        UPDATE_ENROLLMENT_STATUS=failed
        warn "======================================================================"
        warn "ONLINE UPDATE ENROLLMENT FAILED; the appliance installation is complete."
        warn "Retry enrollment later with: sudo pnetlab-update enroll"
        warn "======================================================================"
    fi
else
    log "Online update enrollment disabled."
fi

finish_progress
log ""
log "=== Installation complete ==="
case $UPDATE_ENROLLMENT_STATUS in
    enrolled) log "Online updates: enrolled." ;;
    disabled) log "Online updates: disabled." ;;
    failed)   log "Online updates: enrollment failed (retry: sudo pnetlab-update enroll)." ;;
esac
log "Reboot recommended to activate the KSM kernel (6.12.92-pnetlab-ksm-1)."
log "After reboot, browse to http://<machine-ip>  (login: admin / pnet, offline mode)."
log "Reboot also activates net.ifnames=0 (NIC->eth0) + pnetlab-ovfstartup.service, which builds"
log "pnet0 (mgmt) + pnet1..9 (cloud) + nat0 (NAT cloud, udhcpd + MASQUERADE). pnet0 now adopts the"
log "eth0 NIC MAC (98-pnet0-mac.link), so the mgmt IP is PRESERVED across the bridge handoff."
log "Cloud1->eth1 (2nd VM NIC), Cloud2->eth2, ... map"
log "automatically when those NICs exist (guarded post-up; 1-NIC boxes still boot)."
log "Full log: $LOG"

if [ "$DO_REBOOT" = "1" ]; then
    log "Rebooting in 5 seconds (pass --no-reboot to skip)..."
    systemctl stop apache2 >> "$LOG" 2>&1 || true
    sleep 5
    reboot
fi
