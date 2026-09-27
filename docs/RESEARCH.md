# Reference study — 27 September 2026

Research completed before gameplay implementation. Sources below are developer interviews, official material, and the original Descent source release. Historical observations and proposed implementation are kept distinct. No commercial game's assets or source are incorporated.

**Current design amendments from the owner:** the starting laser now fires straight ahead at a fast cadence with higher critical chance. Mines, homing rockets, and armed orbital drones are implemented as level-up weapons. Runs start without systems; four weapon slots include the laser, while four system slots can be filled freely from six choices. Compact equipment icons join the XP and ship HP bars, and the same icons appear on tiered level-up choices. These later instructions supersede the original targeting, HUD, and proposed orbital/contrail details below; README.md describes the current implementation. Reference observations remain unchanged.

## Vampire Survivors: movement is the player's scarce resource

**Evidence.** Poncle describes a time-survival game with minimal controls; its original demo explicitly keeps dropped gems and encourages concentrating upgrades in a few weapons. In Nintendo's interview, Luca Galante says simplicity let him finish the foundation and spend time on content. He describes the run limit as a response to play becoming stale, and upgrades, unlocks, and surprises as contributors to variety. Sources: [poncle's original demo](https://poncle.itch.io/vampire-survivors), [Nintendo interview, 2024](https://www.nintendo.com/jp/topics/article/3f3d9c44-6cc5-4197-a31b-1397f229c03b).

**Application, not a claim about its internals.** Automatic targeting must leave attention available for navigation. A 3D pilot already manages depth and steering, so manual aiming, weapon selection, and firing would undermine the intended loop. XP should stay where enemies die, with generous attraction once the ship approaches. A swarm behind the ship creates a choice to turn back for XP; immediate reverse movement and automatic stopping make that choice practical. Do not inherit a thirty-minute duration without testing shorter runs.

**Next-layer implementation.** Keep enemies, bolts, and XP in bounded pools. Maintain a spatial grid for neighbor queries once measurements justify it. Pick the closest *visible, reachable* enemy within range, using squared distances and a structure visibility test. Tick targeting at the weapon cadence; do not search every rendered frame. Spawn flocks around the player in a navigable shell, outside structures and the immediate camera view. Retire or reposition remote enemies explicitly. Use a simulation clock for spawn waves; pause it during upgrade selection. Store excess XP and process chained level-ups one choice at a time. Keep upgrades data-driven and filter maxed weapons before offering choices.

**Test gate.** Can a new pilot keep moving, understand an automatic kill, turn back, collect its XP, and make a meaningful upgrade choice without fighting the camera? Do not add hunters or three more weapons until that answer is yes.

## Star Fox: a silhouette must explain motion

**Evidence.** Watanabe describes iterating on fighters to make their nose direction clear with few polygons. Miyamoto describes a screen-wide vertex budget, simple building shapes, and ground patterns that communicated movement. This is a readability argument, not merely a nostalgic polygon count. [Nintendo's original-team interview, 2017](https://www.nintendo.com/en-gb/News/2017/September/Nintendo-Classic-Mini-SNES-developer-interview-Volume-1-Star-Fox-Star-Fox-2-1273086.html).

**Application.** Author an asymmetric front/back ship silhouette: pointed bow, broad swept wings, dark canopy, and two bright rear engines. Use actual triangles with face normals and a small material palette. The ship needs to remain identifiable at gameplay distance; bevels and surface greebles are secondary. Enemies later need equally distinct profiles and brighter values than the environment.

Space lacks a scrolling floor. Put navigation ribs, dock struts, and nearby debris in the traversable volume so optical flow communicates speed. Distant stars communicate rotation but are insufficient for translation. Engine exhaust can lengthen while moving; never substitute screen streaks for real displacement. Keep the field of view fixed.

**Test gate.** A screenshot should explain where the ship faces. A slow pass through the dock should explain its speed without reading a number. Roll feedback must not make a straight flight path seem to turn.

## Star Fox 64: depth, readable effects, and comfortable maneuvers

**Evidence.** Nintendo's retrospective ties all-range flight and scrolling to Star Fox 2 experiments and describes programming experiments specifically intended to improve the Arwing's comfort. The official 3DS remake manual documents charge/homing shots and flight maneuvers; it is a controls reference for the remake, not proof of the N64 renderer's internals. Sources: [Iwata Asks, original team](https://www.nintendo.com/en-gb/Iwata-Asks/Iwata-Asks-Star-Fox-64/Vol-1-Star-Fox-64-3D/4-Star-Fox-2-that-Almost-Was/4-Star-Fox-2-that-Almost-Was-220966.html), [official remake manual](https://csassets.nintendo.com/noaext/image/private/t_KA_PDF/manual-3DS-star-fox-64-3D-en?_a=DATAg1AAZAA0).

**Application.** Borrow the immediate recognition of bright laser cores, colored halos, and large short-lived bursts. These are proposed modern effects, not a reconstruction of Nintendo's shaders. Later laser bolts should be emissive geometry plus additive glow, with an actual local light. Explosions should have a brief bright core, an expanding colored shell, and a few chunky fragments; smoke should not hide an approaching drone. Budget lights separately from visible particles.

Charge-shot input and manual lock-on do not belong in this automatic-combat loop. Their useful lesson is communicating acquisition and impact. The owner also explicitly rejected entity overlays: communicate combat through projectile motion, firing rhythm, sound, and physical reactions. Separate camera pose from decorative ship banking, and reserve dramatic camera movement for a future play-tested decision.

**Test gate.** At swarm density, the player can still distinguish ship, nearby enemy, XP, and entrance. Test effects against both open space and dark interiors; bloom alone cannot illuminate a wall.

## Descent: local axes, spatial structure, and light with a source

**Evidence from source.** `read_flying_controls` combines thrust along the ship's forward, right, and up basis and exposes pitch, heading, and bank. [`CONTROLS.C`](https://raw.githubusercontent.com/videogamepreservation/descent/master/MAIN/CONTROLS.C). `PHYSICS.C` handles thrust, drag, turn-induced bank, orientation repair, and iterative collision handling; its history even records a high-frame-rate drag fix. [`PHYSICS.C`](https://raw.githubusercontent.com/videogamepreservation/descent/master/MAIN/PHYSICS.C).

`LIGHTING.C` accumulates dynamic light at vertices. Dim sources are restricted to their own segment; larger sources touch visible vertices, with work distributed between frames. Muzzle flashes decay, and weapon, fireball, powerup, and debris objects contribute light. [`LIGHTING.C`](https://raw.githubusercontent.com/videogamepreservation/descent/master/MAIN/LIGHTING.C). The original renderer traverses connected segments and renders textured faces, rather than treating a mine as a flat arena. [`RENDER.C`](https://raw.githubusercontent.com/videogamepreservation/descent/master/MAIN/RENDER.C).

**Application, corrected by the owner.** This is Survivors, not a flight simulator: movement is the only active task. Mouse turns; WASD moves immediately; releasing movement stops immediately. No boost, brake, roll, drift, throttle, or momentum-management controls. Pitch aims vertical travel; yaw stays relative to a stable horizon, and banking is cosmetic. The useful part of Descent is local-axis translation, structures, and lighting, not its control burden. Advance collision at 120 Hz and normalize diagonal movement. Sweep the ship collider against expanded structure boxes; project remaining displacement along contact planes. Probe the chase-camera boom against the same geometry.

Use open space connected by a few strongly shaped structures: a hollow relay, a ribbed dock with multiple exits, and a tall refinery. Give entrances distinct colored beacons. Pixel-sized panel marks should be generated in surface coordinates with a stable physical scale, and remain subordinate to silhouette. The future shader can use bounded per-pixel lights; the lesson from Descent is light ownership and locality, not copying its vertex-light limitations. Local lights will initially have no occlusion; avoid claiming physically accurate light transport.

**Test gate.** Turn, reverse, strafe, climb, and descend inside the dock using only mouse and WASD. No wall tunneling, camera penetration, unexpected coast, or diagonal speed advantage. The pilot must be able to identify an exit without managing orientation recovery.

## Adjacent Zig foundation

Inspected `../zig-soulslike/build.zig`, `build.zig.zon`, `_zig.cmd`, `check.cmd`, `src/gfx/gfx.zig`, `src/gfx/shaders.zig`, and `src/core/camera.zig`; also checked the sibling mars-survival project's architecture.

Reuse the installed Zig 0.14.1 toolchain and exact raylib-zig package pin. Adapt the soulslike's `Builder` vertex/color/normal streams, triangle mesh upload and ownership, custom shader material assignment, depth-texture framebuffer, sun-space pass, and matrix conventions. Keep the single-sun and bounded local-light model. Carry over cheap `check`, explicit tests, and screenshots captured before `endDrawing`.

Do not import its world, hero, day/night, or terrain modules: those systems encode a different game's assumptions. Its 8192-pixel ground-focused shadow map is unnecessary here; start with a smaller map following the local flight volume. Keep provenance of adapted helpers in `docs/FOUNDATION.md`.

## Milestone order

1. **Flight, implemented foundation:** ship, immediate movement with mouse and WASD only, collision, camera, three visually distinct landmarks, deterministic screenshots and physics tests. The owner explicitly removed all gameplay HUD and entity overlays. Controls are documented outside the game.
2. **Survivors, implemented current milestone:** nearest-visible-target laser, pursuing drone flocks, persistent XP, upgrade choices, damage/death/restart. The owner explicitly requested this loop rather than stopping at flight. The automated scenario earns its first upgrade through actual kills and collection. Choice and death screens are separate from gameplay; there is no in-world HUD. Human play determines whether the return-for-XP loop is fun.
3. **Builds:** orbitals use swept shard contact; contrail stores time-stamped path segments with finite lifetime; missiles turn at a bounded rate and spread across target groups. Hunters pursue observed positions, with distinct silhouettes and movement.
4. **Style:** density stress scenes, emissive bolts, flashes illuminating metal, explosions with brief readable lifetimes, industrial texture pass, audio feedback.
5. **Exploration:** caches and identifiable sites with entrances, turrets with telegraphed shots, rewards strong enough to justify entering danger. Validate that the open bypass and interior shortcut are both useful choices.
6. **Play and decide:** retain what creates decisions; choose the next feature from actual sessions.

Flight needs enough environment and lighting to judge distance now. That does not count as passing the later style or exploration milestones. All numeric tuning in the prototype is our initial hypothesis, not a recovered constant from a reference game.
