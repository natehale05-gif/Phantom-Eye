# CarPlay integration — read before relying on this

This directory contains a **first-draft, uncompiled** CarPlay integration:

- `NavBridge.swift` — plain Swift state holder, mirrors the Android Auto
  `NavBridge.kt` exactly.
- `CarPlayMapView.swift` — hand-drawn (Core Graphics) route + puck, same
  approach as the Android Auto Canvas rendering (see that file's doc
  comment for why we didn't embed the full MapLibre renderer here).
- `CarPlaySceneDelegate.swift` — `CPTemplateApplicationSceneDelegate`
  implementation: sets the CarPlay window's root view controller to the map
  view, builds a `CPMapTemplate`, and starts/updates a `CPNavigationSession`
  as Flutter nav ticks arrive.

## Why this needs your attention before shipping

**This was written on Linux with no Xcode/macOS available, so none of it
has been compiled or run.** Cursor's cloud agent environment cannot build
or test iOS targets. Before trusting this code:

1. Open `Runner.xcworkspace` in Xcode on a Mac.
2. **Add these three files to the `Runner` target** — this project uses a
   classic (non-filesystem-synchronized) `.pbxproj`, so files dropped on
   disk are *not* automatically picked up. In Xcode: right-click the
   `Runner` group → *Add Files to "Runner"...* → select this folder → make
   sure "Runner" is checked as the target.
3. Build and fix whatever the compiler flags. The riskiest bits, most
   likely to need adjustment:
   - `CPTrip`/`CPRouteChoice`/`CPManeuver` initializer signatures in
     `CarPlaySceneDelegate.handleStateChange` — these were written from
     documentation/memory, not verified against the actual SDK headers.
   - `CPNavigationSession.updateEstimates` argument types.
4. Request the **`com.apple.developer.carplay-maps`** entitlement from
   Apple (Developer Portal → Certificates, Identifiers & Profiles → your
   App ID → request the CarPlay entitlement addendum). This is a *managed
   capability* Apple grants manually per app — there is no self-service
   toggle. Without it:
   - `templateApplicationScene(_:didConnect:to:)` (the window-providing
     variant this code implements) will not be called.
   - Your provisioning profile can't be signed with the capability enabled.
   - The CarPlay Simulator can still be used for basic testing once Xcode
     has a matching (development) entitlement locally, but real device /
     App Store distribution needs the Apple-granted entitlement.
5. Once granted, add `com.apple.developer.carplay-maps = true` to an
   `Entitlements.plist` and set it as the target's Code Signing Entitlements
   build setting (Xcode does this automatically if you add the capability
   via *Signing & Capabilities* after Apple grants it).

This is exactly the limitation flagged in the original build plan ("flag if
you hit the CarPlay navigation-app entitlement requirement so I can sort
that out") — sorting it out means an Apple Developer Program application
process, not a code change.
