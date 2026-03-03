#!/bin/bash
# Xcode Scheme Archive post-action.
# Xcode sets $XcodeArchivePath to the freshly-created .xcarchive.
# Removes UIRequiredDeviceCapabilities injected by Xcode 26.2 and re-signs the bundle.

set -e

APP_PATH="${XcodeArchivePath}/Products/Applications/ScreenTimeRewards.app"
PLIST="${APP_PATH}/Info.plist"

# 1. Remove the injected key FIRST (no-op if absent — idempotent)
/usr/libexec/PlistBuddy -c "Delete :UIRequiredDeviceCapabilities" "${PLIST}" 2>/dev/null || true
echo "strip-uirequired: key removed"

# 2. Detect cert hash from the existing bundle signature.
#    Match authority name → look up hash in keychain → avoids duplicate-name ambiguity.
#    Works with development certs (no distribution cert required on this Mac).
AUTH_NAME=$(codesign -d --verbose=4 "${APP_PATH}" 2>&1 | grep "^Authority=" | head -1 | sed 's/Authority=//')
CERT_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "${AUTH_NAME}" | tail -1 | awk '{print $2}')

# Fallback: any valid Apple Development cert
if [ -z "${CERT_HASH}" ]; then
    CERT_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
fi

# Last resort: any valid codesigning identity
if [ -z "${CERT_HASH}" ]; then
    CERT_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "^\s+[0-9]+\)" | head -1 | awk '{print $2}')
fi

if [ -z "${CERT_HASH}" ]; then
    echo "strip-uirequired: ERROR — no signing identity found in keychain" >&2
    exit 1
fi

echo "strip-uirequired: cert hash = ${CERT_HASH}"

# 3. Re-sign extensions first (inside-out order required by Apple codesigning rules)
for ext in "${APP_PATH}/PlugIns/"*.appex; do
    echo "strip-uirequired: re-signing ${ext##*/}"
    codesign --force --sign "${CERT_HASH}" --preserve-metadata=entitlements,flags,runtime "${ext}"
done

# 4. Re-sign main app
echo "strip-uirequired: re-signing ScreenTimeRewards.app"
codesign --force --sign "${CERT_HASH}" --preserve-metadata=entitlements,flags,runtime "${APP_PATH}"

echo "strip-uirequired: done — bundle re-signed successfully"
