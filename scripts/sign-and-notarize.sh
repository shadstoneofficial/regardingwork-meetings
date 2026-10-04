#!/bin/bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.1.4}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
APP_PATH="${APP_PATH:-${OUTPUT_DIR}/RegardingWork Meetings.app}"
DMG_PATH="${OUTPUT_DIR}/RegardingWork-Meetings-${APP_VERSION}.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"
MAX_POLLS="${MAX_POLLS:-60}"
POLL_SECONDS="${POLL_SECONDS:-10}"
NOTARY_COMMAND_TIMEOUT="${NOTARY_COMMAND_TIMEOUT:-180}"
for number in "${MAX_POLLS}" "${POLL_SECONDS}" "${NOTARY_COMMAND_TIMEOUT}"; do
    [[ "${number}" =~ ^[1-9][0-9]*$ ]] || { echo "Notary limits must be positive integers" >&2; exit 2; }
done
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/regardingwork-meetings-dmg.XXXXXX")"
NOTARY_DIR="${OUTPUT_DIR}/notary"
mkdir -p "${NOTARY_DIR}"

cleanup() {
    rm -rf "${DMG_STAGE}"
}
trap cleanup EXIT

notary_command() {
    # A per-request deadline also bounds a stalled HTTP request, not only polling.
    /usr/bin/perl -e 'alarm shift; exec @ARGV or die "could not start notarytool\n"' \
        "${NOTARY_COMMAND_TIMEOUT}" xcrun notarytool "$@"
}

fetch_notary_log() {
    notary_command log "$1" --keychain-profile "${NOTARY_PROFILE}" \
        "${NOTARY_DIR}/$1-log.json" > "${NOTARY_DIR}/$1-log-request.txt" 2>&1 || true
    echo "Notary diagnostics retained locally; do not upload them without secret review." >&2
}

notarize_and_staple() {
    local submission_artifact="$1"
    local staple_target="$2"
    local response
    local submission_id
    local status
    response="${NOTARY_DIR}/$(basename "${submission_artifact}")-submit.json"
    # Do not blindly resubmit after an uncertain submission outcome.
    if ! notary_command submit "${submission_artifact}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --output-format json > "${response}" 2> "${response}.stderr"; then
        echo "Notary submission failed; inspect local diagnostics and history before retrying." >&2
        return 1
    fi
    submission_id="$(plutil -extract id raw -o - "${response}")"
    echo "Notary submission: ${submission_id}"
    response="${NOTARY_DIR}/${submission_id}-info.json"
    local delay="${POLL_SECONDS}"

    for ((poll = 1; poll <= MAX_POLLS; poll++)); do
        if ! notary_command info "${submission_id}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --output-format json > "${response}" 2> "${response}.stderr"; then
            echo "Notary info unavailable; bounded retry ${poll}/${MAX_POLLS}." >&2
            if (( poll < MAX_POLLS )); then sleep "${delay}"; fi
            delay=$((delay < 30 ? delay * 2 : 60))
            continue
        fi
        delay="${POLL_SECONDS}"
        status="$(plutil -extract status raw -o - "${response}")"
        case "${status}" in
            Accepted)
                xcrun stapler staple "${staple_target}"
                xcrun stapler validate "${staple_target}"
                return 0
                ;;
            Invalid|Rejected)
                fetch_notary_log "${submission_id}"
                return 1
                ;;
        esac
        if (( poll < MAX_POLLS )); then sleep "${delay}"; fi
    done

    echo "Notarization timed out after ${MAX_POLLS} polls: ${submission_id}" >&2
    fetch_notary_log "${submission_id}"
    return 1
}

cd "${PROJECT_ROOT}"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to sign from a dirty source checkout." >&2
    exit 1
fi
if [[ -n "${EXPECTED_SOURCE_COMMIT:-}" && "$(git rev-parse HEAD)" != "${EXPECTED_SOURCE_COMMIT}" ]]; then
    echo "Source commit does not match EXPECTED_SOURCE_COMMIT." >&2
    exit 1
fi
APP_VERSION="${APP_VERSION}" BUILD_NUMBER="${BUILD_NUMBER:-5}" \
    SKIP_CODESIGN=1 OUTPUT_DIR="${OUTPUT_DIR}" scripts/build-app.sh

[[ "$(plutil -extract RWSourceCommit raw -o - "${APP_PATH}/Contents/Info.plist")" == "$(git rev-parse HEAD)" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "${APP_PATH}/Contents/Info.plist")" == "${APP_VERSION}" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "${APP_PATH}/Contents/Info.plist")" == "com.regardingwork.meetings" ]]

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
ditto "${APP_PATH}" "${DMG_STAGE}/RegardingWork Meetings.app"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create -volname "RegardingWork Meetings" \
    -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_PATH}"
codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
notarize_and_staple "${DMG_PATH}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"
(
    cd "${OUTPUT_DIR}"
    shasum -a 256 "$(basename "${DMG_PATH}")" > "$(basename "${DMG_PATH}").sha256"
)

echo "Signed, notarized, and stapled: ${DMG_PATH}"
echo "No release was published."
