# Chat and reusable AI skills

Chat, conversation storage, skills, and the companion are planned, not implemented. These actions belong to the optional AI phase of the [product delivery order](product.md#delivery-order). Core tracking, goals, and calculations remain independent of AI.

The one implemented piece is the data boundary they all sit behind: `domain/snapshot.dart` computes the scoped, read-only snapshot from `FinanceEngine` results — totals, the period they cover, categories, holdings, and freshness and completeness markers, with every unavailable total carrying its reason. It carries no transaction rows, payees, descriptions, bank identity, or file paths. Account names and every row UUID stay behind too: an account is named by a per-snapshot pseudonym such as `cash EUR 1`, and a validation failure is reported as a count per tab rather than by the rows it names, which would otherwise carry row identity — and, in a scoped snapshot, accounts the scope excluded. Approval remains the caller's decision: the snapshot bounds what may be sent, not whether to send it.

## Conversation storage

Keep saved history, displayed messages, and model context separate:

| Layer | Contents | Bound |
| --- | --- | --- |
| Saved history | Messages, completion status, conversation metadata, summaries, and references | Local disk storage; read pages as needed |
| Displayed conversation | Visible and nearby messages plus the active answer | Lazy widgets and a cache limited by both message count and bytes |
| Model context | Instructions, selected skill, approved snapshot, summary, and relevant exchanges | Token budget with space reserved for output and tool results |

Use disk-backed SQLite when saved chat ships, with ordinary Dart collections for the RAM working set. Do not add an in-memory database or load the whole transcript into `ChatController`. Unlike the optional workbook cache, saved chat is user data that cannot be rebuilt from the spreadsheet. It is device-local application state, not a third authoritative finance source or data to synchronize into the workbook.

Prefer one SQLite schema and query implementation across platforms. Native database work runs outside the UI isolate; web uses SQLite WASM in a worker with persistent browser storage. Evaluate a maintained integration such as [Drift](https://drift.simonbinder.eu/platforms/web/) when implementing this feature; no dependency is selected now. Handle quotas, unavailable persistence, cleared site data, and multi-tab access explicitly. If persistence fails, show the failure and offer session-only use without claiming the conversation is saved. Web chat remains limited to a build served by the companion's loopback origin.

Flutter owns saved conversations; the companion remains a transient provider gateway. Do not add a second transcript database to the companion. Follow the [saved-history privacy rules](privacy-and-llm.md#saved-chat-and-external-agents).

## Responsive streaming

Implement these constraints together with chat:

1. Page messages by conversation and stable sequence, using cursor-based queries and appropriate indexes. Evict distant bodies from RAM. Observe bounded query results, not the entire conversation on every update.
2. Coalesce stream deltas and update only the active answer. Measure a 30–60 millisecond display cadence as an initial tuning point, not a guarantee. Avoid rebuilding the conversation for every token.
3. Accumulate text in chunks. Avoid repeatedly copying, parsing Markdown, highlighting, or laying out the complete growing answer. Reuse completed blocks and update the unfinished tail; large completed messages also need bounded rendering. Preserve scroll position when older pages load or the user scrolls away from the active answer. See [Flutter performance guidance](https://docs.flutter.dev/perf/best-practices).
4. In saved-history mode, persist the user message before sending. Checkpoint partial answers in batches, then mark completion atomically. Do not rewrite the transcript per delta. A 500-millisecond checkpoint interval is an initial measurement point with possible loss of the unpersisted tail after a crash. Recover unfinished messages as interrupted. Keep database maintenance off the UI thread and out of the per-token path; [SQLite checkpoints](https://sqlite.org/wal.html) can add latency.
5. Limit message bytes, total answer size, incomplete stream events, queued deltas, and tool results; apply equivalent limits to attachments if introduced. Apply backpressure where possible, or cancel explicitly if a bound is exceeded. Do not buffer indefinitely or label truncated output complete.
6. Start with one active generation per conversation and a small global concurrency limit. Cancel outstanding work on explicit cancellation and ignore late events from cancelled requests. Handle reconnects without duplicate messages. Mobile backgrounding must save permitted progress and tolerate interruption; do not assume continuous background execution.

Database storage alone cannot guarantee spike-free operation. Test synthetic long histories and individual oversized answers separately, including bursty streams, scrolling during generation, malformed events, cancellation, reconnects, quota failures, and background/resume. Measure UI frame times, peak process memory, retained heap, database latency, prompt preparation, and stream backlog. Set device-specific acceptance budgets; retained memory and pending work should plateau once configured limits are reached. Provider/network delays are separate from client responsiveness.

## Bounded model context

Build requests from stable application instructions, the selected skill and necessary references, a current approved snapshot, a bounded summary of older exchanges, relevant recent exchanges, and the current request. Do not send all saved history by default. Budget tokens against the selected model, reserving output/tool capacity and choosing a practical latency/cost target below its maximum context window.

Summarize bounded batches before the budget is exhausted, preferably between turns, while retaining original saved messages. Track which message sequence a summary covers so edits or deletions invalidate affected summaries. Preserve decisions and unresolved questions; retrieve relevant older exchanges only when needed. Keep tool calls and their results together. If preparation is incomplete, explicitly limit context or show that context is being prepared; never imply the model remembers omitted messages.

Summaries and previous assistant answers are conversational memory, never authoritative financial inputs. Obtain balances, goal progress, and valuations from a fresh approved snapshot. Preserve tracker identity, scope, as-of date, provider/model, and skill version with answers so historical explanations cannot masquerade as current reports. Reapply application rules and the selected skill after compaction; a summary cannot grant permissions or suppress data-quality warnings.

Provider-managed history, compaction, and prompt caching are optional adapter optimizations, not the canonical transcript or a substitute for limits. Do not assume provider-specific compaction state transfers to another model. See [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state), [prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching), and [Claude compaction](https://platform.claude.com/docs/en/build-with-claude/compaction). Summarization has its own cost and must follow the selected provider and approved data scope.

For local inference, bound context and concurrent requests in the model server too: its model weights and attention cache are outside Flutter's memory measurements. Avoid concurrent model loading merely to switch providers.

## Portable skills, controlled execution

Use the [Agent Skills format](https://agentskills.io/specification) for reviewed, versioned instructions: `SKILL.md` with metadata and optional reference files. Start with instruction-only workflows over calculated snapshots, such as explaining a spending change, portfolio valuation, or goal contribution. A skill does not implement finance calculations or establish data access.

Keep one authoritative source for each skill and package it for the relevant host. Use portable instructions and relative references; isolate host-specific invocation settings and tool names in packaging/configuration. Bundle app skills as assets rather than assuming a mobile filesystem layout. Discover compact descriptions first, load the selected instructions once per needed context, and include only relevant references. This [progressive disclosure](https://agentskills.io/client-implementation/adding-skills-support) keeps unused material out of requests.

| Host | Recommended integration |
| --- | --- |
| Flutter mobile | App selects a reviewed workflow and prepares the approved snapshot before calling the configured provider. No arbitrary skill scripts. |
| Companion-served web and Flutter desktop | Reuse the same instructions and app-controlled workflow through the companion route; no general-purpose script runtime. |
| Codex | Package for supported skill/plugin discovery; repository skills use `.agents/skills`. Configure the companion MCP connection separately. |
| Claude Code | Package for `.claude/skills` or a plugin, keeping Claude-specific extensions outside the portable core. |
| Antigravity | Current workspace discovery uses `.agents/skills`, with legacy `.agent/skills` support. Configure MCP separately. |

Verify host conventions when packaging: [Codex](https://learn.chatgpt.com/docs/build-skills), [Claude Code](https://code.claude.com/docs/en/skills), and [Antigravity](https://www.antigravity.google/docs/ide/skills/). Calling a provider model does not automatically load skills installed in its coding-agent product. Provider-native execution requires additional runtime configuration; [OpenAI shell skills](https://developers.openai.com/api/docs/guides/tools-skills) and [Claude API skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) are not required for the initial instruction-only workflows.

External agents obtain calculated data through the companion's narrow, read-only MCP tools. Skills explain how to use those results; MCP provides capabilities and data, not universal skill installation. The app's initial workflow supplies its snapshot directly without adding an autonomous tool loop. See [MCP server concepts](https://modelcontextprotocol.io/docs/2026-07-28/learn/server-concepts).

The app and companion enforce authentication, approved scope, expiry, and result-size limits independently of skill text. Never expose Google tokens, raw spreadsheet access, or generic database queries to a skill. Do not treat `allowed-tools` metadata as a portable sandbox: support varies, and some hosts use it to pre-approve tools rather than restrict other capabilities. Review updates, pin versions, and record the version used for an answer. Loading instructions cannot expand permissions or switch providers. External hosts may have other tools and retention policies outside the app's control.

## Delivery actions

1. When chat ships, implement bounded streaming, model context, and user-visible interruption states together; add local SQLite when saved history ships.
2. Validate long-history and oversized-message behavior on representative mobile, web, and desktop targets before claiming stable resource usage.
3. Add a small reviewed set of instruction-only skills over approved snapshots, with synthetic checks for missing/stale data and attempts to exceed scope.
4. Package those skills for external agents when the authenticated read-only companion ships. Keep vector databases, skill marketplaces, arbitrary script execution, and autonomous agent loops deferred until a concrete feature requires them.
