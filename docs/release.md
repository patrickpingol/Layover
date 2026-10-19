# Releasing Layover

Layover is distributed outside the Mac App Store, signed with a Developer ID certificate, notarized, and updated with [Sparkle](https://sparkle-project.org). Version numbers come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.

## One-time setup

### Sparkle signing key

Info.plist ships a placeholder `SUPublicEDKey` (`REPLACE_WITH_PUBLIC_ED_KEY_FROM_GENERATE_KEYS`). Updates cannot be verified until you replace it.

1. Build the app once with `-derivedDataPath .build/xcode` (`xcodebuild -project Layover.xcodeproj -scheme Layover -configuration Debug -derivedDataPath .build/xcode build`) so the Sparkle package is resolved, then find its tools in `.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `generate_appcast`, `sign_update`). Built from Xcode's default DerivedData instead, they are in `~/Library/Developer/Xcode/DerivedData/Layover-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`. The commands below assume the `.build/xcode` path.
2. Run `generate_keys`. It creates an EdDSA key pair, stores the **private key in your login keychain**, and prints the public key.
3. Paste the printed public key into `App/Resources/Info.plist` as the value of `SUPublicEDKey`.
4. Back up the private key outside the repo: `generate_keys -x ~/Safe/layover-sparkle-private-key`. Keep that file in a password manager or encrypted storage. Never commit it. Losing it means existing installs cannot receive updates.

### Appcast hosting

Pick a stable HTTPS location (for example GitHub Pages or an S3 bucket) for `appcast.xml` and the release archives, then replace the placeholder `SUFeedURL` (`https://example.invalid/appcast.xml`) in `App/Resources/Info.plist` with the real appcast URL. Ship that change in a release before relying on updates: installs only look at the feed URL they were built with.

### Developer ID signing

`project.yml` signs ad-hoc (`CODE_SIGN_IDENTITY: "-"`, `OTHER_CODE_SIGN_FLAGS: "-o runtime"`) so the project builds without a certificate. The entitlements differ per configuration:

- **Debug** uses `App/Resources/Layover.AdHoc.entitlements`, which adds `com.apple.security.cs.disable-library-validation`. Without it an ad-hoc signed app cannot load the embedded `Sparkle.framework` (it has no Team ID) and crashes at launch. This file is for local Debug builds only and must never ship.
- **Release** uses `App/Resources/Layover.entitlements`, with no library-validation exemption. Release is Developer-ID-only: an ad-hoc signed Release build compiles but does not launch, because Sparkle fails library validation.

To produce a releasable build, in `project.yml`:

1. Set `CODE_SIGN_IDENTITY` to `Developer ID Application` and `DEVELOPMENT_TEAM` to your Team ID (the Release entitlements are already selected).
2. **Remove `OTHER_CODE_SIGN_FLAGS`.** With a real identity Xcode adds the hardened runtime flag itself. (Debug then needs its own ad-hoc identity and flags, for example under `configs: Debug:`, if you still want local builds without a certificate.)
3. Run `xcodegen generate`.

Store notarization credentials once: `xcrun notarytool store-credentials layover-notary --apple-id <id> --team-id <TEAMID>` (it prompts for an app-specific password).

## Each release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate`.
2. Check the Sparkle key is set. This fails while the placeholder is still in Info.plist:

   ```sh
   grep -q REPLACE_WITH_PUBLIC_ED_KEY App/Resources/Info.plist && { echo "Set SUPublicEDKey first"; exit 1; }
   ```

   Check `SUFeedURL` is not still `https://example.invalid/appcast.xml` as well.
3. Run the tests: `swift test --package-path LayoverKit`, and walk [docs/qa/v1-checklist.md](qa/v1-checklist.md) on the release build.
4. Archive:

   ```sh
   xcodebuild -project Layover.xcodeproj -scheme Layover -configuration Release \
     -derivedDataPath .build/xcode -archivePath .build/Layover.xcarchive archive
   ```

5. Export the app (Developer ID distribution) with an `ExportOptions.plist` (keep it out of the repo or commit it without secrets; it holds only your Team ID):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>method</key>
       <string>developer-id</string>
       <key>teamID</key>
       <string>YOUR_TEAM_ID</string>
       <key>signingStyle</key>
       <string>automatic</string>
   </dict>
   </plist>
   ```

   Then export:

   ```sh
   xcodebuild -exportArchive -archivePath .build/Layover.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath .build/export
   ```

6. Zip it preserving the bundle, notarize and wait:

   ```sh
   ditto -c -k --keepParent .build/export/Layover.app .build/Layover.zip
   xcrun notarytool submit .build/Layover.zip --keychain-profile layover-notary --wait
   ```

   If the status is not `Accepted`, read the log with `xcrun notarytool log <submission-id> --keychain-profile layover-notary`.
7. Staple the ticket, then re-zip the stapled app for distribution:

   ```sh
   xcrun stapler staple .build/export/Layover.app
   xcrun stapler validate .build/export/Layover.app
   mkdir -p .build/updates
   ditto -c -k --keepParent .build/export/Layover.app .build/updates/Layover-<version>.zip
   ```

8. Verify the signature: `codesign -dv --entitlements - .build/export/Layover.app` shows `runtime`, app-sandbox, network.client and the two `mach-lookup` exceptions, and no `disable-library-validation`. `spctl -a -vv .build/export/Layover.app` reports `Notarized Developer ID`.
9. Generate the appcast. Keep earlier archives in the same folder so the feed lists them:

   ```sh
   .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast .build/updates
   ```

   `generate_appcast` reads the private key from your keychain and signs each entry. Add release notes by placing `Layover-<version>.html` next to the archive before running it. If the archives are hosted somewhere other than next to the appcast, add `--download-url-prefix https://<host>/<path>/` so each entry points at the right URL.
10. Upload the new archive and `appcast.xml` to the hosting location behind `SUFeedURL`.
11. Install the previous release, choose Check for Updates…, and confirm the update installs and relaunches.
