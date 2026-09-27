# Validation

Verified on 27 September 2026 with Zig 0.14.1 and the pinned raylib package.

- check.cmd: executable and test roots compile.
- test.cmd --summary all: 44 tests pass. Coverage includes forward-only laser fire, mine arming/area damage/cover/expiry, rocket arcs and target reacquisition, orbital fire and clearance, four-slot limits, freely chosen systems, shared stat effects, fractional leech without overkill or healing storage, weapon pause/reset, and slower opening pursuit. Existing flight, world, combat, input, and settings checks remain passing.
- Audit regressions cover interior ray origins, updated contact positions and thin-wall occlusion, same-tick damage/healing feedback, orbital aim, and 1,600 indexed/unindexed collision comparisons plus recovery inside every generated solid.
- Tier tests verify the 60/25/12/3 distribution, Rare acquisitions, increasing gains, exact description/application agreement, fixed offers while choosing, and critical-chance cap handling.
- build.cmd --prefix zig-out-dev: updated executable installed. The normal zig-out executable was locked; close the running game and use run.cmd to rebuild that location.
- shot.cmd: 42 deterministic captures complete in a hidden window. Shader compilation, all four retro presets, All off, amber plus dithering, all filter menu pages, minimum-size menus, hull feedback, new weapons, equipment icons, tiered choices, and renderer/world replacement succeed.
- Dense CPU benchmark, Debug build on this machine: median 3.770 ms/tick before station collision grouping, 0.833 ms/tick afterward, each over five runs of 600 ticks. Both produced 249 kills and 83 shots. This measures simulation cost, not rendering FPS.
- The progression flight uses ordinary run health, weapon damage, rewards, and XP requirements with scripted steering toward enemies while moving to collect XP. It earns its first upgrade at 41.6 seconds, with 29 kills, 60 XP, and five HP remaining. This scripted flight is a regression check, not a prediction of human leveling time.
- Visually inspected generated station variants, planets, the asteroid field, the XP bar, retro presets, filter menu pages, and the alternate-seed region. Planet/asteroid surfaces are real scene meshes and share collision with gameplay; the previous sky-only planet is gone.
- Inspected fresh hit feedback and HP-bar captures at critical and reinforced hull, plus 960×540 with CRT filtering. The bar stays below the ship and remains readable above the scene filter; damage flashes, the fading lost-health segment, and impact sparks are visible.
- Inspected weapon deployment, mine fade and group detonation, shared icons on HUD/choices, all tier colors and text, Rare unlocks, and full equipment at 960×540. Reduced large blast cores after the first capture obscured too much of the nearby ship.
- After the audit, inspected fresh weapon deployment, tiered choices at 960×540, the retro menu, and amber plus dithering. No visual regression was observed in these captures.
- Hidden menu checks exercise option adjustment, back/resume, restart, quit, Retro filters entry, CRT preset selection, and All off.
- Debug world/run temporaries exceeded Windows' default 1 MiB stack during a longer progression capture. The executable and tests now reserve 8 MiB, matching the explicit-stack approach used by the adjacent soulslike project.

Physical controller input, OS fullscreen transitions, real cursor capture, and listening quality still need hands-on verification. No interactive game was launched for automated verification.

Balance and sustained human play still need playtesting. Hunters, turrets, caches, and exploration rewards remain future work.
