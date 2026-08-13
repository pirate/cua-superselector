---
title: "Decoupling identifiers from location"
source: "https://claude.ai/share/dae3ce4b-33c2-46e4-855c-8d83991fd674"
snapshot_uuid: "dae3ce4b-33c2-46e4-855c-8d83991fd674"
conversation_uuid: "fca6f771-f2d1-4c25-935e-dade2b80d15f"
shared_by: "Nick"
snapshot_created_at: "2026-05-29T22:14:05.352094Z"
snapshot_updated_at: "2026-05-29T22:14:05.352094Z"
message_count: 54
---

# Decoupling identifiers from location

> Shared by Nick on Claude. 
> Original: [https://claude.ai/share/dae3ce4b-33c2-46e4-855c-8d83991fd674](https://claude.ai/share/dae3ce4b-33c2-46e4-855c-8d83991fd674)

## Nick

<!-- message 1; source_index=0; uuid=019e4b8b-9cff-7a81-888a-79ca9fcbba2f; created_at=2026-05-21T17:19:35.036775Z -->

Hardest problems in computer science boils down to basically on problem imo:

Cache invalidation == choosing a good cache key == choosing a good name / naming scheme is hard


How do mesh networks solve the issue of meeting a deterministic handle/address that you can predict without needing to see the entire set of nodes in advance, including when nodes move around within the structure?


It's the same problem as "how do we come up with a stable identifier for DOM nodes that doesn't break all later elements when some elements get added before it / after it or the tree changes slightly"

Is the same problem as "how do we layout our memory address space to avoid excessive hops through lookup tables, while maintaining reasonably fast insertions and deletions"?

 How do mesh networking algorithms and other systems solve this? Stable identifiers that survive global layout shifts but can still be predicted in advance with minimal stored state needed for lookups

---

## Claude

<!-- message 2; source_index=1; uuid=019e4b8b-9d07-747e-96e8-76d56a9bee11; created_at=2026-05-21T17:20:59.721681Z -->

The unifying trick across all three domains is the same: **decouple identifier from location**, then let routing emerge from local state. Once you stop baking "where it lives" into "what it's called," everything else follows.

In mesh networks the canonical move is content-addressing the identity — hash of public key, hash of content, whatever — so the name is intrinsic and globally stable. Then a metric space plus per-node routing tables translate name → location:

- **Kademlia**: id = hash, distance = XOR. Each node keeps k-buckets at each bit-prefix depth. Route to any id with O(log N) state; joins/leaves only perturb nearby buckets.
- **Chord / consistent hashing**: id is a point on a ring, each node owns an arc. Add/remove only reshards adjacent arcs.
- **Yggdrasil / CJDNS**: cryptographic id (IPv6 = hash of pubkey), routing via self-organizing spanning tree or hyperbolic embedding. Identity survives topology changes; coordinates are ephemeral.
- **Rendezvous (HRW) hashing**: pick k servers for a key without coordination — hash (key, server), take top-k. Add a server, only 1/N of keys move.

You pay one hop through the routing layer per lookup, plus the table itself (log N but nonzero).

The DOM case is structurally identical. Positional paths (`/body/div[3]`) are memory offsets — fast, zero state, shatter on insertion. Standard fix: assign intrinsic identifiers (React `key`, ARIA ids, content fingerprints) and maintain a parallel index from id → current node. React's reconciler is a tiny DHT-shaped system: it routes "this key" → "this fiber" via a keyed map alongside the tree. Without keys it falls back to positional, with exactly the breakage you described.

Memory: handles-with-generations (`(slot_index, generation)`) are the slab allocator version. Slot gives O(1) lookup, generation detects ABA when something else moves into the slot. Stable id, fast lookup, survives deletes — pay a 4–8 byte tag and one comparison per deref. Bevy ECS, slotmap, every modern handle system. The "global layout shift" version is content-addressed storage (Git-style: hash *is* the name; mutation produces a new name).

The non-result: you can't get all four of (intrinsic identifier, O(1) lookup, no per-node state, stable under structural shifts) at once. DHTs trade lookup cost. React trades a side index. Handles trade an indirection. Positional schemes trade stability. Content hashing trades mutability.

Closest thing to a universal answer: **hash something intrinsic, accept an indirection layer, bound that layer's state to O(log N) per node.** DHTs, ECS handles, React keys, and Git all converge on that recipe from different directions.

---

## Nick

<!-- message 3; source_index=4; uuid=019e4b95-045e-75c6-8c42-d067262f8e9b; created_at=2026-05-21T17:28:38.269930Z -->

Why not have multiple lookup keys and index them along multiple dimensions and use some scoring system for key prefixes/segments? Just like databases index rows along multiple dimensions and you can match by any index/multiple if some values can change. 

Are there alternative solutions?

---

## Claude

<!-- message 4; source_index=5; uuid=019e4b95-045e-7a5c-a574-09939f97c1e9; created_at=2026-05-21T17:29:54.487502Z -->

Multi-indexing does work — it's basically what databases, Playwright/Selenium, CRDTs, and your day job at Stagehand all do — but there's a subtle catch: databases get away with it because they still have a canonical primary key (rowid, content hash, sequence number) that the secondary indexes *point at*. The secondary indexes are convenience. They don't resolve identity, they accelerate queries.

When you try to make multi-index *be* the identity (no primary, just scored matches), three things break:

1. **Ambiguity becomes the default.** Two candidates with similar scores → probabilistic resolution. Fine for "find the login button" (LLM-driven browser automation), unacceptable for "deref this pointer."
2. **No serializable name.** You can't transmit or persist "the thing that scores highest on these features" — features drift, scoring weights drift, the resolver isn't pure.
3. **Update consistency recurses.** When any indexed dimension changes, you have a mini cache-invalidation problem internally about which indexes are now stale.

The rule is roughly: scoring/multi-index works *as a discovery layer over* canonical identifiers, not *as a substitute for* canonical identifiers. Stagehand is exactly this — accessibility tree, text, structural position, screenshot region are all indexes, but the handle underneath (xpath/targetId in your design) is canonical.

Alternatives that take genuinely different approaches:

- **CRDTs (Yjs, Automerge)**: every element gets a unique id at creation (Lamport clock + replica id). Position is derived by sorting ids in causal order, not stored. Insertions never shift existing ids. Cost: ids grow, ordering computation is nontrivial.
- **Tombstones / append-only**: never actually delete or reorder. Deleted items stay with a flag; new items append. All identifiers stable forever. Cost: unbounded growth, needs GC/compaction.
- **Versioned / persistent structures**: every change produces a new version. Old identifiers still resolve in old versions. Git, immer, Clojure persistent collections. The structural-shift problem dissolves because nothing shifts — you fork.
- **Merkle / content-addressed subtrees**: identifier is hash of the subtree. A stable subtree keeps its identifier even if the surrounding tree changes. IPFS, Git trees, Plan 9 Venti. Cost: any mutation rehashes up the spine.
- **Longest-prefix / hierarchical routing**: identifier is a path, lookup tolerates partial matches. IP routing tables, file paths with symlink fallbacks, CSS selectors. Graceful degradation rather than hard fail.
- **Two-level naming**: cryptographic canonical id + human-friendly lookup name. SSH (host key + hostname), Tor onion services, Unison's content-addressed code. Hash is identity, name is UX.
- **Vivaldi-style continuous coordinates**: assign coordinates in a metric space where neighbors are nearby. Updates only nudge locally. Used for latency estimation in P2P overlays.

The deeper pattern across all of these: when the structure shifts, *something* has to absorb the shift. Either the identifier absorbs it (positional — breaks on change), the index absorbs it (lookup table — costs state), the writer absorbs it (immutability/append-only — costs storage), or the reader absorbs it (scoring/fuzzy match — costs determinism). There's no fifth option. Every system you can name picks one of those four to take the hit, and your engineering taste shows up in which trade you find tolerable for the problem at hand.

---

## Nick

<!-- message 5; source_index=6; uuid=019e4bab-0d82-7464-887c-96d399edc0a6; created_at=2026-05-21T17:52:42.337520Z -->

the problem is even initial insertion order on first pageload is not stable, react can render subtrees in parallel and there are tons of races on first paint

---

## Claude

<!-- message 6; source_index=7; uuid=019e4bab-0d82-74e7-8671-85f6dfac6664; created_at=2026-05-21T17:53:55.754105Z -->

Right — that's the deeper version of the problem and it's where insertion-order schemes structurally fail. Lamport clocks assume a single logical replica per writer. React 18's concurrent rendering, streaming SSR, Suspense boundaries resolving out of order, hydration racing against client-side effects — these collectively mean you don't even have a *total order* of insertions, you have a partial order with genuine races. "The ith node created" isn't a well-defined concept.

This rules out the entire family of "id = creation timestamp + nonce" approaches, including most CRDT identifiers, because they presume the writer can locally totally-order its own insertions. React's renderer can't. The same component rendered twice can produce different child orderings depending on which Suspense boundary resolved first, which streaming chunk arrived first, which effect ran first.

The only identifier schemes that survive this regime are ones derived from something that exists *prior to and independent of* the rendering process:

- **Source-data ids**: `key={item.id}` where `id` comes from the database/API/business domain. This is why React keys are mandatory and why React refuses to autogenerate them — the framework can't fabricate stability that wasn't in the input.
- **Content hashes**: identifier = hash of the rendered content. Same content → same id regardless of render order. Used by snapshot libraries and some testing tools.
- **Semantic-role paths**: "the submit button inside the login form" — derived from accessibility tree semantics, not DOM ordering. Robust to structural shuffles because the semantic relationship survives them.
- **Logical structural paths**: position in the *data model*, not the rendered tree. `state.users[42].posts[0]` rather than `document.querySelector(...)`. Bypasses the render layer entirely.

The principle: **identity must be an input to the rendering process, not an output of it.** Trying to derive stable identity from the output of a non-deterministic process is structurally impossible — the output isn't a function of identity, identity has to feed the output.

This is the actual reason DOM-based browser automation is fundamentally flaky. Playwright tries to expose stable handles over an inherently non-deterministic substrate, and the handles inherit the substrate's non-determinism. "Better primitives" in the sense you've been using it probably has to mean primitives upstream of the DOM — accessibility tree (which is constructed at a later, more settled stage), the React fiber tree (which has internal keyed identity even if you can't reach it from outside), or the underlying data model (the actual source of truth). Or detect quiescence at known synchronization points and accept the latency cost of waiting.

There's also a phase issue, separate from ordering: during streaming SSR + hydration + concurrent rendering, DOM and framework tree literally disagree for a window of time. Identity isn't just unstable in that window, it's *undefined* — the question "what is this element's stable id" has no answer because there isn't a single coherent tree to ask. Realistic responses are (a) don't query for identity until quiescence is detected, or (b) query a layer that doesn't have the race (the data model, the server-rendered HTML pre-hydration, the accessibility snapshot after settle).

---

## Nick

<!-- message 7; source_index=8; uuid=019e4bae-7653-77a0-9343-4e886f81c117; created_at=2026-05-21T17:56:25.743939Z -->

can we embed all the dom elements in some manifold and do vector search / rag?

dom element type and attrs
css classes and styles get mapped to some dimensions
various potential xpaths get embedded
innerText gets embedded
bounding boxes / document relative coordinates get embedded
aria role / attrs get embedded
etc.

is this feasible in <100ms for 2000 DOM elements inside the browser?
we have access to OPFS and wasm and modern browser features

---

## Claude

<!-- message 8; source_index=9; uuid=019e4bae-7653-7170-bd99-dad985f86226; created_at=2026-05-21T17:58:15.759342Z -->

Yes, feasible — but the bottleneck isn't where you'd expect, and it dictates the architecture.

Cost budget for 2000 elements in-browser:

**Cheap (~20–50ms total):**
- DOM traversal: 1–5ms
- `getBoundingClientRect` batched (one layout flush): 5–15ms
- `getComputedStyle` batched: 5–20ms
- Categorical features (tag, role, attrs, class tokens) → one-hot or hashed: <5ms
- Numerical features (bbox normalized, viewport position, z-index, font-size): <5ms

**Expensive — where the budget actually goes:**
- Semantic text embeddings for innerText / aria-label / title / placeholder.
  - all-MiniLM-L6-v2 (22M params, 384-dim) via ONNX Runtime Web on WebGPU: ~5–15ms per short text uncached; batched 2000 → 200–500ms.
  - WASM-only fallback: ~10× slower. Blows the budget.
  - Tiny distilled models (4–8M, INT8): 50–150ms batched, marginal.

**Trivial (~1–5ms):**
- The vector search itself. 2000 × 768-dim brute-force cosine with SIMD is <5ms. HNSW is sub-ms but overkill at this scale.

Cold-path total: ~300ms–2s depending on model + GPU. Hot path with caching: 30–80ms, which clears your <100ms target.

The architectural moves that make this work:

1. **Hierarchical retrieval.** Don't embed all 2000 semantically. Use cheap features first (ARIA role match, bbox intersection, tag filter) to narrow to ~20–50 candidates, then run semantic embedding only on those. Drops the expensive step 50–100×. Standard RAG-over-DOM pattern.

2. **Aggressive OPFS caching.** Text → embedding keyed by content hash (most DOM text is stable per template; hit rate >90% on revisits). Per-site element signatures → known-good xpath, persisted across page loads. Cache the compiled model weights so cold start is JIT, not network.

3. **Late fusion, not concatenation.** Keep per-modality vectors (text, structure, spatial, role) separate. At query time, weight them based on the query. "Click submit" weights text + ARIA; "click the red button top-right" weights spatial + style. Concatenating up front locks the weights and forces full re-embedding when you want to retune.

4. **WebGPU is the dividing line.** With it, ~100ms cold is achievable. Without it, you're stuck with lexical-only (hashed n-grams, no semantics) or a budget closer to 500ms–1s. Feature-detect and downgrade gracefully.

What this buys you over the current Stagehand model: deterministic retrieval that doesn't need an LLM call in the hot path. The LLM moves up the stack — "resolve user intent → query vector" and "rerank top-K," neither of which has to look at 2000 elements. Token cost drops an order of magnitude, latency stops being LLM-bound, and the retrieval layer becomes testable and reproducible in a way pure LLM selection isn't.

Honest tradeoffs:

- The embedding model becomes a coupling point — version bumps invalidate the cache site-wide. Mitigate with model id in the cache key and lazy re-embed on miss.
- Sites without standard semantics (canvas-rendered UIs, custom WebGL, deeply visual layouts without ARIA) degrade hard because most modalities go null. You probably need a vision-based modality (screenshot patch embeddings) as a fallback, which is its own performance conversation.
- It's still probabilistic. You need a canonical handle underneath (xpath/targetId) — vector search is the discovery layer to *get* to the canonical id, it doesn't replace it. Connects back to the multi-index-over-canonical-key point from earlier.

The closest real-world analogs are server-side: reported ACT-1 architecture, Mind2Web baselines, several agent-browsing internal stacks. Doing it in-browser with OPFS + WebGPU is the actual differentiator — you get the latency, offline-capable, and privacy properties without paying for a backend embedding service, which fits the cross-language SEA-binary distribution model better than a hosted endpoint would.

---

## Nick

<!-- message 9; source_index=10; uuid=019e4bb0-c6f5-778e-a7bf-3b26910972e9; created_at=2026-05-21T17:58:57.460990Z -->

forget semantic embedding, can we do strict substring / exact token embedding?

---

## Claude

<!-- message 10; source_index=11; uuid=019e4bb0-c6f5-7513-9c08-d13236052474; created_at=2026-05-21T18:00:21.143219Z -->

Yes, and honestly this is probably the better architecture for your case. Lexical retrieval has been quietly outperforming dense embeddings for tasks with specific terminology — which is exactly what DOM corpora are.

Cost collapses entirely:

- Tokenize all text fields (innerText, aria, attrs, class, id, xpath segments): 5–10ms
- Build inverted index (`Map<token, Set<elementId>>`): 5–15ms
- Character trigram index for fuzzy/substring: 5–15ms additional
- Total index build: ~30ms cold, persistent in OPFS afterward

Query path:
- Tokenize query: <1ms
- Postings list intersect/union: <5ms
- BM25 scoring across fields: <5ms
- Per-query total: <10ms

Different latency regime entirely — you could run this on keystroke if you wanted.

What you lose: synonym/paraphrase matching. "Click submit" won't find a button labeled "Send"; "Login" won't find "Sign in"; multilingual is gone without preprocessing.

The key move for the agent case: **the LLM upstream does the synonym expansion.** The LLM is already in your loop writing the query. Instead of paying for 2000 dense embeddings at index time, the LLM emits a lexically-rich query once per intent:

```
intent: "click login"
expanded: text~(login|"log in"|"sign in"|signin|enter)
          AND role=button
          AND visible=true
```

The LLM did the embedding-equivalent work at query time, once, against a corpus of size 1. Per-query latency stays LLM-bound (~200–400ms) but retrieval itself is deterministic and sub-10ms. Cache the expansion per intent and subsequent matches are free.

What this lets you build:

1. **Field-weighted inverted indexes with BM25.** aria-label > innerText > class tokens > attr values. Weights tunable without re-indexing.
2. **Trigram fuzzy match** for typo tolerance and partial substrings (Postgres `pg_trgm` style).
3. **Boolean structural filters as cheap intersections**: `tag=button AND text~login AND bbox_quadrant=center`. Each filter is just a postings list lookup.
4. **Phrase / proximity matching** if you store positions: "submit form" requires adjacency, not just co-occurrence.
5. **Edge n-grams** for prefix matching.

All of this is sub-100KB of code (minisearch, flexsearch, or hand-rolled in ~150 lines), zero GPU dependency, no model versioning, fully debuggable. The debuggability gap is significant on its own: "matched token 'login' in aria-label, field weight 3.0, BM25 score 8.2" beats "cosine similarity 0.83" for engineering trust and for postmortems when something goes wrong.

Honest limitations:

- Pure visual UIs (canvas, WebGL, custom-rendered) give no lexical signal. You need a vision modality fallback regardless of approach.
- Heavily obfuscated class names (`_a3b4c5`) are noise. Filter or down-weight by entropy heuristic.
- Multilingual sites need either upstream LLM normalization or per-locale token streams.

The useful analog from the LLM RAG world: consensus has shifted toward **hybrid retrieval (BM25 + dense)** with BM25 often the stronger leg for technical corpora. Pure lexical is the rational baseline. Add a dense layer only if you measure a specific failure mode that demands it — not preemptively. For DOM in an agent context, I'd be surprised if you needed the dense layer at all once the LLM is doing query expansion upstream.

This also fits the "better primitives than Playwright" framing cleanly: a deterministic, fast, sub-100KB, debuggable retrieval primitive is a much more honest interface than "the LLM usually returns the right element handle." It's the kind of thing reviewers can reason about and write falsifiable predictions against.

---

## Nick

<!-- message 11; source_index=14; uuid=019e4bba-42dd-7f44-b5e2-bb51c983ecd7; created_at=2026-05-21T18:09:18.973622Z -->

the goal is to have a single dom element address or identifier thats 64~256 chars per element.

<html>
<body>
...
<main>
<div id="loginform" class="dark-mode active" data-username="someguy">
     <label>Username<input type="text" autocomplete="username" id="username"/></label>
     ...
</div>
...
</main>
</body>
</html>

could be something like an xpath but more resilient, or something less readable like a SimHash / MinHash / geohash, morton code, etc.


like:

- `v1:t8p8a8:a23:234sfs:...`

+ ideally a human-readable expanded type/container/string equivalent that shows all the inputs used to generate the condensed form: 

- `xpath=/h/b/m/label[1]/input[@type="text" and autocomplete="username"];css=#loginform input#username;coordinates=...`

---

## Claude

<!-- message 12; source_index=15; uuid=019e4bba-42dd-7aac-a647-b80e8c6e7647; created_at=2026-05-21T18:11:33.811701Z -->

Here's a scheme that fits the 64–256 char budget and supports the partial-match retrieval from the previous messages.

**Structure**: ordered, typed segments. Each is `<2-char type code><:><value>`, segments separated by `.`. Ordered most-stable-first so prefix matches give you the best fallback when later segments drift.

For your `<input>`, a fingerprint might look like:

```
v1.tg:i.ty:tx.ac:un.rl:tbx.id:user.pid:loginf.lbl:s7k2.pth:bmdli.box:cl3.pos:1
```

~70 chars. Segments:

| Code | Meaning | Source | Stability |
|---|---|---|---|
| `v1` | Scheme version | constant | — |
| `tg:i` | Tag (single char for common HTML5 tags) | nodeName | very high |
| `ty:tx` | type=text | attribute | very high |
| `ac:un` | autocomplete=username | attribute | very high |
| `rl:tbx` | ARIA role (implicit or explicit) | computed role | very high |
| `id:user` | xxhash3 prefix of id attr | id | high if dev-set, low if auto-gen |
| `pid:loginf` | nearest stable ancestor id, hashed | ancestry walk | high |
| `lbl:s7k2` | SimHash of associated label text | `<label>` / aria-labelledby | medium-high |
| `pth:bmdli` | tag skeleton compressed (first char of each ancestor tag) | xpath without positions | medium |
| `box:cl3` | geohash-style viewport region | bounding box | low |
| `pos:1` | nth among role-equivalent siblings | sibling walk | low |

The expanded form is the same features in JSON plus selectors derived from them:

```
fingerprint: v1.tg:i.ty:tx.ac:un.rl:tbx.id:user.pid:loginf.lbl:s7k2.pth:bmdli.box:cl3.pos:1
features:
  tag: input, type: text, autocomplete: username
  id: username (xxh: user)
  role: textbox (implicit)
  label_text: "Username" (simhash: s7k2)
  parent_id: loginform (xxh: loginf)
  parent_classes: [dark-mode, active]   # not in fingerprint, recorded for debug
  path_skeleton: body>main>div>label>input
  bbox: {x:480, y:320, w:200, h:32, region: cl3}
  position_among_role_siblings: 1
selectors:
  css_primary:  '#loginform input#username'
  css_fallback: 'input[autocomplete=username]'
  xpath_strict: '//*[@id="username"]'
  xpath_stable: '//div[@id="loginform"]/label/input'
  by_label:     'label:has-text("Username") >> input'
  by_role:      'role=textbox[autocomplete=username]'
```

**Design decisions worth being explicit about:**

1. **Segment order = stability priority**, not feature importance. Tag/type/role/autocomplete come first because they essentially never change between renders or releases. Position and bbox come last because they shift constantly. Prefix-length match → "how confident is the partial match."

2. **Hash family per segment, not one hash for the whole thing.** Specifically:
   - Short categoricals (tag, type, role, autocomplete) → exact match, no hash
   - IDs and parent IDs → xxhash3 prefix, 4 chars. Collisions at 4 chars are tolerable because they reduce ranking precision, not correctness — other segments still differentiate.
   - Label / innerText → **SimHash** (8 chars). Near-duplicates match by low Hamming distance. "Sign in" / "Sign In" hash close.
   - Bounding box → **geohash-style binary subdivision** of viewport (3–6 chars). Nearby boxes share prefix, enables range queries.
   - Tag skeleton → first letter of each ancestor tag.

3. **Versioning prefix is non-negotiable.** This scheme will evolve. Old parsers must skip unknown segments rather than fail.

4. **What's deliberately not in the fingerprint:**
   - Class names — too volatile (Tailwind, CSS-in-JS, theme toggles). Recorded in the expanded form but not fingerprinted. Optionally add `cl:` segment for classes passing a stability filter (no leading underscore, low entropy, dictionary-word-ish).
   - Computed styles — same volatility.
   - `data-*` attributes — usually app-defined and meaningful but high cardinality; consider a single `da:` segment with hash of a sorted subset, or leave for the expanded form.

**Matching semantics:**

Query is a partial fingerprint (any subset of segments). Score is weighted sum of segment matches, normalized by segments specified. Rough weights:

```
id   9   (when present and not auto-gen)
tg  10   (effectively required)
ty   8
rl   8
ac   7
pid  6
lbl  5   (with Hamming distance for SimHash, not exact)
pth  3
box  2   (with geohash prefix-length scoring)
pos  1
```

Single combinations like `tg:i.ac:un` already narrow most pages to 1–3 candidates. Above a score threshold → candidate; top-K returned with confidence.

**Tradeoffs to be honest about:**

- 70 chars is the easy case. Deeply nested elements with long ancestor chains can blow past 256. Truncate `pth:` and rely on `pid:` + `pos:`; add a `tr` (truncated) flag so consumers don't require strict path match.
- Auto-generated IDs (`__next_5kp3`, `:r2:`, `_a3b4c5`) poison the `id:` segment. Detect by entropy/regex and skip — leave the segment empty rather than encode noise.
- Sites that obfuscate every attribute leave you with just `tg:.rl:.pth:.box:.pos:`, which is genuinely ambiguous. No scheme survives this; degrade gracefully to "3 candidates, not sure" and let the LLM rerank.
- SimHash on very short text is unreliable. For labels under ~8 chars, fall back to exact hash and accept lower fuzziness.

**Integration with the previous design:**

Same feature extraction pass feeds both the fingerprint and the inverted index. The fingerprint is the canonical handle you return to callers, log, transmit, persist. The index is what you query against. Two consumers of one extraction pass — costs ~30ms for 2000 elements, amortizable across the page lifetime, and the only thing that needs rerunning on DOM mutation is the affected subtree.

Worth deciding upfront: do you persist fingerprint → element resolution across page loads (in OPFS) so a flow can be replayed? If yes, the fingerprint becomes the durable identifier and the inverted index is just an in-memory accelerator. That's the architecture I'd push for — it lets you record once, replay deterministically, and gives you a real artifact to write falsifiable assertions against.

---

## Nick

<!-- message 13; source_index=16; uuid=019e4bc1-4dd3-7f01-9477-5de87401f9a4; created_at=2026-05-21T18:17:00.671204Z -->

yes the whole point of this is to get replayable selectors across different pageloads (even with different users logged in to the same site in different browsers), we ideally dont want these keys to be reversible back to PII. one user might be using light mode, one might be dark mode, they may be on different browsers with different polyfilled rendering behavior.

its ok if the existing of the key leaks one bit about something appearing on a page, thats unavoidable, but we dont want to leak actual usernames, passwords, private data-attrs, etc if possible.

it's a very tricky problem

how do you reliably select the "currently logged in username" <span> element on a page, when it can contain different text for every user, and be in slightly different places depending on whether the user is on a pro plan or free plan (due to upgrade/prommo banners in and around the account info area)

---

## Claude

<!-- message 14; source_index=17; uuid=019e4bc1-4dd3-7ab4-913e-e0670b4c67fa; created_at=2026-05-21T18:19:12.583308Z -->

The core move for PII-bearing targets: **never derive the identifier from the target's content; derive it from its structural relationship to invariant anchors.** The target's value is the variable you cannot fingerprint by.

Recording protocol for the username span:

1. **Identify the target** (click, hover, or LLM-resolved).
2. **Anchor scan outward.** Walk ancestors and siblings looking for elements with framework-stable attributes, in priority order: `data-testid`/`data-cy`/`data-component`, ARIA landmarks (`role=banner|navigation|main`), semantic HTML5 tags (`header`/`nav`/`main`), filtered stable IDs (not auto-gen), filtered stable classes (low entropy, dictionary-word-ish).
3. **Pick the closest anchor set** that locally uniquely identifies the target.
4. **Encode path from anchor(s) to target structurally** — child index, role match, sibling-of-other-stable-thing — never absolute xpath.
5. **Audit each segment for PII risk** before serializing.

For your case (assuming `<button data-testid="user-menu">` wraps `<img>`, username `<span>`, and chevron):

```
v1.tg:s.rl:n.an:dtst:userM.rp:c.role:tx.sib:img+1.box:tr3
```

- `tg:s.rl:n` — span, no explicit role (structural)
- `an:dtst:userM` — anchor: nearest ancestor `data-testid`, xxhash prefix of the *attribute name's value*, not the user's data
- `rp:c` — relative path: direct child of anchor
- `role:tx` — text-bearing leaf (category, not content)
- `sib:img+1` — comes after a sibling with tag=img (structural)
- `box:tr3` — top-right geohash region (degrades gracefully across themes)

Deliberately excluded: innerText, target's own attribute values, `<img src>` (URL often contains username), any classes that might be user-specific, auto-generated ids.

**Classifier for "is this segment safe":**

Heuristics for "user-specific, exclude":
- contains `@`, looks like email
- entropy above threshold and not in a stable-attr allowlist
- value pattern matches numbers >4 digits
- known PII attr names (`data-username`, `data-email`, `data-user-id`, `data-account-*`)
- **changes across the same recorded flow run with different users** — this is the killer signal

That last one is the most powerful and most underused primitive: **differential recording.** Record the same flow twice with two synthetic users, diff the DOMs, mark every element or attribute that differs as user-specific. The fingerprinter then knows exactly which segments to exclude without heuristics. This is worth building into your recording layer as a first-class feature because it gives ground truth about user-variance rather than guesses.

**Replay protocol:**

1. Find candidate anchors on the new page by stable feature (`[data-testid]` whose xxhash prefix matches `userM`).
2. From each anchor, resolve the relative path.
3. If all anchors converge to one element → high confidence.
4. If multiple candidates → score by remaining structural segments. Return top-K.
5. If anchors don't resolve → fingerprint is stale; surface the failure with the captured features so the LLM can rediscover.

**Promo banners / plan differences:**

Relative-from-anchor wins here. Banners shift absolute positions but don't shift the relationship between the user-menu button and its inner span. As long as the anchor itself exists on both plans, the relative path resolves identically.

Where it still breaks:
- Promo banner inserted **inside** the anchor, between anchor and target. Mitigation: structural relations (`descendant-of` with role/tag match) rather than positional (`nth-child`).
- Anchor only exists on one plan. Mitigation: multi-anchor encoding — record two or three independent anchors with their relative paths; replay accepts any quorum.
- Anchor has user-specific suffix (`data-testid="user-menu-someguy"`). Mitigation: prefix-match on anchor hash, and differential recording detects the suffix as user-variant.

**The deep observation worth sitting with:**

To identify a PII-bearing element, you fundamentally need to know its *role* on the page — and role is app-developer-defined metadata. There's no escape:

- If the site provides good metadata (`data-testid`, ARIA, semantic HTML), your fingerprint is clean and stable.
- If it doesn't, you're inferring "the span that probably holds the username" from structural signals, and the only robust recovery is differential recording — observing how the page varies across users tells you which elements are user-bearing without you having to read their content.

So your recording layer should ideally *always* record a baseline with a second synthetic user, even if the LLM only sees one trace. The diff is free PII detection and free anchor validation.

**Privacy properties of the resulting fingerprint:**

Encoded: tag, role, app-structural attribute hashes (developer-defined names, not user values), positional relations, viewport regions. None of these reveal anything about a specific user — they reveal the app's structure, which you said is acceptable. The 1-bit leak ("this site has a user-menu element") is unavoidable for any selector that can find user-specific content; the question is whether you leak more than that, and with this scheme you don't.

Remaining attack surface: hash collisions on anchor names could in principle support rainbow-table lookup of `data-testid` values across sites. Mitigations: use 8-char xxhash prefixes for anchor segments specifically (not 4), and if cross-site linkability of fingerprints is a concern, keyed hashing with a per-site or

> **Note:** Claude’s response was interrupted.

---

## Nick

<!-- message 15; source_index=18; uuid=019e4bc4-7933-7a14-9c30-589d01de8195; created_at=2026-05-21T18:20:28.313208Z -->

no thats not true, we definitely want to derive *part of* the identifier from its content, sometimes the content is the *only* stable part!

e.g. 

<b>some bolded text</b> in a sea of other text that can shift is impossible to select without hashing the content. it needs to work for that case too, the whole benefit of fuzzy matching is we can throw a little bit of everything in the key, and if the match is super ambiguous, every last bit of entropy helps narrow it down until we get 1 candidate

---

## Claude

<!-- message 16; source_index=19; uuid=019e4bc4-7933-7782-9031-e75d20c995b3; created_at=2026-05-21T18:21:34.041101Z -->

You're right, I overstated. The rule should be "content is included by default, excluded *only when the PII classifier flags it*" — not "never derive from content."

The `<b>` in flowing prose is exactly the case where every weak signal matters and content is most of the signal. No anchor, no stable id, no structural distinguisher between this `<b>` and the next one in the paragraph. The right fingerprint for it looks like:

```
v1.tg:b.txt:5kpz3a8m.ctx:7q2x.pth:adp.box:c2.ix:3
```

- `tg:b` — tag (a few bits, `b` is uncommon enough to filter heavily)
- `txt:5kpz3a8m` — SimHash 8 chars of innerText, the dominant disambiguator
- `ctx:7q2x` — SimHash of surrounding sentence / sibling text, weak signal
- `pth:adp` — tag skeleton from nearest stable ancestor
- `box:c2` — bbox region
- `ix:3` — index among same-tag siblings under nearest stable ancestor

SimHash matters here even when text is short, because small wording edits ("some bold text" vs "some bolded text") still match by Hamming distance. For very short text (<8 chars), fall back to exact hash and accept the brittleness — but short `<b>` content makes surrounding context the bigger signal anyway.

Your information-theoretic framing is the right one for the whole scheme: with k weak features each carrying some mutual information with the target, the combination disambiguates even when no individual feature does. For 2000 elements you need ~11 bits to uniquely identify; features carrying 0.3 bits of MI each add up fast in combination. The 10–12 segment scheme works because of *combinatorial* uniqueness, not per-segment uniqueness. Throwing everything in is the correct instinct.

Corrected policy, segment-by-segment:

| Segment | Default | When stripped |
|---|---|---|
| `txt:` (innerText SimHash) | include | differential recording flags as user-variant, or PII heuristic matches |
| `lbl:` (label SimHash) | include | same as above |
| `id:` | include hash | id pattern looks auto-gen or contains user data |
| Attribute values | include each | per-attribute flag from classifier |
| `href:` | include path prefix | strip user-specific suffix (`/users/someguy` → `/users/*`) |
| `src:` | hash path prefix only | strip user-token URL segments |
| `alt:`, `title:`, `placeholder:` | include | rarely PII, but classifier-checked anyway |
| Structural (`tg`, `rl`, `pth`, `sib`, `pos`, `box`) | always include | (no PII risk) |

The classifier runs **per segment per element**, not per element wholesale. The username span loses its `txt:` but keeps its `tg:`, `rl:`, `an:`, `rp:`, `sib:`, `box:`. The bolded text keeps `txt:` because differential recording shows the same content across users.

That's the actual unification: the fingerprint always contains every signal it has access to, and the PII classifier selectively strips segments that fail the per-user-stability test. Format is uniform across elements; *contents* adapt to what's safe for that specific element. The bolded-prose case and the username case use the same scheme; they just end up with different non-null segments.

One worth-flagging consequence: an element whose fingerprint is mostly stripped (e.g., username span: only structural segments survive) carries less information than one with content (the bolded text: most segments present). The matching engine should expose this — return a "confidence floor" derived from the number of disambiguating bits in the fingerprint, not just the match score. A stripped fingerprint that uniquely matches today might silently start matching the wrong element when the page changes; a content-rich fingerprint failing to match is a louder, more recoverable signal.

---

## Nick

<!-- message 17; source_index=20; uuid=019e4bc6-b13b-7913-99d0-8ae93460aeab; created_at=2026-05-21T18:22:53.971973Z -->

bounding box / location is tricky because pages are responsive and can render in different sized viewports, and elements can move all over the place on the screen. it's ok if the matches are stronger when rendered in the same viewport, and weaker when viewport is different (but hopefully still functional)

---

## Claude

<!-- message 18; source_index=21; uuid=019e4bc6-b13c-7bc6-83dd-5c7483dc8a9a; created_at=2026-05-21T18:23:06.638324Z -->

> **Note:** Claude’s response was interrupted.

---

## Nick

<!-- message 19; source_index=22; uuid=019e4bc7-4882-77d9-a767-4ae3b6a0cd25; created_at=2026-05-21T18:23:32.401550Z -->

differential recording is the obvious optimization path, but we're not there yet, we need to be able to one-shot this for new pages we've never seen before with ~2000 elements in <100ms

---

## Claude

<!-- message 20; source_index=23; uuid=019e4bc7-4882-7663-a7c8-b9e87d736865; created_at=2026-05-21T18:25:43.930607Z -->

Two real constraints worth treating separately.

**Cross-viewport positioning**

Absolute pixel coords are useless across viewports — wrong frame entirely. Replace `box:` with a *bundle* of position segments that degrade gracefully:

- `do:0235` — document order, normalized fraction (4 chars). Element's index in DOM traversal divided by total count. Invariant across viewports — viewport affects layout, not source order.
- `sp:043` — scroll-axis progress: where this element sits along the document scrollable, as a fraction. More stable than y-pixel because total scroll height scales with viewport.
- `qd:tc` — qualitative viewport quadrant (top-center, mid-left, bot-right). 9 buckets, 2 chars. Coarse but mostly stable; a header stays "top" across reflows even if it wraps.
- `lp:c3` — layout-container position: nth child of its nearest layout container (flex/grid/block parent). Very stable because container hierarchy is structural, not layout-pixel.
- `sz:m` — size class as fraction of viewport (tiny/sm/md/lg/full). Stable as a category.
- `ar:21` — aspect ratio bucket. Reasonably stable for non-text containers.

Matching applies viewport-aware weights. Same viewport as recording (within a tolerance band) → all segments full weight, tight match. Different viewport → downweight `qd` and `sp`, upweight `do` and `lp`. Categorical and structural-position signals survive reflow; precise spatial ones don't. Fingerprint still resolves, with lower confidence.

That's the "stronger in same viewport, weaker but functional in different" property. Document order alone gives ~11 bits of disambiguation for 2000 elements regardless of viewport, which combined with the other segments is usually enough.

**One-shot in <100ms for novel pages**

Budget at 2000 elements / 100ms = 50μs per element including everything. Tight but doable. Realistic breakdown:

| Phase | Time |
|---|---|
| TreeWalker walk + attr extraction + path/anchor stacks | 5–10ms |
| `getBoundingClientRect` batched (one forced layout) | 10–20ms |
| Visibility filter (skip `display:none`, off-screen, aria-hidden) | folded into walk, 1–3ms |
| SimHash for text-bearing elements (~500 typical, not 2000) | 20–40ms |
| Categorical segments + structural relations | 5–10ms |
| Fingerprint assembly | 5–10ms |
| **Total cold path** | **~45–90ms** |

The optimizations that get you under 100ms:

1. **One-pass walk with maintained stacks.** TreeWalker, single descent. As you descend, push onto a stable-anchor stack and a path-skeleton stack; pop on ascent. Every element gets its nearest stable anchor and full path skeleton in O(1) incremental. Naïve per-element ancestor walks are O(depth) — that's what kills you on deep trees.

2. **Batch layout reads, defer everything else.** All `getBoundingClientRect` calls in a tight loop *after* the walk, before any hashing. One forced layout total. Then never touch the DOM again — hash off the captured feature table.

3. **Filter aggressively before SimHash.** Only ~25% of elements have meaningful text. `display:none`, `visibility:hidden`, empty leafs, pure container divs — skip SimHash for these. Single biggest cost cut.

4. **Don't compute implicit ARIA role via the accessibility API.** Use a static tag → implicit role table (`input[type=text]` → textbox, `button` → button, `a[href]` → link). The browser-computed role is expensive; the table covers 95% of cases for free.

5. **Skip `getComputedStyle` entirely.** Without class signatures (already deprioritized), you don't need style computation. Saves 20–50ms on a typical page — this alone often makes or breaks the budget.

6. **Move assembly to a worker.** Main thread does DOM walk + bbox batch (~25ms blocking). PostMessage the raw feature table to a worker. Worker does SimHashes + categorical encoding + string assembly in parallel. Main-thread block ~25–30ms, wallclock ~60–80ms.

7. **xxhash3 over crypto hashes.** ~50× faster than SHA-256, and we don't need cryptographic properties — segments are disambiguators, not security boundaries.

**One-shot PII handling without differential recording:**

You lose the killer signal (varies-across-users) but heuristics get you 80–90%:

- Regexes: email, phone, numbers >4 digits, common token formats
- PII-prone attr name allowlist: `data-username`, `data-email`, `data-user-id`, `data-account-*`, `data-customer-*`, `data-tenant-*`
- Entropy classifier on attribute values: high-entropy short strings are likely tokens, not labels
- **Ancestral PII hint propagation**: if any ancestor has `aria-label="Account"`, `data-section="profile"`, `role="banner"` near "user", etc., descendants are more likely user-bearing. Pass the hint down during the walk; downweight or strip `txt:` under PII-hint subtrees.

The last one is the cheap structural version of differential recording. The walk already maintains ancestor state, so the hint costs nothing. Catches the username-span case by *its location in the app's information architecture* rather than by reading its content — which is exactly what you want for one-shot.

The classifier is conservative by default — when in doubt, strip the segment. You get a less informative fingerprint in ambiguous cases but preserve the privacy property. Later, when differential recording lands, it upgrades the classifier's precision without changing the format — same scheme, same fingerprints, just fewer false-positive strips.

**Where the budget gets uncomfortable:**

- Pages with heavy shadow DOM (web components, design systems like Lit-based ones) — TreeWalker doesn't cross shadow boundaries; you need to recurse into `shadowRoot` per element, which adds traversal cost and complicates the path skeleton encoding.
- Pages with thousands of off-screen virtualized list items that the framework keeps in the DOM. Visibility filter helps but not all virtualization marks elements as hidden — some just translate them off-screen.
- Sites with extreme CSS-in-JS where every element has unique class names. Doesn't affect the budget directly (we're skipping classes) but means the anchor scan finds fewer stable attrs, so paths get longer and fingerprints push toward 256 chars.

For those edge cases, accept >100ms and surface it as a metric — better to know than to silently truncate. The 100ms budget should be a normal-case SLA, not a hard ceiling that produces wrong results when violated.

---

## Nick

<!-- message 21; source_index=24; uuid=019e4bcd-d9dc-765c-aaf2-99d5fa6b0ebe; created_at=2026-05-21T18:30:42.863803Z -->

we still need getComputedStyle because cursor style changing to a pointer is one of the main signals that an element is interactive. we also need to do visibility/transparency/occlusion checks to filter out elements that are invisible to a user.

we expose several options like so:

 getDomSnapshot({
   filters: [
     {visible: true, exclude: false},
     {interactive: true, exclude: false},
     {exclude: true}
   ],
})

our function automatically handles recursing into shadow roots and OOPIFs, dont worry about that part.

focus on how we can return a tree given any set of filters that  still produces stable ids that are usable across different snapshot config options/ different pageloads / different users logged in / different viewport sizes

e.g. getDomSnapshot(... only interactive).find(login button).stableId should still fuzzy-match against
getDomSnapshot(...all visible elems).find(login button).stableId for a different logged in user in a different timezone, using dark mode, on mobile viewport settings

---

## Claude

<!-- message 22; source_index=25; uuid=019e4bcd-d9dc-7c1d-9b1c-e396ca283800; created_at=2026-05-21T18:32:47.482690Z -->

The constraint reshapes the design: **stableId must be a function of (element, DOM context) only, never of (element, filter, snapshot).** Filters change which elements appear in the returned tree; they cannot change the identity of any element that does appear.

That kills a few segments from the earlier scheme:

- `do:` (normalized document order) — out. Numerator and denominator both depend on what's in the snapshot. Even fixing the denominator to "all DOM elements" doesn't help since the DOM varies per user.
- Anything counting "filtered children" or "filtered siblings" — out.
- `pos:` defined as "nth among role-equivalent siblings in snapshot" — out. Must be redefined against DOM siblings only.

What survives are segments computed entirely against the underlying DOM, irrespective of any filter:

- `tg:`, `ty:`, `ac:`, `rl:` — intrinsic attributes / static role lookup
- `id:`, `pid:` — hashes of stable IDs (PII-filtered)
- `pth:` — tag skeleton from nearest stable anchor through DOM ancestry
- `rp:c2` — relative path from anchor through DOM children (not filtered children)
- `sib:img+1` — sibling relations through DOM siblings
- `lbl:`, `txt:` — content SimHashes, PII-aware
- `qd:`, `sp:`, `sz:`, `ar:`, `box:` — layout-derived, intrinsic to this element's own rendering

Still 10+ segments worth of disambiguation. For ~200 interactive-only or ~2000 all-visible, well-anchored relative-path segments alone usually suffice; content and layout segments are the long tail of disambiguation.

**The mental model to enforce in code**: the fingerprinter takes a DOM node and returns a string. It is *never* parameterized by filter config. Filters affect which fingerprints get returned, never how one is generated. A one-line property test:

```ts
// for any el, regardless of which filter pass surfaced it:
fingerprint(el) === fingerprint(el)
```

Run it across "visible only," "interactive only," and "all" on a test corpus — equality must hold absolutely. Any inequality is a bug in segment definition.

**getComputedStyle within the budget**

1. **Cheap pre-filter first.** `offsetParent === null` catches most `display:none`. `getBoundingClientRect()` with zero width/height catches collapsed elements. ~30–50% of elements need a full style read after these screens.
2. **Targeted property reads, not full style object inspection.** Read only `cursor`, `pointer-events`, `visibility`, `opacity`, `display`, `position`. ~10–30μs per element.
3. **Occlusion via `elementFromPoint`** at center + 4 corners, only on elements that already pass visibility. Catches z-ordered overlays. Limit to candidates inside the viewport; skip the rest.
4. **Style reads in their own batch** after the bbox batch — same forced-layout-once principle. Read everything in a tight loop, then move to hashing.

Revised cold-path budget:

| Phase | Time |
|---|---|
| TreeWalker walk + attr extract + anchor stack | 5–10ms |
| `getBoundingClientRect` batch | 10–20ms |
| Cheap visibility pre-filter | 3–5ms |
| Targeted `getComputedStyle` on survivors (~1000) | 15–30ms |
| `elementFromPoint` occlusion on candidates (~200) | 5–15ms |
| SimHash for text-bearing visible (~300) | 15–25ms |
| Fingerprint assembly in worker (overlapped) | 5–10ms |
| **Total cold path** | **~55–110ms** |

At the edge. Slips worth accepting:

- First call ~150ms is fine if subsequent calls cache the per-element feature table keyed by node identity and only recompute deltas. Hot path ~20ms.
- For huge pages (5k+), budget genuinely breaks. Return a coarse snapshot first (cheap segments only, no SimHash, no occlusion), then a refined one async. Callers consume whichever arrives first and is sufficient.

**The clean separation: interactive flag ≠ stableId**

This is the architecturally important point. `interactive: true` is a property of the *snapshot output*, not of the stableId. The same element has the same stableId whether it's classified interactive in this snapshot. When dark-mode CSS toggles `cursor: default` on previously-pointer elements (or vice versa), the interactivity flag may flip; stableId stays put. Replay across themes still matches; the consumer separately decides how to treat the matched element in the current rendering.

This means the cursor / pointer-events read informs *filtering and labeling*, not identity. The fingerprinter doesn't need to see computed style at all — that's a separate concern downstream. Splitting the pipeline:

```
DOM walk → raw feature table → [fingerprint pass]  → fingerprints
                              ↘
                                [style + occlusion] → interactive/visible flags
                              ↘
                                [assembler]         → filtered tree with stableIds
```

Each pass is independent. Fingerprint generation is a pure function over DOM. Style classification is re-runnable with different criteria without touching any stableId. This is what makes the filter-stable invariant testable and provable rather than aspirational.

**Cross-viewport interaction with this constraint**

The viewport-aware position bundle (`qd`, `sp`, `lp`, `sz`, `ar`) still holds — every segment is intrinsic to the element's own layout, not to the snapshot's filter. A button at the top-right of a mobile viewport has `qd:tr` regardless of whether the snapshot filtered for interactive-only or all-visible. The replay-side viewport-aware weighting handles the actual cross-viewport degradation. The two constraints (filter-invariance and viewport-degradation) compose cleanly because they target different axes — filter-invariance is about *which DOM context the segment references* (always the full DOM), viewport-degradation is about *how much each segment is trusted* at match time.

One subtle point worth flagging: `lp:c3` (nth child of nearest layout container) is intrinsic to DOM structure, but the *identification* of "nearest layout container" requires computed style (to know whether the parent is flex/grid/block). If you compute layout-container position during fingerprinting, you've smuggled computed-style dependency back in. Two options: (a) compute it once with the style batch and bake it into the feature table, or (b) drop `lp:` and rely on `rp:` (anchor-relative position) which uses pure DOM ancestry. I'd lean (b) — keeps the fingerprinter genuinely pure-over-DOM and removes any chance of style-dependent identity drift.

---

## Nick

<!-- message 23; source_index=26; uuid=019e4bd1-8bb7-7024-8014-fd4064548dce; created_at=2026-05-21T18:34:46.213552Z -->

I dont think this works, we dont want the stable ids to be literally equal, thats impossible without losing tons of potential long tail fuzzy signal.

we just want the generated stable ids to fuzzy match well enough to select the same conceptual element in a way thats resilient to dom changes or environment differences.

are you sure vector embeddings arent better than trying to stuff everything into semi-human-readable chunked ids? I feel like you're overfitting on that narrow approach when we havent properly considered other structures

---

## Claude

<!-- message 24; source_index=27; uuid=019e4bd1-8bb7-729b-9b64-81f04ae6b8de; created_at=2026-05-21T18:37:26.632632Z -->

Fair pushback. I was incrementally patching one design rather than actually reconsidering the structure. Let me lay out the alternatives honestly.

The conflation worth surfacing first: I've been treating stableId as both *identifier* (handle pointing to an observation) and *retrieval key* (what you match against to find similar elements). Those are two different roles, and modern retrieval mostly separates them. The chunked ID tried to do both, which is exactly what produced the budget/exhaustiveness/readability tension you keep hitting.

Structures worth comparing properly:

**1. Chunked human-readable ID** (what I'd been pushing)
- ID *is* the retrieval key.
- Pros: portable single artifact, debuggable, deterministic, no model.
- Cons: budget-constrained, every new drift mode requires schema changes, per-segment weighting is hand-tuned, fuzzy matching only happens *within* segments (Hamming on SimHash) and is boolean *between* segments.

**2. Dense feature vector (no learned model)**
- ~100–200 hand-engineered features → quantized vector → cosine similarity.
- ID is the quantized vector (base64, ~200–270 chars).
- Pros: unified metric, easy to extend (just append dims), well-understood ANN indices, learnable later with a Mahalanobis covariance or projection.
- Cons: opaque, quantization loses info, no natural "must match X" filter.

**3. LSH bands over a feature vector** — probably the most interesting option
- Compute the feature vector, then hash multiple feature subsets into independent bands (e.g. 8 bands × 8 chars = 64 chars total).
- Two elements share a band ↔ those feature subsets are close.
- Match: count shared bands. 8/8 = identical, 5/8 = very similar, 0/8 = unrelated.
- Pros: built-in fuzzy matching, sub-linear lookup at scale, naturally captures the long tail of weak signals, compact.
- Cons: bands themselves uninterpretable; needs the full feature dict alongside for debug.

**4. Multi-key with quorum**
- Several short complementary keys: `s:` structural, `c:` content, `x:` context, `p:` spatial.
- Each 16–32 chars; full ID is the concatenation.
- Match: any key matches → candidate, multiple keys → confidence.
- Pros: graceful single-axis failure (theme change kills spatial, others survive; PII strip kills content, others survive); keys independently interpretable; clean diagnostics ("matched on structure, lost spatial").
- Cons: still hand-designed per axis, scoring is set-based not metric-based.

**5. Graph-locality embedding** (worth naming, probably overkill)
- Weisfeiler-Lehman-style graph hash over element + immediate neighborhood.
- Stable across most local DOM mutations.
- Heavy machinery; useful only if topology truly dominates the signal.

For your actual requirements — fuzzy match resilient to DOM/user/viewport/theme/filter drift, sub-100ms generation, 64–256 chars, replayable — I'd now lean toward **a hybrid of (3) and (4)**:

```
v1.s:Hash16.c:Hash16.x:Hash16.p:Hash16.lsh:b1b2b3b4b5b6b7b8
       ^32 chars axis keys             ^48 chars LSH bands
```

The four axis keys (structural / content / context / spatial) provide the orthogonal-stability property: theme drift breaks the spatial key but the others survive; PII strip nukes the content key but structural/context/spatial survive. Each axis key alone is a useful retrieval signal and gives you interpretable failure modes.

The LSH tail does fuzzy retrieval over the *combined* feature vector. It catches the long-tail similarity cases that hand-designed axis keys miss — exactly the "every last bit of entropy helps" property you mentioned. Two elements that aren't a perfect match on any single axis key might still share enough LSH bands because they're collectively similar across many weak features. The bands let the long tail vote without you having to design what each weak signal means.

Matching protocol:
1. Axis-key direct match → strong candidate, named axis tells you *why*.
2. LSH band overlap → ranked candidates with smooth similarity score.
3. Final score = weighted combination; confidence derived from total signal across both layers.
4. Return top-K plus a per-axis diagnostic ("matched on structure + context, lost spatial because viewport differs, 6/8 LSH bands → confidence 0.78").

About 110 chars compact, well under your ceiling. The expanded form is the full feature dict laid out per axis plus the unhashed vector — usable for debug, training signal, and audit.

On vector embeddings specifically: you don't need a *learned* model to get most of the value. Hand-crafted feature vectors with LSH bands already give you cosine-similarity-style retrieval semantics, no model dependency, no GPU. If later you collect differential-recording pairs and want to learn a projection, you can train a small one on top of the feature vectors with triplet loss without changing the artifact format — same dims, same bands, just better weighting. Clean upgrade path that doesn't lock you in now.

Where I was overfitting: I kept treating the ID as the place where fuzzy matching happens. Once you separate "compact handle / retrieval key" from "feature record / similarity computation," most of the design tensions evaporate. The compact form needs enough bits for LSH-style approximate matching and a few interpretable axis keys; precise scoring uses the expanded record. Both come from the same extraction pass, so generation cost doesn't double.

One honest caveat: LSH band design is itself a hand-tuned choice (which feature subsets per band, how many bands, what hash). It's a smaller and more localized tuning surface than per-segment weights, and the bands can be tested empirically against a corpus of (element, target) pairs once you have one — but it's not magic. The advantage is the tuning happens in one place (band construction) rather than scattered across many segment definitions, and it's the right shape for ML later.

---

## Nick

<!-- message 25; source_index=30; uuid=019e4bd7-929d-70d8-86f2-98fda2df7c3e; created_at=2026-05-21T18:41:19.952043Z -->

we want fuzzy-matching both within specific bands and across all the bands

e.g.

a span can change order within its parent, changing just 1 char in the xpath /some/div/span[1] -> /some/div/span[2], but it still matches the rest of the xpath

---

## Claude

<!-- message 26; source_index=31; uuid=019e4bd7-929d-7221-af2d-1adc0f49d52b; created_at=2026-05-21T18:43:22.912319Z -->

Right, naive LSH bands have exactly that failure mode — they're discrete bucket-equality, not within-band fuzzy. Single bit change in the input → totally different bucket. The fix is to make each band's output a *signature* rather than a single bucket, and compare signatures by distance.

Two primitives do the work:

**SimHash** for weighted-feature bands.
- Output: fixed-length bit string (64 or 128 bits).
- Comparison: Hamming distance via `popcount(a XOR b)`. Single CPU instruction.
- Property: Hamming distance approximates cosine distance of the underlying weighted feature vector. Small input change → few bits flipped.

**MinHash** for set-valued bands (tokens, n-grams, xpath segments).
- Output: K slots, each the min hash value across the set under one hash function. With 1-bit MinHash, just one bit per slot → K bits total.
- Comparison: fraction of matching slots ≈ Jaccard similarity.
- Property: two sets with high overlap share most slots; small set edits perturb few slots.

Worked through on your xpath example:

```
xpath_a = "/some/div/span[1]"
xpath_b = "/some/div/span[2]"
```

Character trigrams:
- a: `/so`, `som`, `ome`, `me/`, `e/d`, `/di`, `div`, `iv/`, `v/s`, `/sp`, `spa`, `pan`, `an[`, `n[1`, `[1]`
- b: same except `n[2`, `[2]` at the end

13/15 trigrams shared, Jaccard ≈ 0.87. Through 64-slot 1-bit MinHash, signatures share roughly 87% of bits → Hamming ≈ 8 out of 64. Within-band score for the structural axis: ~0.87. Strong fuzzy match despite the discrete index difference.

Compare to naive LSH where the whole xpath hashes to one bucket: changing `[1]` to `[2]` → totally different bucket value → 0 match. The signature approach preserves the locality directly.

Revised architecture:

```
v1.s:abc12345abc12345.c:def67890def67890.x:ghi13579ghi13579.p:jkl24680jkl24680
```

Each axis is a 64-bit signature (16 hex chars), using the hash family appropriate to that axis:

- **`s:` structural** — 1-bit MinHash over xpath trigrams + tag-stack tokens + role + anchor signature. Captures path similarity with locality.
- **`c:` content** — SimHash over weighted content trigrams (innerText + label). Already locality-preserving by construction.
- **`x:` context** — 1-bit MinHash over the set of stable ancestor signatures (data-testid values, ARIA landmarks, semantic tags up the tree). Set semantics — order doesn't matter, presence does.
- **`p:` spatial** — Morton-encoded (bit-interleaved) quantized coords + size class. Similar boxes → similar bits via space-filling-curve locality.

Total: ~80 hex chars, well under 256.

Comparison:

```ts
function score(a, b) {
  const axes = {s: 0.30, c: 0.30, x: 0.20, p: 0.20}
  let total = 0
  for (const [axis, weight] of Object.entries(axes)) {
    const hamming = popcount(a[axis] ^ b[axis])
    const sim = 1 - hamming / 64   // within-axis fuzzy
    total += weight * sim
  }
  return total                       // across-axis fuzzy
}
```

Both properties for free in one operation:

- **Within-band fuzzy**: Hamming on signature ≈ similarity of underlying features. xpath index drift, text-typo drift, small bbox drift — all map to small Hamming, not total miss.
- **Across-band fuzzy**: weighted sum across axes. One axis broken by environment drift → contribution drops smoothly, others carry. Theme change kills spatial → 0.2 × low; structure/content/context still contribute → overall score stays high.

The viewport-aware weighting from before slots in naturally: detect recording viewport ≠ replay viewport, downweight the spatial axis at match time. The signature itself doesn't change; just its contribution to the score does. Same for filter-config differences, theme differences, etc. — the failure mode determines which axis contribution to discount, never which signature to recompute.

Practical notes:

1. **Per-axis hash family is the actual design decision.** Once you commit to "every band is a fixed-length signature compared by Hamming," the rest is picking the right family per axis (MinHash for sets, SimHash for weighted vectors, Morton for spatial). Each is well-understood with library support.

2. **64 bits per axis is the sweet spot.** 32 is too coarse for reliable Jaccard estimation (high variance); 128 is overkill at this scale. Need more discrimination → add more axes rather than widening existing ones.

3. **Build-side cost.** MinHash over ~15 trigrams with 64 hash functions ≈ 15μs per element. SimHash over ~100 features ≈ 5-10μs. 2000 elements × all axes: 20–50ms total. Fits the budget.

4. **Lookup against a corpus.** Index by 8-bit prefix of each signature (256 buckets per axis) → brute-force comparison drops from O(n) to ~O(n/256) per axis with ~95% recall. Hamming-radius indices (e.g., multi-index hashing) if you scale further.

5. **Expanded form unchanged**: full per-axis feature dicts, useful for debug and for training a learned projection later if you ever want one. The signatures don't lock you out of upgrading.

This is the architecture used by classic near-duplicate detection systems (Google's original web-dedup paper used SimHash exactly this way), file fuzzy-hashing tools (ssdeep, sdhash), and most pre-LLM semantic-search backbones. Well-trodden ground for "fuzzy match short hashes" specifically — the new thing here is just applying it per-axis with axis-appropriate hash families rather than collapsing everything into one feature soup, which gives you the interpretable failure modes you wanted from multi-key while still getting smooth within-axis similarity.

---

## Nick

<!-- message 27; source_index=32; uuid=019e4bed-f085-7dc0-b8d2-1491d8c658e9; created_at=2026-05-21T19:05:45.820873Z -->

ok so assume matching viewports, can this work for selecting pins on a canvas-based google map element?

all buckets will likely fail except the coordinate based ones, thats ok, as long as those still work (assuming same viewport)

---

## Claude

<!-- message 28; source_index=33; uuid=019e4bed-f085-7ea6-9d9f-df8b5d70bdef; created_at=2026-05-21T19:05:52.306913Z -->

> **Note:** Claude’s response was interrupted.

---

## Nick

<!-- message 29; source_index=34; uuid=019e4bee-2725-7488-b787-9cc5ff1b1099; created_at=2026-05-21T19:05:59.794601Z -->

or google sheets / google docs are canvas based too

---

## Claude

<!-- message 30; source_index=35; uuid=019e4bee-2725-7a0e-98d7-bc99a5c73d3a; created_at=2026-05-21T19:07:47.101148Z -->

Coordinate-only works when both viewport AND app state are stable — not just viewport. That distinction matters because "same viewport" is much weaker than what canvas apps actually need.

For a Google Maps pin specifically:
- Same viewport ✓
- Same map center, zoom, pan, tilt, map type ← also required
- Same selected layers / overlays ← also required

User panned the map 50px between recording and replay → every pin moves → coordinate-only fingerprint matches the wrong thing. The practical constraint is "same rendered scene," not "same viewport."

For Sheets/Docs the equivalent is "same scroll position + same column widths + same zoom + same file revision." Each of those moves the pixel where a given cell lives.

So if app state is genuinely stable, yes — the Morton-encoded spatial signature alone disambiguates 2D positions. That's the easy part. The hard part is guaranteeing app state stability across sessions, which is mostly outside your control.

**The thing worth knowing about Google's canvas apps:**

They aren't actually pure canvas from an accessibility perspective. Maps, Sheets, and Docs all maintain parallel **accessibility shadow layers** — real elements (or virtual a11y nodes) that exist for screen reader compatibility, visually hidden but queryable. These resurrect the structural and content bands:

- **Google Maps**: major pins/landmarks expose `<div role="button" aria-label="Pin name, address">` overlay elements at the canvas-painted positions. The a11y tree is the API for screen readers and it's queryable. (Custom user-added pins may or may not, depending on how the app builds them.)
- **Google Sheets**: hidden focusable input holds the current cell's text + address; cell navigation updates `aria-activedescendant` referencing virtual cell nodes with `aria-rowindex` / `aria-colindex`. The whole grid is virtual but addressable.
- **Google Docs**: parallel hidden DOM mirrors the canvas-rendered text (the `kix-` classes). The actual text lives in the DOM — just invisibly.

If you walk the accessibility tree, not just `document.body`, your structural/content/context bands light up on these apps. "Pin in Google Maps" becomes a node with `aria-label="Coffee shop, 123 Main St"` and the existing scheme works unchanged. Stagehand using CDP already has access to `Accessibility.getFullAXTree` — that's the right primitive here, more than the rendered DOM.

The `getDomSnapshot` API should probably default to a11y-augmented mode by default: walk both the rendered DOM and the accessibility tree, merge them, fingerprint the union. Most "canvas-based" apps fall back into the structural fingerprinting regime once you do this. The expanded form notes the source ("a11y-shadow" vs "dom") so confidence calculations and debugging account for it.

**Where coordinate-only is genuinely the only signal:**

Custom WebGL apps, games, scientific visualizations, some bespoke data viz, browser canvas demos. Anything where the developer didn't build an accessibility layer. For these:

- Spatial signature alone works for same-state replay.
- For different state, you need a vision modality — screenshot patch around the target, embed it (perceptual hash like pHash/dHash for cheap, or a learned visual embedding if you have GPU budget), match by image similarity.
- Cheap option: 64-bit perceptual hash of a ~64×64px patch centered on the target. Same comparison protocol — Hamming distance, fits the same 64-bit-per-axis budget.
- Expensive option: small vision encoder (MobileViT, tiny CLIP variant) producing a 128-dim embedding. Higher quality, ~10-50ms per patch.

The fingerprint format stays uniform: some axes filled in, others empty or set to a coordinate-only proxy or a visual-patch hash. Matching engine down-weights empty/uncertain axes. Format invariant across DOM, a11y-augmented canvas, and pure-canvas — only the signal density varies.

**For Stagehand:**

The architectural payoff is automatic graceful degradation: "prefer rendered DOM, fall back to accessibility tree, fall back to visual patch hash." Picks the most semantic available primitive without the caller thinking about it. Same fingerprint scheme handles all three. The expanded form annotates which layer each axis came from, so when a fingerprint replay fails, you can see "spatial matched but visual-patch hash drifted — app state changed" vs "a11y label matches but structure shifted — site refactored."

This is also where the "better primitives than Playwright" framing pays off concretely. Playwright treats canvas apps as opaque pixel rectangles and largely gives up. A primitive that automatically reaches for the accessibility shadow first works on all of Google's canvas apps — Maps, Sheets, Docs — without the user thinking about it, and falls through to vision only when there's truly no other signal. That's a real surface area win that's hard to argue against in your VP meeting because the user-visible behavior is "automation that just works on Sheets" vs "automation that doesn't."

---

## Nick

<!-- message 31; source_index=36; uuid=019e4bf0-9b7c-78c4-9d4e-071a3095362a; created_at=2026-05-21T19:08:40.562874Z -->

assume they dont contain a11y shadow elements, because we want this to work for less enterprise/hardened apps that have worse accessibility

---

## Claude

<!-- message 32; source_index=37; uuid=019e4bf0-9b7c-7dab-9e2d-54eb542995a5; created_at=2026-05-21T19:08:45.356981Z -->

> **Note:** Claude’s response was interrupted.

---

## Nick

<!-- message 33; source_index=38; uuid=019e4bf1-7b30-7015-843d-3e92bf5536a6; created_at=2026-05-21T19:09:37.983713Z -->

we can replicate app state by loading the same initial url, resetting to a known state through recording and replaying actions, and then replay up to a given point + assert things look as expected. the issue is replaying from that point forward in a best-effort stable fashion with coordinates when only coordinates are available

---

## Claude

<!-- message 34; source_index=39; uuid=019e4bf1-7b30-747a-98b5-5a069376cb97; created_at=2026-05-21T19:11:34.509100Z -->

Yes, this is workable. If app state really is replayable to a known visual state, the remaining drift sources are narrower than they look: sub-pixel positioning, font rendering, animation timing, GPU vs software rasterization, devicePixelRatio differences. None of these typically move things more than a few pixels. The architecture that survives that:

**1. Stability wait before each canvas click.**
Hash the canvas pixels (cheap hash of `getImageData`, or downsampled). Wait until consecutive frames are pixel-stable for ~3 frames / ~50ms. Kills animation races and async-content-loading races without you having to know what's loading. ~1ms per frame check.

**2. Small visual patch hash at the click target.**
At record time, extract a 64×64 patch centered on the click point and store its perceptual hash. At replay, the spatial axis becomes:

```
p:[x16:y16:phash64]
```

~16 hex chars for x:y, 16 for the pHash, ~32 hex total. Combined with the canvas element's own DOM-level fingerprint (which works normally — its tag, position in document, surrounding chrome), the full canvas-click fingerprint lands around 60 chars.

**3. Bounded local search at replay.**
Search a small window (~±20px) around the recorded coordinate. For each candidate offset, hash that patch and compare Hamming to the stored pHash. Best match within threshold → click; no match → fail and surface.

Brute force pHash over a 41×41 window is ~1700 patches × 1-2ms = too slow. Better:
- Coarse stride first (every 8px), then refine around the best coarse match with fine stride.
- Or precompute the canvas's full pHash grid once per stable frame and look up offsets in O(1).
- Or FFT-based normalized cross-correlation — gives sub-pixel accuracy for a few ms on a small search window. Well-understood with library support.

Per-click cost lands ~20–50ms with these. Slower than DOM clicking, but it's one click per action, not 2000.

**4. Use dHash, not pHash, for theme-tolerance.**
pHash is brightness-sensitive; dark mode can flip enough DCT coefficients to break matches. dHash is gradient-based — it captures relative-brightness patterns that survive theme inversion. For same-theme replay (your case) it matters less, but it's a cheap robustness win and the storage cost is identical.

**5. Multi-anchor offset for bigger drift.**
If patch alone isn't enough (e.g., maps that re-render slightly differently each load), record the click target as offset from a more distinctive nearby visual landmark — a high-contrast logo, a UI corner, a distinctive icon. Locate the landmark on replay via patch match (cheap because it's chosen for distinctiveness), apply the recorded offset. Robust to global rendering jitter that affects every pixel equally.

The complete canvas-click fingerprint:

| Axis | Content |
|---|---|
| `s:` structural | empty for canvas-internal targets |
| `c:` content | empty |
| `x:` context | canvas element's own fingerprint (tag, ancestor data-testid, position in app chrome) — normal DOM signals |
| `p:` spatial | `x:y:phash64` (or with anchor offset: `ax:ay:apxh:dx:dy:phash64`) |

Matching: `s:` and `c:` contribute zero weight (empty signatures skipped), `x:` confirms you're on the right canvas, `p:` does the actual targeting. Format stays uniform across DOM and canvas; only signal density per axis differs. The matching engine doesn't branch — it just sums weighted Hamming across whichever axes have signal.

**Honest failure modes:**

- Drift larger than the search window → fails. Mitigation: widen search window adaptively if initial match score is borderline; cap to avoid runaway cost.
- Map zoom or scroll changed between record and replay → patches look different → no match. Mitigation: verify scene-level stability cheaply by comparing a full-canvas dHash against the recorded scene hash *before* trusting any individual patch match. If scene hash diverges significantly, fail loudly rather than click the wrong thing.
- Pixel-art-style canvas with very repetitive visuals (uniform grids, identical icons) → multiple equally-good patch matches → ambiguous. Mitigation: at record time, score the patch's local uniqueness (compare its hash to neighboring patches' hashes) and warn if it's low. Switch to a larger patch or multi-anchor offset in that case.
- True animation that can't be quieted (a constantly-spinning loader, a video) → frame stability check never settles. Mitigation: timeout + median-frame extraction; treat as "best-effort, lower confidence" and surface.

The deeper architectural point: for canvas without a11y, you can't fingerprint the *target element* (there isn't one), you can only fingerprint the *visual signature of where the click should go*. That changes the semantics — "stable id" becomes "stable visual pointer" — but the fingerprint format and matching algebra stay the same. The expanded form should make this distinction explicit (`source: canvas-pixel-region` vs `source: dom` vs `source: a11y-shadow`) so both the matching engine and the human reading the log know that confidence is bounded by visual stability rather than DOM stability. Same scheme, three different stability regimes, one matching protocol.

One thing worth being explicit about for the VP-meeting angle: this isn't a parallel codepath to "real" element identification — it's the same scheme degraded gracefully. The pitch is "our primitive handles canvas apps natively because the fingerprint format absorbs visual signals as just another axis." That's a clean story; "we have a separate canvas mode" is a worse one to defend in scope discussions.

---

## Nick

<!-- message 35; source_index=40; uuid=019e4bf5-9a82-77ff-8bc1-14d0a88eee2e; created_at=2026-05-21T19:14:08.052523Z -->

how does reverse image search work? could we efficiently implement fuzzy semantic image hashing in-browser like apple does with ios photos / google with their reverse image photo search

---

## Claude

<!-- message 36; source_index=41; uuid=019e4bf5-9a82-7415-a45a-ba626728819a; created_at=2026-05-21T19:16:19.574565Z -->

How it actually works under the hood, then in-browser feasibility.

**The pipeline (both Apple and Google):**

1. **Image encoder**: a vision model produces a fixed-length embedding (256–2048 dims). Either a classification model where the penultimate layer is the embedding, or a contrastive model (CLIP, SimCLR, DINO) where the embedding is the explicit output.
2. **Embedding storage**: vectors quantized (int8, or product-quantized into much smaller codes) and indexed.
3. **Approximate nearest neighbor (ANN) index**: HNSW (graph-based, fast and accurate, large memory), IVF (clustering + inverted file), PQ (product quantization for memory), or combinations like IVFPQ for billion-scale.
4. **Query**: encode → ANN lookup → top-K → optional rerank with full-precision cosine or cross-attention.
5. **Metadata join**: return URLs, captions, timestamps.

The interesting engineering at scale is mostly the ANN — getting from "cosine against billions of vectors" (computationally hopeless in <100ms) to "traverse a small-world graph visiting ~1000 candidates" (very feasible). HNSW is the dominant technique outside Google's internal infrastructure.

**Apple's on-device approach specifically:**

- Small proprietary vision encoder (MobileCLIP-style, ~10-30M params); ~5ms per image on Neural Engine
- Separate face-specific embedding (~128 dims, FaceNet-style)
- OCR via Vision framework, real-time on-device
- Scene classification against a fixed taxonomy (~1000 classes)
- Photo Memories joins visual embeddings with EXIF, location, face clusters, calendar
- Visual Look Up extracts features client-side and sends *features only* to the server for landmark/plant/animal recognition

The architectural choice that matters: everything semantic runs locally, so latency stays sub-100ms and privacy stays intact.

**Google's at-scale approach:** server-side, much larger models, distributed index. Models around BiT, CLIP, and larger internal ones. Reverse image search end-to-end: encode (~30ms) + ANN lookup (~50ms) + rerank + metadata fetch = 200–500ms total. Billions of vectors fit only with aggressive PQ compression.

**In-browser feasibility, 2026:**

Genuinely feasible now. Key enablers:

1. **WebGPU** (broadly available in Chrome/Edge/Safari 17+) gives 10–100× speedup over WASM for matrix math. Without it, semantic encoding is seconds; with it, tens of ms.
2. **ONNX Runtime Web** with WebGPU backend, and **transformers.js** (Xenova's HF port), both run vision models in-browser with WebGPU.
3. **OPFS** for persistent embedding storage keyed by content hash.

Per-image latency on WebGPU:

| Step | Time |
|---|---|
| Extract from canvas (`getImageData` / `OffscreenCanvas`) | 1–5ms |
| Resize + normalize to model input | 1–3ms |
| Encoder inference (MobileCLIP visual, ~10M params, INT8) | 10–30ms |
| L2-normalize, optional INT8 quantize | <1ms |
| LSH band computation | <1ms |
| Persist to OPFS / write to in-memory index | 1–2ms |
| **Total** | **~15–40ms** |

Query against an index of 10k images: ~5MB of int8 embeddings, ~640KB of LSH bands, fits trivially in memory or OPFS. Encode query (15–30ms) + LSH band lookup (<5ms) + cosine refine top-K (<5ms) = ~20–40ms end-to-end.

**Models worth considering:**

- **MobileCLIP** (Apple, 2023 — open weights). Visual encoder ~10M params, fast, strong semantic similarity. Best default.
- **DINOv2-small** (Meta, 2023). 21M params, no text alignment. Excellent image-to-image embeddings.
- **EfficientNet-Lite** for pure classification-quality embeddings; fastest, weakest semantics.
- **CLIP ViT-B/32** is the textbook standard but 87M params is painful in-browser; distilled Xenova variants with INT8 are ~30–40MB and run in 30–50ms on WebGPU.

**How this relates to the canvas problem:**

pHash/dHash from before is the fastest, weakest version of this — perceptual hashing without learned semantics. Catches near-pixel-duplicates, semantically blind. "Coffee shop pin" vs "gas station pin" can look similar at the pixel level and pHash treats them as identical.

Adding semantic embeddings as a secondary signal lets you:
- Match the same conceptual icon at different zoom levels (pHash fails, semantic survives)
- Survive theme changes more robustly (visual embeddings are more lighting-invariant)
- Identify "this kind of UI element" rather than "this exact pixel pattern"

The fingerprint format absorbs this naturally — the `p:` (or a new `vis:`) axis becomes `phash64:sem128` (concatenation of fast perceptual + quantized semantic). Match cost goes from ~1ms (pHash only) to ~30ms (with semantic), but the fallback chain is graceful: pHash first, semantic only if pHash is ambiguous or you've detected drift larger than pHash can absorb.

**Honest limitations:**

- The encoder is a coupling point — version bumps invalidate all stored embeddings. Pin model + version in the `v` prefix; lazy re-embed on miss.
- 30ms × 2000 elements = 60s for full-DOM semantic embedding. Not feasible. Only embed *candidate* elements that need it: canvas-internal targets, ambiguous DOM targets after structural matching fails. Reserve the semantic encoder for the long-tail recovery path, not the hot path.
- WebGPU unavailable → fall back to WASM (often 10× slower, mostly unworkable) or skip the semantic axis. Feature-detect and degrade.
- The encoder runs on canvas pixel data, so it sees what the user sees — including PII rendered in the canvas. Whether the embedding leaks PII depends on the model; for safe handling, run encoder locally, never transmit embeddings of canvas regions that contain user content (only persist them in OPFS scoped per-user-per-site).

**The actual architectural pitch:**

You're not building reverse image search. You're using its primitives — small visual encoders, ANN, LSH bands — for the narrower problem of stable replay across visual drift. The expensive parts of Google-scale reverse image search (planet-scale ANN, billions of vectors, massive index infra) don't apply. The cheap parts (one small encoder, thousands of cached embeddings in OPFS, in-browser cosine over a candidate set) absolutely do, and they slot into the existing fingerprint scheme as a `sem:` segment on the visual axis. Same matching algebra (Hamming on LSH bands, cosine on quantized embeddings), no new infrastructure beyond a ~20MB model file shipped with the SEA binary or fetched once and cached. That story holds together in a scope discussion: it's not a separate "AI mode," it's the same fingerprint format with one more axis populated when DOM/a11y signals are absent.

---

## Nick

<!-- message 37; source_index=42; uuid=019e4bfa-2dd1-7e95-a0c7-3ad1df66033b; created_at=2026-05-21T19:19:07.939260Z -->

coul we do this for ~300 elements on a page on initial pageload within 200ms?

---

## Claude

<!-- message 38; source_index=43; uuid=019e4bfa-2dd1-77e5-9341-a1b10e7d1c11; created_at=2026-05-21T19:20:56.011071Z -->

Honest answer: no, not at the full learned-semantic level. The math doesn't work out.

Per-element semantic embedding on WebGPU with MobileCLIP-class models (~10M params): 10–30ms single, ~100–500 imgs/sec batched on modern hardware. For 300 elements in 200ms you'd need ~1500 imgs/sec — 3–15× faster than current in-browser inference delivers. Best consumer hardware today lands at 500–1000ms for full-page semantic embedding.

But the strict version isn't what you actually want. Most DOM elements have strong structural/content signals; spending 30ms semantically embedding a `<span>` whose innerText is already in the fingerprint is wasted budget. The version that fits in 200ms is tiered:

**Tier 1: Cheap perceptual fingerprints for all 300 elements (~50–100ms)**
- pHash + dHash + wHash, 64 bits each
- Color histogram (16-bin RGB), 48 bits
- HOG-lite edge orientation, 32 bits
- ~0.5ms per element on CPU, fully parallelizable with DOM walk
- Catches pixel/perceptual similarity, not semantics

**Tier 2: Tiny ConvNet embedding for medium-value subset (~50–100ms for ~50 elements)**
- 1–2M param model (LeViT-128S, EfficientNet-Lite0, distilled MobileCLIP)
- ~2–5ms per element batched on WebGPU
- Coarse semantic signal ("button-like," "logo-shaped," "icon-class")

**Tier 3: Full semantic embedding for canvas regions + high-value targets (~50–100ms for 5–20 elements)**
- MobileCLIP or DINOv2-small
- 10–20ms per element batched
- Reserved for cases where structural/content/context bands are empty or low-confidence

Triage runs on the main thread during the DOM walk and decides each element's tier:
- DOM structure + content available → tier 1 only (structural already disambiguates)
- Icon-like (`<img>`, `<svg>`, button-with-no-text, sprite background) → tier 2
- Inside canvas without a11y, or structural fingerprint score below threshold → tier 3

Wallclock budget within 200ms:

| Stream | Time |
|---|---|
| Main thread: DOM walk + tier-1 hashes for all 300 | ~50–100ms |
| Worker thread: batched tier-2 inference on ~50 elements | ~100–150ms |
| Worker thread: batched tier-3 inference on ~5–20 elements | ~50–100ms |
| Assembly + LSH bands | ~20–30ms |
| **Wallclock with pipelining** | **~150–200ms** |

What makes this fit where naive doesn't:

1. **Triage by structural confidence.** You only spend semantic cost on elements where structural fingerprinting is weak — typically 5–20% of a page.
2. **Batched GPU inference.** 50 images in one inference call is dramatically faster than 50 sequential calls. ONNX Runtime Web and transformers.js both support batch dimensions transparently.
3. **Pipelined CPU and GPU.** Main thread computes perceptual hashes for cheap-tier elements while the worker is mid-inference on the expensive tiers. Two streams hitting different hardware concurrently.
4. **OPFS embedding cache.** Same visual content → same embedding. Hash image bytes first; only re-embed on miss. Revisit hit rate is usually very high.

What you trade away:

- The 250+ elements that get tier-1 only have no semantic robustness — a UI redesign that changes pixel appearance but keeps semantic identity breaks their visual axis. Structural axes still carry; overall fingerprint survives; you just lose the "find the same conceptual element after visual redesign" property for tier-1 elements. The elements that needed tier 3 (canvas regions) keep it.
- Model load is a one-time cost outside this budget: ~30–50MB of weights, 1–5s cold on first visit, served from HTTP cache + WebGPU pipeline cache after. The 200ms is the warm budget; first-ever-pageload is network-bound and you should be honest about that in the SLO.
- WebGPU unavailable (older browsers, headless without GPU) → tier 2/3 unusable within budget. Fall back to tier 1 only; semantic axis empty for those elements. The matching engine downweights empty axes, so the scheme degrades gracefully rather than failing.

**The feasibility answer:**

Yes for the tiered approach that covers actual use cases — tier 1 for everyone, tier 2/3 only where needed. No for full uniform semantic embedding of all 300 elements; that's a 2027–2028 problem when WebNN matures and on-device NPU access exposes to browsers. For now, intelligent triage gets you 95% of the value at <25% of the compute, and the triage logic is the actual interesting engineering — not the model choice.

One thing worth verifying empirically before committing: what fraction of *real* user-visible page elements actually need tier 2/3 on the sites Stagehand targets? If it's <5% (most B2B SaaS, most consumer apps with reasonable HTML structure), the budget has comfortable headroom. If it's >20% (heavy canvas apps, design tools, games), the budget is genuinely tight and you'd want to expose latency configuration to callers. Worth measuring before this becomes an architectural commitment that's hard to walk back.

---

## Nick

<!-- message 39; source_index=44; uuid=019e4bfd-f429-7e99-8379-050db11218c0; created_at=2026-05-21T19:23:15.266772Z -->

unfortunately we cant do webgpu, our machines have only cpu. also the whole point of this excersize is to try and avoid llm / vision model calls needed, we already have CUA models hooked up to the browser, but we're trying to cache element ids and selector maps to *avoid* needing CUA work

---

## Claude

<!-- message 40; source_index=45; uuid=019e4bfd-f429-78c7-afcc-1bf186ae8c47; created_at=2026-05-21T19:24:59.908445Z -->

That changes the design substantially. Two implications:

1. **No WebGPU** kills tier 2 and tier 3 from the last proposal — neural vision encoders aren't viable in WASM SIMD at the latency you need. Even tiny models are 10–50× slower without GPU.

2. **Caching to avoid CUA** reframes the whole purpose: the fingerprint isn't trying to be "as good as a vision model," it's trying to be "good enough that CUA doesn't have to be re-invoked." Different success criterion — measured in cache hit rate, not match quality.

Under these constraints, the canvas/image branch becomes purely classical CV. The architectural shape:

**Classical visual features (CPU-only, sub-5ms per patch):**

- pHash (8×8 DCT, 64 bits): ~0.5–2ms with WASM SIMD
- dHash (gradient-based, 64 bits): ~0.3–1ms — more theme-robust than pHash
- 3×3 spatial color grid (RGB means per cell, 27 bytes): ~0.3ms
- HOG-lite (8 orientation bins, edge density, 32 bits): ~1–2ms
- Optional: Local Binary Patterns for texture (~1ms, useful for icon-like elements)

Per canvas/image patch: ~3–5ms on CPU. For a typical page where 5–20 elements actually need pixel features: 15–100ms. The other ~280 DOM elements get structural/content/context fingerprints only, no pixel work needed. Total fingerprint for the page: ~100–200ms. Fits.

**What classical CV gives you, and what it doesn't:**

Strong cache-hit signals:
- Same exact rendered content (the common case for stable-state replay): near-perfect match
- Small spatial drift (sub-pixel, anti-aliasing, font rendering): pHash + dHash Hamming distances stay small
- Same icon at same zoom level, light variations: color grid + HOG still match

Cache misses where CUA must re-resolve:
- Theme changes (dark ↔ light): both pHash and color signal flip significantly; dHash survives better but isn't enough alone
- Zoom changes / different canvas-render scale: HOG scrambles
- Localization (text rendered in different language inside canvas): pixel features change wholesale
- Site redesigns: full miss, expected

The honest framing: this isn't "fingerprints replace CUA," it's "fingerprints handle the 80–90% of cases where the page looks the same as last time; CUA handles the 10–20% drift." Hit rate is the metric, not match precision.

**Cache architecture aligned with the CUA-skip purpose:**

```
CUA finds element first time → record fingerprint (all axes recording sees)
                                        ↓
                              store in OPFS keyed by (url, action_context)
                                        ↓
                              replay queries cache before invoking CUA
                                        ↓
        if best candidate score ≥ HIT_THRESHOLD → click, skip CUA
        if score in [CONFIRM, HIT) → click, also invoke CUA in parallel to verify
        if score < CONFIRM → invoke CUA, update cache with new fingerprint
```

The two-threshold scheme is the key piece. HIT means "trust the cache." CONFIRM means "trust the cache but run CUA in background to verify." CONFIRM gives you the learning signal: when CUA disagrees with the cache, lower confidence on that fingerprint or invalidate it. Over time the cache self-calibrates per site without you having to design heuristics for every drift mode.

**Hit-rate expectations to set with the VP:**

For typical SaaS sites with stable DOM and stable canvas rendering:
- DOM-element actions: cache hit rate likely 90–98% (structural fingerprints are very stable)
- Canvas-region actions: 70–90% depending on visual drift (theme, zoom, animations)
- After a site redesign or theme update: drops to ~50% temporarily, recovers as CUA re-caches

That's the value proposition: roughly an order-of-magnitude reduction in CUA calls on stable repeat workflows, with graceful degradation when things change. Concrete cost calculation: if a flow has 20 actions and each CUA call is $X, and you go from 100% CUA invocation to 10% via cache, the per-flow cost drops 10×. That's the number for the VP meeting — directly tied to gross margins, easy to defend in scope discussions, and the failure mode is "we just run CUA more often," which is the existing behavior, not a regression.

**What this gives up vs the semantic embedding plan:**

The big loss is "semantically equivalent but visually redesigned." Classical CV catches pixel-similar matches; it doesn't catch "the new coffee shop pin icon that doesn't look like the old one but plays the same role." Those trigger cache miss → CUA invocation. Acceptable — the cache is an optimization layer, not a correctness layer. CUA is still the ground truth; the cache just makes it 10× cheaper on the common path.

**One thing worth measuring before committing:**

For the canvas-heavy sites in your target set, how deterministic is their canvas rendering across runs? If pHash Hamming distance across "identical" renders is consistently <5, the cache is in great shape. If it varies 10–20 even on intended-identical renders (some apps have stochastic anti-aliasing, GPU-vs-software differences, frame-timing artifacts), you'll need broader Hamming thresholds and the cache gets noisier. Worth a half-day instrumentation pass before architecting around tight thresholds — measure the rendering variance distribution on real targets and let that set your HIT/CONFIRM cutoffs empirically rather than picking numbers a priori.

---

## Nick

<!-- message 41; source_index=46; uuid=019e4c01-df30-74a3-bdad-74d756d0f2a9; created_at=2026-05-21T19:27:32.175169Z -->

unfortunately slight rendering differences are real, e.g. buttons may be ~2-3px off in posiition, aliasing is often different, light/dark mode can change colors while keeping shapes and content similar, etc

---

## Claude

<!-- message 42; source_index=47; uuid=019e4c01-df30-7163-aeee-f8b9c7feaca6; created_at=2026-05-21T19:29:50.401807Z -->

These are the right drifts to design against. Fix is not "one robust hash" but a small bundle of features each robust to a different drift, plus a few cheap tricks that absorb common variation for free.

Per-drift robustness of the classical CV families:

| Drift | pHash | dHash | HOG | Edge density | Color grid |
|---|---|---|---|---|---|
| 2–3px shift | small Hamming | small Hamming | robust after cell pooling | robust | robust if grid is coarse |
| Aliasing | robust (DCT low-pass) | robust | robust (gradient pool) | robust | robust |
| Light/dark inversion | bits flip | bits flip | unsigned orientations preserved | preserved | inverts |
| Zoom / DPR change | breaks | breaks | breaks | preserved if normalized | OK if global |

No single feature handles all of these. Composite that does:

**Theme-invariant features (carry the load on dark/light mode):**
- **HOG-lite on grayscale** — 8 unsigned orientation bins × 8 spatial cells = 64 bits. Unsigned orientations are invariant to brightness inversion. ~1–2ms per patch.
- **Edge density per quadrant** — 4 quadrants × 8 bits = 32 bits. Pixel-difference magnitudes are absolute, so theme-invariant. <0.5ms.

**Brightness-pattern features (sensitive to theme, useful when theme matches):**
- **Grayscale pHash and dHash** — 64 bits each. Combined with the inversion trick below, theme-invariant in practice.
- **3×3 spatial color grid** — RGB means, 48 bits. Genuinely theme-sensitive; weighted accordingly.

Total per patch: ~3ms CPU.

**The free-theme-inversion trick:**

For any bit-vector feature, theme inversion ≈ bitwise complement of the feature. At match time, compute both:

```
score = min(hamming(a, b), hamming(a, ~b))
```

If the patch was inverted (light → dark), `hamming(a, ~b)` is small while `hamming(a, b)` is large. Taking the min handles inversion transparently with zero added cost. This gives free theme-robustness to pHash, dHash, and color features without you having to detect theme explicitly.

Caveat: false-positive rate increases marginally because you accept "matches under inversion" too. In practice this is dominated by the right signal — real inversions are common, accidental complement-matches are rare.

**The bounded search window for position drift:**

At replay time, compute the visual axis at the recorded coordinate and at a small grid of offsets (±4px in each direction = 81 positions for a 9×9 grid, or ±2px = 25 positions for a 5×5). Take the best-scoring offset. Compute cost: 25–81 × 3ms = 75–250ms per cached click lookup. Only paid on the replay-side cache check for one element, not in the page-wide fingerprint budget.

This window also incidentally absorbs small layout drift from font-metric variation, padding rounding, scrollbar presence, etc. — drifts that look like "position shift" from the matcher's perspective.

**For aliasing specifically:**

Mostly handled implicitly. pHash applies DCT (low-pass), HOG averages gradients over cells, edge counts integrate over quadrants. All smoothing operators that destroy aliasing-scale variation by construction.

Cheap extra insurance: apply a 3×3 Gaussian blur (σ=1) to the patch before feature extraction. ~0.3ms, removes residual aliasing noise. Worth doing.

**The composite match formula:**

```ts
const scoreVisual = (a, b) => {
  const hog   = 1 - minHam(a.hog,   b.hog)   / 64
  const edge  = 1 - minHam(a.edge,  b.edge)  / 32
  const phash = 1 - minHam(a.phash, b.phash) / 64
  const dhash = 1 - minHam(a.dhash, b.dhash) / 64
  const color = 1 - chiSquaredDist(a.color, b.color)
  // weights: theme-invariant features get more weight
  return 0.30*hog + 0.20*edge + 0.20*phash + 0.20*dhash + 0.10*color
}
```

Where `minHam(x, y) = min(popcount(x ^ y), popcount(x ^ ~y))`.

**Realistic match scores under each drift:**

- Same browser, same theme, same render: visual score ~0.95–1.0
- 2–3px shift only: ~0.90–0.98 (search window finds the right offset)
- Aliasing differences: ~0.92–0.98
- Light↔dark inversion (clean): ~0.75–0.90 (HOG+edge carry, complement trick gives back pHash/dHash, color drops out)
- Partial theme shift (light gray ↔ medium gray): ~0.65–0.85 (messier, complement trick less precise)
- Different zoom / DPR: ~0.30–0.60 → cache miss → CUA fallback
- Major redesign (different shapes): ~0.20–0.50 → cache miss

Combined with structural / content / context fingerprint axes contributing, the total fingerprint score stays in HIT territory for the first three drifts and most of the theme-shift cases. Zoom and redesign genuinely need CUA — accept that and design the fallback path to be smooth rather than try to engineer past it with classical CV.

**Worth empirically measuring before committing to thresholds:**

Take 5 real Stagehand target sites, record the same canvas action 10× across (same Chrome run, fresh Chrome run, different Chrome version, light theme, dark theme, before/after a known minor UI change). Compute per-feature Hamming distance distributions. The empirical histograms tell you:

- What HIT threshold makes sense (e.g., if real-match distances cluster around 5–15 and false-match around 30+, threshold at 22)
- Which features actually carry signal on your specific corpus (some sites might have HOG so noisy it doesn't help; some might have rock-solid pHash)
- Which drift modes are common enough to design against vs accept as CUA-fallback cases
- Whether the complement trick fires often enough to be worth the slight FPR cost (count how often `hamming(a, ~b) < hamming(a, b)` across pairs)

That half-day measurement pass is the difference between "we picked thresholds that sound reasonable" and "we picked thresholds that actually maximize cache hit rate on the workloads we care about." The first is theater; the second is what gets you a real 10× CUA-call reduction to bring to the VP.

---

## Nick

<!-- message 43; source_index=48; uuid=019e4c0a-38c9-763d-8635-68edb528fc16; created_at=2026-05-21T19:36:39.272457Z -->

but what if an element is visually the same and semantically the same, but it moves 25px down because a banner is sometimes shown above it. dont we run into offset issues? isn't it too expensive to do sliding window patshets for every possible offset?

---

## Claude

<!-- message 44; source_index=49; uuid=019e4c0a-38c9-78a0-9c17-74a4ae93a800; created_at=2026-05-21T19:38:15.034778Z -->

Right — brute force sliding doesn't scale. ±100px alone is 40,000 candidate positions per element; even at 8px stride that's 625 positions × 3ms = 1.8s per cached click. Untenable.

The fix isn't expanding the window. It's changing the coordinate frame so banner shifts don't show up as shifts in the first place.

**Primary fix: anchor-relative coordinates**

For canvas-internal clicks, record:
- The canvas's own DOM-level bounding box (this is what shifts when a banner appears above)
- The click point as offset *within the canvas content*: `(click_x − canvas.left, click_y − canvas.top)`

At replay, read the canvas's current bbox, click at `canvas.top_left + recorded_offset`. The 25px banner shift moves the canvas; the click target moves with it; the offset in canvas-internal coordinates is unchanged. Cost: ~0ms.

This generalizes to non-canvas DOM elements: express click position as offset from the nearest stable DOM ancestor (the form, the section, the modal). When chrome above shifts, the ancestor moves; the offset relative to it stays fixed. The fingerprint already carries `pid:` (nearest stable parent) as an axis — bbox-relative-to-pid is essentially free to compute from that.

The visual patch hash you stored at record time is computed at the anchor-relative position too — you don't search globally for it. Compute it at the anchor-relative position on replay, verify by Hamming distance. The ±4–8px search window still handles sub-pixel drift around that resolved position. The 25px page shift never enters the search.

**Secondary fix: phase correlation for canvas-internal shifts**

The above handles "the canvas moved on the page." What if the content *inside* the canvas shifted — user panned the map between record and replay?

Phase correlation gives you the single (dx, dy) translation between two images via FFT. Process:
1. FFT the recorded canvas image, FFT the replay canvas image
2. Compute the normalized cross-power spectrum
3. Inverse FFT
4. Argmax gives the translation offset
5. Apply that offset to the recorded click position

Handles arbitrary translation in one shot, sub-pixel accurate. Cost on a typical 1920×1080 canvas: ~10–30ms via WASM SIMD FFT. On a downsampled 4× canvas: ~3–5ms, then refine in a small window at full res. Doesn't handle rotation or scale, but "user panned" is pure translation, so it's the right tool for that case.

**Tertiary fix: ORB feature matching for general transforms**

For cases where translation isn't enough (zoom changed, slight rotation, sub-region of canvas moved while rest stayed), detect ORB features in both images, match descriptors, infer transform from matched points. ~10–30ms for moderate feature counts. Handles translation + scale + rotation, robust to partial occlusion. Pure JS implementations exist (opencv.js, or hand-rolled ORB at ~500 lines).

**Putting it together — cache lookup tiers:**

```
1. Compute candidate click point = anchor.top_left + recorded_offset
2. Extract patch at candidate, hash, compare to recorded
3. If Hamming ≤ threshold → done. (banner-shift case lands here, ~3-5ms total)
4. Else: phase-correlate recorded canvas vs current canvas
   4a. Get (dx, dy), apply to candidate point
   4b. Re-extract patch, re-hash, re-compare
   (~15-30ms total; covers canvas-internal pan/scroll)
5. Else: ORB feature match, infer transform, apply
   (~30-50ms total; covers zoom + rotation)
6. Else: CUA fallback (~hundreds of ms)
```

Cost is roughly proportional to how rare or severe the drift is. The banner-shift case lands in tier 1 — essentially free.

**The deeper architectural point:**

Sliding-window patch matching is the wrong tool because it brute-forces a problem with structure. The structure: things don't move arbitrarily, they move relative to other things. Coordinate-frame-aware matching exploits that structure — anchor-relative coords, phase correlation, feature-point matching all do this in different ways. Brute force ignores it and pays linearly in the search area.

The visual patch hash is for *verification* (is this the right element?), not for *localization* (where is it?). Localization comes from the coordinate-frame transformation; the hash just confirms. This is why 4K video stabilization runs in real time on phones — they're not brute-forcing translation, they're using phase correlation. Same idea applies here: pay structural cost once, near-zero per-frame search after.

**For your specific case:**

The 25px banner-shift example is exactly the "anchor-relative" win. As long as the click target's nearest stable DOM ancestor — or the canvas it's inside, in the canvas case — is itself findable on replay (which it should be, given DOM structural fingerprints are strong), the click target moves with that ancestor and you never compute the page-level shift directly. The whole class of "stuff above changed size" drifts collapses to "no shift detected" at the matching layer.

The cases that actually need phase correlation or ORB are the ones where the *interior* of the anchor has shifted — canvas pan, content scroll within the anchor, internal layout change. Those are rarer than chrome-level shifts and have a different fingerprint anyway (the recorded canvas's overall hash will differ, which can be the trigger to invoke phase correlation rather than just doing it always).

---

## Nick

<!-- message 45; source_index=50; uuid=019e4c22-4e17-7169-827c-cfb44be46c3c; created_at=2026-05-21T20:02:57.714889Z -->

```coffeescript

// only match the map zoom in button on real map pages, not help pages where it's just an example element

SuperSelector = {
    prefer: [
        {text__contains: '+'},      // prefer elements that contain the text '+'
        {text__contains: 'in'},     // prefer elements that contain the text 'in'
        {title__icontains: 'in'},   // prefer elements that contain the text 'in' in the title
        {css: '.map-zoom-in-button'},
        {documentBoundingBox:       {top: 10vh, bottom: 15vh, left: 80vw, right: 100vw}},  // look for the button inside the top right area of the page
        {pageActive: True},         // prefer foreground page
        {pageIdx: 0},               // or the first open page in the tabstrip
        // ? {visualHashes: ['1234567890', 'abacw32rsf', '1234567890']},
        // ? {visualEdgeSignature: 25},
        // ? {backgroundColor: '#000000'},
        // ? {fontColor: '#fff'},
    ]
    include: [
        {url: 'https://map.example.com/*'},    // only match on known map pages
    ],
    exclude: [
        {css: '.disabled', exclude: true},
        {url: 'https://map.example.com/help/*'},
        {text__icontains: 'out'},
        {title__icontains: 'out'},
        {text__contains: '-'},
    ],
    _resolved: {   // once a SuperSelector is matched to a real element on the page, we can hydrate these values live from the DOM, but they are assumed to go stale basically anytime the DOM changes
        elementType: 'button',
        targetId: '234523234325505111',
        nodeId: '234',
        backendNodeId: '23523542',
        parentFrameIds: ['234523234325505333', '2345232343255052222', '234523234325505111'],     // [root frame -> child frame -> grandchild frame -> direct parent frame] -> element node
        parentTargetIds: ['234523234325505333', '234523234325505111'],                           // middle frame might be same-origin, so no separate target id for it
        text: 'Zoom in',
        style: {
            cursor: 'pointer',
            backgroundColor: '#000000',
            color: '#ffffff',
            fontSize: '16px',
            fontWeight: 'bold',
            textAlign: 'center',
            textDecoration: 'none',
            textTransform: 'uppercase',
            borderRadius: '5px',
        },
        css: [
            '.map-zoom-in-button',
            'main > div#map > div:nth-child(1) > button.map-zoom-in-button:nth-of-type(1)',
            ...
        ],
        xpath: [
            '//button[text()="Zoom in"]',
            '/html/body/main/div[1]/div[1]/button[1]',
            '/html/body/main/div[@id="map"]/...',
            ...
        ],
        documentBoundingBoxes: [
            {top: 250px, left: 1300px, right: 100px, bottom: 300px},    // only multiple entires if the element is inline / wrapping multiple lines
        ],
        viewportBoundingBoxes: [
            {top: 12.2vh, bottom: 13.5vh, left: 84.2vw, right: 89.1vw},    // only multiple entires if the element is inline / wrapping multiple lines / actually multiple elements (e.g. ::before / ::after + content)
        ],
    },
}


SuperSelector.getFuzzyHash() => 'v1:2342:adkl:asdf1:23jbksjhcodyf:235n23kjfshdf:kjj34!:23n4sdfk:23lkr2rsfd:k2n342lk4j:skn3r24:...'  // some string representation? doesnt need to be reversible just needs to be stable-ish / fuzzy-match across bands and within bands
```

---

## Claude

<!-- message 46; source_index=51; uuid=019e4c22-4e17-7c51-8df7-d03a4c80f58b; created_at=2026-05-21T20:05:07.785267Z -->

The structure cleanly separates query intent (`prefer`/`include`/`exclude`) from observed state (`_resolved`). The hash should pull from both, but with explicit handling of which fields are stable vs ephemeral. Walking through:

**Fields to exclude from the hash entirely:**

- `targetId`, `nodeId`, `backendNodeId` — CDP session-scoped, change every reload
- `parentFrameIds`, `parentTargetIds` — same; ephemeral
- `documentBoundingBoxes` (absolute pixels) — viewport-dependent, not stable
- `pageActive`, `pageIdx` — runtime page-routing state, not element identity
- `_resolved.style.backgroundColor`, `.color` — theme-sensitive; record but don't hash directly
- `include.url` — query routing filter, not part of element identity within a page

The CDP IDs should be moved into a `_resolved.live` sub-block, not mixed with stable features. Useful as a hot-cache within a session, useless for cross-session matching. Segregating them at the type level prevents them ever leaking into the hash by accident.

**Concrete `getFuzzyHash` sketch:**

```ts
function getFuzzyHash(sel: SuperSelector): string {
  const r = sel._resolved
  const p = sel.prefer

  // s: structural — element type, css selector tokens, xpath tokens
  const structuralTokens = new Set([
    `tg:${r.elementType}`,
    ...r.css.flatMap(tokenizeCss),                 // class, attr, tag tokens
    ...r.xpath.flatMap(tokenizeXpath),             // path segments, attr predicates
    ...prefer_css(p).flatMap(tokenizeCss),
  ])
  const s = minHash64(structuralTokens)            // 16 hex chars

  // c: content — own text + 'prefer' text criteria (trigram-tokenized for fuzzy match)
  const contentTrigrams = new Set([
    ...trigrams(r.text),
    ...prefer_text(p).flatMap(trigrams),
    ...prefer_title(p).flatMap(t => trigrams(t.toLowerCase())),
  ])
  const c = simHash64(contentTrigrams)             // 16 hex chars

  // x: context — stable ancestor tokens (data-testid, ARIA, semantic tags),
  //    NOT frame/target IDs. Capture during element resolution.
  const contextTokens = new Set(r.ancestorAnchors ?? [])
  const x = minHash64(contextTokens)               // 16 hex chars

  // p: spatial — center + size from viewportBoundingBoxes (vh/vw, viewport-relative)
  //    Morton-encoded so similar boxes share bit prefixes
  const vb = r.viewportBoundingBoxes[0]
  const cx = quantize((vb.left + vb.right) / 2, 8)
  const cy = quantize((vb.top + vb.bottom) / 2, 8)
  const w  = quantize(vb.right - vb.left, 6)
  const h  = quantize(vb.bottom - vb.top, 6)
  const p_axis = mortonInterleave(cx, cy, w, h)    // 28 bits → pad to 64

  // LSH bands over the union for long-tail disambiguation
  const lshBands = computeLSHBands(
    [...structuralTokens, ...contentTrigrams, ...contextTokens],
    {bands: 4, bitsPerBand: 16}
  )

  return `v1.s:${hex(s)}.c:${hex(c)}.x:${hex(x)}.p:${hex(p_axis)}.lsh:${hex(lshBands)}`
}
```

Output: `v1.s:a3f2c918d4e5b760.c:ff21...` — fixed widths per segment, trivially parseable. (Different from your `'v1:2342:adkl:...'` sketch in that segments have explicit type prefixes and fixed bit-widths, which makes per-axis Hamming comparison free.)

**Specific changes worth making to the SuperSelector shape:**

1. **Split `_resolved` into stable + ephemeral.** `_resolved.live` for CDP IDs (targetId/nodeId/backendNodeId/parentFrameIds), `_resolved.observed` for the rest. Type-level separation prevents accidental hash contamination.

2. **Add `_resolved.observed.ancestorAnchors: string[]`.** During resolution, capture hashes of stable ancestor identifiers (data-testid values, ARIA labels filtered for PII, semantic landmark tags). Without this the `x:` axis is empty and you lose context disambiguation. Cheap during the existing DOM walk.

3. **Drop or relocate `documentBoundingBoxes`.** Absolute pixels are useful for debug/replay but not invariant — viewport-relative (vh/vw) is what the hash should consume. Move to a debug block or compute lazily from `viewportBoundingBoxes × viewport size`.

4. **Theme-sensitive style fields stay in `_resolved.observed` but are excluded from the hash.** Or: store hue separately from luminance so the hash can use hue (theme-invariant). Practical default: just exclude. If you add the visual axis later, the complement-Hamming trick from earlier handles theme inversion for free.

5. **`prefer.documentBoundingBox` as a region constraint** is a query-time *filter*, not an element-identity bit. Use it at match time to prune candidates outside the region; don't fold it into the element hash. The region describes "where I expect this to be," not "what this is."

6. **Commented-out `visualHashes`, `visualEdgeSignature`, `backgroundColor`, `fontColor`** — right direction. Slot them into a fifth axis (`vis:`) using the classical CV bundle (pHash + dHash + HOG + edge density, with complement-Hamming for theme). Adds ~16 hex chars.

**Bigger architectural point — two hashes, not one:**

`prefer/include/exclude` describes *the query*; `_resolved` describes *one observed match*. Two semantically different things. Your `getFuzzyHash` currently conflates them, but they should probably produce two hashes:

- `getQueryHash()` — derived only from `prefer`/`include`/`exclude`. Stable across sessions and DOM changes. Cache key for "have we seen this query before?"
- `getElementHash()` — derived from `_resolved.observed`. Fingerprint of a specific element that matched. Used for fuzzy matching against new observations.

```
queryHash  →  elementHash  →  (replay) fuzzy-match against current DOM candidates
   ^               ^
   cache key       what gets matched
```

The `include`/`exclude` filters apply at query-routing time (which page scope, which URL), and the element hash matching happens only on candidates that already pass them. Two-phase: filter to scope, then fuzzy-match within scope.

This separation also clarifies the staleness story: `_resolved` going stale invalidates the elementHash but not the queryHash. So on staleness, you re-resolve the query (using `prefer` criteria to find candidates), update `_resolved`, recompute elementHash. The query identity persists across resolution churn, which is what you want for long-lived recordings.

A small detail on `prefer`: the way you've written it, each entry is a constraint with implicit AND-of-OR semantics. Worth being explicit about how the matcher combines them — are they additive (each match adds score)? Soft-required (penalty for missing)? Strict (must match)? The CoffeeScript syntax doesn't distinguish. Naming convention or per-entry weight (`{text__contains: '+', weight: 2.0}`) would make scoring auditable later when you're debugging why a wrong element matched.

---

## Nick

<!-- message 47; source_index=52; uuid=019e4c26-44fb-7837-aa6c-8a62a9f1f847; created_at=2026-05-21T20:07:17.524143Z -->

I dont understand why you want to split _resolved, everything in _resolve is live/observed, none of it can be assumed to be stable, stable stuff belongs at the top level, not inside _resolved.

---

## Claude

<!-- message 48; source_index=53; uuid=019e4c26-44fb-7462-a493-c27f110de043; created_at=2026-05-21T20:09:16.317241Z -->

You're right, I misread the model. The split is already there — top level is the durable spec, `_resolved` is the snapshot of one observed match, fully ephemeral by design. Nothing inside `_resolved` is durable; everything in it is "what we saw last time," including text and bounding boxes, which shift across renders. Trying to split `_resolved` further was redundant — the partition is at the level above.

Recalibrating: the fuzzy hash derives from the top-level stable fields only. `_resolved` doesn't enter into it. It's runtime state — hot cache for in-session CDP work, last-known features for verification on replay, debugging surface. None of that belongs in an identity hash.

What the hash pulls from, per axis:

```ts
function getFuzzyHash(sel: SuperSelector): string {
  const canonical = canonicalize(sel.prefer)  // sort by criterion type, normalize values, dedupe

  // s: structural — css selectors, element type hints from prefer
  const structuralTokens = new Set([
    ...prefer_css(canonical).flatMap(tokenizeCss),
    ...prefer_tagOrRole(canonical),
  ])

  // c: content — all text/title criteria (exclude criteria get negative weighting at match time, not in the hash)
  const contentTrigrams = new Set([
    ...prefer_text(canonical).flatMap(trigrams),
    ...prefer_title(canonical).flatMap(t => trigrams(t.toLowerCase())),
  ])

  // x: context — URL patterns from include, scope filters
  const contextTokens = new Set([
    ...sel.include.flatMap(extractUrlTokens),
    ...sel.exclude.flatMap(extractUrlTokens).map(t => `~${t}`),  // negative-prefixed for exclude
  ])

  // p: spatial — documentBoundingBox regions specified in prefer (part of the spec, not observation)
  const spatialFeatures = prefer_region(canonical).map(quantizeRegion)
  const p_axis = mortonInterleave(spatialFeatures)

  // LSH bands over the combined feature set for long-tail disambiguation
  const lshBands = computeLSHBands(
    [...structuralTokens, ...contentTrigrams, ...contextTokens],
    {bands: 4, bitsPerBand: 16}
  )

  return [
    'v1',
    `s:${hex(minHash64(structuralTokens))}`,
    `c:${hex(simHash64(contentTrigrams))}`,
    `x:${hex(minHash64(contextTokens))}`,
    `p:${hex(p_axis)}`,
    `lsh:${hex(lshBands)}`,
  ].join('.')
}
```

The hash is a content-addressed identifier for the *spec*, not for any observed match. Two SuperSelectors with the same canonical spec (after sorting/dedup) produce the same hash. Two SuperSelectors that happen to resolve to the same element but were specified differently produce different hashes — correct, because they're different durable identities.

`_resolved` is used at runtime for:
- Direct CDP retargeting within a session (the live IDs save a re-resolution round trip)
- Quick verification on replay ("does this candidate look roughly like what we saw last time, in text/bbox/css?")
- Debugging ("what did this selector actually match the last time it was resolved?")

None of those are identity needs. Identity is what the user or recording system specified as the durable description, which is the top-level fields.

One practical implication of this clarification: `_resolved` should probably be omittable / strippable when serializing SuperSelectors for storage or transmission. Two SuperSelectors with the same top-level spec but different `_resolved` snapshots are the same selector — equality and hashing don't depend on `_resolved` at all. Treating it as transient cache rather than persisted state makes that explicit and keeps stored selectors from churning every time `_resolved` refreshes.

The other thing worth being explicit about now that the data-model split is clear: canonicalization of `prefer` matters more than I initially gave it credit for. Two recordings of the same intent could specify the criteria in different orders, with `text__contains: 'in'` vs `text__contains: 'In'`, with redundant overlapping CSS selectors, etc. Without canonicalization, semantically-identical specs produce different hashes and break the cache-key story. A `canonicalize()` step that sorts by criterion type, lowercases `__icontains` values, dedupes equivalent CSS selectors (e.g., `.x.y` vs `.y.x`), and normalizes region representations (e.g., `top: 10vh, bottom: 15vh` → `top: 10vh, height: 5vh` or vice versa, pick one) is the small but high-leverage piece that makes the hash actually stable.

---

## Nick

<!-- message 49; source_index=54; uuid=019e4c3b-2ac0-77e8-8bfa-eec4bc6925e1; created_at=2026-05-21T20:30:07.264100Z -->

why are you so fixated in sorting by criterion type / not having the fuzzy hash just be based on whats in prefer/include/exclude?

---

## Claude

<!-- message 50; source_index=55; uuid=019e4c3b-2ac0-702a-8ee6-216f5b7c455e; created_at=2026-05-21T20:30:24.321361Z -->

> **Note:** Claude’s response was interrupted.

---

## Nick

<!-- message 51; source_index=56; uuid=019e4c3b-f47c-78b7-93b5-da402c26876a; created_at=2026-05-21T20:30:58.808730Z -->

the whole point of the hashes is they are fuzzy matched! they never need to be identical, it's expected for different predicates to produce slightly different fuzzy hashes for the same element, but they need to still match when fuzzy matching!

---

## Claude

<!-- message 52; source_index=57; uuid=019e4c3b-f47c-7a5a-82e9-c30e47e9dd58; created_at=2026-05-21T20:31:51.539243Z -->

You're right, my mistake. I was conflating "make the hash deterministic" with "make the hash exactly equal across equivalent specs." For a fuzzy hash, those are different goals — only the first matters.

The MinHash/SimHash primitives already absorb the variations I was trying to canonicalize away:

- **MinHash over feature sets** is order-invariant by construction. `[text__contains: 'in', text__contains: '+']` and `[text__contains: '+', text__contains: 'in']` produce the same set of trigrams, same MinHash. No pre-sort needed.
- **Trigrams of CSS selectors** dedupe naturally. `.x.y` tokenizes to `{class:x, class:y}`, same as `.y.x`. No CSS canonicalizer needed.
- **Case sensitivity is just operator semantics.** Processing `text__icontains: 'IN'` lowercases before trigram extraction because that's what the operator means — that's the criterion's implementation, not preprocessing the spec.
- **Small variations produce small Hamming distances** by construction — that's the entire point of these hash families. Two specs differing by one criterion produce hashes differing by ~5–10 bits out of 64, well within fuzzy-match thresholds.

So `getFuzzyHash` is just:

```ts
function getFuzzyHash(sel: SuperSelector): string {
  // No canonicalization. Extract features directly from prefer/include/exclude.

  const structuralTokens = new Set([
    ...prefer_css(sel.prefer).flatMap(tokenizeCss),
    ...prefer_tagOrRole(sel.prefer),
  ])

  const contentTrigrams = new Set([
    ...prefer_text(sel.prefer).flatMap(trigrams),                        // case preserved
    ...prefer_textIc(sel.prefer).flatMap(t => trigrams(t.toLowerCase())),// op-defined lowercase
    ...prefer_title(sel.prefer).flatMap(trigrams),
    ...prefer_titleIc(sel.prefer).flatMap(t => trigrams(t.toLowerCase())),
  ])

  const contextTokens = new Set([
    ...sel.include.flatMap(extractUrlTokens),
    ...sel.exclude.flatMap(extractUrlTokens).map(t => `~${t}`),
  ])

  const spatialFeatures = prefer_region(sel.prefer).map(quantizeRegion)
  const p_axis = mortonInterleave(spatialFeatures)

  const lshBands = computeLSHBands(
    [...structuralTokens, ...contentTrigrams, ...contextTokens],
    {bands: 4, bitsPerBand: 16}
  )

  return [
    'v1',
    `s:${hex(minHash64(structuralTokens))}`,
    `c:${hex(simHash64(contentTrigrams))}`,
    `x:${hex(minHash64(contextTokens))}`,
    `p:${hex(p_axis)}`,
    `lsh:${hex(lshBands)}`,
  ].join('.')
}
```

Two specs that the user wrote in different orderings, with redundant overlapping CSS, with different-but-overlapping text criteria — all produce hashes within small Hamming distance of each other. The matching layer finds them as the same fuzzy-equivalence class without me having to pre-engineer the equivalence into the input.

The deeper thing I keep reaching for in this thread and need to stop: I default to treating the hash as an exact-equality key, then patch around the fact that it's not. It isn't — it's a smooth similarity signal, and the smoothness is the feature. Preprocessing to make hashes exactly-equal for "equivalent" inputs actively undoes the smoothness and introduces a coupling point (the canonicalization rules) that becomes its own version-brittleness over time. The right mental model is: extract features straight from the spec, let the hash families do their job, trust the matcher to handle the rest.

---

## Nick

<!-- message 53; source_index=58; uuid=019e4d24-6aa8-76c4-91e9-e0871a9a8be1; created_at=2026-05-22T00:44:53.715995Z -->

Let's say we want to do away with heuristic matching and just do cosine similarity for everything and use prefixed vectors and real structs for different bands, what's the bare minimum pseudocode to do something like this in CDP / browser js

---

## Claude

<!-- message 54; source_index=59; uuid=019e4d24-6aa8-7ed0-8496-df34b90bfad5; created_at=2026-05-22T00:47:02.994081Z -->

The shift from the previous design: one primitive (cosine), no MinHash/SimHash/LSH-band machinery. Each band becomes a fixed-dim float vector; everything else is feature hashing into those vectors and L2 normalization so cosine reduces to dot product.

```ts
// 1. Per-band dimensionality (only real design choice)
const DIMS = {
  structural: 128,  // tag, role, classes, attrs, xpath tokens
  content:    256,  // text/label/title trigrams
  context:     64,  // ancestor anchors, URL tokens
  spatial:      8,  // bbox (viewport-relative), aspect, doc order, depth, z
  visual:      64,  // optional: perceptual hash floats, color histogram, edge density
} as const

type BandName = keyof typeof DIMS
type ElementVector = { [K in BandName]: Float32Array }

// 2. Feature hashing with signed buckets (Weinberger trick — kills collision bias)
function hashToken(t: string, dim: number) {
  const h = xxhash32(t)
  return { slot: h % dim, sign: ((h >> 16) & 1) ? 1 : -1 }
}

function vectorizeTokens(tokens: Iterable<string>, dim: number): Float32Array {
  const v = new Float32Array(dim)
  for (const t of tokens) {
    const { slot, sign } = hashToken(t, dim)
    v[slot] += sign
  }
  return normalize(v)
}

function vectorizeNumeric(vals: number[], dim: number): Float32Array {
  const v = new Float32Array(dim)
  for (let i = 0; i < Math.min(vals.length, dim); i++) v[i] = vals[i]
  return normalize(v)
}

function normalize(v: Float32Array): Float32Array {
  let n = 0
  for (let i = 0; i < v.length; i++) n += v[i] * v[i]
  n = Math.sqrt(n) || 1
  for (let i = 0; i < v.length; i++) v[i] /= n
  return v
}

// 3. Build a per-element vector from extracted features.
//    Token prefixes (cls:, xp:, at:) keep different feature kinds from colliding in the same band.
function buildVector(f: ElementFeatures): ElementVector {
  return {
    structural: vectorizeTokens(function* () {
      yield `tg:${f.tag}`
      yield `rl:${f.role}`
      for (const c of f.classes) yield `cls:${c}`
      for (const [k, v] of f.attrs) yield `at:${k}=${v}`
      for (const t of tokenizeXpath(f.xpath)) yield `xp:${t}`
    }(), DIMS.structural),

    content: vectorizeTokens(function* () {
      yield* trigrams(f.text)
      yield* trigrams(f.label ?? '')
      yield* trigrams(f.title ?? '')
    }(), DIMS.content),

    context: vectorizeTokens(function* () {
      yield* f.ancestorAnchors
      yield* tokenizeUrl(f.pageUrl)
    }(), DIMS.context),

    spatial: vectorizeNumeric([
      f.bbox.cx_vw, f.bbox.cy_vh,
      f.bbox.w_vw,  f.bbox.h_vh,
      f.bbox.aspect,
      f.docOrderFrac, f.depthFrac, f.zIndex / 100,
    ], DIMS.spatial),

    visual: vectorizeNumeric(f.visualFeatures ?? [], DIMS.visual),
  }
}

// 4. Cosine = dot product, since vectors are L2-normalized
function cosine(a: Float32Array, b: Float32Array): number {
  let d = 0
  for (let i = 0; i < a.length; i++) d += a[i] * b[i]
  return d
}

// 5. Weighted score across bands — the only matching primitive
const WEIGHTS: Record<BandName, number> = {
  structural: 0.30, content: 0.30, context: 0.20, spatial: 0.15, visual: 0.05,
}

function score(a: ElementVector, b: ElementVector): number {
  let total = 0
  for (const band of Object.keys(DIMS) as BandName[]) {
    total += WEIGHTS[band] * cosine(a[band], b[band])
  }
  return total
}

// 6. Pack for storage / transmission (quantize to int8, concat bands in fixed order)
function pack(ev: ElementVector): Uint8Array {
  const total = Object.values(DIMS).reduce((a, b) => a + b, 0)
  const out = new Uint8Array(total)
  let off = 0
  for (const band of Object.keys(DIMS) as BandName[]) {
    const v = ev[band]
    for (let i = 0; i < v.length; i++) {
      out[off + i] = ((Math.round(v[i] * 127) + 256) & 0xff)  // signed → unsigned int8
    }
    off += DIMS[band]
  }
  return out
}

// 7. CDP bulk feature extraction — DOMSnapshot is the right primitive
async function extractAllElements(cdp: CDPSession): Promise<ElementFeatures[]> {
  const snap = await cdp.send('DOMSnapshot.captureSnapshot', {
    computedStyles: ['cursor', 'pointer-events', 'visibility', 'opacity', 'display'],
    includePaintOrder: true,
    includeDOMRects: true,
  })
  // snap.documents[0] has parallel arrays: nodeName, nodeValue, attributes, layout (bboxes),
  // computedStyles, paintOrders. One CDP round-trip for the whole page.
  return snap.documents[0].nodes.map(toFeatures)
}
```

Rough cost on the numbers from earlier:

| Step | Cost |
|---|---|
| `DOMSnapshot.captureSnapshot` (one CDP round-trip) | 20–50ms for ~2000 elements |
| `buildVector` per element (~50 tokens × 128 dims) | 50–100μs |
| Full page: 2000 × buildVector | 100–200ms |
| `cosine` (one band, ~256 floats) | ~3μs |
| Full score (5 bands, 520 floats total) | ~5μs |
| Lookup vs 2000 candidates | ~10ms |
| Storage per element (int8 packed) | 520 bytes |
| Storage for 2000 elements | ~1MB |

What this gets you that the prior design didn't:

1. **One primitive everywhere**. Match score is `score(a, b)`, period. No per-band Hamming vs Jaccard vs Hamming-with-complement. No weight tuning inside each hash family. Single function, vectorized, SIMD-friendly.
2. **Smooth similarity by construction**. Two specs/elements differing by one token shift each affected band's cosine by ~`1/sqrt(num_tokens)` — small, smooth, continuous. No threshold artifacts at hash-collision boundaries.
3. **Tunable per-band weights at query time**. Detected theme change → drop visual weight to 0. Different viewport → drop spatial. Same code path, just different `WEIGHTS`.
4. **Drop-in for ML later**. The vectors are now exactly the shape a small projection model expects. If you eventually collect differential-recording pairs and want to learn weights, train a 5-dim diagonal Mahalanobis or a small linear projection on top — same artifact format, better scoring.

Things deliberately kept out of the bare minimum:
- ANN indices (HNSW etc.) — unnecessary at 2000 elements where brute force is 10ms
- Quantization-aware training — int8 packing is the only quantization, applied at storage time
- Per-band normalization other than L2
- Caching — orthogonal concern, slots in at any layer

The "prefixed vectors" property holds two ways: tokens are prefixed (`cls:`, `at:`, `xp:`) so the hashing keeps feature kinds disjoint within a band, and the bands themselves are real struct fields with fixed offsets in the packed form, so an int8 buffer is trivially parseable back into the per-band vectors. No metadata needed beyond the `DIMS` constant.

The whole matching engine is `score()` — six lines of dot products and a weighted sum. Everything else is just feeding it the right vectors.

---
