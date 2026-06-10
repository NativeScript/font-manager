#!/usr/bin/env bash
# Publish the fontmanager library to Maven Central via Sonatype Central Portal.
#
# All credentials are read from ~/.gradle/gradle.properties:
#   mavenCentralUsername      - Central Portal username (token)
#   mavenCentralPassword      - Central Portal password (token secret)
#   signing.keyId             - Last 8 chars of your GPG key ID
#   signing.password          - Passphrase for the GPG key
#   signing.secretKeyRingFile - Absolute path to your .gpg keyring file
#
# Usage:
#   ./publish.sh            # publish current VERSION_NAME from gradle.properties
#   ./publish.sh 1.2.3      # override version at publish time

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $# -ge 1 ]]; then
  VERSION_OVERRIDE="-PVERSION_NAME=$1"
  VERSION="$1"
else
  VERSION_OVERRIDE=""
  VERSION=$(grep '^VERSION_NAME=' gradle.properties | cut -d= -f2)
fi

echo "Publishing org.nativescript:fontmanager:$VERSION to Maven Central..."
echo ""

./gradlew :fontmanager:publishAndReleaseToMavenCentral \
  $VERSION_OVERRIDE \
  --no-daemon \
  --stacktrace

echo ""
echo "Done! org.nativescript:fontmanager:$VERSION is on its way to Maven Central."
echo "Allow ~30 minutes to appear at https://repo1.maven.org/maven2/org/nativescript/fontmanager/"
