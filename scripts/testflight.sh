#!/bin/zsh
# Tests, archives and uploads the iPhone app to TestFlight in one go.
#
#   scripts/testflight.sh            # next build number, then upload
#   scripts/testflight.sh --no-bump  # upload the build number in project.yml
#
# Signs with the Apple account signed in to Xcode (Settings ▸ Accounts) and
# the team in iOS/signing.env (ignored). TestFlight shows the build to
# testers about 10-15 minutes after the upload, once Apple has processed it.
set -euo pipefail
cd "${0:A:h}/.."

[[ -f iOS/signing.env ]] || { print -u2 "Missing iOS/signing.env (DEVELOPMENT_TEAM=…)"; exit 1; }
set -a; source iOS/signing.env; set +a
[[ -n "${DEVELOPMENT_TEAM:-}" ]] || { print -u2 "DEVELOPMENT_TEAM is empty in iOS/signing.env"; exit 1; }

# Optional: an App Store Connect API key works even when the Mac is locked
# (the Xcode sign-in doesn't). In iOS/signing.env:
#   ASC_KEY_ID=…  ASC_ISSUER_ID=…  (key file ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
auth=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  [[ -f "$key" ]] || { print -u2 "Missing API key file $key"; exit 1; }
  auth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  print "Signing in with App Store Connect API key $ASC_KEY_ID"
fi

build=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' iOS/project.yml | head -1)
if [[ "${1:-}" != "--no-bump" ]]; then
  build=$((build + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$build\"/" iOS/project.yml
fi
version=$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' iOS/project.yml | head -1)
print "TodayFlow iPhone $version ($build)"

print "1/4 Tests"
swift test 2>&1 | grep -E "✘|error:" && { print -u2 "Tests failed; nothing uploaded."; exit 1; }

print "2/4 Project"
./iOS/generate.sh >/dev/null

print "3/4 Archive"
archive=build/TodayFlowPhone.xcarchive
rm -rf "$archive"
xcodebuild archive -project iOS/TodayFlowPhone.xcodeproj -scheme TodayFlowPhone \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates "${auth[@]}" -quiet
built=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$archive/Info.plist")
[[ "$built" == "$build" ]] || { print -u2 "Archive has build $built, expected $build."; exit 1; }

print "4/4 Upload to App Store Connect"
plist=build/ios-export.plist
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$DEVELOPMENT_TEAM</string>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
rm -rf build/ios-export
log=build/testflight-upload.log
if ! xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$plist" \
     -exportPath build/ios-export -allowProvisioningUpdates "${auth[@]}" >"$log" 2>&1 \
   || ! grep -q "EXPORT SUCCEEDED" "$log"; then
  grep -iE "error|failed" "$log" | head -20 >&2
  if grep -q "Failed to Use Accounts\|missing Xcode-Username" "$log"; then
    print -u2 "Xcode's Apple ID can't be read while the Mac is locked. Unlock it, or add an API key (see the top of this script)."
  fi
  print -u2 "Upload failed; full log in $log"
  exit 1
fi

print "Uploaded $version ($build). TestFlight offers it in about 10-15 minutes."
