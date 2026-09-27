#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/install-ios.sh [options]

Build Marquee and install it on a paired iPhone (Wi-Fi or USB) via devicectl.
The first server is seeded from Ember's active server in ~/.ember/servers.json.

Options:
  --device <udid>   Target device (env: MARQUEE_IOS_DEVICE). Default: first available iPhone
  --team <id>       Development team (env: DEVELOPMENT_TEAM). Default: from the Apple Development cert
  --simulator       Build for the booted simulator instead, install and launch there
  --no-seed         Don't bake the Ember server or TMDB key into the build
  --no-launch       Install only
  -h, --help        Show this help
USAGE
}

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/Marquee.xcodeproj"
scheme="Marquee"
bundle_id="com.abcdlsj.marquee"
device="${MARQUEE_IOS_DEVICE:-}"
team="${DEVELOPMENT_TEAM:-}"
simulator=false
seed=true
launch=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --device) device="$2"; shift 2 ;;
        --team) team="$2"; shift 2 ;;
        --simulator) simulator=true; shift ;;
        --no-seed) seed=false; shift ;;
        --no-launch) launch=false; shift ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
xcodegen generate --spec "$root/project.yml" --project "$root" --quiet

# Seed values travel as environment variables and are referenced indirectly in build
# settings, so xcodebuild never echoes the password in its command-line log.
if [[ "$seed" == true && -f "$HOME/.ember/servers.json" ]]; then
    eval "$(python3 - <<'PY'
import json, os, shlex
d = json.load(open(os.path.expanduser("~/.ember/servers.json")))
servers = d.get("servers") or []
if servers:
    s = servers[min(d.get("active_server", 0), len(servers) - 1)]
    for k, v in {"NAME": s.get("name", ""), "URL": s.get("url", ""), "USER": s.get("username", ""), "PASSWORD": s.get("password", "")}.items():
        print(f"export MARQUEE_BUILD_SEED_{k}={shlex.quote(v)}")
PY
)"
    echo "Seed     : ${MARQUEE_BUILD_SEED_NAME:-?} (${MARQUEE_BUILD_SEED_URL:-?})"
fi
if [[ "$seed" == true ]]; then
    tmdb_file="$HOME/.config/marquee/tmdb_key"
    if [[ -z "${MARQUEE_TMDB_KEY:-}" && -f "$tmdb_file" ]]; then MARQUEE_TMDB_KEY="$(tr -d '[:space:]' < "$tmdb_file")"; fi
    export MARQUEE_BUILD_SEED_TMDB_KEY="${MARQUEE_TMDB_KEY:-}"
    [[ -n "$MARQUEE_BUILD_SEED_TMDB_KEY" ]] && echo "TMDB     : key provided"
fi
seed_settings=(
    'MARQUEE_SEED_NAME=$(MARQUEE_BUILD_SEED_NAME)'
    'MARQUEE_SEED_URL=$(MARQUEE_BUILD_SEED_URL)'
    'MARQUEE_SEED_USER=$(MARQUEE_BUILD_SEED_USER)'
    'MARQUEE_SEED_PASSWORD=$(MARQUEE_BUILD_SEED_PASSWORD)'
    'MARQUEE_SEED_TMDB_KEY=$(MARQUEE_BUILD_SEED_TMDB_KEY)'
)

redact() {
    MARQUEE_REDACT="${MARQUEE_BUILD_SEED_PASSWORD:-}" MARQUEE_REDACT2="${MARQUEE_BUILD_SEED_TMDB_KEY:-}" perl -pe '
        s/\Q$ENV{MARQUEE_REDACT}\E/[redacted]/g if length $ENV{MARQUEE_REDACT};
        s/\Q$ENV{MARQUEE_REDACT2}\E/[redacted]/g if length $ENV{MARQUEE_REDACT2};'
}

build() {
    local log=/tmp/marquee-build.log
    set +e
    xcodebuild -project "$project" -scheme "$scheme" -configuration Debug -derivedDataPath "$root/build/$1" "${@:2}" build \
        "${seed_settings[@]}" 2>&1 | redact > "$log"
    local status=${PIPESTATUS[0]}
    set -e
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$log" | sort -u || true
    [[ $status -eq 0 ]] || { echo "Build failed, see $log" >&2; exit "$status"; }
}

if [[ "$simulator" == true ]]; then
    sim="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for v in d.values() for x in v), ""))')"
    if [[ -z "$sim" ]]; then
        sim="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for k,v in d.items() if "iOS-26" in k for x in v if x["name"].startswith("iPhone")), ""))')"
        xcrun simctl boot "$sim"
    fi
    echo "Simulator: $sim"
    build sim -destination "id=$sim"
    app="$root/build/sim/Build/Products/Debug-iphonesimulator/Marquee.app"
    xcrun simctl install "$sim" "$app"
    [[ "$launch" == true ]] && xcrun simctl launch "$sim" "$bundle_id" >/dev/null
    echo "Installed on simulator."
    exit 0
fi

if [[ -z "$device" ]]; then
    tmp="$(mktemp -t marquee-devices).json"
    xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1 || true
    device="$(python3 - "$tmp" <<'PY'
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devs = []
for d in devs:
    hp = d.get("hardwareProperties", {}) or {}
    cp = d.get("connectionProperties", {}) or {}
    if hp.get("platform") == "iOS" and hp.get("deviceType") == "iPhone" and cp.get("pairingState") == "paired":
        print(hp.get("udid") or d.get("identifier")); break
PY
)"
    rm -f "$tmp"
fi
[[ -n "$device" ]] || { echo "No paired iPhone found. Pass --device <udid>." >&2; exit 2; }

if [[ -z "$team" ]]; then
    team="$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p' | head -n 1)"
fi
[[ -n "$team" ]] || { echo "No development team found. Pass --team <id>." >&2; exit 2; }

echo "Device   : $device"
echo "Team     : $team"
build device -destination "id=$device" -allowProvisioningUpdates -allowProvisioningDeviceRegistration "DEVELOPMENT_TEAM=$team"

app="$root/build/device/Build/Products/Debug-iphoneos/Marquee.app"
echo "==> Installing"
xcrun devicectl device install app --device "$device" "$app" 2>&1 | tail -n 5

if [[ "$launch" == true ]]; then
    echo "==> Launching"
    if ! xcrun devicectl device process launch --device "$device" "$bundle_id" >/tmp/marquee-launch.log 2>&1; then
        if grep -q -i "locked" /tmp/marquee-launch.log; then
            echo "iPhone is locked — unlock it and tap Marquee." >&2
        else
            echo "Launch failed (app is installed). Details: /tmp/marquee-launch.log" >&2
        fi
    fi
fi
echo "Done."
