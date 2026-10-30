#!/bin/sh
# Generates your own release keystore. Run on your PC (needs Java), then keep the .jks safe and private.
set -e
read -r -p "Keystore password: " PW
keytool -genkeypair -keystore darkchess-release.jks -alias darkchess -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PW" -keypass "$PW" -dname "CN=DarkRoot, OU=DarkChess, O=DarkRoot Organizations, C=NP"
keytool -list -v -keystore darkchess-release.jks -storepass "$PW" | grep -E "SHA1|SHA256"
base64 -w0 darkchess-release.jks > keystore.b64 && echo "Base64 saved to keystore.b64 (paste into the KEYSTORE_BASE64 secret)"
