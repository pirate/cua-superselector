# Email draft

To: OpenAI Codex / Computer Use engineering

Subject: Repeated `SkyComputerUseService` crash during macOS app-state capture

Hello,

I am seeing a highly repeatable crash in the `SkyComputerUseService` process used by ChatGPT Desktop/Codex Computer Use to capture and interact with native macOS app state. The target app and ChatGPT Desktop remain alive, but the helper terminates and the Computer Use pipe closes.

- **Environment:** ChatGPT Desktop 26.818.61809 (7019); `SkyComputerUseService` 26.823.1000854 (1000854); macOS 26.4.1 (25E253); Apple silicon.
- **Frequency:** 13 matching crashes in about 16 minutes, including crashes from separate helper launches.
- **Trigger:** Requesting app state while ordinary UI activity is creating, closing, hiding, replacing, or reordering native windows or accessibility elements. Interaction replay makes the timing window especially easy to hit, but the failure is not specific to any one target app.
- **Crash signature:** Repeated `AccessibilitySupport.TransformedUIElement` errors immediately followed by `Swift/Array.swift:1350: Fatal error: Index out of range`. The crash is `EXC_BREAKPOINT / SIGTRAP` on `com.apple.root.user-initiated-qos.cooperative`, with `Array.remove(at:)` at the top of the relevant stack.
- **Related reports:** This appears consistent with openai/codex#32293 and #34432 and remains reproducible in helper build 1000854.

Minimal reproduction:

1. Start Computer Use against any native macOS app with dynamically changing windows or views.
2. Request app state.
3. While an interaction or replay changes window/view visibility or ordering, request app state again.
4. Repeat until the race hits; a new `SkyComputerUseService-*.ips` report is produced.

Expected behavior: if accessibility state changes during capture, the helper should retry, skip stale elements, or return partial state/a screenshot rather than terminate on an unchecked collection index.

I have attached a sanitized diagnostic containing the binary fingerprint, normalized stack, repeat count, and pre-crash log sequence. I can provide the raw `.ips` reports privately if needed.

Thanks.
