#!/bin/bash
# Let a touch of the YubiKey stand in for the password at sudo, and nowhere else.
#
#   sudo ./yubikey-sudo.sh            # install, register the key, wire up PAM
#   sudo ./yubikey-sudo.sh --add      # register another key (only it inserted)
#   sudo ./yubikey-sudo.sh --remove   # take the PAM lines back out
#
# Idempotent. The lock screen, GDM login, polkit and su are untouched: they
# still want the password. See yubikey.md for why.
#
# Keep a second root shell open (`sudo -s` in another terminal) until you have
# tested `sudo -k; sudo true` in a fresh terminal.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
no(){ printf '  [FAIL] %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./yubikey-sudo.sh"; exit 1; }

USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || {
    echo "run via sudo from your own account, so the key maps to you"; exit 1; }

MAP=/etc/u2f_mappings
# A fixed origin, so the registration survives a hostname change.
ORIGIN=pam://sudo
LINE="auth       sufficient pam_u2f.so authfile=$MAP origin=$ORIGIN appid=$ORIGIN cue"
FILES="/etc/pam.d/sudo /etc/pam.d/sudo-i"

if [ "${1:-}" = --remove ]; then
    say "Removing pam_u2f from sudo"
    for f in $FILES; do sed -i '/pam_u2f\.so/d' "$f" && ok "$f"; done
    info "$MAP left in place; delete it by hand if you want"
    exit 0
fi

say "Packages"
if dpkg -s libpam-u2f pamu2fcfg >/dev/null 2>&1; then ok "libpam-u2f, pamu2fcfg"
else apt-get install -y libpam-u2f pamu2fcfg >/dev/null && ok "installed libpam-u2f, pamu2fcfg" \
    || { no "apt install failed"; exit 1; }; fi
MOD=$(find /usr/lib -name pam_u2f.so -path '*security*' 2>/dev/null | head -1)
[ -n "$MOD" ] && ok "$MOD" || { no "pam_u2f.so not found"; exit 1; }

say "Key registration ($MAP)"
# pamu2fcfg talks to the first key it finds, so enrol with exactly one inserted.
one_key(){
    command -v ykman >/dev/null || return 0
    local n; n=$(ykman list 2>/dev/null | grep -c .)
    [ "$n" = 1 ] && { info "key: $(ykman list)"; return 0; }
    no "$n YubiKeys inserted; plug in exactly the one to register"; exit 1
}
have=$(grep -s "^$USER_NAME:" "$MAP" | tr -cd ':' | wc -c)
if [ "${1:-}" = --add ]; then
    [ "$have" -gt 0 ] || { no "no first key yet; run without --add"; exit 1; }
    one_key; info "touch the YubiKey when it blinks..."
    CRED=$(pamu2fcfg -n -o "$ORIGIN" -i "$ORIGIN") \
        || { no "pamu2fcfg failed (key not touched in time?)"; exit 1; }
    # -n prints ":keyhandle,pubkey,type,opts"; extra keys go on the same line.
    sed -i "s|^$USER_NAME:.*|&$CRED|" "$MAP"
    ok "added; $USER_NAME now has $((have + 1)) key(s)"
elif [ "$have" -gt 0 ]; then
    ok "$USER_NAME has $have key(s) registered"
    info "more keys: swap in each one alone, run: sudo ./yubikey-sudo.sh --add"
else
    one_key; info "touch the YubiKey when it blinks..."
    ENTRY=$(pamu2fcfg -u "$USER_NAME" -o "$ORIGIN" -i "$ORIGIN") \
        || { no "pamu2fcfg failed (key not touched in time?)"; exit 1; }
    printf '%s\n' "$ENTRY" >> "$MAP"
    ok "registered first key for $USER_NAME"
    info "more keys: swap in each one alone, run: sudo ./yubikey-sudo.sh --add"
fi
# Root-owned, so nothing running as you can enrol a different key.
chown root:root "$MAP"; chmod 644 "$MAP"; ok "owner root, mode 644"

say "PAM"
for f in $FILES; do
    if grep -q 'pam_u2f\.so' "$f"; then ok "$f already has pam_u2f"; continue; fi
    cp -a "$f" "$f.pre-u2f"
    # Before common-auth: a touch succeeds immediately; anything else (no key,
    # timeout, module error) falls through to the usual password prompt.
    sed -i "0,/^@include common-auth/s||$LINE\n@include common-auth|" "$f"
    grep -q 'pam_u2f\.so' "$f" && ok "$f (backup: $f.pre-u2f)" || no "$f edit failed"
done

say "Next"
info "in a NEW terminal:  sudo -k; sudo true   -> 'Please touch the device.'"
info "pull the key and retry -> falls back to the password prompt"
