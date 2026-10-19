# Releasing Layover

Layover is distributed as GitHub Releases and updated with [Sparkle](https://sparkle-project.org). Pushing a version tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which tests, builds, signs and publishes the release with its Sparkle feed.

Releases are signed with a **self-signed certificate**, not a Developer ID, so they are not notarized:

- **First launch.** Gatekeeper blocks a downloaded build until the user allows it once, in System Settings → Privacy & Security → Open Anyway. Updates installed by Sparkle don't ask again.
- **A stable identity.** Every release is signed with the same certificate, so macOS treats each update as the same app: the sandbox container and the saved file bookmarks keep working.
- **`disable-library-validation`.** A self-signed app has no Team ID, and neither does the embedded `Sparkle.framework`, so the hardened runtime would refuse to load Sparkle. `App/Resources/Layover.entitlements` turns library validation off for that reason. It goes once releases move to a Developer ID (see the end of this page).

## One-time setup

### Sparkle signing key

This is done: `App/Resources/Info.plist` has the project's `SUPublicEDKey`, and its private key is in the maintainer's login keychain. Repeat these steps only to rotate the key, which cuts off updates for existing installs. (Sparkle rejects a key it cannot decode and shows an "Unable to Check For Updates" alert at launch, so never add a placeholder.)

1. Build the app once with `-derivedDataPath .build/xcode` (`xcodebuild -project Layover.xcodeproj -scheme Layover -configuration Debug -derivedDataPath .build/xcode build`) so the Sparkle package is resolved. Its tools are then in `.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `generate_appcast`, `sign_update`).
2. Run `generate_keys`. It creates an EdDSA key pair, stores the **private key in your login keychain**, and prints the public key.
3. Put the printed public key in `App/Resources/Info.plist` as `SUPublicEDKey`.

### Self-signed code-signing certificate

1. In Keychain Access, choose Keychain Access → Certificate Assistant → Create a Certificate. Name it (for example "Layover Release"), set Identity Type to **Self Signed Root** and Certificate Type to **Code Signing**, tick **Let me override defaults**, and set a long validity period (for example 3650 days). Accept the remaining defaults.
2. In My Certificates, select the certificate, then File → Export Items as a `.p12` with a strong password.
3. Keep the `.p12` and its password in a password manager. The certificate is now part of Layover's identity: if it is lost or expires, the next release is signed by a different identity, and macOS may treat it as a different app.

The certificate does not need to be trusted on the build machine: CI picks it by its SHA-1.

### Feed hosting

Each GitHub Release carries the disk image and an `appcast.xml` listing every release. `SUFeedURL` is `https://github.com/patrickpingol/Layover/releases/latest/download/appcast.xml`, which GitHub redirects to the newest published (not draft or pre-release) release's copy. The repository must stay public: Sparkle cannot download assets that need a login.

### GitHub secrets

The workflow runs in the `release` environment. Create it, and allow only `v*` tags to deploy to it:

```sh
gh api -X PUT repos/patrickpingol/Layover/environments/release \
  -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/patrickpingol/Layover/environments/release/deployment-branch-policies -f name='v*' -f type=tag
```

Then add its secrets:

| Secret | Value |
|---|---|
| `SIGNING_CERT_P12_BASE64` | The certificate: `base64 -i Layover.p12 \| gh secret set SIGNING_CERT_P12_BASE64 --env release` |
| `SIGNING_CERT_PASSWORD` | The `.p12` password: `gh secret set SIGNING_CERT_PASSWORD --env release` (prompts for it) |
| `SPARKLE_ED_PRIVATE_KEY` | The Sparkle private key. Export it with `generate_keys -x sparkle-private-key`, run `gh secret set SPARKLE_ED_PRIVATE_KEY --env release < sparkle-private-key`, then keep that file in a password manager and delete it from disk |

## Each release

1. Run the tests (`swift test --package-path LayoverKit`) and walk [docs/qa/v1-checklist.md](qa/v1-checklist.md).
2. Tag the commit on `main` and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

   The tag sets the version (`CFBundleShortVersionString`); the commit count sets the build number (`CFBundleVersion`), which Sparkle compares. The `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` only apply to local builds.
3. The workflow then:
   - checks `SUPublicEDKey` is set and `SUFeedURL` points at this repository's releases;
   - runs the tests and builds the universal (arm64 and x86_64) Release app;
   - re-signs it with the certificate ([`scripts/sign-app.sh`](../scripts/sign-app.sh), innermost code first, as Sparkle documents) and checks the hardened runtime is on and `get-task-allow` is absent;
   - puts it in a disk image next to a shortcut to Applications, signs the image, adds it to the previous release's `appcast.xml` with `generate_appcast`, and fails if the update isn't signed with the key matching `SUPublicEDKey`. Sparkle installs updates from the same disk image;
   - publishes the GitHub Release with the disk image, `appcast.xml` and generated notes.
4. Install the previous release, choose Check for Updates…, and confirm the update installs and relaunches.

If the workflow fails before publishing, fix the cause, delete the tag (`git push origin :refs/tags/v0.2.0` and `git tag -d v0.2.0`) and tag again.

## Moving to a Developer ID

With an Apple Developer Program membership, releases can be notarized so Gatekeeper opens them without a prompt:

1. Remove `com.apple.security.cs.disable-library-validation` from `App/Resources/Layover.entitlements`. A Developer ID gives Layover and the re-signed Sparkle the same Team ID. Local ad-hoc builds then need their own entitlements with the exemption again.
2. Import the Developer ID Application certificate instead of the self-signed one, and sign with `--timestamp` (in `scripts/sign-app.sh`).
3. Add notarization after the disk image is signed: `xcrun notarytool submit <dmg> --key <AuthKey.p8> --key-id <id> --issuer <issuer> --wait`, then `xcrun stapler staple <dmg>`.

The switch changes Layover's code identity once. Sparkle accepts it because the update is still signed with the same EdDSA key, but macOS may ask users once whether Layover may access its own data.
