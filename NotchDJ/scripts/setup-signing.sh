#!/bin/zsh
# Creates the local code-signing identity "Notch DJ Local Signing" in your login keychain.
# Safe to run again: it only does what is still missing.
#
# Why: build.sh otherwise signs ad hoc, and an ad hoc app has a new identity after every
# build. macOS then forgets System Audio Recording and Automation and asks again. With a
# stable certificate the designated requirement stays the same, so a grant sticks.
#
# The certificate is self-signed, valid for code signing only, and never leaves this Mac.
# Release builds should use a Developer ID certificate and notarization instead (README).
set -euo pipefail

NAME="Notch DJ Local Signing"
# macOS's own LibreSSL. Homebrew's OpenSSL 3 writes .p12 files the keychain can't import.
OPENSSL=/usr/bin/openssl
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [[ ! -f "$KEYCHAIN" ]]; then
  KEYCHAIN=$(security default-keychain -d user | tr -d ' "')
fi

say()  { print -r -- "==> $*"; }
ok()   { print -r -- "    ok: $*"; }
warn() { print -r -- "    warning: $*" >&2; }

valid_hash() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -F "\"$NAME\"" | head -n 1 | awk '{print $2}' || true
}

any_hash() {
  security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -F "\"$NAME\"" | head -n 1 | awk '{print $2}' || true
}

identity_count() {
  security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | sed -n '1,/identities found/p' | grep -cF "\"$NAME\"" || true
}

trust() {
  local pem="$1"
  say "Trusting the certificate for code signing (macOS asks for your password)"
  if security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$pem"; then
    ok "trusted for code signing"
  else
    warn "trust was not added. Signing still works, but 'security find-identity -v' won't list it."
  fi
}

finish() {
  local hash
  hash=$(valid_hash)
  if [[ -n "$hash" ]]; then
    ok "\"$NAME\" is a valid signing identity ($hash)"
  else
    hash=$(any_hash)
    ok "\"$NAME\" is installed ($hash), but not marked as trusted"
  fi
  print
  print -r -- "Next steps:"
  print -r -- "  1. ./build.sh --run"
  print -r -- "     The first time, macOS asks whether codesign may use the key: choose Always Allow."
  print -r -- "  2. Allow System Audio Recording once (onboarding, or the first fader move)."
  print -r -- "     It stays granted after rebuilds from now on."
  print -r -- "  If an older ad hoc build was granted before, reset that entry once:"
  print -r -- "     tccutil reset AudioCapture com.local.notchdj"
}

say "Notch DJ local signing setup"
ok "keychain: $KEYCHAIN"

if [[ -n "$(valid_hash)" ]]; then
  ok "\"$NAME\" already exists and is trusted. Nothing to do."
  finish
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [[ -n "$(any_hash)" ]]; then
  if [[ "$(identity_count)" -gt 1 ]]; then
    warn "found more than one \"$NAME\" identity. build.sh uses the first one."
    warn "Remove extras in Keychain Access if you like; nothing else is affected."
  fi
  say "\"$NAME\" exists but isn't trusted yet"
  if security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$TMP/cert.pem" 2>/dev/null; then
    trust "$TMP/cert.pem"
  else
    warn "couldn't read the certificate to trust it. Signing still works."
  fi
  finish
  exit 0
fi

# A certificate without its private key can't sign. Remove it so a fresh pair can be made.
STALE=$(security find-certificate -a -c "$NAME" -Z "$KEYCHAIN" 2>/dev/null | awk '/SHA-1 hash:/ {print $3}' || true)
if [[ -n "$STALE" ]]; then
  say "Removing a \"$NAME\" certificate that has no private key"
  for sha in ${(f)STALE}; do
    security delete-certificate -Z "$sha" "$KEYCHAIN" >/dev/null 2>&1 || true
  done
  ok "removed"
fi

say "Creating a self-signed code-signing certificate"
cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
if ! "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>"$TMP/openssl.log"; then
  cat "$TMP/openssl.log" >&2
  exit 1
fi
ok "certificate created (valid for 10 years)"

PASS=$("$OPENSSL" rand -hex 12)
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$TMP/identity.p12" -passout "pass:$PASS"

say "Importing into the login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
ok "imported; codesign may use the key"

trust "$TMP/cert.pem"

if [[ -z "$(any_hash)" ]]; then
  warn "the identity didn't show up in 'security find-identity'. Open Keychain Access,"
  warn "check for \"$NAME\" in the login keychain, then run this script again."
  exit 1
fi
finish
