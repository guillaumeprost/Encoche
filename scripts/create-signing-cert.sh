#!/usr/bin/env bash
# Crée le certificat auto-signé « Notch Local Signing » dans le Trousseau de session.
#
# Le projet signe l'app avec ce certificat : son identité reste la même d'un build à
# l'autre, et macOS conserve donc les autorisations accordées (accès complet au disque,
# calendrier, automatisation). À lancer une seule fois par Mac.
set -euo pipefail

NAME="Notch Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Le certificat « $NAME » existe déjà."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 12)
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/notch.p12" -passout "pass:$PASS" 2>/dev/null
security import "$WORK/notch.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security

echo "Certificat « $NAME » créé."
