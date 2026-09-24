#!/bin/bash
# Tidy /etc/apt/sources.list.d after the 24.04 -> 26.04 upgrade.
#
#   sudo ./apt-sources.sh
#
# The release upgrade migrated one-line .list files to deb822 .sources but left
# the originals behind, carried a component forward that no longer exists, and
# wrote OEM entries without a keyring. Each of those is a line of `apt update`
# noise. Idempotent; backs up the whole directory before touching anything.
#
# See oem-stack.md for what the OEM archives actually supply.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
CHANGED=0
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./apt-sources.sh"; exit 1; }

. /etc/os-release
D=/etc/apt/sources.list.d

say "System"
info "$PRETTY_NAME"
[ "${VERSION_CODENAME:-}" = resolute ] || {
    echo "  these notes target Ubuntu 26.04 (resolute); found ${VERSION_CODENAME:-unknown}"
    exit 1; }

# ------------------------------------------------------------------- backup
say "Backup"
B=/var/backups/apt-sources-$(date +%Y%m%d-%H%M%S).tar.gz
tar czf "$B" -C /etc/apt sources.list.d sources.list 2>/dev/null
ok "$B"

# ------------------------------------------------------- migration leftovers
# apt scans this directory and complains about every file whose extension it
# does not recognise. These are the pre-upgrade `noble` .list files, kept as
# .migrate alongside the .sources that replaced them.
say "Migration leftovers (.migrate)"
for f in "$D"/*.list.migrate; do
    [ -e "$f" ] || { ok "none left"; break; }
    base=$(basename "$f" .list.migrate)
    # Only drop it once its deb822 replacement is in place.
    if [ -e "$D/$base.sources" ]; then
        rm -f "$f"; CHANGED=1; ok "removed $(basename "$f")"
    else
        info "kept $(basename "$f") — no $base.sources yet"
    fi
done

# ------------------------------------------------------------ claude-desktop
# This one failed to migrate automatically and was parked as .list.disabled,
# so claude-desktop has had no repository at all since the upgrade and can
# never receive an update. Rewrite it in deb822 by hand.
say "claude-desktop"
if [ ! -e "$D/claude-desktop.sources" ]; then
    cat > "$D/claude-desktop.sources" <<'EOF'
Types: deb
URIs: https://downloads.claude.ai/claude-desktop/apt/stable
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/claude-desktop-archive-keyring.asc
EOF
    rm -f "$D/claude-desktop.list.disabled" "$D/claude-desktop.list.migrate"
    CHANGED=1; ok "rewritten as deb822; updates restored"
else
    ok "already configured"
fi

# ---------------------------------------------------------------- nantou
# `nantou` was a component of noble. resolute does not have it, which is the
# nine "component misspelt in sources.list?" warnings. The oem-nantou-meta
# package is a leftover with no 26.04 successor (see oem-stack.md).
say "Dead 'nantou' component"
if [ -e "$D/oem-nantou-meta.sources" ]; then
    rm -f "$D/oem-nantou-meta.sources"; CHANGED=1
    ok "removed oem-nantou-meta.sources"
    info "the oem-nantou-meta package remains installed and inert;"
    info "purge with: apt purge oem-nantou-meta"
else
    ok "already removed"
fi

# ------------------------------------------------------------------ Signed-By
# Both OEM archives were written without a keyring line. The key is shipped by
# ubuntu-oem-keyring, which oem-*-meta already depends on.
say "OEM archive signing keys"
KEY=/usr/share/keyrings/ubuntu-oem-keyring.gpg
if [ ! -e "$KEY" ]; then
    apt-get install -y ubuntu-oem-keyring >/dev/null 2>&1 || true
fi

# dpkg left the corrected upstream version of this file unapplied.
if [ -e "$D/oem-somerville-hypno-meta.sources.dpkg-dist" ]; then
    mv "$D/oem-somerville-hypno-meta.sources.dpkg-dist" \
       "$D/oem-somerville-hypno-meta.sources"
    CHANGED=1; ok "oem-somerville-hypno-meta.sources <- packaged version"
fi

for f in "$D"/oem-hwe-meta.sources "$D"/oem-somerville-hypno-meta.sources; do
    [ -e "$f" ] || continue
    if grep -q '^Signed-By:' "$f"; then
        ok "$(basename "$f") signed"
    else
        printf 'Signed-By: %s\n' "$KEY" >> "$f"
        CHANGED=1; ok "$(basename "$f") <- Signed-By"
    fi
done

# ------------------------------------------------------------ stale backups
# .distUpgrade / .curtin.orig copies from the upgrade and the original install.
# Silent, but they are the reason this directory is hard to read; the tarball
# above holds them.
say "Stale upgrade backups"
N=$(find "$D" -maxdepth 1 \( -name '*.distUpgrade' -o -name '*.curtin.orig' \) -print -delete | wc -l)
[ "$N" -gt 0 ] && { CHANGED=1; ok "removed $N"; } || ok "none"

# ---------------------------------------------------------------------- check
say "Result"
apt-get update -qq 2>&1 | grep -vE '^$' && info "(warnings above)" || ok "apt update is clean"
echo
ls -1 "$D"
[ "$CHANGED" = 1 ] && info "" && info "restore with: tar xzf $B -C /etc/apt"
exit 0
