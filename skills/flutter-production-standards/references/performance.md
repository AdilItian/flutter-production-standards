# Performance

Read when: building lists, image-heavy screens, animations, large payloads, startup code, or when a screen janks. **Measure before optimizing**: profile mode on a real mid-range device, DevTools Performance and CPU views. Never trust debug-mode numbers.

Budget: 60/120 fps means ≤16 ms/8 ms per frame for build + raster. Cold start to first interactive frame: aim < 2 s on a mid-range device.

## Rebuilds

| Do | Why |
|---|---|
| `const` constructors and `const` widget instances everywhere possible | Identical const widgets are skipped during rebuild; zero allocation |
| Extract subtrees into their own widget **classes** | A class has its own `Element`; a parent rebuild can skip a const child. Helper methods rebuild with the parent |
| Push state consumers down the tree | Rebuild only the part that changes |
| Subscribe to slices (`select`, `BlocSelector`, `buildWhen`, small `Obx`) | A list-length change should not rebuild the whole screen |
| Keep `setState` scopes tiny and local | |
| Read `MediaQuery.sizeOf(context)`, `Theme.of(context)`-derived values narrowly | `MediaQuery.of` rebuilds on every metric change (keyboard, insets) |
| Pass stable callbacks/objects to children | New closures/lists every build defeat equality-based skipping in some widgets |

Never: create `Future`/`Stream`/controllers in `build`; do heavy computation (sorting, parsing, formatting large lists) in `build`; call `setState` in a loop; listen to a whole provider/bloc when you need one field.

## Lists and scrolling

- `ListView.builder` / `SliverList.builder` / `GridView.builder` for anything not tiny. Never `Column` inside `SingleChildScrollView` for unbounded data.
- Provide `itemExtent`/`prototypeItem` when rows are uniform (skips layout work).
- Stable `ValueKey(id)` for items that reorder/insert.
- Avoid `shrinkWrap: true` on large lists (forces measuring all children); use slivers (`CustomScrollView`).
- Keep item widgets cheap: no `Opacity`, `ClipRRect` + `saveLayer` stacks, or per-item shadows with large blur; use decoration properties and precomputed styles.
- Preload nothing eagerly; tune `cacheExtent` only when profiling says so.
- `AutomaticKeepAliveClientMixin` sparingly (tabs with expensive state).

## Pagination and lazy loading

Load on demand with a threshold trigger (`networking.md`); page size 20-50; show a footer loader; dedupe; cancel on dispose. Lazy-load heavy screens/tabs (build when first visited; `IndexedStack` keeps every tab alive, so use it knowingly (the tab shell in `routing.md`)). Defer-load large optional modules with deferred components on Android / `deferred as` imports for web when bundle size matters.

## Images

- Network: always through `AppNetworkImage`, which wraps `cached_network_image` with a sized skeleton, a failure state with retry, and decode at display size (`ui-guidelines.md`, "Network images"). Never `Image.network` in feature code. Set a disk cache limit in `core`.
- Decode at display size: set `cacheWidth`/`cacheHeight` (or `ResizeImage`) to the rendered pixel size × device pixel ratio. Full-resolution decoding of a 12 MP photo into a 48 dp avatar wastes ~48 MB.
- Ask the server for the right size/format (width param, WebP/AVIF) rather than shipping originals.
- Assets: WebP for raster, SVG/vector_graphics for icons, compress PNGs, no 4K assets for 100 dp slots. Provide density variants only when needed.
- Reserve space (`AspectRatio`, fixed size) so loading does not shift layout.
- `precacheImage` only for the next likely screen's hero image.
- Dispose large images/video controllers when leaving the screen.

## Caching (data)

Cache with keys, TTL, size bound and clear-on-sign-out (`networking.md`). Memoize expensive pure derivations (providers/`select`, `Selector`) instead of recomputing per build. Avoid caching entire responses in memory unboundedly.

## Heavy work off the UI thread

- `Isolate.run(() => parse(bytes))` for JSON > ~50-100 KB, image processing, encryption, big sorts/filters. `compute` is the older equivalent.
- Isolates cannot touch plugins/UI; pass plain data in and out (sendable types) and keep results small.
- Never block with synchronous file I/O or `jsonDecode` of megabytes on the main isolate.

## Animations and rendering

- Use implicit animations (`AnimatedContainer`, `TweenAnimationBuilder`) first; explicit controllers dispose properly (`SingleTickerProviderStateMixin`).
- Animate with `AnimatedBuilder`/`child` parameter so the static subtree is not rebuilt per frame.
- Prefer transforms/opacity on `RepaintBoundary`-isolated layers; avoid animating layout-affecting properties on big subtrees.
- `RepaintBoundary` only where profiling shows repaint of a large region caused by a small animated part.
- Avoid `saveLayer` triggers: `Opacity` on large trees (use `FadeTransition`/color alpha), `ShaderMask`, `BackdropFilter`, clip with anti-alias on complex paths. Check "Highlight repaints/Raster cache" in DevTools.
- Respect reduced motion: `MediaQuery.disableAnimationsOf(context)`.
- Impeller is the default renderer on current Flutter; shader jank guidance from Skia days (warm-up) is mostly obsolete. Verify on target devices.

## Memory

- Cancel `StreamSubscription`s, `Timer`s, `AnimationController`s, `TextEditingController`s, `FocusNode`s, `ScrollController`s in dispose (or use state-holder lifecycle hooks).
- Don't capture `BuildContext` or large objects in long-lived closures/singletons.
- Bound caches (LRU) and image cache (`PaintingBinding.instance.imageCache.maximumSizeBytes`) for image-heavy apps.
- Watch for leaks with DevTools Memory (snapshots before/after navigating in and out of a screen); `leak_tracker` in tests for widget leaks.

## Startup

- Keep `main()`/`bootstrap` minimal: bindings, env validation, error hooks, then `runApp`. Initialize non-critical SDKs (analytics, remote config, push token) **after** the first frame (`WidgetsBinding.instance.addPostFrameCallback` / unawaited init).
- Keep the native splash until the first meaningful frame (`flutter_native_splash`); avoid a Dart-side splash that waits on network.
- Don't read large files, open databases with migrations, or parse big JSON before `runApp`.

## Build size

`flutter build apk --split-per-abi` or App Bundle; `--obfuscate --split-debug-info`; tree-shake icons (default in release); remove unused assets, fonts and dependencies; check with `--analyze-size`.

## Network performance

HTTP/2, gzip/br, conditional requests (ETag), field selection, batching, prefetch on likely next screens, avoid request waterfalls (parallelize independent calls with `Future.wait`), debounce search, cancel obsolete requests.

## Checklist before declaring a screen done

- [ ] Profile mode, scroll/transition: no dropped frames on a mid-range device
- [ ] Rebuild counts reasonable (DevTools "Track widget rebuilds") for the primary interaction
- [ ] Lists are builders, with keys
- [ ] Images sized and cached
- [ ] Everything disposable disposed
- [ ] No work in `build`
