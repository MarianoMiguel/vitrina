#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/.local-codesign"
KEYCHAIN="$STORE/DynamicShareTarget.keychain"
CERT_NAME="Dynamic Share Target Local"
PASSWORD_FILE="$STORE/password"
OPENSSL_CONFIG="$STORE/openssl.cnf"
CERT_PEM="$STORE/cert.pem"
KEY_PEM="$STORE/key.pem"
P12="$STORE/identity.p12"

mkdir -p "$STORE"
chmod 700 "$STORE"

if [[ ! -f "$PASSWORD_FILE" ]]; then
  openssl rand -hex 24 > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
fi

PASSWORD="$(cat "$PASSWORD_FILE")"

if [[ ! -f "$KEYCHAIN" || ! -f "$P12" ]]; then
  cat > "$OPENSSL_CONFIG" <<EOF
[req]
distinguished_name=req_distinguished_name
x509_extensions=v3_req
prompt=no

[req_distinguished_name]
CN=$CERT_NAME

[v3_req]
keyUsage=critical,digitalSignature
extendedKeyUsage=codeSigning
basicConstraints=critical,CA:false
subjectKeyIdentifier=hash
EOF

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$KEY_PEM" \
    -out "$CERT_PEM" \
    -days 3650 \
    -nodes \
    -config "$OPENSSL_CONFIG" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$KEY_PEM" \
    -in "$CERT_PEM" \
    -name "$CERT_NAME" \
    -out "$P12" \
    -passout "pass:$PASSWORD" >/dev/null 2>&1

  security create-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null
  security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null
  security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
  security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$CERT_PEM" >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERT_NAME"; then
  security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$CERT_PEM" >/dev/null
fi

echo "$KEYCHAIN"
