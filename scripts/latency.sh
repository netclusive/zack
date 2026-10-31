#!/usr/bin/env bash
# p50/p95 of Zack's latency signposts from the system log: names, timings and flags only, never dictation text.
# The system log keeps the signposts for a few minutes only, so for longer rounds use --record: it captures
# them live while you dictate and reports when the time is up or on Ctrl-C.
# Usage: scripts/latency.sh [--record [30m]] [--last 5m] [--input file.ndjson]
# --record without a duration records for 30 minutes.
set -euo pipefail

USAGE="usage: $0 [--record [30m]] [--last 5m] [--input file.ndjson]"
LAST="1h"
INPUT=""
RECORD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --record)
            if [[ $# -ge 2 && "$2" != --* ]]; then
                RECORD="$2"
                shift 2
            else
                RECORD="30m"
                shift
            fi
            ;;
        --last | --input)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "$1 needs a value; $USAGE" >&2
                exit 2
            fi
            if [[ "$1" == --last ]]; then LAST="$2"; else INPUT="$2"; fi
            shift 2
            ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
done

PARSER="$(cat <<'PY'
import json
import sys
from datetime import datetime

FORMAT = "%Y-%m-%d %H:%M:%S.%f%z"
begins, groups = {}, {}

for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    event = json.loads(line)
    if event.get("eventType") != "signpostEvent":
        continue
    key = (event.get("signpostName"), event.get("signpostID"))
    kind = event.get("signpostType")
    # Dropped marks (release without insert, retry) have a begin and no end and are never counted.
    if kind == "begin":
        begins[key] = event["timestamp"]
    elif kind == "end" and key in begins:
        start = datetime.strptime(begins.pop(key), FORMAT)
        end = datetime.strptime(event["timestamp"], FORMAT)
        ms = (end - start).total_seconds() * 1000
        name = key[0]
        labels = {"pill": ["Drücken bis Pille"], "micstart": ["Mikrofonstart, kalt"]}.get(name, [])
        if name == "insert":
            fields = dict(part.split("=", 1) for part in event.get("eventMessage", "").split() if "=" in part)
            label = "Loslassen bis eingefügt, " + ("mit KI" if fields.get("cleaner") == "1" else "ohne KI")
            labels.append(label)
            if 8 <= int(fields.get("audio", "0")) <= 12:
                labels.append(label + ", 8-12 s Audio")
        for label in labels:
            groups.setdefault(label, []).append(ms)

def percentile(values, p):
    ordered = sorted(values)
    rank = max(1, -(-len(ordered) * p // 100))
    return ordered[min(rank, len(ordered)) - 1]

if not groups:
    print("keine Messwerte")
for label in sorted(groups):
    values = groups[label]
    print(f"{label}: n={len(values)}, p50 {percentile(values, 50):.0f} ms, p95 {percentile(values, 95):.0f} ms")
PY
)"

PREDICATE='subsystem == "com.netclusive.zack" AND category == "latency"'

if [[ -n "$RECORD" ]]; then
    CAPTURE="$(mktemp)"
    trap 'rm -f "$CAPTURE"' EXIT
    echo "recording until $RECORD are over or Ctrl-C; dictate now" >&2
    # Ctrl-C stops only the stream (the handler keeps the script alive), then the report is printed.
    trap ':' INT
    /usr/bin/log stream --signpost --style ndjson --timeout "$RECORD" --predicate "$PREDICATE" > "$CAPTURE" || true
    trap - INT
    /usr/bin/python3 -I -c "$PARSER" < "$CAPTURE"
elif [[ -n "$INPUT" ]]; then
    /usr/bin/python3 -I -c "$PARSER" < "$INPUT"
else
    /usr/bin/log show --last "$LAST" --signpost --style ndjson \
        --predicate "$PREDICATE" \
        | /usr/bin/python3 -I -c "$PARSER"
fi
