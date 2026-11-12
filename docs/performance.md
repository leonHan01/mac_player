# Performance measurements

Measured on 2026-09-12 with Swift 6.3.3, arm64 macOS, using production code compiled with `swiftc -O`. Each timing is the median of five runs. Fixtures are created before timing and removed afterwards; compilation is excluded.

| Scenario | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Scan 2,000 files and prepare name/size orders | 61.26 ms | 53.79 ms | 12% |
| Collect eight shared tags across 10,000 records | 29.67 ms | 3.49 ms | 88% |
| Collect tags for a folder containing those 10,000 records | 69.15 ms | 38.97 ms | 44% |
| Collect tags for 10,000 files with an empty tag database | 34.64 ms | <0.01 ms | Full traversal eliminated |
| Polls to process 100 queued playback-property events | 200 | 101 | Empty polls reduced from 100 to 1 |

The scanner reuses natural-name ranks when sorting by size. Equal-sized videos retain natural filename order. Tag collection streams values and skips exact duplicates before trimming and case conversion, preserving the first spelling and localized ordering. An empty database returns immediately.

Playback wakeups share one queued drain per engine. Drains process at most 64 events before scheduling another batch, allowing other main-actor work to run. The pending flag clears before draining so events arriving during processing can schedule another pass.

Reproduce with:

```sh
python3 scripts/benchmark-performance.py
python3 scripts/test-regressions.py
```

The benchmark is a synthetic workload, not a playback FPS, decoder CPU, or memory measurement. Scanning depends on filesystem caching, file counts, and names; tag collection gains depend on repeated tags and folder size. The event check uses a fake libmpv client and does not create a renderer or decode media. Existing hidden-window input checks were skipped because this environment could not provide an OpenGL pixel format.

## Playlist improvements — 2026-10-22

Measured with Swift 6.4 on arm64 macOS, using `swiftc -O` and the median of five samples. The selected video sits halfway through a synthetic 10,000-row playlist. The before and after timings use the same benchmark and model operations; fixture creation and compilation are excluded.

| Scenario | Before | After |
| --- | ---: | ---: |
| Switch cached sort order while retaining the current video | 15.22 ms | 0.29 ms |
| Reapply an all-matching filter to unchanged rows | 15.39 ms | 0.37 ms |
| Content invalidations per unchanged filter operation | 1 | 0 |

`PlaylistState` first looks up the existing URL directly. URLs coming from the same scan normally match without repeatedly constructing standardized paths; an explicit URL containing `../` still uses the existing normalized-path fallback. Filtering and sorting now increment the content revision only when row membership or order changes. `PlayerView` uses that revision to decide whether to reload the whole table, while filter controls, sort controls, and selection still update independently.

The filter benchmark uses an always-matching closure to isolate playlist rebuilding; it does not include tag lookup or AppKit drawing. Avoiding a table reload is verified through the production content revision, not a rendered UI timing. Two post-change runs produced sort medians of 0.16–0.29 ms and unchanged-filter medians of 0.37–0.38 ms; filesystem and tag-load measurements varied more with machine conditions. These figures are not claims about playback FPS or overall launch speed.

Regression checks cover retained selection, equivalent path spellings, unchanged filtering, actual membership changes, one-row sorting, restoration of a full sorted list, and existing deletion/loading races. Run `python3 scripts/test-regressions.py`; the checks pass, with hidden-window UI checks skipped when OpenGL is unavailable. No player window or media decoder was started for this investigation.

## Seek input pacing — 2026-10-22

The user reported stutter while dragging the timeline and repeatedly seeking forward/backward. The command queue previously coalesced seeks only while waiting for a command reply. A reply confirms command acceptance; it does not mean the decoder has finished locating the target frame. With immediate replies, every input update could therefore submit another exact seek.

A deterministic check against the production `MPVCommandQueue` reproduced 100 submissions for 100 input updates with replies between them. The queue now applies a 100 ms cooldown independently of reply latency: the first target goes through immediately, later updates replace the pending target, and the timer delivers the latest target. In the same synthetic burst within one cooldown window, only two commands are submitted, including the trailing target. This is a command-count measurement, not a playback speedup or frame-rate measurement.

Mouse release and left/right-arrow release flush the final target without waiting for the cooldown, subject to the existing in-flight command ordering. In version 1.0.1 all submitted targets retained `absolute+exact` positioning; the interactive-preview change below builds on this pacing. The displayed position updates immediately; progress refreshes cannot overwrite the slider throughout mouse tracking. Timers run in common run-loop modes so they continue during slider tracking. Loading another file or stopping discards deferred seeks, and shutdown cancels scheduled work.

Regression checks cover immediate replies, delayed replies, trailing targets, release flushing, control commands, cancellation, and file changes through the fake-libmpv playback engine. Existing first-drag, stale-position, paused-seek, failure, and load-order checks remain in place. Run `python3 scripts/test-regressions.py`. No real video was decoded and no player was launched; hidden-window UI checks remain skipped where an OpenGL pixel format is unavailable. Single-seek latency and the reported MP4 backward-seek issue still require a reproducible media sample.

## Startup tag normalization reuse — 2026-10-22

The synchronous tag-store load normalized and sorted every file's tag array independently, even when thousands of files had identical tags. `TagStore.load` now reuses the normalized result for identical raw arrays within that load. The temporary cache is limited to 256 combinations and is released when loading finishes; it does not retain a new cache for the lifetime of the player. Distinct arrays retain their own spelling and normalization rules.

Measured with the same optimized production-code harness and five-sample medians:

| Scenario | Before | After |
| --- | ---: | ---: |
| Load 10,000 records sharing eight tags | 74.36 ms | 36.45 ms |
| Load 10,000 records with distinct combinations (eight shared tags plus one unique tag) | 83.00 ms | 85.78 ms |
| Read/decode 10,000 shared-tag records without normalization, for comparison | 34.29 ms | 33.84 ms |

The shared-combination case takes about 51% less time. Distinct combinations do not benefit and incur a small cache-lookup cost; these synthetic fixtures do not establish overall app-launch speed or playback FPS. An initial after-change run overlapped regression compilation and raised unrelated scan timing to 101.54 ms, so the reported after-change figures come from a separate run without that competing job. Regression checks exercise shared and distinct arrays, whitespace/case normalization, first spelling, unchanged on-disk data after loading, and independent edits followed by reopening. The existing damaged-database write protection and asynchronous-save checks still pass. Hidden-window UI checks were skipped because an OpenGL pixel format was unavailable; no player or real media decoding was launched.

The benchmark now also measures the actual tag-match closure used by the controller and explicit-file scanning. Applying a tag filter across 10,000 tagged records takes 39.97 ms, whereas the earlier always-matching filter fixture takes 0.31 ms: the earlier figure isolates playlist rebuilding and excludes tag lookup/comparison. Preparing a specified video in a 2,000-file folder takes 53.53 ms versus 47.97 ms for folder scanning. These measurements identify remaining work below; they are not claims that those operations have been optimized in this change.

## Playback open, switch, and drag path — 2026-10-22

The user's focus is video opening, switching, and seeking. Version 1.0.3 changes those paths directly:

- **Open the selected file before scanning its siblings.** The scanner validates an explicit local file on a worker and publishes a one-file playlist. The controller starts playback immediately after that validation, then continues enumerating and sorting the directory in the background. Folder opens still require a complete scan to choose their first video. Background expansion preserves the selected video and does not send a second load to the decoder; playback controls remain usable while the list fills. Filtering is enabled after the complete list arrives. A replacement request cancels the obsolete scan; failed scans preserve the selected file; deletions during scanning are excluded from the expanded list.
- **Preview keyframes during a gesture; seek exactly on release.** Slider tracking and repeated arrow-key input use `absolute+keyframes` under the existing 100 ms pacing. Mouse/key release or window focus loss replaces any deferred preview with one `absolute+exact` command to the final target. Single arrow presses and other discrete seeks remain exact. Preview positions do not replace the displayed target, paused playback stays paused, and file changes/stop discard the gesture state. This follows [mpv's documented distinction between fast keyframe seeks and precise seeks](https://mpv.io/manual/stable/#command-interface): precise seeks may need to decode forward from an earlier keyframe. Preview images can therefore differ from the requested position until release.
- **Remove redundant settings from file switches.** The controller no longer resends unchanged volume/mute before every start. The engine initializes those values before its first load, preserves subsequent changes, and submits only `loadfile` plus resume for each load, instead of its former four-command sequence. The existing engine and render context continue to be reused. Hardware decoding was already configured as `auto-safe`; this change does not claim that hardware decoding is active for every codec.

In the same optimized, five-sample benchmark with a 2,000-file directory, the new single-file validation takes **0.02 ms**, compared with **55.18 ms** for preparing the full sibling list. The full scan still happens; it has been removed from the work that must complete before playback is requested. These figures exclude libmpv initialization, decoding, rendering, and time to the first displayed frame.

The regression harness first failed on `An explicit video must reach playback before its sibling-folder scan finishes`. It now passes with that scan deliberately blocked. Tests reach the controller's unattached-renderer boundary to record playback attempts without opening a renderer, and confirm no restart when the list expands. Additional checks cover replacement, failure, deletion during expansion, latest sort choice, keyframe/exact command flags, paused and discrete seeks, rejected previews, repeated releases, gesture cancellation on file changes, initial audio options, and two-command loading/switching through fake libmpv. Run `python3 scripts/test-regressions.py`; core checks pass, with hidden-window UI checks skipped for unavailable OpenGL. No real player or decoder was started. Actual codec-specific first-frame, seek latency, dropped frames, and CPU/GPU usage remain unmeasured.

## Playback-control responsiveness — 2026-10-29

Version 1.0.4 reduces repeated UI work while handling playback events. Wakeups were already coalesced, but each property event still notified the UI individually. A replay of 100 queued progress events while paused produced **100 progress callbacks** before the change and **2 callbacks** afterwards; 100 changing volume events now produce **2 state callbacks**. Every event still updates the cached engine state. Notifications and the pause-dependent timer update are applied once at the end of each bounded 64-event drain, preserving the latest values and yielding between batches. Direct seek/play/pause input and load/EOF notifications remain synchronous.

Ordinary pause/volume/mute notifications now refresh playback controls without repeating the empty-state text, layout, and navigation-control work. Transitions into or out of active media still update the full presentation. Volume images are rebuilt only when the icon changes (muted, low, or high), with the cache reset on language changes; unchanged slider values are not assigned again. These AppKit changes were compiled and inspected, but not measured with a rendered window.

`python3 scripts/test-regressions.py` first failed with `100 paused progress events triggered 100 UI refreshes; notify once per drain batch`. It now passes, checking final positions/volume, alternating pause bursts, timer stop/resume, synchronous seek feedback, shutdown from an observer, and events arriving during callback delivery. Earlier file-opening, switching, and seek regressions also pass. Hidden-window UI checks were skipped because an OpenGL pixel format was unavailable. This is a callback-count measurement using fake libmpv, not an FPS or input-latency measurement; no real player or media decoder was launched.

## Further opportunities, not implemented

1. **Seek diagnostics and recovery.** In `Sources/MacVideoPlayer/MPVPlayback.swift`, a rejected seek only clears the pending target, and a successful command starts a fixed five-second recovery timer. The UI cannot distinguish a rejected command from an engine that is still locating or decoding the target. Add explicit seek/error diagnostics and engine completion state before changing compatibility behavior. The previously reported MP4 backward-seek problem still needs a reproducible media sample; this investigation does not claim to fix it.
2. **Move tag loading off the main actor.** `TagStore.init` still synchronously reads and decodes the entire JSON store before the main window is created. After normalization reuse, loading 10,000 shared-tag records takes 36.45 ms, of which read/decode alone takes 33.84 ms; distinct tag combinations take 85.78 ms. A background initial load could shorten the work blocking startup; it must preserve the current write protection on load failure and prevent edits from racing initialization.
3. **Avoid repeated tag lookup during filtering and sorting.** The controller's real tag-match closure takes the 10,000-record filter from the isolated 0.31 ms rebuild to 39.97 ms. Investigate reusable matches or an index for the active tag and store revision. Preserve equivalent path spellings, case-insensitive comparison, legacy file-ID tags, committed-save invalidation, and selection. This has not yet been implemented.
4. **Measure the decoder/render path with representative media.** Opening and seeking a real slow sample is still needed to distinguish decoder initialization, unsupported hardware decoding, long keyframe intervals, and rendering stalls. The current headless tests verify command/lifecycle behavior, not playback frame rate or actual seek latency. Preserve image quality and frame accuracy when evaluating engine options.
