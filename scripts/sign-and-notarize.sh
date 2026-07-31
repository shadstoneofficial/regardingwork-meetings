#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.1.0}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
APP_PATH="${APP_PATH:-${OUTPUT_DIR}/RegardingWork Meetings.app}"
DMG_PATH="${OUTPUT_DIR}/RegardingWork-Meetings-${APP_VERSION}.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"
MAX_POLLS="${MAX_POLLS:-60}"
POLL_SECONDS="${POLL_SECONDS:-10}"

notarize_and_staple() {
    local submission_artifact="$1"
    local staple_target="$2"
    local response
    local submission_id
    local status
    response="$(mktemp)"
    xcrun notarytool submit "${submission_artifact}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --output-format json > "${response}"
    submission_id="$(plutil -extract id raw -o - "${response}")"
    echo "Notary submission: ${submission_id}"

    for ((poll = 1; poll <= MAX_POLLS; poll++)); do
        xcrun notarytool info "${submission_id}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --output-format json > "${response}"
        status="$(plutil -extract status raw -o - "${response}")"
        case "${status}" in
            Accepted)
                xcrun stapler staple "${staple_target}"
                xcrun stapler validate "${staple_target}"
                return 0
                ;;
            Invalid|Rejected)
                xcrun notarytool log "${submission_id}" \
                    --keychain-profile "${NOTARY_PROFILE}"
                return 1
                ;;
        esac
        sleep "${POLL_SECONDS}"
    done

    echo "Notarization timed out after ${MAX_POLLS} polls: ${submission_id}" >&2
    xcrun notarytool info "${submission_id}" \
        --keychain-profile "${NOTARY_PROFILE}"
    return 1
}

cd "${PROJECT_ROOT}"
APP_VERSION="${APP_VERSION}" BUILD_NUMBER="${BUILD_NUMBER:-1}" \
    SKIP_CODESIGN=1 OUTPUT_DIR="${OUTPUT_DIR}" scripts/build-app.sh

codesign --force --deep --options runtime --timestamp \
    --entitlements packaging/RegardingWorkMeetings.entitlements \
    --sign "${SIGNING_IDENTITY}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

APP_ZIP="${OUTPUT_DIR}/RegardingWork-Meetings-${APP_VERSION}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}"
notarize_and_staple "${APP_ZIP}" "${APP_PATH}"
rm -f "${APP_ZIP}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"

rm -f "${DMG_PATH}"
hdiutil create -volname "RegardingWork Meetings" \
    -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}"
codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
notarize_and_staple "${DMG_PATH}" "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

echo "Signed, notarized, and stapled: ${DMG_PATH}"
echo "No release was published."
