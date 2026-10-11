# Publishing a release

## Once: signing and notarization

Needs a paid Apple Developer Program membership (developer.apple.com/programs, 99 USD a year). Without it the workflow still releases, but macOS warns that the app can't be checked and people must allow it in System Settings > Privacy & Security.

1. **Certificate**: Xcode > Settings > Accounts > your team > Manage Certificates > + > **Developer ID Application**.
2. **Export it**: Keychain Access > login > My Certificates > right-click "Developer ID Application: …" > Export > `.p12`, with a password.
3. **Encode it**: `base64 -i Certificates.p12 | pbcopy` (now in the clipboard).
4. **App-specific password**: account.apple.com > Sign-In and Security > App-Specific Passwords > + (name it "Estris notarization").
5. **Team ID**: developer.apple.com/account > Membership details > Team ID.
6. **GitHub secrets**: this repo > Settings > Secrets and variables > Actions > New repository secret, one each:
   - `DEVELOPER_ID_CERTIFICATE`: the base64 text from step 3.
   - `DEVELOPER_ID_CERTIFICATE_PASSWORD`: the `.p12` password from step 2.
   - `APPLE_ID`: your Apple Account email.
   - `APPLE_APP_PASSWORD`: the password from step 4.
   - `APPLE_TEAM_ID`: from step 5.
7. **Let the workflow push**: Settings > Actions > General > Workflow permissions > **Read and write permissions**. If main has branch protection, allow GitHub Actions to bypass it, or the release commit can't be pushed.

## Each release

1. Check `CHANGELOG.md`: what's under **Unreleased** becomes the release notes.
2. Actions > **Release** > Run workflow > branch `main` > choose **patch** (fixes), **minor** (new features) or **major** > Run workflow.
3. It takes about 10 minutes (notarization is most of it). When it finishes there is a "Release X.Y.Z" commit, a `vX.Y.Z` tag and a release with `Estris.dmg`, which the website's Download button already points to.

If it fails before the last step, nothing is committed or published: fix it and run it again.
