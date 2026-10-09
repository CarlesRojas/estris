#!/usr/bin/env bash
# One-time setup: creates a self-signed code signing certificate, "PasteRing Development",
# in the login keychain. build-app.sh signs with it when it exists, so every build keeps
# the same identity and macOS keeps the Accessibility permission across rebuilds.
set -euo pipefail

NAME="PasteRing Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.conf" -extensions ext \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# OpenSSL 3 (Homebrew) writes PKCS#12 files the keychain can't read without -legacy;
# the LibreSSL that ships with macOS doesn't know the flag.
LEGACY=()
if openssl version | grep -q "^OpenSSL 3"; then LEGACY=(-legacy); fi
openssl pkcs12 -export "${LEGACY[@]}" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/cert.p12" -passout pass:pastering

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P pastering -T /usr/bin/codesign
# Trust it for code signing (asks for your password once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "Created \"$NAME\". Build with ./scripts/run.sh; grant Accessibility once more, then it sticks."
