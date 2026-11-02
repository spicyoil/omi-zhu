# Omi Zhu fork

This repository is a personal fork of [BasedHardware/omi](https://github.com/BasedHardware/omi). Branch `zhu` carries the fork. Branch `main` stays identical to upstream `main` so it can be fast-forwarded. Do not merge `zhu` into `main`, and do not open a pull request to BasedHardware/omi.

## What `zhu` changes

- Android prod application id is `com.friend.ios.arm`, so this build installs beside the store app (`com.friend.ios`). The launcher label is **Omi Zhu**.
- The production web auth callback scheme is `omi-arm` (`AppEnvironmentProfile.production`, so the redirect is `omi-arm://auth/callback`). The prod Android intent filter registers that scheme. iOS still reads `AUTH_CALLBACK_SCHEME` from the Xcode config; `app/ios/Flutter/Base.xcconfig` defaults to `omi`, so an iOS build that should receive the callback needs that setting set to `omi-arm`.
- Offline recordings upload to your own server, not to Omi. `uploadLocalFilesV2` (`/v2/sync-local-files`) is hard-disabled. There is no fallback to Omi's upload.
- A recording is marked synced, and its copy is deleted from the phone, only after the server responds HTTP 200 with `stored: true` and a sha256 that matches the hash computed on the phone. Anything else stays on the phone and is retried on the next sync.
- Custom STT no longer disables offline auto-sync, and the custom-STT sync confirmation is skipped, because the audio does not go to Omi.
- Crashlytics mapping upload is disabled for this side-by-side build. Native libraries are stored compressed in the APK.

## Build-time defines

Pass both with `--dart-define`. If either value is empty, the uploader refuses and leaves the files on the phone.

- `ARM_UPLOAD_URL` — absolute URL of your offline-upload endpoint.
- `ARM_UPLOAD_TOKEN` — bearer token sent as `Authorization`. It is never logged.

```bash
flutter build apk --flavor prod \
  --dart-define=ARM_UPLOAD_URL=<your-upload-url> \
  --dart-define=ARM_UPLOAD_TOKEN=<your-token>
```

Do not commit the token, `.env` files, keystores, `google-services.json`, `key.properties`, or `local.properties`.

## Sync with upstream

Add the upstream remote once:

```bash
git remote add upstream https://github.com/BasedHardware/omi.git
```

Keep `main` a fast-forward of upstream, then merge that into the fork branch:

```bash
git fetch upstream
git checkout main
git merge --ff-only upstream/main
git checkout zhu
git merge upstream/main
```

Resolve conflicts on `zhu` so the upstream change and this fork both remain: application id `com.friend.ios.arm`, label Omi Zhu, `omi-arm` auth callback, and offline uploads only to your server after a matching sha256 confirmation. Push `zhu` only.
