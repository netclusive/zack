#!/usr/bin/env bash
# Local quality gate: secrets, lint, versions, test, build of package and app. Stops at the first failure.
# Usage: ./build.sh [--static-only | --skip-static]
#   --static-only  secret scan, lint and versions only, no build
#   --skip-static  tests and builds only; scripts/release.sh checks the advisories between the two parts
set -euo pipefail
cd "$(dirname "$0")"

# The versions docs/development.md names as tested; another version only warns.
warn_untested() {
    if [[ "$3" != "$2" ]]; then echo "warning: $1 ${3:-not found}, tested with $2" >&2; fi
}

static_checks() {
    echo "==> secret scan (tracked files at HEAD)"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    git archive HEAD | tar -x -C "$TMP"
    ( cd "$TMP" && gitleaks dir . --redact --no-banner )

    echo "==> tool versions"
    warn_untested gitleaks 8.30.1 "$(gitleaks version 2> /dev/null || true)"
    warn_untested swift-format 6.4.4 "$(xcrun swift-format --version 2> /dev/null || true)"
    warn_untested XcodeGen 2.46.0 "$(xcodegen --version 2> /dev/null | sed -n 's/^Version: //p' || true)"
    warn_untested ShellCheck 0.11.0 "$(shellcheck --version 2> /dev/null | sed -n 's/^version: //p' || true)"

    echo "==> lint"
    xcrun swift-format lint --strict --recursive Package.swift Sources Tests App/Zack
    for script in build.sh scripts/*.sh; do bash -n "$script"; done
    shellcheck build.sh scripts/*.sh

    echo "==> version"
    local package_version app_version
    package_version="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/ZackCore/Zack.swift)"
    app_version="$(sed -n 's/^ *MARKETING_VERSION: *//p' App/project.yml)"
    # The app version has no pre-release suffix such as -dev.
    if [[ -z "$app_version" || "${package_version%%-*}" != "$app_version" ]]; then
        echo "version mismatch: Zack.version $package_version, MARKETING_VERSION $app_version" >&2
        exit 1
    fi
}

tests_and_builds() {
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
}

usage() {
    echo "usage: $0 [--static-only | --skip-static]" >&2
    exit 2
}

if (($# > 1)); then usage; fi
case "${1-}" in
    "")
        static_checks
        tests_and_builds
        ;;
    --static-only) static_checks ;;
    --skip-static) tests_and_builds ;;
    *) usage ;;
esac
