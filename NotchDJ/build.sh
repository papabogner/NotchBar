#!/bin/zsh
# Builds "Notch DJ.app" into ./build. Usage: ./build.sh [--run]
#
# Signing, in this order:
#   1. "Notch DJ Local Signing"  (create it once with ./scripts/setup-signing.sh)
#   2. "NotchBar Local Signing"  (the parent project's certificate, if you have it)
#   3. ad hoc, with a warning. macOS then asks for its permissions again after every build.
# Release builds use a Developer ID certificate and notarization instead (see README).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release

APP="build/Notch DJ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchDJ "$APP/Contents/MacOS/NotchDJ"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for lproj in Resources/*.lproj(N); do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# SHA-1 of the first identity with that name. Valid (trusted) ones first, then any.
identity_hash() {
  local line
  line=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$1\"" | head -n 1 || true)
  if [[ -z "$line" ]]; then
    line=$(security find-identity -p codesigning 2>/dev/null | grep -F "\"$1\"" | head -n 1 || true)
  fi
  if [[ -n "$line" ]]; then
    print -r -- "$line" | awk '{print $2}'
  fi
}

SIGNED=""
for NAME in "Notch DJ Local Signing" "NotchBar Local Signing"; do
  HASH=$(identity_hash "$NAME")
  [[ -z "$HASH" ]] && continue
  if OUTPUT=$(codesign --force --sign "$HASH" --identifier com.local.notchdj "$APP" 2>&1); then
    SIGNED="$NAME"
    break
  fi
  print -r -- "warning: signing with \"$NAME\" failed:" >&2
  print -r -- "$OUTPUT" >&2
done

if [[ -n "$SIGNED" ]]; then
  print -r -- "Built $APP (signed with \"$SIGNED\")"
else
  codesign --force --sign - --identifier com.local.notchdj "$APP" >/dev/null
  print -r -- "Built $APP (ad hoc)"
  cat >&2 <<'EOF'

  ************************************************************************
  *  WARNING: Notch DJ is signed AD HOC.                                 *
  *                                                                      *
  *  macOS sees every build as a new app, so it asks for System Audio    *
  *  Recording and Automation again after each rebuild.                  *
  *                                                                      *
  *  Fix it once:   ./scripts/setup-signing.sh   then run ./build.sh     *
  ************************************************************************

EOF
fi

if [[ "${1:-}" == "--run" ]]; then
  pkill -x NotchDJ 2>/dev/null || true
  open "$APP"
fi
