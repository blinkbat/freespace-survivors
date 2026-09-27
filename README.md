# Freespace Survivors

Vampire Survivors, but you fly through space or the ruins of an alien jungle.

**Current milestone: weapon builds.** Fly through pursuing drone flocks while your weapons fire automatically. Start with a forward laser, collect XP, and build a loadout of mines, homing rockets, orbital drones, and systems. Flocks grow over time, contact damages the ship, and destruction ends the run. The native Zig prototype includes solid industrial structures, lighting, and a camera that avoids walls.

## Play

Double-click `run.cmd`, or run it from PowerShell:

```powershell
.\run.cmd
```

This builds and launches `zig-out/bin/freespace-survivors.exe`. The scripts use the installed adjacent Zig 0.14.1 toolchain. The pinned raylib dependency is already cached on this machine; a clean machine needs network access for its first build.

| Input | Action |
| --- | --- |
| Mouse | Turn; point up or down to climb or descend while moving |
| W / S | Move forward / backward |
| A / D | Move left / right |
| Release movement | Stop immediately |
| Esc | Open pause menu; go back / resume |
| Tab | Lock / unlock mouse |
| Right mouse, while unlocked | Hold to turn |
| Alt+Enter or F11 | Toggle fullscreen |
| Arrows / Enter | Navigate menus and select; left/right adjusts options |
| 1 / 2 / 3, during a level-up | Choose an upgrade |
| Enter, after destruction | Start a fresh run |

The start menu offers Jungle Ruins, Space, Options, and Quit. The pause menu has Resume, Options, Restart, Main menu, and Quit. Restart stays in the current region with a fresh seed and loadout. Options include fullscreen, mouse lock, mouse/controller sensitivity, inverted look Y, stick deadzone, volume, and Retro filters. Mouse clicks also select entries; use the option arrows to decrease/increase values. Controls, display, and audio preferences save to `settings.json` in the project folder. Menus release the mouse, then restore your chosen capture setting when play resumes. Losing window focus pauses automatically.

Retro filters are adapted from the adjacent soulslike project: fifteen adjustable effects, PS1/CRT/VHS/Game Boy presets, Restore defaults, and All off. Use left/right or the on-screen arrows to adjust strength; use up/down or the mouse wheel to reach all three pages. Changes preview on the paused scene and last only for the current session. Every launch starts with all filters off; old saved filter values are ignored and removed on startup. The XP and HP bars and menus remain clear above the filters.

Controllers use the left stick to move and the right stick to turn. Start/Menu pauses; D-pad or left stick navigates menus and upgrades; A (south button) confirms and B (east button) goes back. A also restarts after destruction. Controllers can connect during play; disconnecting the active controller pauses. The first available controller is used.

Movement responds immediately, with no boost, braking button, roll, drift, throttle, or firing controls. The ship banks visually; its horizon stays stable. Steering also points the forward laser. Support weapons attack automatically around the ship. The optional move-speed system increases your normal movement speed.

## Survive and grow

Both regions use the same automatic weapons, wave progression, XP, and upgrades. Jungle Ruins spans a roughly 2.8 km playable region with an uneven triangulated surface, a winding river, 280 giant banyans with aerial roots, ferns, twelve ruin sites, and half-submerged river pillars. Monumental arches, stepped temples, standing stones, and alien guardian statues carry glowing runes. A procedural sky includes haze, clouds, sun, and an alien moon. The ship eases into a 215m world-height ceiling; terrain, water, ruins, and trunks block movement and projectiles. Canopies and thin hanging roots are visual cover that can be flown through. Space retains its original larger region, planets, asteroids, and industrial structures.

The opening flock approaches from 120 metres ahead; later flocks form around 185–225 metres away and converge on you. Your starting laser fires straight ahead every 0.16 seconds, even without a target. Its base critical chance is 25%, compared with 5% for support weapons; critical hits deal double damage and laser critical bolts glow gold. Bolts travel through the world, hit drones, and stop at walls. Move through the glowing crystals left by kills; nearby crystals fly toward you, but do not pass through walls.

The run opens with six drones, followed by four-drone flocks every six seconds. Opening drones take two normal laser hits. Every 30 seconds of active survival time starts a tougher wave with extra reinforcements: newly spawned drones gain two health, move faster (up to a cap), and arrive in larger, more frequent groups. Regular flocks grow by two drones per wave, up to 24; their interval falls toward 1.4 seconds. Wave colors cycle coral, gold, violet, and blue; existing drones retain their original color and strength. Tougher drones drop more XP. Pausing and choosing upgrades freeze the wave clock.

Opening drones reach 40.5–43.5 metres per second against the ship's 46. Later waves add 0.8 metres per second per wave, reaching a base cap of 50 plus the same small individual variation. Drones carry momentum through turns, so sharp changes of direction can make them overshoot.

The thin green bar at the top tracks XP toward the next upgrade. The first upgrade costs 60 XP (previously 6); subsequent costs are 96, 144, 204, and continue growing quadratically. Drone rewards cap at five XP so later waves do not overwhelm that curve.

Fresh runs start with the laser and **no systems**. There are four weapon slots, including the laser, and four system slots. All six systems are initially available; choose any four. Once a category fills, its new items stop appearing while upgrades to installed items remain available. Capped upgrades leave the pool; excess XP carries into the next level. Choose with 1, 2, or 3, mouse, or menu navigation controls.

| Weapon | Behavior |
| --- | --- |
| Laser | Fast, forward fire with higher critical chance; always equipped |
| Proximity mine | Launches sideways and behind every 2.4 seconds, settles and arms after 0.7 seconds, triggers within 12m, and damages visible foes in a 20m radius; unused mines fade out between 8 and 9 seconds |
| Homing rocket | Two rockets launch in wide arcs every 3.6 seconds, then home toward nearby foes; 8 base damage each, a small blast, and a six-second lifetime |
| Orbital drone | Circles the ship and fires at visible foes every 0.65 seconds; upgrades add damage and another drone, up to three |

Damage, critical chance, attack rate, and life leech affect every weapon. Mines and rockets respect solid cover. Weapon ranks improve mine blast radius and rocket launch cadence; attack-rate systems shorten all firing intervals. Life leech accumulates fractional healing from actual damage dealt, excludes overkill, and cannot store healing at full HP.

New weapon and system acquisitions are always **Rare**. Upgrades to equipped items roll Common (white, 60%), Uncommon (light blue, 25%), Rare (magenta, 12%), or Legendary (gold, 3%). The choice screen shows each tier by name and color, with its exact stat gain. System gains accumulate as follows:

| System | Common | Uncommon | Rare | Legendary |
| --- | --- | --- | --- | --- |
| Attack damage | +10% | +20% | +35% | +60% |
| HP, with full repair | +1 | +2 | +3 | +5 |
| Crit chance | +2% | +4% | +7% | +12% |
| Move speed | +1 m/s | +2 m/s | +5 m/s | +10 m/s |
| Attack rate | +5% | +10% | +18% | +30% |
| Life leech | +1% | +2% | +3% | +5% |

Damage and attack-rate bonuses add against their base values. Critical bonuses are percentage points, capped at +60 points; a choice near the cap shows only its remaining effective gain. Weapon upgrade damage also scales by tier. The two small HUD rows show four weapon slots and four system slots, using the same icons as level-ups, plus each item's rank.

Enemy contact costs one hull point, with a short grace period before another hit. A compact HP bar below the ship changes from teal to amber to red as hull falls, briefly highlighting lost health. Damage flashes the ship white fading to orange, adds a subtle red pulse at the screen edges, and releases short impact sparks. Struck drones flash ivory. XP collection flashes the ship green and releases a few fading motes; upgrades add a slightly larger particle burst. These effects light nearby metal. Low hull emits smoke, and explosions, pickups, and upgrades have synthesized sound cues. There are no damage numbers, entity labels, or markers. Destruction ends the run; Enter resets enemies, XP, weapons, systems, and hull, and generates a new region. Runs currently continue until destruction.

## Region

The Kestrel Expanse is roughly 7.2 kilometres across. Each fresh run generates 20 industrial stations, three solid planets, and clustered asteroids. Placement avoids overlapping planets and stations and keeps the launch area clear. The screenshot seed contains 90 asteroids; counts vary with the generated layout.

Stations combine broken octagonal trusses, canted radiator wings, unequal refinery stacks, offset service booms, asymmetric drydocks, and suspended cargo. Heights, lengths, positions, yaw, pitch, and roll vary by seed. Shared transforms keep rendered parts and their collision aligned.

Planets and asteroids are physical world geometry: fly around their surfaces, use them as cover, or thread gaps in the asteroid clusters. Swept ellipsoid collision keeps the ship, camera, drones, bolts, and XP attraction outside them. Faceted asteroid surfaces use conservative ellipsoid collision envelopes.

Outward movement tapers off beyond 3,600 metres from the region center; returning stays responsive. The chase camera sits about 29 metres behind/above the ship and moves inward around obstructions. Bumps cause no damage. The three planets use procedural surface colors and polar caps; the old sky-painted planet has been removed.

## Playtest

Collect several flocks' XP before the first upgrade, then keep circling back for crystals while new flocks approach. Use stations, planets, and asteroids to break pursuit, but remember that solid objects also block your laser. Staying in open space makes collecting easier and exposes you to more approach directions.

Judge whether collecting XP is worth turning back into the swarm, whether upgrades are noticeable, and whether movement leaves enough attention for the enemies. Automated checks verify the loop but do not establish that the balance is fun.

## Development

```powershell
.\check.cmd             # type-check executable and tests
.\test.cmd --summary all
.\build.cmd
.\shot.cmd              # hidden window, flight and combat captures, exits automatically
.\zig-out\bin\freespace-survivors.exe --bench # bounded CPU benchmark; no window
```

Screenshots are in `shots/`: generated stations, planets, asteroids, an alternate region seed, live combat, an earned upgrade, a dense swarm, restart, laser fire, wave colors, pause/options, XP/hit feedback, retro presets, All off, and each filter menu page. The combat/progression captures advance the real simulation; the harness fails if the scripted flight does not earn a level-up. Menu actions are also exercised in the hidden window. `shot.cmd` installs to `zig-out-shot` so it can run while the normal game is open. Build elsewhere with `build.cmd --prefix zig-out-dev` if the normal executable is locked.

The source is independent of sibling repositories. It adapts the Zig/raylib setup, procedural mesh Builder, shadow framebuffer, and shader conventions from `../zig-soulslike`. See [technical provenance](docs/FOUNDATION.md).

| File | Responsibility |
| --- | --- |
| `src/main.zig` | Input, fixed simulation ticks, focus/pause, screenshot harness |
| `src/controls.zig` | Controller detection, radial deadzones, menu navigation input |
| `src/menu.zig` | Pause/options screens, saved preferences, fullscreen transitions |
| `src/flight.zig` | Movement, collision response, camera, behavior tests |
| `src/survivors.zig` | Flocks, targeting, bolts, XP, upgrades, damage, death |
| `src/choices.zig` | Separate upgrade-selection and restart screens |
| `src/hud.zig`, `src/icons.zig` | Compact equipment slots and shared weapon/system glyphs |
| `src/rarity.zig` | Tier colors, labels, and weighted rolls |
| `src/benchmark.zig` | Deterministic dense-swarm CPU benchmark |
| `src/audio.zig` | Synthesized firing, explosion, pickup, upgrade, hit sounds |
| `src/world.zig` | Seeded stations, planets, asteroid clusters, rotated-box and ellipsoid collision |
| `src/terrain.zig` | Jungle heightfield, water plane, ceiling, terrain sweeps and recovery |
| `src/jungle.zig`, `src/jungle_mesh.zig` | Seeded ruins, banyans, hanging roots, river pillars, terrain and foliage meshes |
| `src/math.zig` | Vector helpers and swept box intersection |
| `src/mesh.zig` | Procedural flat-shaded mesh builder and ship |
| `src/render.zig`, `src/shaders.zig` | Sun shadows, local light, pixel metal, sky, modest glow, XP/HP bars and hit feedback |
| `src/retro.zig` | Soulslike filter shader, intensity controls, presets, render target |

Physics runs at 120 Hz with accumulated mouse motion and time-scaled controller turning distributed across steps. Geometry is batched into one static mesh. The scene renders at two-thirds window resolution with point filtering. The 2048-pixel directional shadow map follows the ship. Four local lights illuminate nearby surfaces; bolts and explosions contribute light. Local lights do not cast shadows. Bounded pools hold 192 drones, 128 bolts, 32 mines, 24 rockets, three orbital drones, and 768 XP crystals; at capacity, new XP merges into an existing crystal without losing value. Drones use local obstacle avoidance, not a global pathfinder.

Generated station collision uses cached bounds to skip distant groups before testing individual parts. Station geometry remains immutable during a run; manually constructed worlds can use the unindexed path. Shader uniform locations are cached when each renderer is created. See [the audit report](docs/AUDIT_SWEEP.md) for fixes and benchmark evidence.

## Research and next layers

[The reference study](docs/RESEARCH.md) covers Vampire Survivors, Star Fox, Star Fox 64, and Descent using developer interviews, official material, and source inspection. It separates observed mechanics from proposed implementation and records the owner's movement-only constraint.

Laser, mines, homing rockets, orbital drones, six optional systems, tiered upgrades, drone flocks, XP, damage, and restart are implemented. Hunters, caches, exploration rewards, and turrets remain future layers. Choose further work from playtesting the actual survival loop.
