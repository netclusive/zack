#!/usr/bin/env bash
# Local quality gate: secrets, lint, versions, test, build of package and app. Stops at the first failure.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> secret scan (tracked files at HEAD)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git archive HEAD | tar -x -C "$TMP"
( cd "$TMP" && gitleaks dir . --redact --no-banner )

echo "==> lint"
xcrun swift-format lint --strict --recursive Package.swift Sources Tests App/Zack
for script in build.sh scripts/*.sh; do bash -n "$script"; done
shellcheck build.sh scripts/*.sh

echo "==> version"
PACKAGE_VERSION="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/ZackCore/Zack.swift)"
APP_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' App/project.yml)"
# The app version has no pre-release suffix such as -dev.
if [[ -z "$APP_VERSION" || "${PACKAGE_VERSION%%-*}" != "$APP_VERSION" ]]; then
    echo "version mismatch: Zack.version $PACKAGE_VERSION, MARKETING_VERSION $APP_VERSION" >&2
    exit 1
fi

echo "==> test"
swift test
scripts/release.sh --self-test
scripts/check-strings.sh --self-test

echo "==> build"
swift build -c release

echo "==> app"
scripts/build-app.sh Release

echo "==> strings"
scripts/check-strings.sh .build/xcode-app Release
