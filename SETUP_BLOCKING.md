# System-level blocking — setup guide (Tier 3)

MacTrack ships two blocking layers:

- **Tier 1 (works now, no signing):** the app hides blocked apps and bounces blocked
  websites to `about:blank`, with a locked countdown. Bypassable by quitting MacTrack.
- **Tier 3 (this guide):** a **Network Extension content filter** — a system extension
  enforced by macOS itself. It keeps filtering even when MacTrack is quit, and it's
  **DoH-proof** because it decides per network flow by hostname, not via `/etc/hosts`.

Tier 3 can't be built from an unsigned/ad-hoc build. It requires your Apple Developer
account, code signing, notarization, and a one-time approval in System Settings. The
code is already in this repo — these are the steps to turn it on.

> Honest ceiling: because you hold admin on this Mac, you can always boot to Recovery,
> disable SIP, and remove a system extension. Truly unremovable blocking requires an
> MDM/parental-controls profile that someone else controls. Tier 3 is "Screen-Time-grade":
> painful enough that you stop trying, enforced system-wide.

---

## What's already in the repo

| File | Role |
| --- | --- |
| `NetworkFilter/FilterDataProvider.swift` | The `NEFilterDataProvider` — the filter itself. Kept **outside** `MacTrack/` so it isn't compiled into the app. |
| `NetworkFilter/NetworkFilter.entitlements` | Entitlements for the extension target (NE + App Group). |
| `MacTrack/Services/BlockFilterManager.swift` | App-side: activates the extension + enables the filter. |
| `MacTrack/Services/BlockController.swift` | Writes the blocked-domain list to the shared App Group (`syncToAppGroup`). |
| Settings → **Blocking** → "System-level blocking" | The Enable / Turn off buttons + status. |

The app and extension share data through the App Group **`group.com.mactrack.MacTrack`**
(file `blocked-domains.json`).

---

## One-time Apple Developer portal setup

Replace `<YOUR_TEAM_ID>` everywhere below with your 10-character Team ID.

1. **App Group** — Certificates, IDs & Profiles → Identifiers → **App Groups** →
   create `group.com.mactrack.MacTrack`.
2. **App ID** for the app (`com.mactrack.MacTrack`):
   - Enable **App Groups** (assign the group above).
   - Enable **Network Extensions**.
   - Enable **System Extension** (if listed).
3. **App ID** for the extension (`com.mactrack.MacTrack.NetworkFilter`):
   - Enable **App Groups** (same group).
   - Enable **Network Extensions**.
4. Let Xcode manage signing (Automatic) for both targets with your team, or create
   provisioning profiles for both App IDs.

> The **Content Filter** Network Extension type is available with a normal paid
> account — no special entitlement request to Apple is required.

---

## project.yml additions

Add the extension target and embed it in the app. (XcodeGen — run `xcodegen generate`
after editing.)

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: <YOUR_TEAM_ID>
    CODE_SIGN_STYLE: Automatic

targets:
  MacTrack:
    # ... existing app target ...
    dependencies:
      - target: NetworkFilter
        embed: true                      # embed into Contents/Library/SystemExtensions
    entitlements:
      path: MacTrack/Resources/MacTrack.entitlements
      # add the keys in "App entitlements" below

  NetworkFilter:
    type: system-extension              # com.apple.system-extension
    platform: macOS
    sources:
      - NetworkFilter
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mactrack.MacTrack.NetworkFilter
        DEVELOPMENT_TEAM: <YOUR_TEAM_ID>
        CODE_SIGN_STYLE: Automatic
        INFOPLIST_KEY_NSSystemExtensionUsageDescription: "MacTrack blocks distracting sites system-wide."
    entitlements:
      path: NetworkFilter/NetworkFilter.entitlements
    info:
      path: NetworkFilter/Info.plist
      properties:
        CFBundleDisplayName: MacTrack Filter
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.filter-data
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).FilterDataProvider
```

### App entitlements

Add to `MacTrack/Resources/MacTrack.entitlements`:

```xml
<key>com.apple.developer.networking.networkextension</key>
<array><string>content-filter-provider-systemextension</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.com.mactrack.MacTrack</string></array>
```

(The extension's entitlements are already in `NetworkFilter/NetworkFilter.entitlements`.)

---

## Build, sign, notarize, install

System extensions only load from **`/Applications`** and must be signed + (for
distribution) notarized.

```bash
xcodegen generate
xcodebuild -project MacTrack.xcodeproj -scheme MacTrack -configuration Release \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> -derivedDataPath build build

# Notarize (Developer ID distribution)
xcrun notarytool submit MacTrack.app.zip --apple-id <you@apple.id> \
  --team-id <YOUR_TEAM_ID> --password <app-specific-password> --wait
xcrun stapler staple MacTrack.app

cp -R build/Build/Products/Release/MacTrack.app /Applications/
open /Applications/MacTrack.app
```

For local development you can run unnotarized if you enable developer mode for
system extensions: `systemextensionsctl developer on` (toggle off when done).

---

## Turn it on

1. Open MacTrack → gear → **Settings → Blocking → Enable**.
2. macOS prompts to allow the system extension → **System Settings → General →
   Login Items & Extensions → Network Extensions** (or Privacy & Security) → allow
   **MacTrack Filter**.
3. Approve the content filter when prompted. Status should read **On**.

Now block a site (right-click any site row → Block…). The system filter drops its
connections in every browser and app, even if you quit MacTrack.

---

## Verify / debug

```bash
systemextensionsctl list                       # should show MacTrack Filter [activated enabled]
log stream --predicate 'subsystem CONTAINS "NetworkFilter"' --level debug
cat "$HOME/Library/Group Containers/group.com.mactrack.MacTrack/blocked-domains.json"
```

If a flow isn't dropped: confirm the hostname appears in `blocked-domains.json`, and
that `handleNewFlow` is being called (the filter must be enabled and approved).

---

## Hardening roadmap (optional, beyond this guide)

- **Root LaunchDaemon** (`SMAppService.daemon`) that re-enables the filter if disabled
  and re-launches MacTrack — survives quitting.
- **Clock-tamper for quit periods:** the daemon records monotonic + wall time so moving
  the clock while MacTrack is closed can't skip a block (the app already resists this
  while running).
- **Self-protection:** have the daemon own the block database (root-only) so the
  countdown can't be edited from user space.
