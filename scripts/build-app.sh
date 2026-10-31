#!/usr/bin/env bash
# Generates the Xcode project and builds Zack.app.
# Usage: scripts/build-app.sh [Debug|Release]   build with the packages already fetched, no network
#        scripts/build-app.sh --resolve         fetch the packages once (network, only after approval)
# ZACK_DERIVED_DATA overrides the build directory (default .build/xcode-app), e.g. for clean builds that must not
# touch the app being run from the default one.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED_DATA="${ZACK_DERIVED_DATA:-.build/xcode-app}"

if [[ ! -f App/Local.xcconfig ]]; then
    echo "App/Local.xcconfig missing: copy App/Local.xcconfig.example and enter the team ID" >&2
    exit 1
fi
xcodegen generate --spec App/project.yml --quiet

# The app resolves the root package's dependencies itself; start from the root's pinned versions.
RESOLVED_DIR="App/Zack.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DIR"
cp Package.resolved "$RESOLVED_DIR/Package.resolved"
PACKAGES=(-project App/Zack.xcodeproj -scheme Zack -clonedSourcePackagesDirPath .build/xcode-packages
    -onlyUsePackageVersionsFromResolvedFile)

if [[ "${1:-}" == "--resolve" ]]; then
    xcodebuild -resolvePackageDependencies "${PACKAGES[@]}"
else
    CONFIGURATION="${1:-Debug}"
    # After the one approved resolution, builds neither change nor update packages.
    xcodebuild "${PACKAGES[@]}" -disableAutomaticPackageResolution -skipPackageUpdates \
        -configuration "$CONFIGURATION" -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" -quiet build
fi

# Fail if Xcode picked other package versions than Package.resolved.
/usr/bin/python3 -I - Package.resolved "$RESOLVED_DIR/Package.resolved" <<'PY'
import json
import sys

def pins(path):
    with open(path) as file:
        return {pin["identity"]: pin["state"].get("revision") for pin in json.load(file)["pins"]}

root, app = pins(sys.argv[1]), pins(sys.argv[2])
drift = {name: (root.get(name), revision) for name, revision in app.items() if root.get(name) != revision}
if drift:
    sys.exit(f"package versions differ from Package.resolved: {drift}")
PY
if [[ "${1:-}" != "--resolve" ]]; then
    # The speech synthesis lexicon (no licence stated) must not ship; App/project.yml removes it before signing.
    if [[ -e "$DERIVED_DATA/Build/Products/${1:-Debug}/Zack.app/Contents/Resources/FluidAudio_FluidAudio.bundle" ]]; then
        echo "FluidAudio_FluidAudio.bundle is still in Zack.app" >&2
        exit 1
    fi
    echo "built $DERIVED_DATA/Build/Products/${1:-Debug}/Zack.app"
fi
