#!/usr/bin/env bash
# Builds, notarizes and publishes a Zack release with its Sparkle appcast; stops at the first failure.
# Usage: scripts/release.sh [--local | --dry-run | --self-test]
#   (none)       real release from main: checks, gate, archive, notarization, appcast, push, GitHub release, post-check
#   --dry-run    the same without push, publish and post-check
#   --local      Apple Development build for the local test feed, signed with the test key; no notarization, no network
#   --self-test  checks the CHANGELOG, appcast and version helpers without any network
# Output goes to .build/zack-release/<version>/ (.build/release belongs to SwiftPM). Team IDs come from the ignored
# App/Local.xcconfig and are never printed.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly FEED_URL="https://github.com/netclusive/zack/releases/latest/download/appcast.xml"
readonly DOWNLOAD_PREFIX="https://github.com/netclusive/zack/releases/download"
readonly REPO="netclusive/zack"
readonly MIN_SYSTEM_VERSION="26.0"
readonly NOTARY_PROFILE="zack-notary"
readonly TEST_KEY_ACCOUNT="zack-test"
readonly LOCAL_FEED_URL="http://127.0.0.1:8000/appcast.xml"
readonly LOCAL_DOWNLOAD_PREFIX="http://127.0.0.1:8000"
readonly ENTITLEMENT="com.apple.security.device.audio-input"
# Public EdDSA key for the Sparkle feed; the private key is in the login keychain (generate_keys, default account).
ED_PUBLIC_KEY="5YWYp4u+EBOFNvklOCAI7zynBumo/inbbikw+C9oE8A="

# Set by main and preflight; ZIP by package_feed.
MODE="" WORK="" VERSION="" OUT="" NOTES="" TEAM="" MASK_TEAMS="" SPARKLE_BIN="" FEED="" KEY="" ZIP="" ZIP_URL=""

# Print the body of "## [<version>]" (or "## [Unreleased]") without heading and surrounding blank lines.
# Stops at the next "## [" heading; exit 1 if the section is missing or has no content.
changelog_section() {
    local version="$1" file="$2"
    awk -v v="$version" '
        BEGIN { head = "## [" v "]" }
        index($0, "## [") == 1 {
            if (found) exit
            if (index($0, head) == 1 && (length($0) == length(head) || substr($0, length(head) + 1, 1) == " ")) found = 1
            next
        }
        found {
            if ($0 ~ /^[ \t]*$/) { if (printed) pending++; next }
            for (; pending > 0; pending--) print ""
            print; printed = 1
        }
        END { exit(printed ? 0 : 1) }
    ' "$file"
}

# Exit 0 only if dotted version $1 is numerically greater than $2, compared per component.
version_greater() {
    local a b i x y
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        x="${a[i]:-0}"
        y="${b[i]:-0}"
        [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || { echo "version_greater: not numeric: $1 / $2" >&2; return 2; }
        if ((10#$x > 10#$y)); then return 0; fi
        if ((10#$x < 10#$y)); then return 1; fi
    done
    return 1
}

# write_appcast <version> <zip-url> <sign-attributes> <notes-file> <out>
# Sign attributes are Sparkle sign_update's output, passed through verbatim. Notes go into CDATA unchanged.
# Checks every step itself, so it also fails correctly where set -e is suppressed (if, ||).
write_appcast() {
    local version="$1" url="$2" sign="$3" notes_file="$4" out="$5" notes pub tmp
    if ! notes="$(cat "$notes_file")"; then
        echo "write_appcast: cannot read $notes_file" >&2
        return 1
    fi
    if [[ -z "${notes//[[:space:]]/}" ]]; then
        echo "write_appcast: notes are empty" >&2
        return 1
    fi
    if [[ "$notes" == *']]>'* ]]; then
        echo "write_appcast: notes contain the CDATA terminator ]]>" >&2
        return 1
    fi
    pub="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    if ! tmp="$(mktemp)"; then
        echo "write_appcast: mktemp failed" >&2
        return 1
    fi
    cat > "$tmp" <<XML || { rm -f "$tmp"; echo "write_appcast: cannot write $tmp" >&2; return 1; }
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Zack</title>
    <item>
      <title>Zack $version</title>
      <pubDate>$pub</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$notes]]></description>
      <enclosure url="$url" type="application/octet-stream" $sign/>
    </item>
  </channel>
</rss>
XML
    if ! xmllint --noout "$tmp"; then
        rm -f "$tmp"
        echo "write_appcast: generated appcast is not well-formed" >&2
        return 1
    fi
    if ! mv "$tmp" "$out"; then
        rm -f "$tmp"
        echo "write_appcast: cannot write $out" >&2
        return 1
    fi
}

die() {
    echo "release: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

# Ask on the terminal; anything but exactly "ja" aborts.
confirm() {
    local answer=""
    printf '%s ' "$1" 2> /dev/null > /dev/tty || die "no terminal for the confirmation"
    IFS= read -r answer < /dev/tty || true
    [[ "$answer" == "ja" ]] || die "aborted"
}

# Hide team IDs, signing identity names and email addresses (Apple ID) in tool output (stdin to stdout).
mask() {
    local team names='Apple Development|Apple Distribution|Developer ID Application|Mac Developer'
    local args=(-E -e "s/(($names): )[^\")]*\\)?/\\1<masked>/g"
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g')
    for team in $MASK_TEAMS; do args+=(-e "s/$team/<team>/g"); done
    LC_ALL=C sed "${args[@]}"
}

# xcconfig_value <name> [file]: print the last plain "NAME = value" assignment, default file App/Local.xcconfig.
# Comment lines, trailing // comments and conditional assignments (NAME[config=…]) are skipped.
xcconfig_value() {
    awk -v name="$1" '
        /^[ \t]*\/\// { next }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (index(line, name) != 1) next
            rest = substr(line, length(name) + 1)
            if (rest !~ /^[ \t]*=/) next
            sub(/^[ \t]*=[ \t]*/, "", rest)
            sub(/[ \t]*(\/\/.*)?$/, "", rest)
            value = rest
        }
        END { print value }
    ' "${2:-App/Local.xcconfig}"
}

# team_setting <name> [file]: print a team ID setting; nothing if it is missing, CHANGEME or malformed.
team_setting() {
    local value
    value="$(xcconfig_value "$1" "${2:-App/Local.xcconfig}")"
    if [[ "$value" =~ ^[A-Z0-9]{10}$ ]]; then printf '%s\n' "$value"; fi
}

# Print the version of package identity $1 pinned in Package.resolved.
pinned_version() {
    awk -v id="$1" '
        { value = $3; gsub(/[",]/, "", value) }
        $1 == "\"identity\"" { found = (value == id) }
        found && $1 == "\"version\"" { print value; exit }
    ' Package.resolved
}

# release_view <tag or empty for latest> <json fields> <jq>: print the result; nothing if there is no such release.
release_view() {
    local out
    if out="$(gh release view ${1:+"$1"} --repo "$REPO" --json "$2" --jq "$3" 2> "$WORK/gh.err")"; then
        printf '%s\n' "$out"
    elif ! grep -q 'release not found' "$WORK/gh.err"; then
        cat "$WORK/gh.err" >&2
        return 1
    fi
}

# Step 1: all local checks first, then the ones that use the network.
preflight() {
    step "preflight ($MODE)"
    local status branch section name keychain latest
    VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' App/project.yml)" || die "cannot read App/project.yml"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION in App/project.yml is not X.Y.Z"
    OUT=".build/zack-release/$VERSION"

    if [[ "$MODE" != local ]]; then
        status="$(git status --porcelain)" || die "git status failed"
        [[ -z "$status" ]] || die "working tree is not clean"
        branch="$(git symbolic-ref --quiet --short HEAD)" || die "HEAD is detached; releases are made from main"
        [[ "$branch" == main ]] || die "on branch $branch; releases are made from main"
        git remote get-url origin > /dev/null 2>&1 || die "no remote origin"
        [[ "$ED_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
            || die "ED_PUBLIC_KEY in scripts/release.sh is empty or not a public EdDSA key"
    fi

    NOTES="$WORK/notes.md"
    if changelog_section "$VERSION" CHANGELOG.md > "$NOTES"; then
        section="$VERSION"
    elif [[ "$MODE" != release ]] && changelog_section Unreleased CHANGELOG.md > "$NOTES"; then
        section=Unreleased
    elif [[ "$MODE" == release ]]; then
        die "CHANGELOG.md has no section [$VERSION] with content"
    else
        die "CHANGELOG.md has no section [$VERSION] or [Unreleased] with content"
    fi
    [[ "$(< "$NOTES")" != *']]>'* ]] || die "CHANGELOG section [$section] contains the CDATA terminator ]]>"
    echo "  version $VERSION, notes from CHANGELOG section [$section]"

    if [[ "$MODE" == release ]]; then
        [[ "$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/ZackCore/Zack.swift)" == "$VERSION" ]] \
            || die "Zack.version in Sources/ZackCore/Zack.swift is not $VERSION"
        [[ "$(git cat-file -t "refs/tags/v$VERSION" 2> /dev/null)" == tag ]] || die "no annotated tag v$VERSION"
        [[ "$(git rev-parse "refs/tags/v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] \
            || die "tag v$VERSION is not on HEAD"
    fi

    [[ -f App/Local.xcconfig ]] || die "App/Local.xcconfig missing: copy App/Local.xcconfig.example"
    if [[ "$MODE" == local ]]; then name=DEVELOPMENT_TEAM; else name=ZACK_RELEASE_TEAM; fi
    TEAM="$(team_setting "$name")"
    [[ -n "$TEAM" ]] || die "$name in App/Local.xcconfig is missing, CHANGEME or not a 10-character team ID"
    MASK_TEAMS="$TEAM $(team_setting DEVELOPMENT_TEAM)"

    SPARKLE_BIN="$(find .build -path '*Sparkle/bin/sign_update' -type f 2> /dev/null | head -1 || true)"
    [[ -n "$SPARKLE_BIN" ]] || die "Sparkle's sign_update not found under .build: the packages are not resolved"
    SPARKLE_BIN="$(dirname "$SPARKLE_BIN")"

    if [[ "$MODE" == local ]]; then
        KEY="$("$SPARKLE_BIN/generate_keys" --account "$TEST_KEY_ACCOUNT" -p)" \
            || die "no test key in the keychain under account $TEST_KEY_ACCOUNT"
        [[ "$KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "test key '$TEST_KEY_ACCOUNT' is not a public EdDSA key"
        FEED="$LOCAL_FEED_URL"
        ZIP_URL="$LOCAL_DOWNLOAD_PREFIX/Zack-$VERSION.zip"
        return
    fi
    keychain="$("$SPARKLE_BIN/generate_keys" -p)" || die "no Sparkle signing key in the keychain"
    [[ "$keychain" == "$ED_PUBLIC_KEY" ]] || die "the Sparkle signing key in the keychain does not match ED_PUBLIC_KEY"
    KEY="$ED_PUBLIC_KEY"
    FEED="$FEED_URL"
    ZIP_URL="$DOWNLOAD_PREFIX/v$VERSION/Zack-$VERSION.zip"

    step "preflight: GitHub and notary service"
    git fetch origin || die "git fetch origin failed"
    git rev-parse --verify --quiet refs/remotes/origin/main > /dev/null || die "origin/main does not exist"
    # main may be ahead (the release commit is pushed in step 9), but neither behind nor diverged.
    git merge-base --is-ancestor refs/remotes/origin/main refs/heads/main \
        || die "main is behind or has diverged from origin/main; integrate origin/main first"
    latest="$(release_view "" tagName .tagName)" || die "gh release view failed"
    if [[ -n "$latest" ]]; then
        version_greater "$VERSION" "${latest#v}" \
            || die "$VERSION is not higher than the published $latest; Sparkle would never offer it"
    fi
    [[ "$(gh api "repos/$REPO" --jq .permissions.push)" == true ]] || die "the gh account may not push to $REPO"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 \
        || die "notary profile $NOTARY_PROFILE is missing or not usable"
}

# Steps 2 and 4: ./build.sh in two parts, so the advisories (sca) come after lint and sast and before test and build.
# Step 2 (--static-only): secret scan, lint, versions. Step 4 (--skip-static): tests, package and app build; it also
# generates App/Zack.xcodeproj.
gate() {
    step "gate: ./build.sh $1"
    # pipefail: a failing build.sh fails the pipeline even though mask succeeds.
    ./build.sh "$1" 2>&1 | mask || die "./build.sh $1 failed"
}

# Step 3: Swift has no SCA tool in the stack matrix; list the advisories of the pinned packages instead.
advisories() {
    step "security advisories of the pinned packages"
    local repo list
    local format='.[] | "    \((.published_at // "")[0:10])  \(.severity // "-")  \(.summary)'
    format+='  (affected: \([.vulnerabilities[]?.vulnerable_version_range // empty] | join(", ")))"'
    for repo in sparkle-project/Sparkle FluidInference/FluidAudio; do
        list="$(gh api --paginate "repos/$repo/security-advisories" --jq "$format")" \
            || die "cannot list the advisories of $repo"
        echo "  $repo, pinned $(pinned_version "$(printf '%s' "${repo#*/}" | tr '[:upper:]' '[:lower:]')"):"
        printf '%s\n' "${list:-    none}"
    done
    confirm "weiter? (ja)"
}

# remove_distribution_logs <export log> [temp folder, default the user temp folder]
# The export writes a log bundle (team, signing identities) to the user temp folder on success and failure; it
# ignores TMPDIR. Delete the bundle the export log names, but only directly inside that folder; without one, nothing.
remove_distribution_logs() {
    local temp="${2-}" path
    [[ -n "$temp" ]] || temp="$(getconf DARWIN_USER_TEMP_DIR)" || return 0
    [[ -n "$temp" ]] || return 0
    temp="${temp%/}/"
    while IFS= read -r path; do
        if [[ "$path" == "$temp"* && "${path#"$temp"}" != */* ]]; then rm -rf "$path"; fi
    done < <(sed -n 's/.*Created bundle at path "\(.*\.xcdistributionlogs\)".*/\1/p' "$1")
}

# Step 5: archive with feed and key, export with the signing of the mode; the export also re-signs Sparkle's helpers.
build_export() {
    step "archive and export"
    local method style signing exported
    if [[ "$MODE" == local ]]; then
        # This export signs Sparkle's helpers with the app's team, and a local update runs.
        method=debugging
        style=automatic
        signing=(CODE_SIGN_STYLE=Automatic)
    else
        method=developer-id
        style=manual
        signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$TEAM")
    fi
    # shellcheck disable=SC2015 # die if either step fails
    rm -rf "$OUT" && mkdir -p "$OUT" || die "cannot prepare $OUT"
    xcodebuild archive -project App/Zack.xcodeproj -scheme Zack -configuration Release \
        -clonedSourcePackagesDirPath .build/xcode-packages -onlyUsePackageVersionsFromResolvedFile \
        -disableAutomaticPackageResolution -skipPackageUpdates -destination 'generic/platform=macOS' \
        -derivedDataPath "$WORK/DerivedData" -archivePath "$OUT/Zack.xcarchive" -quiet \
        "ZACK_FEED_URL=$FEED" "ZACK_ED_PUBLIC_KEY=$KEY" "${signing[@]}" 2>&1 | mask \
        || die "xcodebuild archive failed"

    # Holds the team ID, so it stays in the temporary folder.
    cat > "$WORK/ExportOptions.plist" <<PLIST || die "cannot write the export options"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$method</string>
    <key>signingStyle</key>
    <string>$style</string>
    <key>teamID</key>
    <string>$TEAM</string>
</dict>
</plist>
PLIST
    # The export folder also gets copies of the options and a summary with the team; only Zack.app leaves it.
    exported=yes
    xcodebuild -exportArchive -archivePath "$OUT/Zack.xcarchive" -exportPath "$WORK/export" \
        -exportOptionsPlist "$WORK/ExportOptions.plist" -quiet 2>&1 | tee "$WORK/export.log" | mask || exported=no
    remove_distribution_logs "$WORK/export.log"
    [[ "$exported" == yes ]] || die "xcodebuild -exportArchive failed"
    mv "$WORK/export/Zack.app" "$OUT/Zack.app" || die "the export did not produce Zack.app"
    echo "  exported $OUT/Zack.app ($method)"
}

# Print the TeamIdentifier of signed code $1 (for comparison only, never shown).
team_of() {
    local out
    out="$(codesign -dv "$1" 2>&1)" || return 1
    sed -n 's/^TeamIdentifier=//p' <<< "$out"
}

# Step 6: signature, hardened runtime, entitlements, contents, feed and key, version, team of Sparkle's helpers.
verify_bundle() {
    step "verify Zack.app"
    local app="$OUT/Zack.app" out xml keys name value code runtime='flags=0x[0-9a-f]+\([^)]*runtime'
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    out="$(codesign --verify --strict --deep "$app" 2>&1)" \
        || { printf '%s\n' "$out" | mask >&2; die "the signature of Zack.app is not valid"; }
    out="$(codesign -dv "$app" 2>&1)" || die "cannot read the signature of Zack.app"
    [[ "$out" =~ $runtime ]] || die "Zack.app is not signed with the hardened runtime"
    echo "  signature valid, hardened runtime"

    out="$(codesign -d --entitlements - --xml "$app" 2> /dev/null)" || die "cannot read the entitlements of Zack.app"
    # xml1 puts each key and each value on its own line.
    xml="$(plutil -convert xml1 -o - - <<< "$out")" || die "cannot parse the entitlements of Zack.app"
    keys="$(sed -n 's/^[[:space:]]*<key>\(.*\)<\/key>[[:space:]]*$/\1/p' <<< "$xml")"
    [[ "$keys" == "$ENTITLEMENT" ]] || die "Zack.app must have exactly one entitlement, $ENTITLEMENT"
    value="$(awk -v key="<key>$ENTITLEMENT</key>" '
        found { gsub(/[ \t]/, ""); print; exit }
        { line = $0; gsub(/[ \t]/, "", line) }
        line == key { found = 1 }
    ' <<< "$xml")"
    [[ "$value" == "<true/>" ]] || die "$ENTITLEMENT in Zack.app is not true"
    echo "  entitlements: $ENTITLEMENT = true only"

    [[ ! -e "$app/Contents/Resources/FluidAudio_FluidAudio.bundle" ]] \
        || die "FluidAudio_FluidAudio.bundle is in Zack.app"
    value="$(plutil -extract SUFeedURL raw -o - "$app/Contents/Info.plist" 2> /dev/null || true)"
    [[ "$value" == "$FEED" ]] || die "SUFeedURL in Zack.app is not $FEED"
    value="$(plutil -extract SUPublicEDKey raw -o - "$app/Contents/Info.plist" 2> /dev/null || true)"
    [[ "$value" == "$KEY" ]] || die "SUPublicEDKey in Zack.app is not the expected public key"
    echo "  no speech synthesis lexicon, SUFeedURL $FEED, SUPublicEDKey set"

    # Sparkle compares CFBundleVersion, which App/project.yml derives from MARKETING_VERSION.
    for name in CFBundleShortVersionString CFBundleVersion; do
        value="$(plutil -extract "$name" raw -o - "$app/Contents/Info.plist" 2> /dev/null || true)"
        [[ "$value" == "$VERSION" ]] || die "$name in Zack.app is not $VERSION"
    done
    echo "  CFBundleShortVersionString and CFBundleVersion $VERSION"

    value="$(team_of "$app")" || die "cannot read the team of Zack.app"
    [[ "$value" == "$TEAM" ]] || die "Zack.app is not signed by the team from App/Local.xcconfig"
    for code in "$framework" "$framework/Versions/Current/Autoupdate" "$framework/Versions/Current/Updater.app" \
        "$framework"/Versions/Current/XPCServices/*.xpc; do
        [[ -e "$code" ]] || { [[ "$code" == *'*.xpc' ]] && continue; die "missing ${code#"$app/"}"; }
        value="$(team_of "$code")" || die "${code#"$app/"} is not signed"
        [[ "$value" == "$TEAM" ]] || die "${code#"$app/"} is not signed by the team of Zack.app"
    done
    echo "  Sparkle and its helpers signed by the team of Zack.app"
}

# Step 7: notarize a temporary ZIP, staple the app, let Gatekeeper confirm.
notarize() {
    step "notarize (takes a few minutes)"
    local zip="$WORK/notarize.zip" log="$WORK/notarytool.log" id out
    ditto -c -k --keepParent "$OUT/Zack.app" "$zip" || die "cannot zip Zack.app for notarization"
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$log" | mask || true
    if ! grep -Eq '^[[:space:]]+status: Accepted' "$log"; then
        id="$(awk '$1 == "id:" { print $2; exit }' "$log")"
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" 2>&1 | mask || true
        fi
        die "notarization failed"
    fi
    xcrun stapler staple "$OUT/Zack.app" 2>&1 | mask || die "stapler staple failed"
    out="$(spctl --assess --type execute -vv "$OUT/Zack.app" 2>&1)" \
        || { printf '%s\n' "$out" | mask >&2; die "Gatekeeper rejects Zack.app"; }
    [[ "$out" == *"Notarized Developer ID"* ]] \
        || { printf '%s\n' "$out" | mask >&2; die "Gatekeeper does not report Notarized Developer ID"; }
    echo "  Gatekeeper: Notarized Developer ID"
}

# Step 8: update ZIP, EdDSA signature, appcast with exactly one item.
package_feed() {
    step "package and appcast"
    local sign format='^sparkle:edSignature="[A-Za-z0-9+/=]+" length="[0-9]+"$'
    ZIP="$OUT/Zack-$VERSION.zip"
    ditto -c -k --sequesterRsrc --keepParent "$OUT/Zack.app" "$ZIP" || die "cannot create $ZIP"
    if [[ "$MODE" == local ]]; then
        sign="$("$SPARKLE_BIN/sign_update" --account "$TEST_KEY_ACCOUNT" "$ZIP")" || die "sign_update failed"
    else
        sign="$("$SPARKLE_BIN/sign_update" "$ZIP")" || die "sign_update failed"
    fi
    [[ "$sign" =~ $format ]] || die "unexpected output from sign_update"
    # write_appcast checks every step itself, so the || does not weaken it.
    write_appcast "$VERSION" "$ZIP_URL" "$sign" "$NOTES" "$OUT/appcast.xml" || die "cannot write $OUT/appcast.xml"
    echo "  $ZIP, $OUT/appcast.xml"
    if [[ "$MODE" == local ]]; then
        # Served on its own, so the HTTP server never exposes the archive or the app next to it.
        # shellcheck disable=SC2015 # die if either step fails
        mkdir -p "$OUT/feed" && cp "$ZIP" "$OUT/appcast.xml" "$OUT/feed/" || die "cannot fill $OUT/feed"
        echo "  test feed in $OUT/feed; serve it with:"
        echo "  python3 -m http.server 8000 --bind 127.0.0.1 --directory \"$PWD/$OUT/feed\""
    fi
}

overview() {
    local file
    if [[ "$MODE" == release ]]; then
        echo "  Zack $VERSION, tag v$VERSION, $REPO"
    else
        echo "  Zack $VERSION, $REPO (dry run, no tag required)"
    fi
    for file in "$ZIP" "$OUT/appcast.xml"; do
        printf '  %-22s %12s bytes\n' "${file##*/}" "$(stat -f %z "$file")"
    done
}

# Step 9: push, then create the release, or finish a draft an interrupted run left behind.
publish() {
    step "publish"
    local draft commits
    overview
    commits="$(git log --oneline refs/remotes/origin/main..refs/heads/main)" || die "git log failed"
    echo "  commits git push origin main will push:"
    printf '%s\n' "${commits:-none}" | sed 's/^/    /'
    confirm "veröffentlichen? (ja)"
    git push origin main || die "git push origin main failed"
    # The full ref, so a branch of the same name cannot make the push ambiguous.
    git push origin "refs/tags/v$VERSION" || die "git push origin refs/tags/v$VERSION failed"
    draft="$(release_view "v$VERSION" isDraft .isDraft)" || die "gh release view v$VERSION failed"
    case "$draft" in
        "")
            gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --title "Zack $VERSION" \
                --notes-file "$NOTES" --verify-tag --latest \
                || die "gh release create failed; run again to finish the draft"
            ;;
        true)
            # Files in the draft come from another build and do not match this appcast; replace both.
            gh release upload "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --clobber \
                || die "gh release upload failed; run again"
            gh release edit "v$VERSION" --repo "$REPO" --title "Zack $VERSION" --notes-file "$NOTES" \
                --draft=false --latest || die "gh release edit failed; run again"
            ;;
        *) die "release v$VERSION is already published; a broken release is replaced by a higher version" ;;
    esac
}

# Run "$@" up to three times, 10 s apart: GitHub's download servers may lag behind a new release.
retry() {
    local attempt
    for attempt in 1 2 3; do
        "$@" && return 0
        if ((attempt < 3)); then
            echo "  attempt $attempt failed, again in 10 s" >&2
            sleep 10
        fi
    done
    return 1
}

feed_offers_version() {
    local feed
    feed="$(curl -fsSL "$FEED_URL")" || return 1
    [[ "$feed" == *"<sparkle:version>$VERSION</sparkle:version>"* ]]
}

zip_matches() {
    curl -fsSL -o "$WORK/download.zip" "$ZIP_URL" || return 1
    [[ "$(shasum -a 256 < "$WORK/download.zip")" == "$(shasum -a 256 < "$ZIP")" ]]
}

# Step 10: the public feed offers the new version, the public ZIP matches the local one.
postcheck() {
    step "post-check"
    retry feed_offers_version || die "the feed at $FEED_URL does not offer $VERSION"
    retry zip_matches || die "the ZIP at $ZIP_URL is missing or differs from $ZIP"
    echo "  feed offers $VERSION, ZIP checksum matches"
}

main() {
    WORK="$(mktemp -d)" || die "mktemp failed"
    trap 'rm -rf "$WORK"' EXIT
    preflight
    gate --static-only
    if [[ "$MODE" != local ]]; then advisories; fi
    gate --skip-static
    build_export
    verify_bundle
    if [[ "$MODE" != local ]]; then notarize; fi
    package_feed
    case "$MODE" in
        local) echo "local build complete: not notarized, nothing published" ;;
        dry-run)
            overview
            echo "dry run complete: nothing pushed or published"
            ;;
        release)
            publish
            postcheck
            echo "released Zack $VERSION"
            ;;
    esac
}

self_test() {
    local dir
    dir="$(mktemp -d)"
    # Expanded now: the trap fires after this function has returned.
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    cat > "$dir/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

- Pending change

## [1.0.1] - 2026-11-02

- Second fix

## [1.0.10] - 2026-11-03

- Tenth patch

## [1.0.0] - 2026-11-01

### Added

- First release
MD
    printf '## [2.0.0] - x\n\n\n## [1.0.0] - x\n\n- old\n' > "$dir/EMPTY.md"

    local got want
    got="$(changelog_section 1.0.0 "$dir/CHANGELOG.md")" || { echo "self-test: section" >&2; return 1; }
    want=$'### Added\n\n- First release'
    [[ "$got" == "$want" ]] || { echo "self-test: section" >&2; return 1; }
    got="$(changelog_section Unreleased "$dir/CHANGELOG.md")" || { echo "self-test: section" >&2; return 1; }
    [[ "$got" == "- Pending change" ]] || { echo "self-test: section" >&2; return 1; }
    got="$(changelog_section 1.0.1 "$dir/CHANGELOG.md")" || { echo "self-test: section" >&2; return 1; }
    [[ "$got" == "- Second fix" ]] || { echo "self-test: section" >&2; return 1; }

    if changelog_section 9.9.9 "$dir/CHANGELOG.md" > /dev/null; then echo "self-test: missing section" >&2; return 1; fi
    if changelog_section 1.0 "$dir/CHANGELOG.md" > /dev/null; then echo "self-test: missing section" >&2; return 1; fi
    if changelog_section 2.0.0 "$dir/EMPTY.md" > /dev/null; then echo "self-test: missing section" >&2; return 1; fi
    if changelog_section 1.0.x "$dir/CHANGELOG.md" > /dev/null; then echo "self-test: missing section" >&2; return 1; fi

    local sign='sparkle:edSignature="c2lnbmF0dXJl" length="12345"'
    printf '%s\n' '- Fix <tag> & ⌃⌥V' > "$dir/notes.md"
    write_appcast 1.0.1 "$DOWNLOAD_PREFIX/v1.0.1/Zack-1.0.1.zip" "$sign" "$dir/notes.md" "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    xmllint --noout "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    grep -qF '<![CDATA[- Fix <tag> & ⌃⌥V' "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    grep -qF 'sparkle:format="markdown"' "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    grep -qF '<sparkle:version>1.0.1</sparkle:version>' "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    grep -qF '<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>' "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }
    grep -qF "$sign/>" "$dir/appcast.xml" || { echo "self-test: xml" >&2; return 1; }

    printf '%s\n' 'bad ]]> notes' > "$dir/bad.md"
    if write_appcast 1.0.1 "$DOWNLOAD_PREFIX/v1.0.1/Zack-1.0.1.zip" "$sign" "$dir/bad.md" "$dir/bad.xml" 2> /dev/null; then
        echo "self-test: cdata terminator" >&2; return 1
    fi
    [[ ! -e "$dir/bad.xml" ]] || { echo "self-test: cdata terminator" >&2; return 1; }

    # Called from if, so set -e is off inside write_appcast: it must still refuse empty or unreadable notes.
    local url="$DOWNLOAD_PREFIX/v1.0.1/Zack-1.0.1.zip"
    printf '\n  \n' > "$dir/blank.md"
    if write_appcast 1.0.1 "$url" "$sign" "$dir/blank.md" "$dir/blank.xml" 2> /dev/null; then
        echo "self-test: empty notes" >&2; return 1
    fi
    if write_appcast 1.0.1 "$url" "$sign" "$dir/none.md" "$dir/none.xml" 2> /dev/null; then
        echo "self-test: missing notes" >&2; return 1
    fi
    [[ ! -e "$dir/blank.xml" && ! -e "$dir/none.xml" ]] || { echo "self-test: empty notes" >&2; return 1; }

    version_greater 1.0.1 1.0.0 || { echo "self-test: version_greater" >&2; return 1; }
    version_greater 1.10.0 1.9.0 || { echo "self-test: version_greater" >&2; return 1; }
    if version_greater 1.0.0 1.0.0; then echo "self-test: version_greater" >&2; return 1; fi
    if version_greater 1.0.0 1.0.1; then echo "self-test: version_greater" >&2; return 1; fi

    # Fake values only; this MASK_TEAMS shadows the global one for mask.
    local MASK_TEAMS="ABCDE12345"
    got="$(printf '%s\n' 'error: no certificate for team ABCDE12345' \
        'Signing Identity: "Apple Development: Max Mustermann (ABCDE12345)"' \
        'origin=Developer ID Application: Example GmbH (ABCDE12345)' \
        'Apple ID max.mustermann@example.com rejected' 'unrelated line' | mask)"
    want='error: no certificate for team <team>
Signing Identity: "Apple Development: <masked>"
origin=Developer ID Application: <masked>
Apple ID <email> rejected
unrelated line'
    [[ "$got" == "$want" ]] || { echo "self-test: mask" >&2; return 1; }

    # Independent of App/Local.xcconfig: commented, conditional, prefixed and repeated assignments, bad team IDs.
    cat > "$dir/Local.xcconfig" <<'XCCONFIG'
// DEVELOPMENT_TEAM = AAAAAAAAAA
DEVELOPMENT_TEAM = BBBBBBBBBB
DEVELOPMENT_TEAM[config=Debug] = CCCCCCCCCC
  DEVELOPMENT_TEAM=DDDDDDDDDD // personal team
DEVELOPMENT_TEAMS = EEEEEEEEEE
ZACK_RELEASE_TEAM = CHANGEME
SHORT_TEAM = ABC1234
LOWER_TEAM = abcde12345
LONG_TEAM = ABCDE123456
EMPTY_TEAM =
XCCONFIG
    [[ "$(xcconfig_value DEVELOPMENT_TEAM "$dir/Local.xcconfig")" == DDDDDDDDDD ]] \
        || { echo "self-test: xcconfig" >&2; return 1; }
    [[ "$(xcconfig_value ZACK_RELEASE_TEAM "$dir/Local.xcconfig")" == CHANGEME ]] \
        || { echo "self-test: xcconfig" >&2; return 1; }
    [[ "$(team_setting DEVELOPMENT_TEAM "$dir/Local.xcconfig")" == DDDDDDDDDD ]] \
        || { echo "self-test: team_setting" >&2; return 1; }
    local name
    for name in ZACK_RELEASE_TEAM SHORT_TEAM LOWER_TEAM LONG_TEAM EMPTY_TEAM MISSING_TEAM; do
        [[ -z "$(team_setting "$name" "$dir/Local.xcconfig")" ]] \
            || { echo "self-test: team_setting $name" >&2; return 1; }
    done

    # Only a bundle directly inside the temp folder is deleted; a nested path the log names stays.
    local logs="$dir/temp" bundle="Zack_2026-11-01_12-00-00.000.xcdistributionlogs"
    mkdir -p "$logs/$bundle" "$logs/nested/$bundle" || { echo "self-test: distribution logs" >&2; return 1; }
    printf 'Created bundle at path "%s".\n' "$logs/$bundle" "$logs/nested/$bundle" > "$dir/export.log"
    remove_distribution_logs "$dir/export.log" "$logs"
    [[ ! -e "$logs/$bundle" && -d "$logs/nested/$bundle" ]] || { echo "self-test: distribution logs" >&2; return 1; }

    # Without a temp folder (getconf prints nothing) nothing is deleted, not even a bundle directly under /.
    local removed=()
    getconf() { :; }
    rm() { removed+=("$@"); }
    printf 'Created bundle at path "/%s".\n' "$bundle" > "$dir/root.log"
    remove_distribution_logs "$dir/root.log"
    unset -f getconf rm
    ((${#removed[@]} == 0)) || { echo "self-test: distribution logs without temp folder" >&2; return 1; }

    echo "release self-test passed"
}

usage() {
    echo "usage: $0 [--local | --dry-run | --self-test]" >&2
    exit 2
}

if (($# > 1)); then usage; fi
case "${1-}" in
    --self-test) self_test ;;
    --local)
        MODE=local
        main
        ;;
    --dry-run)
        MODE=dry-run
        main
        ;;
    "")
        if (($# == 1)); then usage; fi
        MODE=release
        main
        ;;
    *) usage ;;
esac
