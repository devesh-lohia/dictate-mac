#!/bin/bash
# Creates a local self-signed code-signing certificate named "DictateLocal" in your login keychain.
# Signing every build with the same certificate lets macOS keep the privacy permissions you granted
# (Microphone, Accessibility, Input Monitoring) instead of asking again after each rebuild.
# The certificate never leaves your Mac and is not used to distribute anything.
set -euo pipefail
NAME="${1:-DictateLocal}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
  -subj "/CN=$NAME" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
PASS="$(openssl rand -hex 8)"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$PASS" -legacy 2>/dev/null
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "created code-signing identity \"$NAME\""
