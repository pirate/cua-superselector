# Email draft

To: OpenAI Codex / Computer Use engineering

Subject: Repeated SkyComputerUseService crash during macOS accessibility-tree churn

Hello,

I am seeing a repeatable crash in the ChatGPT/Codex Computer Use helper when it snapshots or observes a native macOS accessibility hierarchy while that hierarchy is changing.

- Environment: ChatGPT Desktop 26.818.61809 (7019), SkyComputerUseService 26.823.1000854 (1000854), macOS 26.4.1 (25E253), Apple silicon.
- Failure class: accessibility elements or windows become invalid, disappear, or reorder while Sky is transforming an AX tree. Sky emits a burst of `AccessibilitySupport.TransformedUIElement` errors, then traps in Swift `Array.remove(at:)` with `Index out of range`.
- Impact: the Computer Use helper exits with `EXC_BREAKPOINT / SIGTRAP`, its native pipe closes, and the helper must be relaunched. The foreground and inspected applications remain alive.
- Frequency: 13 crashes with the same fingerprint occurred between 14:49 and 15:05. The two latest reports came from separate helper launches at 15:02:33 and 15:05:00 and have the same exception, faulting queue, top stack, helper UUID, and relative Sky frame offsets.
- Scope: interaction replay is one reliable way to provoke the timing window, but this appears to be a generic Sky resilience issue with concurrent AX traversal and invalidation—not a defect specific to the application being inspected.
- This appears to be the same bounds/invalidation failure class described in openai/codex#32293 and #34432, still present in helper build 1000854.

Suggested generic reproduction:

1. Launch any native macOS test app whose accessibility tree can change dynamically—for example, a SwiftUI window with AppKit panels or transient child windows.
2. Have Codex Computer Use request full app state so Sky begins observing and transforming the accessibility hierarchy.
3. While state capture or an interaction replay is active, repeatedly hide, show, destroy, or reorder windows and panels; replace SwiftUI view subtrees; and switch activation between native apps.
4. Request another state during the transition. Repeating the transition makes the race easy to reproduce.
5. Observe a burst of `AccessibilitySupport.UIElementError Code=0` messages from `TransformedUIElement`, followed by `Swift/Array.swift:1350: Fatal error: Index out of range` and a `SkyComputerUseService-*.ips` report.

The attached sanitized diagnostic includes the binary fingerprint, repeat count, normalized top stack, and error sequence immediately preceding the crash. I retained the raw `.ips` reports and can provide them privately if needed.

The defensive behavior I would expect is for Sky to treat a failed or invalidated AX node as a stale tree revision: generation-check pending work, re-resolve or skip the invalid subtree, and return a partial AX tree or screenshot rather than performing an unchecked collection removal and terminating the helper.

Thanks.
