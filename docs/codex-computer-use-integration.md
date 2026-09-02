# Codex Computer Use integration

SuperSelector Studio should extend Codex Computer Use, not fork or impersonate its private
service. The stable boundary is a companion plugin/MCP server plus a durable recording format.
Private `SkyComputerUseService` IPC, binary symbols, and revision-local element indexes are
diagnostic context only.

## Shared vocabulary

| Computer Use concept | Studio type | Lifetime |
| --- | --- | --- |
| Skyshot/capture | `ComputerUseSkyshot` | One observation |
| AX node | `AccessibilityNode` | One render-tree revision |
| Agent tree | `UIElementRenderTree` / `AppState.text` | One render-tree revision |
| Element index | `AccessibilityNode.elementIndex` | Never durable |
| Screenshot geometry | `SuperSelectorBoxModel` | One capture, portable with its frame |
| Recorded action | `ComputerUseRecordedAction` | Durable workflow data |
| Workflow recording | `ComputerUseWorkflowRecording` | Durable/shareable |
| Fast-path plan | `ComputerUseReplayPlan` | One execution attempt |
| Durable target | `ss3/e1` SuperSelector | Re-resolved in every new capture |

The critical rule is that an agent may act with a current `element_index`, while a recording must
store a SuperSelector. An index is an address into one rendered tree. A SuperSelector is evidence
used to find the corresponding target again.

## Implemented Studio bridge

Studio now captures a bounded AX hierarchy and renders it with the current Computer Use
`AppState.text` grammar: window/app header, numbered and indented roles, disabled/selected state,
secondary actions, and focused-element summary. The popup displays that tree beside the clean
screenshot. The highlighted tree index and screenshot box come from the same target and the same
`SuperSelectorBoxModel` projection.

Each newly recorded action stores:

- the exact durable `ss3/e1` selector;
- the readable target path;
- the raw input event/action;
- screenshot asset plus capture/target/pointer geometry;
- the agent-facing `AppState.text` captured for that action; and
- `ComputerUseWorkflowBridgeMetadata`, which declares resolve-then-act cached execution and a
  return-to-Computer-Use cache-miss policy.

Studio can mark any recorded step as a cache-range start and run through a later selected step.
This skips a new LLM decision between actions. It does **not** reuse AX objects, process IDs, or
element indexes: every action resolves its SuperSelector against the current app immediately
before input is synthesized. Ambiguity stops execution.

## Recommended product boundary

Build a local `superselector` MCP server and package it with a small Codex skill. Keep the current
app as the recorder/debugger and make the MCP server the headless bridge.

Suggested tools:

1. `list_workflow_recordings()` — return IDs, names, apps, steps, and last verified time.
2. `get_workflow_recording(id)` — return the readable plan, inputs, checks, and redacted evidence.
3. `resolve_target(selector, app_state?)` — return a current target, confidence explanation, and
   either a Computer Use element index or coordinate/AX action fallback.
4. `run_cached_subsequence(workflow_id, from, through, inputs)` — execute resolve-then-act steps
   without another model turn; stop on the first failed precondition, ambiguous target, policy
   boundary, or unexpected postcondition.
5. `verify_workflow(workflow_id)` — dry-resolve every target against the current UI without acting.
6. `export_workflow(id, redaction_policy)` / `import_workflow(package)` — share a portable,
   content-addressed recording.

The skill should teach Codex this policy:

```text
Structured connector or app API
  → verified cached SuperSelector subsequence
    → ordinary Computer Use observation/reason/action loop
```

That ordering matches the official Computer Use guidance: use GUI control where command-line or
structured integrations are insufficient, not as a replacement for stable semantic operations.

## Ingesting the real Sky state

Studio's native AX renderer is intentionally compatible, but it cannot be byte-for-byte identical
to a private renderer forever. The companion plugin should therefore accept the public values that
Codex already sees:

```ts
type AppState = {
  app: string
  screenshot: { url: string } | null
  text: string
}
```

A Codex skill can call `sky.get_app_state({app, disableDiff: true})`, then call an
`ingest_app_state` MCP tool with the tree text, screenshot attachment, app identity, and capture
timestamp. Studio can display the authoritative Computer Use rendering and use its own AX capture
only when no ingested state is available. Text diffs must be expanded against a known full-tree
revision before they are archived or shared.

Do not parse an element index and save it as target identity. Instead, correlate the chosen index
with current AX/screenshot evidence, generate a durable SuperSelector, and attach the current index
only under ephemeral `_resolved` execution state.

## Fast replay without unsafe replay

The performance target is zero new LLM turns for a verified run, not zero validation.

For each cached action:

1. Verify the expected app/window scope.
2. Resolve the durable selector from fresh AX/UI evidence.
3. Require action-specific confidence and ambiguity margins.
4. Verify a lightweight precondition fingerprint.
5. Perform the native semantic action when available, otherwise the recorded physical input.
6. Wait for the expected AX/window change, using debounce rather than a fixed long delay.
7. Verify a postcondition fingerprint.
8. Continue, or return a typed cache miss to Codex with the failing step and fresh state.

Read-only hover/navigation can accept a lower confidence threshold than destructive clicks or text
submission. Sensitive or externally consequential steps remain subject to Computer Use approvals;
caching must never become an approval bypass.

## Durable sharing format

The current JSON remains importable, but a scalable shared package should use:

```text
workflow.cua/
  manifest.json          version, provenance, apps, privacy policy, content hashes
  steps.jsonl            selectors, actions, pre/postconditions, timing envelopes
  app-state/             full initial tree + revision-addressed diffs
  screenshots/           content-addressed image blobs
  skill/SKILL.md         optional human/model instructions and input contract
```

Persist semantic and visual evidence, provider versions, coordinate frames, and verification rules.
Never persist AX object references, PIDs, HWNDs, UIA RuntimeIds, CDP node IDs, or Computer Use
element indexes. Redaction happens per hint/asset before hashing and export.

## Highest-value next implementation slice

1. Add the local MCP server with `list`, `verify`, `resolve`, and `run_cached_subsequence`.
2. Move replay input injection behind an executor protocol so the same plan can use Studio's local
   CGEvent backend today and a Computer Use action backend later.
3. Add pre/postcondition fingerprints and a typed cache-miss result.
4. Add authoritative `AppState` ingestion from the Codex skill.
5. Replace fixed replay sleeps with AX/window settle observation and measure end-to-end latency.
6. Add fuzz/property tests for changing AX children, stale revisions, app termination, and reordered
   controls before allowing unattended cached batches.

