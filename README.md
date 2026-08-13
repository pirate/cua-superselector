# Cache-able "SuperSelectors" for Computer Use Agents

`SuperSelectors` are my attempt at giving CUA systems one cachable "visual element selector" string that can carry hints from any source the driver has access to.

Think of it as a fuzzy `xpath` or CSS selector, but for arbitrary things on your screen, not only DOM elements.

<img width="720" height="555" alt="Screenshot 2026-08-13 at 12 36 44 PM (4)" src="https://github.com/user-attachments/assets/cc90ca6a-05cf-48b5-be3b-014023e0f277" />


`SuperSelector.app` is a small macOS app for inspecting the SuperSelector generated for whatever is under your cursor.

**[Build and run the app](#build-and-run)**

During a normal computer-use loop, a driver usually has several ways to reference a UI element:

- its x,y bounding box on the screen
- its role, label, value, and actions in the OS accessibility tree
- text and edge bounds from OCR
- visual features (computer vision)
- viewport and document-relative CSS box coordinates (when in a browser)
- CSS, XPath, DOM attributes, and the browser accessibility tree
- framework- or app-specific identifiers from Electron, Qt, or other UI frameworks

A **SuperSelector** collects all of these hints into one provider-attributed description of the element as it appeared in a particular screen, view, or scene.

For example, one element might produce:

```text
[screen.absolute] pointer.position.screen = 1432.0,811.0
[screen.absolute] element.frame.screen = x=1391.0,y=790.0,w=92.0,h=32.0
[mac.ax] application.bundle-id = com.apple.Safari
[mac.ax] semantic.role = button
[mac.ax] semantic.name = Continue
[mac.ax] capability.action = invoke  {native=AXPress}
[mac.ax] ancestor.role-path = application>window>group
[browser.viewport] element.frame = x=804,y=612,w=92,h=32
[browser.css] selector = button[data-action="continue"]
[ocr] text = Continue  {confidence=0.99}
```

The available hints depend on the scene. A native macOS app may have screen and AX hints. A web page may add browser hints. A remote desktop or game may only expose coordinates, OCR, and visual features. Providers can be added independently, and every provider says where each hint came from.

---

## How it works

The hint engine runs alongside the CUA loop:

1. The driver captures the current scene and target point.
2. Each registered provider reports whether it is available, degraded, or unavailable.
3. Available providers inspect the scene and emit namespaced hints.
4. The engine sorts the hints into a stable order.
5. Every hint is encoded losslessly into its own typed field in the final SuperSelector string.
6. The expanded observation stays available for debugging and future resolution.

```mermaid
flowchart LR
    S["Current scene + target point"] --> E["Hint engine"]
    E --> P1["screen.absolute"]
    E --> P2["mac.ax"]
    E --> P3["ocr"]
    E --> P4["browser.*"]
    E --> P5["other providers..."]
    P1 --> H["Ordered hint record"]
    P2 --> H
    P3 --> H
    P4 --> H
    P5 --> H
    H --> C["Compact SuperSelector"]
    H --> D["Expanded debug form"]
```

The current compact format looks like this:

```text
ss3/e1~pscreen.absolute|bgeometry|kpointer.position.screen|tn|v1432.0%2C811.0|morigin=top-left;space=quartz-global|q1.000000|rpublic~...
```

`ss3/e1` identifies the selector and encoding version. Every following field contains:

- the exact provider, band, and hint kind;
- an explicit scalar (`tn`) or text (`ts`) type;
- the exact escaped value and sorted metadata;
- the provider-reported quality and privacy classification.

The provider data remains available in the encoded string. Nearby scalar values retain their textual prefixes, and text stays available to whatever prefix or fuzzy comparison the resolver chooses. Every emitted hint contributes a field. Moving the pointer by a pixel changes the relevant coordinate characters.

## Hint providers

Providers are organized by the layer they can inspect. Several providers can describe the same element at once.

| Provider | Layer | Example hints | Status |
| --- | --- | --- | --- |
| `screen.absolute` | Display server | pointer position, display ID, element frame, normalized geometry | Implemented |
| `mac.ax` | macOS Accessibility | application, role, label, value, actions, state, ancestor roles | Implemented |
| `windows.ax` | Windows UI Automation | control type, AutomationId, name, patterns, bounding rectangle | Planned |
| `ocr` | Screenshot | text spans, language, confidence, bounding polygons | Planned |
| `visual` | Screenshot | icons, region features, color, nearby visual landmarks | Planned |
| `browser.viewport` | Browser view | viewport-relative coordinates and visible bounds | Planned |
| `browser.document` | Browser document | document coordinates, scroll state, frame ancestry | Planned |
| `browser.css` | DOM | tag, attributes, classes, selector candidates | Planned |
| `browser.xpath` | DOM | structural paths and nearby document context | Planned |
| `browser.ax` | Browser accessibility | roles, names, properties, and tree relationships | Planned |
| `electron.*` | Application runtime | renderer, accessibility, and app-specific identifiers | Planned |

Provider IDs and hint kinds are strings, so the format has no fixed list of engines. A driver can register the providers supported by its environment and include application-specific providers when they expose useful information.

Provider status is also emitted as a hint. This makes the final observation say which sources were present at generation time. A later resolver can tell the difference between a missing value and a provider that was unavailable for the whole scene.

## Generation and fuzzy resolution

SuperSelector generation records the full provider output. Every hint gets an exact field in the compact string, including hints that may be session-specific or likely to change.

Fuzzy matching happens later, when a resolver compares the stored observation with candidates from a new scene. The resolver can compare compatible hint types, apply provider-specific rules, require agreement across several independent sources, and decline ambiguous matches.

The resolver should be tuned to avoid false positives. A cache miss can trigger another inspection or a fresh model decision. A false cache hit can send an input event to the wrong element.

Keeping generation exact also leaves room for different resolution policies. A read-only hover action may tolerate a weaker match. A click on a destructive control can require strong agreement between semantic, structural, and geometric hints.

## `SuperSelector.app`

The app is a live view of the generation side on macOS. As the cursor moves, it:

- draws translucent pink crosshairs and ruler ticks on the current display;
- outlines the macOS Accessibility element under the cursor;
- runs the registered hint providers continuously;
- updates the final SuperSelector string;
- shows every expanded hint on its own line;
- labels each hint with its provider, category, value, metadata, and privacy class;
- shows the availability state of each provider;
- copies a fresh selector sampled at the exact click location whenever a click passes through to another app;
- keeps the 15 most recent exact selectors in a newest-first menu section, using exact-string deduplication only;
- provides **Resolve selector…** in the menu bar to paste an `ss3/e1` selector and temporarily pin its screen-provider crosshairs and outline.

The current app registers `screen.absolute` and `mac.ax`.

`screen.absolute` emits display and screen geometry. `mac.ax` calls the macOS system Accessibility APIs to read the application, process, role, subrole, identifier, title, description, value, actions, state, bounds, and ancestor roles for the element under the cursor.

The overlay uses provider icons and category colors so changes are easy to follow while moving between applications and UI elements.

The overlay is hidden while the pointer is over SuperSelector's own status item and while its menu is open, so the inspector does not cover or record its own controls.

The resolver decodes the lossless format and, when `mac.ax` identity hints are present, enumerates the target application's live accessibility tree. It requires exact application and role agreement plus a strong identifier, name/value, or structural match; then it uses the remaining AX hints as corroboration and declines tied results. After finding the element at its current location, it preserves the original click's relative offset within the element. This allows an element to resolve after scrolling or window movement without replaying stale absolute coordinates. A selector without usable AX identity falls back to its `screen.absolute` hints. The resolver only visualizes the result and never clicks.

## Adding a provider

Providers implement this protocol:

```swift
protocol HintProvider {
  var id: String { get }
  func report(for scene: SceneSnapshot) -> ProviderReport
  func hints(for scene: SceneSnapshot) -> [Hint]
}
```

Then they are registered with the engine:

```swift
HintEngine(providers: [
  AbsoluteScreenHintProvider(),
  MacAccessibilityHintProvider(),
  BrowserViewportHintProvider(),
  BrowserDocumentHintProvider(),
  BrowserCSSHintProvider(),
])
```

A browser provider can run beside the existing screen and macOS AX providers. It receives the same scene, finds the browser target and frame at the target point, and emits browser-specific hints into the same observation. The encoder and overlay already accept arbitrary provider IDs, hint kinds, values, and metadata.

## Build and run

Requires macOS 14+, Xcode Command Line Tools, and a Swift 6 toolchain.

```bash
./scripts/build-app.sh
open SuperSelector.app
```

The build script uses the first available **Apple Development** signing identity. You can also provide one explicitly:

```bash
SUPERSELECTOR_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
  ./scripts/build-app.sh
```

A stable signature lets macOS keep the app's Accessibility authorization across rebuilds. On first launch, grant access under **System Settings → Privacy & Security → Accessibility**, then quit and reopen the app if the overlay does not appear immediately.

The script requires a stable signing identity by default. Disposable ad-hoc builds can be enabled with:

```bash
SUPERSELECTOR_ALLOW_ADHOC=1 ./scripts/build-app.sh
```

Ad-hoc builds usually require a new Accessibility grant after rebuilding. Use the crosshair item in the menu bar to quit the app.

## Status

The repository currently implements live selector generation and inspection on macOS, recent-selector capture, and an initial read-only AX resolver. Input dispatch is still manual. OCR, visual, Windows, browser, and app-specific providers can be added through the existing provider interface.
