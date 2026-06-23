# System-level blocking — setup guide (Tier 3)

MacTrack ships two blocking layers:

- **Tier 1 (works now, no signing):** the app hides blocked apps and bounces blocked
  websites to `about:blank`, with a locked countdown. **Bypassable by quitting MacTrack.**
- **Tier 3 (this guide):** a **Network Extension content filter** — a system extension
  enforced by macOS itself. It keeps filtering **even when MacTrack is quit**, and it's
  **DoH-proof** because it decides per network flow by hostname, not via `/etc/hosts`.

Tier 3 can't run from an unsigned/ad-hoc build — it has to be code-signed with your
Apple Developer team and approved once in System Settings. **All the build wiring is
already done** (target, entitlements, embedding); the steps below are just the parts
that need your account and a couple of clicks.

> **You only want this on your own Mac, so you can skip notarization entirely** —
> notarization is only for distributing the app to *other* people's Macs. A signed
> build from your own team runs fine on your own machine after a one-time approval.

> Honest ceiling: because you hold admin on this Mac, you can always boot to Recovery,
> disable SIP, and remove a system extension. Truly unremovable blocking requires an
> MDM/parental-controls profile that someone else controls. Tier 3 is "Screen-Time-grade":
> painful enough that you stop trying, enforced system-wide, survives quitting.

---

## What's already wired up

| File | Role |
| --- | --- |
| `NetworkFilter/FilterDataProvider.swift` | The `NEFilterDataProvider` — the filter itself. Drops any flow whose host matches a blocked domain. |
| `NetworkFilter/NetworkFilter.entitlements` | Entitlements for the extension target (Network Extension + App Group). |
| `project.signed.yml` | XcodeGen spec that adds the `NetworkFilter` system-extension target, embeds it into the app, and turns on signing. |
| `Signing.xcconfig` | **Local, gitignored.** Holds your Team ID so it stays out of the public repo. Copy it from `Signing.xcconfig.example`. |
| `MacTrack/Resources/MacTrack.entitlements` | App entitlements — already include the Network Extension + App Group keys. |
| `MacTrack/Services/BlockFilterManager.swift` | App-side: activates the extension + enables the content filter (Settings → Blocking). |
| `MacTrack/Services/BlockController.swift` | Writes the blocked-domain list to the shared App Group (`syncToAppGroup`). |

The app and extension share data through the App Group **`group.com.mactrack.MacTrack`**
(file `blocked-domains.json`). Bundle IDs: app `com.mactrack.MacTrack`, extension
`com.mactrack.MacTrack.NetworkFilter`.

---

## Step 1 — set your Team ID (once)

```bash
cp Signing.xcconfig.example Signing.xcconfig
# edit Signing.xcconfig → DEVELOPMENT_TEAM = your 10-char Team ID
```

`Signing.xcconfig` is gitignored, so your Team ID never gets committed.

## Step 2 — generate the signed project and open it

```bash
xcodegen generate --spec project.signed.yml
open MacTrack.xcodeproj
```

> The plain `xcodegen generate` (no `--spec`) still makes the fast **unsigned** dev
> build with no extension — use it for day-to-day work. Use the `--spec` form only
> when you want the real, quit-proof blocker.

## Step 3 — let Xcode register the capabilities

In Xcode, for **both** the `MacTrack` and `NetworkFilter` targets:

1. **Signing & Capabilities** → check **Automatically manage signing**, pick your Team.
2. Xcode sees the entitlements files and **auto-registers** the App Group
   (`group.com.mactrack.MacTrack`) and the Network Extension capability in your
   developer account for you — no manual portal trip needed. If it shows a "Fix
   Issue" button, click it.

That's the only Apple-portal interaction, and Xcode does it for you.

## Step 4 — build and install to /Applications

System extensions only load from **`/Applications`**. In Xcode: **Product → Archive →
Distribute App → Copy App**, then drag `MacTrack.app` into `/Applications`. Or from the
command line:

```bash
xcodebuild -project MacTrack.xcodeproj -scheme MacTrack -configuration Release \
  -derivedDataPath build build
ditto build/Build/Products/Release/MacTrack.app /Applications/MacTrack.app
open /Applications/MacTrack.app
```

> Running a **signed-but-not-notarized** extension on your own Mac for the first time
> may need developer mode for system extensions:
> `systemextensionsctl developer on` (you can toggle it `off` later).

## Step 5 — turn it on

1. MacTrack → gear → **Settings → Blocking → Enable**.
2. macOS prompts to allow the extension → **System Settings → General → Login Items &
   Extensions → Network Extensions** (or Privacy & Security) → allow **MacTrack Filter**.
3. Approve the content filter when prompted. Status should read **On**.

Now block a site (right-click any site row → **Block…**). The system filter drops its
connections in **every browser and app — even if you quit MacTrack**.

---

## Verify / debug

```bash
systemextensionsctl list                       # should show MacTrack Filter [activated enabled]
log stream --predicate 'subsystem CONTAINS "NetworkFilter"' --level debug
cat "$HOME/Library/Group Containers/group.com.mactrack.MacTrack/blocked-domains.json"
```

If a flow isn't dropped: confirm the hostname appears in `blocked-domains.json`, and
that the filter is enabled and approved (Status **On**).

---

## Hardening roadmap (optional, beyond this guide)

- **Root LaunchDaemon** (`SMAppService.daemon`) that re-enables the filter if disabled
  and re-launches MacTrack — closes the "disable the extension" gap.
- **Clock-tamper for quit periods:** a daemon recording monotonic + wall time so moving
  the clock while MacTrack is closed can't skip a block (the app already resists this
  while running).
- **Self-protection:** have the daemon own the block database (root-only) so the
  countdown can't be edited from user space.
