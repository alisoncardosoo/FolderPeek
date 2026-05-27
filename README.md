# Folder Peek

Folder Peek is a free macOS Quick Look app for previewing folder and archive contents from Finder.

Portuguese guide (primary): [README.pt-BR.md](./README.pt-BR.md)

## What it includes

- Native macOS SwiftUI host app.
- Quick Look Preview Extension for folders.
- Finder-style table with name, kind, size, modified date, and relative path.
- Shared, testable `FolderPeekCore` framework.
- ZIP listing through a safe central-directory reader in the shared core, ready to re-enable once archive UTTypes are finalized.

## Donation

If Folder Peek has been helpful, you can support the project with PIX:

- PIX key: `d6d63f9b-5e12-4b96-8f33-d2b83a23e86d`
- The app also includes a dedicated donation tab with a QR code and copy button.

## Build

```sh
./script/build_and_run.sh
```

The script installs and opens the user-facing app at:

```text
/Applications/FolderPeek.app
```

The generated app bundle is also committed in the repo at:

```text
dist/FolderPeek.app
```

To install it manually, copy `dist/FolderPeek.app` to `/Applications`, or run the build script above to refresh the installed copy.

For tests:

```sh
xcodebuild -project FolderPeek.xcodeproj -scheme FolderPeekCore -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Auto updates (Sparkle)

Folder Peek now uses Sparkle for in-app updates (stable channel).

- Feed URL (configured in `Info.plist`): `https://github.com/alisoncardosoo/FolderPeek/releases/latest/download/appcast.xml`
- Menu bar action: `Verificar atualizacoes…`
- Automatic checks: enabled once per day (`SUScheduledCheckInterval=86400`)

### One-time setup

1. Generate Sparkle keys on your Mac:
   ```sh
   /path/to/generate_keys
   ```
2. Copy the public key and replace `SUPublicEDKey` in `FolderPeek/Resources/Info.plist`.
3. Keep the private key out of git (local keychain or CI secret).

### Release workflow (N -> N+1)

1. Bump app version:
   - `CFBundleShortVersionString`
   - `CFBundleVersion`
2. Build and archive the signed app (`.app`), then package as `.zip` or `.dmg`.
3. Generate Sparkle appcast entry and signature with Sparkle tools (`generate_appcast`).
4. Publish release assets on GitHub Releases.
5. Upload the generated `appcast.xml` as a release asset named `appcast.xml`.
6. Validate update flow from an older installed version.

Template appcast file: `docs/sparkle/appcast.xml`.

## Enable the extension

1. Open Folder Peek once.
2. Use the Folder Peek menu bar icon and choose **Mostrar app no Finder** if you need to locate the app.
3. Open System Settings.
4. Go to General > Login Items & Extensions > Quick Look.
5. Enable Folder Peek Quick Look Extension.
6. In Finder, select a folder and press Space.

The app also has a button to open the Extensions settings directly.
