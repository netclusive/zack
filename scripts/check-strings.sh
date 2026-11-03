#!/usr/bin/env bash
# Compares the interface strings the compiler extracted (*.stringsdata) with the String Catalogs; one line per problem.
# Usage: scripts/check-strings.sh <derived-data> <configuration> [--inventory <file>]
#        scripts/check-strings.sh --self-test
#   <derived-data>  Xcode derived data folder, e.g. .build/xcode-app (read from Build/Intermediates.noindex)
#   <configuration> build configuration whose extraction is read, e.g. Release
#   --inventory     JSON object {"<area>": [keys]}; every key must be extracted and have a German value equal to the key
#   --self-test     runs the check against a throwaway repo and derived data
# Exit 0 with "strings: <n> keys from <m> files match the catalogs", otherwise exit 1.
set -euo pipefail
cd "$(dirname "$0")/.."

# check <repo root> <derived-data> <configuration> [inventory file]
check() {
    /usr/bin/python3 -I - "$@" <<'PY'
import json
import os
import sys

root = os.path.realpath(sys.argv[1])
derived, configuration = sys.argv[2], sys.argv[3]
inventory_file = sys.argv[5] if len(sys.argv) > 5 else None

AREAS = ["App/Zack", "Sources/ZackDesktop", "Sources/ZackUpdate"]
problems = []
extracted = {area: set() for area in AREAS}
files_used = 0
keyed_files = 0


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def area_of(relative):
    for area in AREAS:
        if relative.startswith(area + "/"):
            return area
    return None


def unit_ok(unit):
    return (
        isinstance(unit, dict)
        and unit.get("state") == "translated"
        and bool(unit.get("value"))
    )


def localization_ok(localization):
    if not isinstance(localization, dict):
        return False
    if "stringUnit" in localization:
        return unit_ok(localization["stringUnit"])
    plural = localization.get("variations", {}).get("plural")
    if isinstance(plural, dict):
        return all(unit_ok(plural.get(form, {}).get("stringUnit")) for form in ("one", "other"))
    return False


def german_value(entry):
    german = entry.get("localizations", {}).get("de", {})
    if "stringUnit" in german:
        return german["stringUnit"].get("value")
    other = german.get("variations", {}).get("plural", {}).get("other", {})
    return other.get("stringUnit", {}).get("value")


catalogs = {}
for area in AREAS:
    path = os.path.join(root, area, "Localizable.xcstrings")
    try:
        catalogs[area] = load(path).get("strings", {})
    except FileNotFoundError:
        # No catalog yet: every key of the area is reported as missing.
        catalogs[area] = None
    except (OSError, ValueError) as error:
        catalogs[area] = None
        problems.append("%s/Localizable.xcstrings: cannot read (%s)" % (area, error))

base = os.path.join(derived, "Build", "Intermediates.noindex")
found = []
for folder, _, names in os.walk(base):
    if configuration in os.path.relpath(folder, base).split(os.sep):
        found += [os.path.join(folder, name) for name in names if name.endswith(".stringsdata")]

for path in sorted(found):
    try:
        data = load(path)
    except (OSError, ValueError) as error:
        problems.append("%s: cannot read (%s)" % (path, error))
        continue
    source = data.get("source")
    if not source:
        continue
    source = os.path.realpath(source)
    if not os.path.exists(source):
        continue
    relative = os.path.relpath(source, root)
    if not (relative.startswith("App" + os.sep) or relative.startswith("Sources" + os.sep)):
        continue
    files_used += 1
    area = area_of(relative)
    if any(data.get("tables", {}).values()):
        keyed_files += 1
    for table, items in data.get("tables", {}).items():
        for item in items:
            key = item["key"]
            if area is None or table != "Localizable":
                problems.append("%s: %s" % (relative, key))
                continue
            extracted[area].add(key)
            entry = (catalogs[area] or {}).get(key)
            if entry is None:
                problems.append("%s: %s" % (relative, key))
            elif entry.get("shouldTranslate") is False:
                continue
            elif not localization_ok(entry.get("localizations", {}).get("en")):
                problems.append("%s: %s" % (relative, key))

if files_used == 0:
    problems.append("no string data; build the app first")

if inventory_file:
    inventory = load(inventory_file)
    for area in AREAS:
        for key in inventory.get(area, []):
            if key not in extracted[area]:
                problems.append("%s: %s (in the inventory, not extracted)" % (area, key))
            entry = (catalogs[area] or {}).get(key)
            if entry is None:
                problems.append("%s: %s (in the inventory, not in the catalog)" % (area, key))
            elif entry.get("shouldTranslate") is not False and german_value(entry) != key:
                problems.append("%s: %s (German value differs from the key)" % (area, key))

if problems:
    for problem in sorted(set(problems)):
        print(problem, file=sys.stderr)
    sys.exit(1)

total = sum(len(keys) for keys in extracted.values())
print("strings: %d keys from %d files match the catalogs" % (total, keyed_files))
PY
}

# Fixture helpers: catalog <file> <entry>... and data <file> <source> <table> <key>...
catalog() {
    local file="$1" body="" entry
    shift
    for entry in "$@"; do body+="${body:+,}$entry"; done
    mkdir -p "$(dirname "$file")"
    printf '{"sourceLanguage":"de","strings":{%s},"version":"1.0"}\n' "$body" > "$file"
}

# Entry builders: en_entry <key> <en value>, de_entry <key>, skip_entry <key>, plural_entry <key>
en_entry() {
    printf '"%s":{"localizations":{"de":{"stringUnit":{"state":"translated","value":"%s"}},"en":{"stringUnit":{"state":"translated","value":"%s"}}}}' "$1" "$1" "$2"
}
de_entry() {
    printf '"%s":{"localizations":{"de":{"stringUnit":{"state":"translated","value":"%s"}}}}' "$1" "$1"
}
skip_entry() {
    printf '"%s":{"shouldTranslate":false}' "$1"
}
plural_entry() {
    local unit='{"stringUnit":{"state":"translated","value":"x"}}'
    printf '"%s":{"localizations":{"de":{"variations":{"plural":{"one":%s,"other":{"stringUnit":{"state":"translated","value":"%s"}}}}},"en":{"variations":{"plural":{"one":%s,"other":%s}}}}}' \
        "$1" "$unit" "$1" "$unit" "$unit"
}

data() {
    local file="$1" source="$2" table="$3" items="" key
    shift 3
    for key in "$@"; do
        items+="${items:+,}{\"key\":\"$key\",\"location\":{\"startingColumn\":1,\"startingLine\":1,\"startingOffset\":0}}"
    done
    mkdir -p "$(dirname "$file")"
    printf '{"source":"%s","tables":{"%s":[%s]},"version":1}\n' "$source" "$table" "$items" > "$file"
}

self_test() {
    local dir root derived inter out
    dir="$(mktemp -d)"
    # shellcheck disable=SC2064 # expanded now: the trap fires after this function has returned
    trap "rm -rf '$dir'" EXIT
    root="$dir/repo"
    derived="$dir/derived"
    inter="$derived/Build/Intermediates.noindex"
    mkdir -p "$root/App/Zack" "$root/Sources/ZackDesktop" "$root/Sources/ZackUpdate" "$root/Sources/ZackCore" \
        "$root/.build/xcode-packages/pkg"
    touch "$root/Sources/ZackDesktop/A.swift" "$root/Sources/ZackUpdate/B.swift" "$root/Sources/ZackCore/C.swift" \
        "$root/App/Zack/D.swift" "$root/.build/xcode-packages/pkg/E.swift"
    # Resolve like the checker does (macOS temp folders are symlinks).
    root="$(cd "$root" && pwd -P)"

    reset() {
        rm -rf "$derived"
        catalog "$root/Sources/ZackDesktop/Localizable.xcstrings" "$(en_entry Hello Hi)" "$(skip_entry Skip)" \
            "$(de_entry OnlyDe)" "$(plural_entry 'Lines %lld')"
        catalog "$root/Sources/ZackUpdate/Localizable.xcstrings" "$(en_entry Update Refresh)"
        catalog "$root/App/Zack/Localizable.xcstrings" "$(en_entry Menu Menu)"
    }
    # expect <name> <exit code> <stderr/stdout substring> -- <args>
    expect() {
        local name="$1" want="$2" text="$3" rc=0
        shift 4
        out="$(check "$root" "$derived" "$@" 2>&1)" || rc=$?
        [[ "$rc" == "$want" ]] || { echo "self-test: $name: exit $rc, want $want: $out" >&2; return 1; }
        [[ "$out" == *"$text"* ]] || { echo "self-test: $name: output lacks '$text': $out" >&2; return 1; }
    }

    reset
    data "$inter/Z.build/Release/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable Hello Skip 'Lines %lld'
    data "$inter/Z.build/Release/b.stringsdata" "$root/Sources/ZackUpdate/B.swift" Localizable Update
    expect "complete" 0 "strings: 4 keys from 2 files match the catalogs" -- Release

    data "$inter/Z.build/Release/c.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable Missing
    expect "missing key" 1 "Sources/ZackDesktop/A.swift: Missing" -- Release

    reset
    data "$inter/Z.build/Release/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable OnlyDe
    expect "only de" 1 "Sources/ZackDesktop/A.swift: OnlyDe" -- Release

    reset
    data "$inter/Z.build/Release/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable Hello
    data "$inter/P.build/Release/e.stringsdata" "$root/.build/xcode-packages/pkg/E.swift" Localizable Foreign
    expect "package source skipped" 0 "strings: 1 keys from 1 files" -- Release

    data "$inter/Z.build/Release/f.stringsdata" "$root/Sources/ZackCore/C.swift" Localizable Hello
    expect "other source" 1 "Sources/ZackCore/C.swift: Hello" -- Release

    reset
    data "$inter/Z.build/Release/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Strings Hello
    expect "other table" 1 "Sources/ZackDesktop/A.swift: Hello" -- Release

    reset
    data "$inter/Z.build/Debug/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable Hello
    expect "other configuration" 1 "no string data; build the app first" -- Release

    reset
    data "$inter/P.build/Release/e.stringsdata" "$root/.build/xcode-packages/pkg/E.swift" Localizable Foreign
    expect "no data" 1 "no string data; build the app first" -- Release

    reset
    data "$inter/Z.build/Release/a.stringsdata" "$root/Sources/ZackDesktop/A.swift" Localizable Hello 'Lines %lld'
    printf '{"Sources/ZackDesktop":["Hello","Lines %%lld"]}\n' > "$dir/inventory.json"
    expect "inventory complete" 0 "strings: 2 keys from 1 files" -- Release --inventory "$dir/inventory.json"
    printf '{"Sources/ZackDesktop":["Hello","Gone"]}\n' > "$dir/inventory.json"
    expect "inventory not extracted" 1 "Sources/ZackDesktop: Gone" -- Release --inventory "$dir/inventory.json"

    echo "check-strings self-test passed"
}

usage() {
    echo "usage: $0 <derived-data> <configuration> [--inventory <file>] | --self-test" >&2
    exit 2
}

case "${1-}" in
    --self-test)
        if (($# != 1)); then usage; fi
        self_test
        ;;
    "") usage ;;
    *)
        if (($# != 2 && $# != 4)); then usage; fi
        if (($# == 4)) && [[ "$3" != --inventory ]]; then usage; fi
        check "$PWD" "$@"
        ;;
esac
