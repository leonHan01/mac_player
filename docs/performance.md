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
