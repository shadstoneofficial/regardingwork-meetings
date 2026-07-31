#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
APP_PATH="${OUTPUT_DIR}/RegardingWork Meetings.app"
CONTENTS="${APP_PATH}/Contents"

cd "${PROJECT_ROOT}"
swift build -c release

rm -rf "${APP_PATH}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
install -m 0755 \
    ".build/release/regardingwork-meetings" \
    "${CONTENTS}/MacOS/regardingwork-meetings"

sed \
    -e "s/@VERSION@/${APP_VERSION}/g" \
    -e "s/@BUILD_NUMBER@/${BUILD_NUMBER}/g" \
    packaging/Info.plist > "${CONTENTS}/Info.plist"
plutil -lint "${CONTENTS}/Info.plist"

ICON_WORK="$(mktemp -d)"
trap 'rm -rf "${ICON_WORK}"' EXIT
ICONSET="${ICON_WORK}/AppIcon.iconset"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" Assets/AppIcon.png \
        --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" Assets/AppIcon.png \
        --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${CONTENTS}/Resources/AppIcon.icns"
install -m 0644 LICENSE "${CONTENTS}/Resources/LICENSE"
install -m 0644 THIRD_PARTY_NOTICES.md "${CONTENTS}/Resources/THIRD_PARTY_NOTICES.md"
install -m 0644 PRIVACY.md "${CONTENTS}/Resources/PRIVACY.md"

if [[ "${SKIP_CODESIGN:-0}" == "1" ]]; then
    echo "Built unsigned app: ${APP_PATH}"
else
    codesign --force --sign - \
        --entitlements packaging/RegardingWorkMeetings.entitlements \
        "${APP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
    echo "Built ad-hoc signed development app: ${APP_PATH}"
fi
