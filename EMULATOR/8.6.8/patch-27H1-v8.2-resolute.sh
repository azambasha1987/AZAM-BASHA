#!/bin/bash
# patch-27H1-v8.2-resolute.sh — apply the latest PNetLab 27H1 v8.2 fixes to an already-installed
# box WITHOUT a full reinstall. Run it from inside an extracted bundle
# (pnetlab-27H1-v8.2-resolute/), as root:
#
#       cd pnetlab-27H1-v8.2-resolute && sudo bash patch-27H1-v8.2-resolute.sh
#
# It upgrades the pnetlab package (pnetlab-store + pnetlab-webconsole are retired)
# from the bundle's local apt repo and restarts the affected services. Since
# 6.8.54, it also needs the normal Ubuntu mirrors for python3-httpx and
# python3-websockets; this patch path therefore requires mirror connectivity.
# The debs are the same fully-built, smoke-tested artifacts the installer uses,
# so this is identical to what a fresh install ships — no in-place source edits.
#
# Fixes delivered by 6.7.21 over earlier builds:
#   * SECURITY: auth bypass — any username + the admin password logged in
#     (AND condition groups were compiled to OR in the store query builder)
#   * Workspace lab import (CSP regression: upload posted without 'path')
#   * Link quality (jitter/latency/loss/rate) + per-interface VLAN — silently
#     ignored since B7 dropped www-data's sudo (now via the privilege broker)
#   * Non-html5 double-click opens the native telnet/ssh/vnc console
#   * Logout entry invisible (dark-on-dark) in the main-page account menu
#
# Idempotent. After it runs, hard-refresh the browser (Ctrl+Shift+R).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBS_DIR="$SCRIPT_DIR/pnetlab-debs"

LIST=/etc/apt/sources.list.d/pnetlab-bundle.list
cleanup_bundle_source() {
    # A failed preflight must not strand a source pointing at a bundle that may
    # disappear as soon as the operator leaves the extracted bundle directory.
    rm -f "$LIST" 2>/dev/null || true
}
trap cleanup_bundle_source EXIT

[ "$(id -u)" = "0" ] || { echo "ERROR: run as root (sudo bash patch-27H1-v8.2-resolute.sh)"; exit 1; }
[ -d "$DEBS_DIR" ] || { echo "ERROR: pnetlab-debs/ not found next to this script — run it from inside an extracted bundle"; exit 1; }
[ -f "$DEBS_DIR/Packages.gz" ] || { echo "ERROR: $DEBS_DIR has no apt index (Packages.gz)"; exit 1; }

# 6.8.54 added these two Ubuntu-archive dependencies to the engine deb. Refresh
# the box's normal sources first so apt can see them. This is deliberately a
# separate update from the restricted bundle-only refresh below: the latter
# uses Dir::Etc overrides and cannot refresh Ubuntu's archive indexes.
cleanup_bundle_source
if ! apt-get update -q >/dev/null 2>&1; then
    echo "ERROR: this patch path needs connectivity to the Ubuntu mirrors to refresh the indexes for python3-httpx and python3-websockets; pnetlab was not upgraded." >&2
    exit 1
fi

echo "deb [trusted=yes] file:$DEBS_DIR ./" > "$LIST"
# Keep the bundle-only refresh: it makes the local pnetlab deb visible without
# replacing or cleaning the normal Ubuntu indexes refreshed above. Both updates
# are required: one supplies the engine's Python runtime, the other supplies
# the pnetlab package itself.
if ! apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 >/dev/null 2>&1; then
    echo "ERROR: the local PNetLab bundle apt index could not be refreshed; pnetlab was not upgraded. Check pnetlab-debs/ and Packages.gz, then retry." >&2
    exit 1
fi

ENGINE_DEPS=(python3-httpx python3-websockets)
echo "Installing engine runtime dependencies: ${ENGINE_DEPS[*]}"
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${ENGINE_DEPS[@]}" >/dev/null 2>&1; then
    echo "ERROR: this patch path needs connectivity to the Ubuntu mirrors to install python3-httpx and python3-websockets; pnetlab was not upgraded." >&2
    exit 1
fi

# pnetlab is apt-held by the installer; allow the held bump. pnetlab-store and
# pnetlab-webconsole are RETIRED (store decommission / webconsole fold-in): the
# store deb is no longer built (apt-get would abort under set -euo pipefail with
# "unable to locate package pnetlab-store"), and the engine deb's Conflicts/
# Replaces cleanly removes any lingering pnetlab-webconsole on this install — so
# do NOT list either here.
PKGS="pnetlab"

# pnetlab-vpcs (the netprobe VPCS replacement, shipped since 6.8.58) must be
# named EXPLICITLY. pnetlab Depends on it, but UNVERSIONED — so apt pulls it in
# on a box that never had it and is then satisfied forever, leaving an already-
# installed older copy untouched. Without this line every netprobe fix after the
# first is stranded on the patch path: 6.8.59 patched a box to engine 6.8.59
# while pnetlab-vpcs sat at 6.8.58. Guarded on the deb actually being in the
# bundle so a bundle that predates it warns instead of aborting under set -e.
if ls "$DEBS_DIR"/pnetlab-vpcs_*.deb >/dev/null 2>&1; then
    PKGS="$PKGS pnetlab-vpcs"
else
    echo "WARNING: pnetlab-vpcs_*.deb not found in pnetlab-debs/ — VPCS will not be upgraded by this patch."
fi

# pnetlab-qemu ships alongside the engine in every bundle but, like
# pnetlab-vpcs above, is UNVERSIONED in pnetlab's Depends — so it must be
# named explicitly or an already-installed older copy is never bumped.
# Content-free today (changelog/copyright only), but the release always pins
# a version for it and the patch path should honor that pin like every other
# shipped deb. Guarded the same way as pnetlab-vpcs.
if ls "$DEBS_DIR"/pnetlab-qemu_*.deb >/dev/null 2>&1; then
    PKGS="$PKGS pnetlab-qemu"
else
    echo "WARNING: pnetlab-qemu_*.deb not found in pnetlab-debs/ — pnetlab-qemu will not be upgraded by this patch."
fi

echo "Upgrading: $PKGS"
# --force-confold: a box can have a conffile (e.g. ovfstartup.service) that was
# deleted by a script/operator since install; dpkg then prompts interactively
# even under DEBIAN_FRONTEND=noninteractive and this patch has no tty to answer
# it, so it hangs/aborts. Keep the existing file in that case (same default the
# prompt itself offers) rather than blocking the upgrade.
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-change-held-packages \
    -o Dpkg::Options::="--force-confold" $PKGS

# Verify the imports the pnet-http-bridge and web-console bridge actually use;
# a package being marked installed is not enough if Python's runtime path is
# damaged. Missing either module can leave Apache's console proxy at 503.
if python3 -c 'import httpx' >/dev/null 2>&1; then
    echo "Verified: python3 can import httpx."
else
    echo "WARNING: python3 cannot import httpx — pnet-http-bridge may crash-loop; node web consoles and Wireshark captures will show Apache 503."
fi
if python3 -c 'import websockets' >/dev/null 2>&1; then
    echo "Verified: python3 can import websockets."
else
    echo "WARNING: python3 cannot import websockets — the web-console bridge may not start; node web consoles and Wireshark captures will show Apache 503."
fi

cleanup_bundle_source
apt-get update >/dev/null 2>&1 || true

# Stage the satellite deb to the persistent path so the "Sync satellites" feature
# can find it.  Every delta patch MUST bundle pnetlab-satellite_*.deb in pnetlab-debs/.
SAT_DEST="/opt/unetlab/data/satellite"
SAT_DEB="$(ls -t "$DEBS_DIR"/pnetlab-satellite_*.deb 2>/dev/null | head -1)"
if [ -n "$SAT_DEB" ]; then
    mkdir -p "$SAT_DEST"
    cp -f "$SAT_DEB" "$SAT_DEST/"
    chmod 0644 "$SAT_DEST/$(basename "$SAT_DEB")"
    echo "Staged satellite deb: $(basename "$SAT_DEB") -> $SAT_DEST/"
else
    echo "WARNING: pnetlab-satellite_*.deb not found in pnetlab-debs/ — satellite Sync will not work until the deb is staged at $SAT_DEST/. Patches MUST include the satellite deb."
fi

# Stop the appliance auto-upgrading under itself. Installs before this patch
# disabled apt-daily{,-upgrade}.timer but left unattended-upgrades.service ENABLED
# and the APT::Periodic keys at "1", so unattended upgrades still ran. That is not
# just wasted cycles: an auto-upgrade that restarts a service can take running labs
# with it — older boxes put every QEMU in cpulimit.service's shared cgroup and
# that unit was KillMode=control-group. Current per-node transient scopes are
# independent; the package migration moves legacy guests uncapped first. That
# is the "lab ran fine for days, then every qemu shut down" report being retired.
#
# Masked, not merely disabled: apt/unattended-upgrades postinst re-enables a
# disabled timer on the next package upgrade. Idempotent; safe to re-run.
# Manual `apt-get update/upgrade` is unaffected — only the automatic schedule is.
echo "Disabling automatic apt upgrades (they can kill running lab nodes)..."
for _tmr in apt-daily.timer apt-daily-upgrade.timer motd-news.timer; do
    systemctl disable --now "$_tmr" 2>/dev/null || true
    systemctl mask "$_tmr" 2>/dev/null || true
done
systemctl disable --now unattended-upgrades.service 2>/dev/null || true
systemctl mask unattended-upgrades.service 2>/dev/null || true
# apt reads apt.conf.d in lexical order, last wins — 99- overrides the
# unattended-upgrades package's own 10periodic/20auto-upgrades conffiles without
# editing them (which would trigger a dpkg conffile prompt on a later upgrade).
cat > /etc/apt/apt.conf.d/99pnetlab-no-auto-upgrade <<'APTEOF'
// PNetLab appliance: never auto-update or auto-upgrade under a running lab.
// An unattended upgrade that restarts a service can kill every running qemu node
// (legacy guests shared cpulimit.service's cgroup; current guests use independent
// pnetlab-qemu-*.scope units). Operators apply updates deliberately, via the
// bundle's patch script.
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APTEOF
chmod 0644 /etc/apt/apt.conf.d/99pnetlab-no-auto-upgrade

# the link-quality/VLAN fix adds broker verbs; the import/auth/console fixes
# are web assets — bounce the services that cache them. (The retired Laravel
# store's `php artisan optimize:clear` is gone with the store.)
# NB: safe for running labs — qemu nodes are parented to systemd (ppid 1) in
# independent pnetlab-qemu-*.scope units, NOT in brokerd's or php-fpm's, so
# these restarts don't reap them.
systemctl restart pnetlab-brokerd 2>/dev/null || true
systemctl restart php8.5-fpm 2>/dev/null || true

echo
echo "DONE. Installed: $(dpkg-query -W -f '${Version}' pnetlab) (pnetlab)."
echo "Hard-refresh the browser (Ctrl+Shift+R) before re-testing."
