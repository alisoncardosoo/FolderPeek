# Folder Peek

Folder Peek is a free macOS Quick Look app for previewing folder and archive contents from Finder.

Portuguese guide: [README.pt-BR.md](./README.pt-BR.md)

## What it includes

- Native macOS SwiftUI host app.
- Quick Look Preview Extension for folders.
- Finder-style table with name, kind, size, modified date, and relative path.
- Shared, testable `FolderPeekCore` framework.
- ZIP listing through a safe central-directory reader in the shared core, ready to re-enable once archive UTTypes are finalized.

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
xcodebuild -project FolderPeek.xcodeproj -target FolderPeekCoreTests -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Enable the extension

1. Open Folder Peek once.
2. Use the Folder Peek menu bar icon and choose **Mostrar app no Finder** if you need to locate the app.
3. Open System Settings.
4. Go to General > Login Items & Extensions > Quick Look.
5. Enable Folder Peek Quick Look Extension.
6. In Finder, select a folder and press Space.

The app also has a button to open the Extensions settings directly.
