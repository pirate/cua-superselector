#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
build_dir="$project_dir/.build/$configuration"
app_dir="$project_dir/SuperSelector.app"
signing_identity="${SUPERSELECTOR_SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
    signing_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
            | head -n 1
    )"
fi

if [[ -z "$signing_identity" && "${SUPERSELECTOR_ALLOW_ADHOC:-0}" != "1" ]]; then
    cat >&2 <<'EOF'
No stable Apple Development code-signing identity is available.

Create one in Xcode → Settings → Accounts → select your team →
Manage Certificates… → + → Apple Development, then run this script again.

For disposable testing only, opt into a build-specific identity with:
  SUPERSELECTOR_ALLOW_ADHOC=1 ./scripts/build-app.sh

Ad-hoc rebuilds receive a new CDHash and therefore require Accessibility
permission again. The script refuses that insecure/confusing default.
EOF
    exit 2
fi

if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    echo "warning: using an ad-hoc signature; Accessibility permission will not survive rebuilds" >&2
fi

cd "$project_dir"
xcrun swift build -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/SuperSelector" "$app_dir/Contents/MacOS/SuperSelector"
cp "$project_dir/support/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign "$signing_identity" --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
