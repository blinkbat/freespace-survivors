# Freespace Survivors

- Windows/PowerShell: `login: false`, UTF-8 without BOM; use targeted patches.
- Read `docs/RESEARCH.md` and `README.md` before changing scope. Owner explicitly requested the actual Survivors loop; flight alone is not the deliverable.
- Owner: this is VS, not a flight sim. Movement is the only active task. No boost, braking, roll, drift, or throttle controls; stopping is automatic on release. Cosmetic banking only.
- Owner requested minimal HUD: XP bar, HP bar below ship, and compact weapon/system slots with shared icons and ranks on HUD and level-up menus. No entity labels or damage numbers. Pause/options, retro filters, upgrade selection, and death/restart are authorized; brief flashes and particles provide feedback.
- Current build rules: start with a fast forward-firing laser and NO installed systems. Four weapon slots including laser, four freely chosen system slots. Attack damage and HP are optional level-up systems alongside crit, move speed, attack rate, and life leech. Opening foes are slower than base flight after the owner rejected faster opening pursuit.
- Start menu selects Space or Jungle Ruins; restart preserves the level. Jungle shares the survival loop, with collidable terrain/water and a 215m ceiling. Use World.spawn/boundaryCenter/boundaryRadius rather than space constants in shared gameplay.
- Retro filters start off and are session-only. Never serialize filter intensities; retain persisted controls/display/audio preferences.
- Tiered choices show exact gains and tier text: Common white, Uncommon light blue, Rare magenta, Legendary gold. New item acquisitions are always Rare; equipped-item upgrade tiers currently roll 60/25/12/3 percent. Keep descriptions and applied gains on the same data path.
- Foundation: Zig 0.14.1 and pinned raylib-zig from adjacent `zig-soulslike`. Keep this project independent of sibling source files.
- Use `check.cmd` while editing, `test.cmd` for physics contracts, then `build.cmd` and `shot.cmd`. Never start an interactive window for automated verification.
- Keep screenshot mode bounded and deterministic; capture before `endDrawing`. Inspect the PNGs before claiming a visual change works.
- Flush `rlDrawRenderBatchActive` before `loadImageFromScreen` so pending geometry appears in captures. Batch scripts call helpers by `%~dp0` paths on this machine.
- No commits, branches, or pushes unless requested. Keep machine learnings here succinctly; design belongs in docs.
- Windows Debug builds need an explicit stack reserve for bounded world/run temporaries; 8 MiB is set in build.zig. The default 1 MiB exhausted during the longer progression screenshot simulation.
