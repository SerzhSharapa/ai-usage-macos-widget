# Architecture Research

**Domain:** Native macOS companion app (menu bar agent) + WidgetKit widget showing AI subscription usage limits
**Researched:** 2026-10-11
**Confidence:** HIGH — every load-bearing claim below is grounded in current Apple official documentation (fetched 2026-10-11, pages show © 2026); items that rest on community consensus are explicitly marked MEDIUM

## Standard Architecture

### System Overview

The owner chose **Horizontal Layers**: complete technical layers assembled at the end. The architecture maps naturally onto that: each layer is independently testable, and the two UI shells (menu bar, widget) are thin consumers of the layers below.

```
┌──────────────────────────────────────────────────────────────────────┐
│ L4  PRESENTATION (two thin shells, one process each)                 │
│  ┌──────────────────────────────┐  ┌───────────────────────────────┐ │
│  │ Menu Bar App (main target)   │  │ Widget Extension (2nd target) │ │
│  │ SwiftUI MenuBarExtra +       │  │ WidgetBundle → TimelineProvider│ │
│  │ Settings window              │  │ reads ONLY the group container │ │
│  └──────────────┬───────────────┘  └───────────────┬───────────────┘ │
├─────────────────┼───────────────────────────────────┼─────────────────┤
│ L3  APPLICATION │  ProbeScheduler (Task loop)       │ getTimeline():  │
│                 │  RefreshCoordinator               │ entry = cache   │
│                 │  KeychainStore (app-only)         │ + fetchedAt age │
├─────────────────┴───────────────────────────────────┴─────────────────┤
│ L2  DOMAIN — local SwiftPM package «UsageCore» (shared by both)      │
│  ┌────────────┐ ┌──────────────────────┐ ┌──────────────────────────┐ │
│  │ Models:    │ │ ProviderAdapters:    │ │ SnapshotStore:           │ │
│  │ UsageSnap- │ │ OpenAI / Kimi / Z.ai │ │ atomic JSON in group     │ │
│  │ shot, Plan,│ │ / OpenRouter         │ │ container + UserDefaults │ │
│  │ Window     │ │ (parse only, no UI)  │ │ suite for display prefs  │ │
│  └────────────┘ └──────────────────────┘ └──────────────────────────┘ │
├───────────────────────────────────────────────────────────────────────┤
│ L1  PLATFORM                                                          │
│  ┌──────────────┐ ┌───────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │ URLSession   │ │ Keychain      │ │ App Group    │ │ WidgetCenter│ │
│  │ (app proc.)  │ │ (app proc.)   │ │ container    │ │ reloads     │ │
│  └──────────────┘ └───────────────┘ └──────────────┘ └─────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Main app target (agent) | Owns everything: UI, scheduling, networking, secrets. Runs as login agent (`LSUIElement = YES`), lives for the whole login session | SwiftUI app, `MenuBarExtra`, no Dock icon |
| Widget extension target | Renders cached data only. **No networking, no Keychain, no keys** (hard project constraint) | `WidgetBundle` with one widget, `TimelineProvider` reading the group container |
| `UsageCore` (local SwiftPM package) | All reusable logic: models, provider adapters, snapshot store. Compiled into both targets, pure Swift, no AppKit/SwiftUI imports at this layer | Local package, no third-party dependencies |
| Provider adapters (4) | One endpoint each: OpenAI wham/usage, Kimi coding usages, Z.ai/bigmodel plan, OpenRouter credits. Parse response → `UsageSnapshot`. Pure functions over `Data` so they are unit-testable without network | `protocol ProviderAdapter { var provider: Provider; func fetch(key:) async throws -> UsageSnapshot }` |
| ProbeScheduler | Periodic in-app polling loop (menu-bar cadence) + manual refresh trigger + refresh-on-launch | `Task` with `Task.sleep` inside the always-running app process |
| SnapshotStore | Writes last-known-good data to the App Group container atomically; records `fetchedAt` per provider; never overwrites good data with zeros | JSON file in group container, write-to-temp-then-rename |
| KeychainStore | Persists provider API keys. Used **only** by the app target | `SecItemAdd/CopyMatching` with `kSecClassGenericPassword`; `kSecUseDataProtectionKeychain = true` |
| WidgetCenter bridge | App pushes "data changed" to WidgetKit after each probe that changed the snapshot | `WidgetCenter.shared.reloadTimelines(ofKind:)` |

### Why exactly two targets

WidgetKit renders widgets **in a separate process managed by the system**; the extension "is not continually active even if the widget is onscreen" (Apple, *Keeping a widget up to date*). Therefore the widget cannot share a process, singletons, or in-memory state with the app — the only sanctioned communication channels are: the shared App Group container (files / `UserDefaults(suiteName:)`) and app→WidgetKit reload signals. This is why the split is targets + a shared SwiftPM package, not modules inside one target.

## Recommended Project Structure

```
ai-usage-macos-widget/
├── Package.swift                # local package UsageCore
├── Sources/UsageCore/
│   ├── Models/
│   │   ├── UsageSnapshot.swift  # provider, windows, percent, resetAt, fetchedAt
│   │   └── ProviderID.swift
│   ├── Adapters/
│   │   ├── ProviderAdapter.swift    # protocol + common HTTP plumbing
│   │   ├── OpenAIAdapter.swift
│   │   ├── KimiAdapter.swift
│   │   ├── ZaiAdapter.swift
│   │   └── OpenRouterAdapter.swift
│   ├── Store/
│   │   ├── SnapshotStore.swift      # App Group container JSON I/O
│   │   └── DisplayPrefs.swift       # UserDefaults(suiteName:) thin wrapper
│   └── Keychain/
│       └── KeychainStore.swift      # SecItem wrapper (used by app target only)
├── App/                        # main app target (menu bar)
│   ├── AiUsageApp.swift        # @main, MenuBarExtra, LSUIElement
│   ├── ProbeScheduler.swift    # periodic loop + manual refresh
│   ├── RefreshCoordinator.swift# runs adapters → SnapshotStore → WidgetCenter
│   ├── MenuBarView.swift
│   └── SettingsView.swift      # key entry, intervals, provider toggles
├── Widget/                     # widget extension target
│   ├── UsageWidgetBundle.swift
│   ├── UsageWidget.swift       # TimelineProvider + SwiftUI views
│   └── WidgetViews.swift       # LIMITS-card layout, stale/age states
└── Entitlements/
    ├── App.entitlements        # sandbox, network client, app group
    └── Widget.entitlements     # sandbox, app group (NO network client)
```

### Structure Rationale

- **`UsageCore` as a local SwiftPM package**, not a folder of shared files: both targets import it via Xcode; the package has no UI imports, so `xcodebuild test` can exercise adapters and the store headlessly. Matches the project constraint "SwiftPM, no heavy third-party dependencies".
- **Adapters parse-only:** endpoint knowledge (paths, response shapes from the DSH reference `@linxin666/dsh-usage`) lives in one file per provider. Transport (URLSession call) is a thin shared helper so retry/timeout policy is uniform.
- **Entitlements as first-class files:** sandbox + app group + network-client differences between targets are the #1 source of "works in app, widget shows nothing" bugs; keeping them explicit in the structure forces attention.

## Architectural Patterns

### Pattern 1: App-prepared cache + WidgetCenter push (recommended)

**What:** All HTTP probing lives in the main app process. The app writes a `UsageSnapshot` JSON into the App Group container and calls `WidgetCenter.shared.reloadTimelines(ofKind:)`. The widget extension's `getTimeline` reads the container and builds entries — it never touches the network.
**When to use:** Always, here. This is Apple's own stated approach: "Have the containing app prepare data for the widget in advance of when the widget needs it. Use a shared group container to store the data" (TimelineProvider docs, *Refresh widgets efficiently*).
**Trade-offs:** Widget data is only as fresh as the app's last probe — acceptable, because the companion app runs continuously and the project explicitly rejects minute-freshness in the widget. Bonus: the extension process starts faster (file read instead of 1–4 HTTP round-trips), which matters because WidgetKit gives the provider limited time to respond.

**Example:**
```swift
// App side, after a probe run:
try SnapshotStore.save(combined)                     // atomic write to group container
if combined != previous {
    WidgetCenter.shared.reloadTimelines(ofKind: "ai-usage-card")
}

// Widget side:
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let snapshot = SnapshotStore.load()              // may be nil / stale — still renders
    let entry = UsageEntry(date: .now, snapshot: snapshot)
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
}
```

### Pattern 2: Last-known-good snapshot with age (never show zeros)

**What:** Every successful provider response is written with a `fetchedAt` timestamp. A failed probe (network down, 401/403, changed API) **does not modify the stored numbers** — at most it stamps a `lastError` side-record. The widget renders stored percentages plus "обновлено N мин назад".
**When to use:** Any widget over an unreliable/authenticated API. This is the project's explicit requirement ("ошибка сети/auth не выдаётся за 0%").
**Trade-offs:** Requires honest age display to avoid showing ancient data as if fresh. The age label should use `Text(fetchedAt, style: .relative)` — a dynamic date that WidgetKit re-renders live **without consuming reload budget** (Apple, *Displaying dynamic dates*).
**Detection of the failure mode to avoid:** if the widget ever shows 0% / "—%" right after going offline, the pipeline wrote an error object over good data.

**Example:**
```swift
struct UsageSnapshot: Codable {
    let provider: ProviderID
    let windows: [UsageWindow]   // name, usedPercent, resetsAt
    let fetchedAt: Date          // set ONLY on successful parse
}
// On probe failure:
store.recordError(provider, error)   // goes to a separate error side-file
// numbers in the main snapshot file remain untouched
```

### Pattern 3: Single always-running agent app as the scheduler

**What:** The menu bar app is a login agent (`LSUIElement`) that lives for the whole session; scheduling is a plain in-process loop (`Task { while true { probe(); try await Task.sleep(for: .seconds(interval)) } }`) with wakeups on manual refresh and settings changes.
**When to use:** When the "background" component is by design a always-visible menu bar item — which this project is.
**Trade-offs:** No `NSBackgroundActivityScheduler`/`BGTaskScheduler` machinery needed because the process is expected to be alive; the cost is zero extra scheduling complexity, and if the user quits the app the widget simply ages (Pattern 2 covers this honestly). Note MEDIUM confidence: `NSBackgroundActivityScheduler` exists for apps that get suspended, but its Apple doc page currently 404s (checked 2026-10-11), suggesting deprecation drift — do not build on it; a plain `Task` loop in a permanently running agent is the simpler and sufficient mechanism here.

### Pattern 4: One app group for container + (optionally) keychain

**What:** Declare a single app group (e.g. `group.sharapa.ai-usage` — or, important for a **free personal team**, the macOS-only format `TEAMID.groupname`, which Apple documents as not requiring Developer-portal registration). Add `com.apple.security.application-groups` to **both** targets. Apple documents that app groups also act as keychain access groups.
**When to use:** For the container — always. For the Keychain — in this design **not needed at all**: keys are read/written only by the app process (the widget is keyless by constraint), so keychain items can stay in the app's default access group (`$(TeamID).bundleID`, private by definition). No `keychain-access-groups` entitlement is required.
**If it were ever needed** (e.g. a future probe-capable extension): share via the app group name as the keychain access group, and on macOS set `kSecUseDataProtectionKeychain = true` on queries — Apple states macOS keychain sharing applies when that key (or synchronizable attribute) is used. Items carry `kSecAttrAccessGroup`; adding with a group the process doesn't belong to fails with `errSecMissingEntitlement`.

## Data Flow

### Probe Flow (app process, every N minutes + manual + on launch)

```
ProbeScheduler (Task loop)
    ↓
RefreshCoordinator
    ↓ (for each enabled provider, concurrently)
ProviderAdapter.fetch(key: from KeychainStore) → URLSession (app process only)
    ↓ success                                    ↓ failure
parse → UsageSnapshot(fetchedAt: now)          recordError(provider) — side file only
    ↓
SnapshotStore.save(combined)  → atomic JSON write into App Group container
    ↓ (if changed)
WidgetCenter.shared.reloadTimelines(ofKind:)
    ↓ (system may coalesce/throttle — that's fine)
MenuBar UI updates in-place (no WidgetKit involved)
```

### Widget Render Flow (extension process, whenever WidgetKit asks)

```
WidgetKit wakes extension (budgeted reload, or app push, or widget added)
    ↓
getTimeline → SnapshotStore.load() from group container (milliseconds, no network)
    ↓
UsageEntry(date: now, snapshot, perProvider ages)
    ↓
SwiftUI view: percentages + Text(fetchedAt, style: .relative)  ← age ticks live, free
    ↓
Timeline(entries: [entry], policy: .after(now + 30 min))   ← pull fallback if app is dead
```

### State / Failure Matrix

| Situation | Menu bar shows | Widget shows |
|-----------|---------------|--------------|
| Probe OK | Fresh numbers | Fresh numbers, age ≈ 0 |
| Network down | Old numbers + offline marker | Old numbers + growing age |
| Auth failed (401) | Old numbers + "ключ устарел" hint | Old numbers + age (data intact) |
| App quit / not launched yet | — (no icon) | Old numbers + age; if never probed → placeholder/«запустите приложение» |
| First ever run, no keys | Setup prompt | Placeholder entry (gallery-grade sample data) |

### Key Data Flows

1. **Secrets flow:** user → Settings → Keychain (app process). Keys never enter UserDefaults, git, logs, the snapshot JSON, or the widget target. The widget never requests a key.
2. **Usage data flow:** provider HTTP → adapter parse → `UsageSnapshot` → App Group container → (a) menu bar UI in-process, (b) widget via timeline reload. One writer (app), one reader (widget) — no locks needed beyond atomic file replace.
3. **Refresh signal flow:** only app → WidgetKit (`reloadTimelines`). Widget → app communication does not exist and is not needed; the widget's `.after(date)` policy is the pull-side fallback when the app hasn't pushed.

## Refresh Budget Management

WidgetKit gives each widget a 24-hour rolling budget, "typically 40 to 70 refreshes — roughly every 15 to 60 minutes"; entries must be ≥ ~5 minutes apart; **reloads don't count against the budget while the containing app is in the foreground**. For a personal tool:

| Mechanism | Cadence | Counts against budget? |
|-----------|---------|------------------------|
| App probe loop (menu bar freshness) | 5–15 min (user setting) | n/a — app process, not WidgetKit |
| `reloadTimelines` after changed probe | on change only (official guidance: call it "only when information the widget is currently displaying changes") | Yes, but system throttles; foreground app = free |
| Timeline `.after(now + 30 min)` | fallback tick | Yes, 30–60/day — inside budget |
| Age label (`Text(.relative)`) | live, continuous | **No** — dynamic date, no reload |

This matches the project constraint "~15–60 мин, поминутную свежесть не обещаем" — the numbers in PROJECT.md are the official Apple figures, now confirmed verbatim.

## Scaling Considerations

| Concern | Today (4 providers, 1 user) | If it grows |
|---------|------------------------------|-------------|
| Probe cost | 4 HTTP calls / 5–15 min — negligible | Stagger adapters (5-min offsets) instead of shortening the global interval; keep per-provider intervals independent |
| Snapshot size | A few KB JSON | Still fine in container; do NOT move to `UserDefaults` suite for payloads |
| Widget families | systemSmall + systemMedium of one widget kind | Add families to the same kind — one snapshot feeds all; `getCurrentConfigurations` before selective reloads |
| Providers with heavy HTML/scrape | none (all JSON per DSH reference) | If one appears, isolate it in its adapter; never leak parsing quirks into the store schema |
| Multiple Macs | out of scope | Would need sync — deliberately out of scope |

## Anti-Patterns

### Anti-Pattern 1: Widget extension fetching provider APIs itself
**What people do:** Put URLSession calls (and the keys) in the widget's `getTimeline`.
**Why it's wrong:** Extension runs are budgeted and throttled — a network failure there means the widget shows placeholder data at the worst moment; and per project constraint keys must not reach the widget at all. Apple's guidance is explicit: the containing app prepares data in advance.
**Do this instead:** Widget reads the group container; all networking stays in the app process (Pattern 1).

### Anti-Pattern 2: Writing error/zero values over the snapshot
**What people do:** `store.save(failedState)` or map HTTP 401 to 0% entries.
**Why it's wrong:** Destroys last-known-good data; the widget then shows a confident, wrong "0%" — precisely what the requirements forbid.
**Do this instead:** Side-file for errors; main snapshot changes only on successful parse (Pattern 2).

### Anti-Pattern 3: Treating `reloadTimelines` as a guaranteed, immediate refresh
**What people do:** Call `reloadTimelines` in a loop expecting minute-level widget freshness, then file "widget doesn't update" bugs.
**Why it's wrong:** WidgetKit may coalesce, delay, or deny reloads — the budget is system-controlled and dynamic.
**Do this instead:** Treat app-side reloads as hints; keep the `.after(date)` fallback in the timeline; keep menu bar as the "frequent freshness" surface (that is the project's own two-views-of-one-collector decision).

### Anti-Pattern 4: Secrets or payloads in `UserDefaults`
**What people do:** Save API keys via `UserDefaults.standard` (or even a shared suite "temporarily"), or stuff full snapshots into the suite.
**Why it's wrong:** Keys in plaintext prefs violate the project's security constraint (Keychain-only); `UserDefaults` is also the wrong shape for structured payloads that need atomic replace and migration.
**Do this instead:** Keys → Keychain (`kSecClassGenericPassword`). Snapshot JSON → group container file. `UserDefaults(suiteName:)` only for small display prefs (interval, toggles, widget kind settings).

### Anti-Pattern 5: Sharing the Keychain "just in case"
**What people do:** Add `keychain-access-groups` and shared groups across both targets preemptively.
**Why it's wrong:** Extra entitlement surface for zero need — in this design only the app ever reads keys; a personal free team also makes extra entitlements/provisioning fragile.
**Do this instead:** Keep the widget keyless; document Pattern 4's recipe for if that ever changes.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| OpenAI (Codex) usage | `ProviderAdapter` → `chatgpt.com/backend-api/wham/usage` | Endpoint/parser source: DSH plugin reference, verified 11.10.2026 (PROJECT.md); re-implement in Swift |
| Kimi Code | `chatgpt`…→ `api.kimi.com/coding/v1/usages` | Same reference, same pattern |
| Z.ai / bigmodel plan | `api.z.ai` / `open.bigmodel.cn` plan endpoint | Two hosts possible — keep host selection inside the adapter |
| OpenRouter credits | `openrouter.ai/api/v1/credits` | Simplest adapter — build it first as the vertical slice |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| App target ↔ UsageCore package | Direct import (same process) | Package must stay UI-free to remain testable |
| Widget target ↔ UsageCore package | Direct import (same process as widget ext) | Widget uses Models + SnapshotStore; never Keychain module |
| App → Widget extension | App Group container (files/defaults) + `WidgetCenter` reloads | One-way data, one-way signal; no XPC needed |
| App ↔ Keychain | Security framework, app process only | `kSecUseDataProtectionKeychain = true` for future-proof, data-protection semantics |
| ProbeScheduler ↔ UI | `@Observable`/`ObservableObject` snapshot store view-model | Menu bar renders latest in-memory state; widget renders latest persisted state |

## Build Order Implications (Horizontal Layers)

Dependency-driven; each layer is complete and testable before the next consumes it:

1. **L2 Core: `UsageCore` package** — models, snapshot schema, `SnapshotStore` against a temp directory. No Xcode targets needed yet; pure `swift test`. Everything downstream depends on the snapshot schema — freeze it early (`fetchedAt`, per-window `resetsAt`).
2. **L2+L1: Adapters + probe engine** — OpenRouter first (simplest) as the vertical slice, then OpenAI/Kimi/Z.ai; adapters unit-tested against recorded response fixtures. Still no UI.
3. **L3/L4 Shell A: Menu bar app** — `MenuBarExtra` agent, Settings + Keychain entry, `ProbeScheduler` loop, manual refresh. After this phase the product is already useful without any widget — an early validation milestone.
4. **L3/L4 Shell B: Widget extension** — second Xcode target, shared app group entitlements, `TimelineProvider` reading the container, placeholder/stale/age states. Depends only on the schema from step 1 and the files written by step 3.
5. **Assembly & polish** — `WidgetCenter` reload wiring (push on change), refresh-budget tuning (`.after` interval), login-item/launch-at-login, error/stale visual states, README/docs.

**Why this order:** the widget (4) is the riskiest Xcode-plumbing step (entitlements, app group, second target, personal-team signing) but it is *pure consumption* — it can be built and debugged against files produced by step 3 without touching the engine. End-assembly integration (step 5) is deliberately last, matching the Horizontal Layers decision.

## Sources

Official Apple documentation, fetched and read 2026-10-11 (pages current, © 2026); provider endpoint references as recorded in PROJECT.md:

- Keeping a widget up to date — budget 40–70/day ≈ 15–60 min, `.atEnd`/`.after`/`.never`, app push via `WidgetCenter`, ≥5-min entry spacing, budget-free cases. https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date — **HIGH**
- TimelineProvider — snapshot/timeline/placeholder contract, "containing app prepares data… shared group container", refresh-policy guidance. https://developer.apple.com/documentation/widgetkit/timelineprovider — **HIGH**
- WidgetCenter — `reloadTimelines(ofKind:)` / `reloadAllTimelines()`, macOS 11+. https://developer.apple.com/documentation/widgetkit/widgetcenter — **HIGH**
- App Groups entitlement — `group.<name>` and macOS `<teamID>.<name>` (no portal registration), container sharing, app groups as keychain access groups, IPC rules. https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups — **HIGH**
- Sharing access to keychain items among a collection of apps — access-group composition order, `kSecAttrAccessGroup`, `errSecMissingEntitlement`, macOS `kSecUseDataProtectionKeychain` requirement. https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps — **HIGH**
- Configuring the macOS App Sandbox — `com.apple.security.app-sandbox`, Outgoing Connections (Client) = `com.apple.security.network.client`. https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox — **HIGH**
- Menu bar agent lifecycle (`LSUIElement`, `MenuBarExtra`), in-process `Task` loop scheduling, atomic-file cache convention — **MEDIUM** (standard practice, not re-verified against a single doc page in this session)
- `NSBackgroundActivityScheduler` doc page returned 404 on 2026-10-11 — treated as unavailable; **do not build scheduling on it** (negative claim, verified by direct fetch attempt)

---
*Architecture research for: ai-usage-macos-widget (macOS menu bar + WidgetKit usage limits)*
*Researched: 2026-10-11*
