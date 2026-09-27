# Audit sweep — 27 September 2026

Scope: project source, shaders, build scripts, and documentation. Correctness, structure, and performance were audited in order, with fixes and a successful `build.cmd --prefix zig-out-dev` after each phase. No interactive game was launched.

## Correctness — five confirmed findings fixed

1. [math.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/math.zig:85): `sweep` returned no hit when a ray began strictly inside a box, unlike the ellipsoid cast. It now returns immediate contact with a finite outward normal; tests also preserve free departure from an exact surface.
2. [survivors.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/survivors.zig:250): contact damage used the distance calculated before enemy movement and could also cross a very thin wall. Contact now checks the moved position and an unobstructed path; regressions exercise both cases.
3. [main.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/main.zig:163): comparing frame-end HP suppressed hit sounds when life leech healed the same amount during that frame, and could falsely play a hit on restart. Damage now has an explicit `hits_taken` event counter, with restart excluded and a simultaneous damage/healing regression.
4. [survivors.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/survivors.zig:482), [render.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/render.zig:307): orbital visuals independently selected the nearest enemy without considering cover or projectile lead. Rendering now uses the actual firing direction stored by the simulation, verified with a nearer enemy hidden behind a wall.
5. [retro.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/retro.zig:272): dithering can produce negative luminance, which was passed into the amber filter's fractional `pow`. The input is clamped to zero; a dedicated combined-filter capture compiles and renders successfully.

Phase validation: 43 tests passed and the executable built. No confirmed correctness finding remains open; physical controller, fullscreen, cursor, and audible output still require hands-on verification.

## Structure — six groups of findings fixed

1. [survivors.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/survivors.zig:40), [icons.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/icons.zig:6): `upgrade_names`, `caps`, categories, gains, and the icon mapping depended on matching numeric enum positions. Upgrade metadata now comes from one exhaustive definition; counts/caps derive from it, and icons map by enum name instead of `+1` arithmetic.
2. [hud.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/hud.zig:13): HUD storage and rendering independently hardcoded four slots. Both now use `MAX_WEAPONS` and `MAX_SYSTEMS`, matching gameplay eligibility.
3. [choices.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/choices.zig:69): drawing and mouse picking separately encoded card positions, spacing, and dimensions. Both now use `rowRect`, including consistent rounding at odd window sizes.
4. [survivors.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/survivors.zig:10), [render.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/render.zig:268): enemy/XP flash durations, mine arming/fading/lifetime, radius growth, and bolt speed were repeated between behavior, visuals, descriptions, and scripted steering. Shared constants now keep those consumers aligned.
5. [retro.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/retro.zig:4), [menu.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/menu.zig:73): filter names, uniforms, defaults, preset indices, and option actions used parallel arrays and raw numeric dispatch. Filter metadata is keyed by enum; presets and menu rows use typed enums, derived counts, and a shared page-size helper. Persisted filter order is unchanged.
6. [build.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/build.zig:13): build help still described only a flight prototype and collision tests. It now describes the current game and verification scope; README and validation documentation include the audit and benchmark workflow.

Phase validation: 43 tests passed and the executable built. No material structural finding was intentionally deferred.

## Performance — two material findings fixed

1. [world.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/world.zig:208): every collision, clearance, and recovery query scanned all 572 station parts in the screenshot region. Cached station bounds now reject distant groups while preserving solid order and the unindexed fallback; tests compare 1,600 queries and recovery from every solid against the original scan.
2. [render.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/render.zig:15), [retro.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/retro.zig:79): rendering repeated eleven shader uniform-name lookups per filtered frame, plus two per active mine. Locations are now resolved at renderer creation and refreshed naturally on recreation.

[benchmark.zig](C:/Users/DavidBennett/Desktop/projects/tests/freespace-survivors/src/benchmark.zig:8) supplies a bounded CPU-only `--bench` mode. In Debug on this machine, the median over five 600-tick dense-swarm runs fell from **3.770 to 0.833 ms/tick** after collision grouping: approximately 78% less simulation time. Both versions produced 249 kills and 83 shots; these numbers do not measure rendering FPS.

The bounded 192-enemy neighbor scan and tiny arithmetic costs were left unchanged. A dynamic spatial index, mesh partitioning, and GPU tuning need separate evidence to justify their added complexity.

## Final verification

- `check.cmd` and the final development build passed.
- `test.cmd --summary all`: **44/44 passed**.
- `shot.cmd`: **42 captures**, menu actions, and renderer/world recreation passed.
- Fresh weapon deployment, tiered choices at 960×540, retro menu, and amber/dither captures were visually inspected; no regression was observed in those views.
- Scripted progression remains 41.6 seconds, 29 kills, 60 XP, and five HP at the first upgrade.
- Updated executable: `zig-out-dev/bin/freespace-survivors.exe`. The alternate prefix avoids replacing the normal executable while it is in use.
