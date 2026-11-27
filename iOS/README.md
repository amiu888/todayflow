# TodayFlow for iPhone

Design: `docs/ios/DESIGN.md`. Screens live in `Sources/TodayFlowPhone` (shared
Swift package); this folder holds the Xcode project spec, the app entry, the
share extension and the iOS tests.

## Build and run

```sh
brew install xcodegen          # once
cp iOS/signing.env.example iOS/signing.env   # once; put your team id in it (ignored by git)
iOS/generate.sh                # writes iOS/TodayFlowPhone.xcodeproj (not committed)
open iOS/TodayFlowPhone.xcodeproj
```

- **Simulator:** pick an iPhone and Run. Launch arguments for checks (Debug only):
  `-seedSample` fills an empty database with examples, `-openTask <uuid>`,
  `-tab calendar|search|settings`, `-pairServer <url> -pairCode <code>`.
- **Your iPhone:** sign in under Xcode ▸ Settings ▸ Accounts first. With
  automatic signing Xcode creates `com.todayflow.ios`, `com.todayflow.ios.share`
  and the app group `group.com.todayflow.ios`. Plug in the phone, pick it, Run.
- **Tests:** `xcodebuild test -project iOS/TodayFlowPhone.xcodeproj -scheme TodayFlowPhone -destination 'platform=iOS Simulator,name=iPhone 17'`.

## Sync

Settings ▸ Sync: the server address and a pairing code for the **same user as
your Mac** (server admin page ▸ Users ▸ New pairing code). At home use the NAS
address; away from home the phone needs the server's Tailscale address.

## TestFlight

`scripts/testflight.sh` does it all: raises `CURRENT_PROJECT_VERSION` in
`project.yml`, runs the tests, archives, and uploads with the Apple account
signed in to Xcode (team from `iOS/signing.env`). `--no-bump` uploads the
current build number. The upload log is `build/testflight-upload.log`.
By hand: Product ▸ Archive in Xcode, then Distribute App ▸ TestFlight.
