const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const world = @import("world.zig");
const flight = @import("flight.zig");
const render = @import("render.zig");
const survivors = @import("survivors.zig");
const choices = @import("choices.zig");
const audio = @import("audio.zig");
const controls = @import("controls.zig");
const menu = @import("menu.zig");
const retro = @import("retro.zig");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);
    var shot = false;
    var bench = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--shot")) shot = true else if (std.mem.eql(u8, arg, "--bench")) bench = true else {
            std.debug.print("Usage: freespace-survivors [--shot | --bench]\n", .{});
            return error.UnknownArgument;
        }
    }
    if (bench) return @import("benchmark.zig").run();
    rl.setTraceLogLevel(.warning);
    rl.setConfigFlags(.{ .window_resizable = !shot, .window_hidden = shot, .vsync_hint = !shot, .window_always_run = shot });
    rl.initWindow(1440, 810, "Freespace Survivors");
    defer rl.closeWindow();
    rl.setWindowMinSize(960, 540);
    rl.setExitKey(.null);
    var w = world.World.generateLevel(if (shot) .space else .jungle, if (shot) 0xF123 else @bitCast(std.time.milliTimestamp()));
    var renderer = render.Renderer.init(&w);
    defer renderer.deinit();
    if (shot) {
        try shots(&renderer, &w);
        return;
    }
    var sound = audio.Audio.init();
    defer sound.deinit();
    rl.setTargetFPS(120);
    defer rl.enableCursor();
    var settings = menu.Settings.load();
    settings.save();
    var display = menu.Display{};
    display.apply(settings.fullscreen);
    if (sound.enabled) rl.setMasterVolume(settings.volume);
    var ship = flight.Ship{ .position = w.spawn() };
    var run = survivors.Run.init(ship, &w, @bitCast(std.time.milliTimestamp()));
    var rig = flight.Camera{};
    var accumulator: f32 = 0;
    var pending = rl.Vector2{ .x = 0, .y = 0 };
    var time: f32 = 0;
    var warmup = true;
    var captured = false;
    var input = controls.Input{};
    var menus = menu.Menu.start();
    var upgrade_selected: usize = 0;
    while (!rl.windowShouldClose()) {
        const old_shots = run.shots_fired;
        const old_kills = run.kills;
        const old_xp = run.xp;
        const old_hp = run.hp;
        const old_hits = run.hits_taken;
        const old_choosing = run.choosing;
        const dt = std.math.clamp(rl.getFrameTime(), 0, 0.10);
        input.poll(dt, settings.deadzone);
        const focused = rl.isWindowFocused();
        var blocked = menus.screen != .closed or run.choosing or run.dead;
        var restart = false;
        var next_level = w.level;
        var changed = false;
        if (focused and input.fullscreen) {
            settings.fullscreen = !settings.fullscreen;
            changed = true;
            warmup = true;
        }
        if (focused and rl.isKeyPressed(.tab)) {
            settings.mouse_locked = !settings.mouse_locked;
            changed = true;
        }
        if (!focused or input.disconnected) {
            if (menus.screen == .closed) menus.open();
            blocked = true;
        } else if ((input.pause and menus.home != .start) or (menus.screen == .closed and input.back)) {
            if (menus.screen == .closed) menus.open() else menus.screen = .closed;
            blocked = true;
            warmup = true;
        } else if (menus.screen != .closed) {
            switch (menus.update(input, &settings)) {
                .none => {},
                .resume_game => warmup = true,
                .restart => restart = true,
                .quit => break,
                .changed => changed = true,
                .start_jungle => {
                    next_level = .jungle;
                    restart = true;
                },
                .start_space => {
                    next_level = .space;
                    restart = true;
                },
                .main_menu => menus = menu.Menu.start(),
            }
        } else if (run.dead) {
            restart = input.accept;
        } else if (run.choosing) {
            menu.navigate(&upgrade_selected, run.choice_count, input.nav);
            const pick: ?usize = if (rl.isKeyPressed(.one)) 0 else if (rl.isKeyPressed(.two)) 1 else if (rl.isKeyPressed(.three)) 2 else choices.pick(&run, &upgrade_selected, input.accept);
            if (pick) |index| {
                if (run.choose(index)) run.burst(ship.position, .level, 2);
                upgrade_selected = 0;
                warmup = true;
            }
        }
        if (changed) {
            display.apply(settings.fullscreen);
            settings.fullscreen = rl.isWindowFullscreen();
            if (sound.enabled) rl.setMasterVolume(settings.volume);
            settings.save();
        }
        if (restart) {
            renderer.deinit();
            w = world.World.generateLevel(next_level, @bitCast(std.time.milliTimestamp()));
            renderer = render.Renderer.init(&w);
            ship = .{ .position = w.spawn() };
            run = survivors.Run.init(ship, &w, @bitCast(std.time.milliTimestamp()));
            rig = .{};
            time = 0;
            menus = .{};
            upgrade_selected = 0;
            warmup = true;
        }
        syncCursor(settings, menus, &run, focused, &captured, &warmup);
        if (!blocked and menus.screen == .closed and !run.choosing) {
            const mouse = rl.getMouseDelta();
            const invert: f32 = if (settings.invert_y) -1 else 1;
            if (!warmup and (captured or rl.isMouseButtonDown(.right))) {
                pending.x += mouse.x * 0.0025 * settings.mouse_sensitivity;
                pending.y += mouse.y * 0.0025 * settings.mouse_sensitivity * invert;
            }
            warmup = false;
            pending.x += input.look.x * 2.2 * settings.controller_sensitivity * dt;
            pending.y += input.look.y * 2.2 * settings.controller_sensitivity * dt * invert;
            accumulator += dt;
            const ticks: usize = @intFromFloat(@floor(accumulator / flight.STEP));
            if (ticks > 0) {
                const count: f32 = @floatFromInt(ticks);
                const movement = flight.Input{
                    .thrust = m.v(controls.key(.d) - controls.key(.a) + input.move.x, 0, controls.key(.s) - controls.key(.w) + input.move.y),
                    .look = .{ .x = pending.x / count, .y = pending.y / count },
                };
                for (0..ticks) |_| {
                    if (run.choosing or run.dead) break;
                    ship.speed_multiplier = run.speedMultiplier();
                    ship.tick(movement, flight.STEP, &w);
                    run.tick(&ship, &w, flight.STEP);
                    time += flight.STEP;
                }
                accumulator -= count * flight.STEP;
                pending = .{ .x = 0, .y = 0 };
            }
        } else {
            accumulator = 0;
            pending = .{ .x = 0, .y = 0 };
            if (run.dead and menus.screen == .closed) run.tick(&ship, &w, dt);
        }
        syncCursor(settings, menus, &run, focused, &captured, &warmup);
        const camera = rig.view(ship, if (menus.screen == .closed) dt else 0, &w);
        if (run.shots_fired > old_shots) sound.play(.laser);
        if (run.kills > old_kills or (old_hp > 0 and run.hp == 0)) sound.play(.explosion);
        if (run.xp > old_xp) sound.play(.pickup);
        if (!restart and run.hits_taken != old_hits) sound.play(.hit);
        if (run.choosing and !old_choosing) {
            upgrade_selected = 0;
            sound.play(.level);
        }
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        renderer.filters.values = settings.filters;
        if (menus.screen != .closed) {
            if (menus.screen == .retro or menus.screen == .start) renderer.draw(ship, camera, time, if (menus.home == .start) null else &run);
            menus.draw(settings);
        } else if (run.choosing or (run.dead and deathAge(&run) > 1.2)) {
            choices.drawSelected(&run, upgrade_selected);
        } else renderer.draw(ship, camera, time, &run);
        rl.endDrawing();
    }
}

fn syncCursor(settings: menu.Settings, menus: menu.Menu, run: *const survivors.Run, focused: bool, captured: *bool, warmup: *bool) void {
    const desired = settings.mouse_locked and menus.screen == .closed and !run.choosing and !run.dead and focused;
    if (desired == captured.*) return;
    if (desired) rl.disableCursor() else rl.enableCursor();
    captured.* = desired;
    warmup.* = true;
}
fn shots(renderer: *render.Renderer, w: *const world.World) !void {
    try std.fs.cwd().makePath("shots");
    try worldShot(renderer, w, m.v(0, 0, 70), m.v(0, 0, -100), "01_departure");
    for (w.sites[0..4], 0..) |site, i| {
        var name: [80]u8 = undefined;
        const label = try std.fmt.bufPrint(&name, "world_station_{d}", .{i});
        const position = m.add(site.position, m.rotate(site.rotation, m.v(90, 65, 245)));
        try worldShot(renderer, w, position, site.position, label);
    }
    for (w.bodies[0..3], 0..) |body, i| {
        var name: [80]u8 = undefined;
        const label = try std.fmt.bufPrint(&name, "world_planet_{d}", .{i});
        try worldShot(renderer, w, m.add(body.position, m.scale(m.norm(m.v(-0.7, 0.3, 1)), body.extent() + 210)), body.position, label);
    }
    const rock = w.bodies[3];
    try worldShot(renderer, w, m.add(rock.position, m.v(90, 40, 160)), rock.position, "world_asteroids");
    std.debug.print("Region: {d} stations, {d} planets, {d} asteroids, {d} structural boxes\n", .{ w.site_count, @as(usize, 3), w.body_count - 3, w.count });
    try combatShots(renderer, w);
    try feedbackShots(renderer, w);
    try weaponShots(renderer, w);
    try menuShots();
    try retroShots(renderer, w);
    const variant = world.World.generate(92);
    renderer.deinit();
    renderer.* = render.Renderer.init(&variant);
    try worldShot(renderer, &variant, m.v(0, 0, 70), m.v(0, 0, -100), "world_alternate_seed");
    std.debug.print("Region rebuild and renderer resource reload passed\n", .{});
    try jungleShots(renderer);
}

fn jungleShots(renderer: *render.Renderer) !void {
    const w = world.World.generateLevel(.jungle, 0xF123);
    renderer.deinit();
    renderer.* = render.Renderer.init(&w);
    try worldShot(renderer, &w, w.spawn(), m.add(w.spawn(), m.v(0, 15, -210)), "jungle_departure");
    try worldShot(renderer, &w, m.v(260, 130, 480), m.v(170, 32, -130), "jungle_river");
    for (w.sites[0..4], 0..) |site, i| {
        var name: [64]u8 = undefined;
        const label = try std.fmt.bufPrint(&name, "jungle_ruin_{d}", .{i});
        var position = m.add(site.position, m.rotate(site.rotation, m.v(115, 65, 210)));
        position.y = @max(position.y, w.floorHeight(position.x, position.z) + 30);
        try worldShot(renderer, &w, position, m.add(site.position, m.v(0, 40, 0)), label);
    }
    var ship = flight.Ship{ .position = w.spawn() };
    var rig = flight.Camera{};
    var run = survivors.Run.init(ship, &w, 92);
    run.flock(m.add(ship.position, m.v(-20, 10, -75)), 15, &w);
    for (0..120) |_| run.tick(&ship, &w, flight.STEP);
    try combatSnap(renderer, &w, ship, &run, &rig, "jungle_combat");
    var menus = menu.Menu.start();
    var settings = menu.Settings{};
    if (menus.update(.{ .back = true }, &settings) != .none or menus.screen != .start) return error.StartBackFailed;
    if (menus.update(.{ .accept = true }, &settings) != .start_jungle) return error.JungleSelectionFailed;
    menus.selected = 1;
    if (menus.update(.{ .accept = true }, &settings) != .start_space) return error.SpaceSelectionFailed;
    menus.selected = 2;
    _ = menus.update(.{ .accept = true }, &settings);
    _ = menus.update(.{ .back = true }, &settings);
    if (menus.screen != .start) return error.StartOptionsBackFailed;
    menus.selected = 0;
    const camera = rig.view(ship, 0, &w);
    for (0..2) |size| {
        if (size == 1) rl.setWindowSize(960, 540);
        for (0..3) |frame| {
            rl.beginDrawing();
            renderer.draw(ship, camera, 0, null);
            menus.draw(settings);
            if (frame == 2) {
                rl.gl.rlDrawRenderBatchActive();
                const picture = try rl.loadImageFromScreen();
                defer rl.unloadImage(picture);
                if (!rl.exportImage(picture, if (size == 0) "shots/jungle_start_menu.png" else "shots/jungle_start_small.png")) return error.ScreenshotFailed;
            }
            rl.endDrawing();
        }
    }
    rl.setWindowSize(1440, 810);
    std.debug.print("Jungle: {d} ruins, {d} banyans; terrain, combat and start menu captured\n", .{ w.site_count, w.tree_count });
}

fn worldShot(renderer: *render.Renderer, w: *const world.World, position: m.V, target: m.V, name: []const u8) !void {
    const direction = m.norm(m.sub(target, position));
    var ship = flight.Ship{ .position = position, .yaw = std.math.atan2(-direction.x, -direction.z), .pitch = std.math.asin(direction.y) };
    ship.tick(.{}, flight.STEP, w);
    var rig = flight.Camera{};
    const run = survivors.Run{ .xp = 18 };
    try combatSnap(renderer, w, ship, &run, &rig, name);
}

fn deathAge(run: *const survivors.Run) f32 {
    const index = (run.burst_next + run.bursts.len - 1) % run.bursts.len;
    return run.bursts[index].age;
}

fn combatShots(renderer: *render.Renderer, w: *const world.World) !void {
    var ship = flight.Ship{};
    var run = survivors.Run.init(ship, w, 91);
    var rig = flight.Camera{};
    // Use ordinary weapons, damage, XP and progression with scripted steering.
    for (0..240) |_| run.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &run, &rig, "07_combat");
    for (0..14400) |_| {
        if (run.dead or run.choosing) break;
        var direction = m.v(@sin(run.elapsed * 0.22), 0, -@cos(run.elapsed * 0.22));
        var nearest: f32 = 120;
        for (run.gems) |gem| {
            if (!gem.active) continue;
            const delta = m.sub(gem.position, ship.position);
            const distance = m.length(delta);
            if (distance < nearest) {
                nearest = distance;
                direction = m.norm(delta);
            }
        }
        for (run.drones) |drone| {
            if (!drone.active) continue;
            const delta = m.sub(ship.position, drone.position);
            const distance = m.length(delta);
            if (distance < 24) direction = m.add(direction, m.scale(m.norm(delta), (24 - distance) / 12));
        }
        direction = m.norm(direction);
        var aim = direction;
        if (run.target(ship.position, w, null)) |id| {
            const enemy = run.drones[id];
            const lead = m.length(m.sub(enemy.position, ship.position)) / survivors.BOLT_SPEED;
            aim = m.norm(m.sub(m.add(enemy.position, m.scale(enemy.velocity, lead)), ship.position));
        }
        const yaw = std.math.atan2(-aim.x, -aim.z);
        const pitch = std.math.asin(std.math.clamp(aim.y, -1, 1));
        const orientation = m.qmul(m.axis(m.v(0, 1, 0), yaw), m.axis(m.v(1, 0, 0), std.math.clamp(pitch, -1.4, 1.4)));
        const thrust = m.rotate(m.inverse(orientation), direction);
        ship.speed_multiplier = run.speedMultiplier();
        ship.tick(.{ .thrust = thrust, .look = .{ .x = ship.yaw - yaw, .y = ship.pitch - pitch } }, flight.STEP, w);
        run.tick(&ship, w, flight.STEP);
    }
    std.debug.print("Progression flight: {d:.1}s, {d} kills, {d} XP, {d} HP\n", .{ run.elapsed, run.kills, run.xp, run.hp });
    if (!run.choosing) return error.ProgressionNotReached;
    try combatSnap(renderer, w, ship, &run, &rig, "08_progression");
    var dense = survivors.Run.init(ship, w, 913);
    dense.flock(m.add(ship.position, m.v(-20, 8, -42)), 65, w);
    dense.flock(m.add(ship.position, m.v(25, -6, -68)), 65, w);
    for (0..20) |_| dense.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &dense, &rig, "09_swarm");
    run = .{ .dead = true, .kills = 43, .elapsed = 87, .level = 4 };
    try combatSnap(renderer, w, ship, &run, &rig, "10_restart");
    ship = .{};
    run = survivors.Run.init(ship, w, 91);
    for (0..51) |_| run.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &run, &rig, "11_laser");
    run = .{};
    for (0..4) |tier| {
        for (0..4) |i| {
            run.drones[tier * 4 + i] = .{
                .active = true,
                .wave = @intCast(tier),
                .hp = 2 + @as(f32, @floatFromInt(tier)) * 2,
                .position = m.add(ship.position, m.v(-24 + @as(f32, @floatFromInt(tier)) * 16, 2 + @as(f32, @floatFromInt(i % 2)) * 6, -33 - @as(f32, @floatFromInt(i / 2)) * 9)),
            };
        }
    }
    try combatSnap(renderer, w, ship, &run, &rig, "12_wave_colors");
}

fn menuShots() !void {
    var settings = menu.Settings{};
    var menus = menu.Menu{};
    menus.open();
    try menuSnap(menus, settings, "13_pause");
    // Exercise the same actions produced by keyboard, D-pad and controller A/B.
    _ = menus.update(.{ .nav = 1 }, &settings);
    _ = menus.update(.{ .accept = true }, &settings);
    if (menus.screen != .options) return error.OptionsDidNotOpen;
    _ = menus.update(.{ .nav = 1 }, &settings);
    const action = menus.update(.{ .accept = true }, &settings);
    if (action != .changed or settings.mouse_locked) return error.MouseToggleFailed;
    _ = menus.update(.{ .nav = 2, .adjust = 1 }, &settings);
    if (settings.controller_sensitivity <= 1) return error.SensitivityAdjustmentFailed;
    try menuSnap(menus, settings, "14_options");
    rl.setWindowSize(960, 540);
    try menuSnap(menus, settings, "15_options_small");
    rl.setWindowSize(1440, 810);
    _ = menus.update(.{ .back = true }, &settings);
    if (menus.screen != .pause) return error.OptionsBackFailed;
    const resumed = menus.update(.{ .back = true }, &settings);
    if (resumed != .resume_game or menus.screen != .closed) return error.ResumeFailed;
    menus.open();
    _ = menus.update(.{ .nav = 2 }, &settings);
    if (menus.update(.{ .accept = true }, &settings) != .restart) return error.RestartFailed;
    menus.open();
    _ = menus.update(.{ .nav = -1 }, &settings);
    if (menus.update(.{ .accept = true }, &settings) != .quit) return error.QuitFailed;
    menus = .{ .screen = .options, .selected = @intFromEnum(menu.OptionRow.retro) };
    _ = menus.update(.{ .accept = true }, &settings);
    if (menus.screen != .retro) return error.RetroMenuFailed;
    menus.selected = retro.COUNT + @intFromEnum(retro.Preset.crt);
    _ = menus.update(.{ .accept = true }, &settings);
    if (settings.filters[11] != 0.6) return error.RetroPresetFailed;
    menus.selected = retro.COUNT + @intFromEnum(retro.Preset.off);
    _ = menus.update(.{ .accept = true }, &settings);
    for (settings.filters) |value| if (value != 0) return error.RetroDisableFailed;
    std.debug.print("Menu navigation and option actions passed\n", .{});
}

fn retroShots(renderer: *render.Renderer, w: *const world.World) !void {
    for (0..4) |i| {
        retro.preset(&renderer.filters.values, @enumFromInt(i));
        var name: [80]u8 = undefined;
        try worldShot(renderer, w, m.v(0, 0, 70), m.v(0, 0, -100), try std.fmt.bufPrint(&name, "retro_preset_{d}", .{i}));
    }
    renderer.filters.values = retro.defaults;
    retro.preset(&renderer.filters.values, .off);
    try worldShot(renderer, w, m.v(0, 0, 70), m.v(0, 0, -100), "retro_all_off");
    renderer.filters.values[@intFromEnum(retro.Filter.dither)] = 1;
    renderer.filters.values[@intFromEnum(retro.Filter.amber)] = 1;
    try worldShot(renderer, w, m.v(0, 0, 70), m.v(0, 0, -100), "retro_amber_dither");
    renderer.filters.values = retro.defaults;
    var settings = menu.Settings{};
    var menus = menu.Menu{ .screen = .retro };
    try menuSnap(menus, settings, "retro_menu_1");
    menus.selected = 10;
    try menuSnap(menus, settings, "retro_menu_2");
    menus.selected = 18;
    try menuSnap(menus, settings, "retro_menu_3");
    rl.setWindowSize(960, 540);
    retro.preset(&settings.filters, .crt);
    try menuSnap(menus, settings, "retro_menu_small");
    rl.setWindowSize(1440, 810);
}

fn feedbackShots(renderer: *render.Renderer, w: *const world.World) !void {
    var ship = flight.Ship{};
    var rig = flight.Camera{};
    var run = survivors.Run{ .spawn_clock = 100, .fire_clock = 100 };
    run.gems[0] = .{ .active = true, .position = m.add(ship.position, m.v(4, 0, 0)) };
    run.gems[1] = .{ .active = true, .position = m.add(ship.position, m.v(-4, 0, 0)) };
    for (0..7) |_| run.tick(&ship, w, flight.STEP);
    if (run.xp != 2 or run.xp_flash <= 0) return error.PickupFeedbackMissing;
    try combatSnap(renderer, w, ship, &run, &rig, "21_xp_flash");
    run = .{ .spawn_clock = 100, .fire_clock = 100 };
    run.drones[0] = .{ .active = true, .position = m.add(ship.position, m.v(6, 0, 0)) };
    run.drones[1] = .{ .active = true, .position = m.add(ship.position, m.v(-9, 3, -27)) };
    run.bolts[0] = .{ .active = true, .position = m.add(run.drones[1].position, m.v(0, 0, 3)), .velocity = m.v(0, 0, -230), .life = 1 };
    for (0..7) |_| run.tick(&ship, w, flight.STEP);
    if (run.hp != 4 or run.hit_flash <= 0 or run.drones[1].flash <= 0) return error.HitFeedbackMissing;
    try combatSnap(renderer, w, ship, &run, &rig, "22_hit_flash");
    run = .{ .hp = 1, .max_hp = 5, .elapsed = 10 };
    try combatSnap(renderer, w, ship, &run, &rig, "hull_critical");
    run = .{ .hp = 7, .max_hp = 7, .elapsed = 10 };
    try combatSnap(renderer, w, ship, &run, &rig, "hull_reinforced");
    run = .{ .hp = 2, .max_hp = 7, .elapsed = 10 };
    rl.setWindowSize(960, 540);
    retro.preset(&renderer.filters.values, .crt);
    try combatSnap(renderer, w, ship, &run, &rig, "hull_small_crt");
    renderer.filters.values = retro.defaults;
    rl.setWindowSize(1440, 810);
}

fn weaponShots(renderer: *render.Renderer, w: *const world.World) !void {
    var ship = flight.Ship{};
    var rig = flight.Camera{};
    var run = survivors.Run{ .spawn_clock = 100, .fire_clock = 100 };
    run.ranks[@intFromEnum(survivors.Upgrade.mine)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.rocket)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.orbital)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.crit)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.leech)] = 1;
    run.drones[0] = .{ .active = true, .position = m.add(ship.position, m.v(0, 5, -90)), .hp = 100 };
    for (0..90) |_| run.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &run, &rig, "weapons_online");
    if (!run.mines[0].active or !run.rockets[0].active or !run.orbitals[0].visible) return error.WeaponNotDeployed;
    run.drones[0].active = false;
    run.fire_clock = 100;
    run.mine_clock = 100;
    run.rocket_clock = 100;
    for (&run.rockets) |*rocket| rocket.active = false;
    for (&run.bolts) |*bolt| bolt.active = false;
    run.mines[0].age = 8.5;
    try combatSnap(renderer, w, ship, &run, &rig, "mine_fading");
    run.mines[0].age = 1;
    for (0..4) |i| run.drones[i] = .{ .active = true, .position = m.add(run.mines[0].position, m.v(0, 1, -6 - @as(f32, @floatFromInt(i)) * 3)) };
    run.tick(&ship, w, flight.STEP);
    if (run.kills < 3) return error.MineBlastMissing;
    for (0..10) |_| run.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &run, &rig, "mine_blast");
    run = .{ .choosing = true, .choice_count = 3, .choices = .{ .mine, .rocket, .orbital } };
    try combatSnap(renderer, w, ship, &run, &rig, "weapon_choices");
    run.choices = .{ .hull, .speed, .leech };
    try combatSnap(renderer, w, ship, &run, &rig, "system_unlock_choices");
    run.ranks[@intFromEnum(survivors.Upgrade.crit)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.rate)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.damage)] = 1;
    run.ranks[@intFromEnum(survivors.Upgrade.hull)] = 1;
    run.choices = .{ .damage, .crit, .rate };
    run.choice_tiers = .{ .legendary, .uncommon, .common };
    rl.setWindowSize(960, 540);
    try combatSnap(renderer, w, ship, &run, &rig, "system_choices_small");
    run.ranks[@intFromEnum(survivors.Upgrade.damage)] = 0;
    run.ranks[@intFromEnum(survivors.Upgrade.speed)] = 1;
    run.choices = .{ .speed, .crit, .rate };
    run.choice_tiers = .{ .legendary, .rare, .uncommon };
    try combatSnap(renderer, w, ship, &run, &rig, "tiered_choices_small");
    run.choosing = false;
    run.ranks[@intFromEnum(survivors.Upgrade.mine)] = 2;
    run.ranks[@intFromEnum(survivors.Upgrade.rocket)] = 2;
    run.ranks[@intFromEnum(survivors.Upgrade.orbital)] = 3;
    run.tick(&ship, w, flight.STEP);
    try combatSnap(renderer, w, ship, &run, &rig, "loadout_full_small");
    rl.setWindowSize(1440, 810);
}

fn menuSnap(menus: menu.Menu, settings: menu.Settings, name: []const u8) !void {
    for (0..3) |frame| {
        rl.beginDrawing();
        rl.clearBackground(m.color(7, 11, 17));
        menus.draw(settings);
        if (frame == 2) {
            rl.gl.rlDrawRenderBatchActive();
            const capture = try rl.loadImageFromScreen();
            defer rl.unloadImage(capture);
            var buf: [128]u8 = undefined;
            const path = try std.fmt.bufPrintZ(&buf, "shots/{s}.png", .{name});
            if (!rl.exportImage(capture, path)) return error.ScreenshotFailed;
            std.debug.print("Captured {s}\n", .{path});
        }
        rl.endDrawing();
    }
}

fn combatSnap(renderer: *render.Renderer, w: *const world.World, ship: flight.Ship, run: *const survivors.Run, rig: *flight.Camera, name: []const u8) !void {
    const camera = rig.view(ship, 1, w);
    for (0..3) |frame| {
        rl.beginDrawing();
        if (run.choosing or run.dead) choices.draw(run) else renderer.draw(ship, camera, run.elapsed, run);
        if (frame == 2) {
            rl.gl.rlDrawRenderBatchActive();
            const capture = try rl.loadImageFromScreen();
            defer rl.unloadImage(capture);
            var buf: [128]u8 = undefined;
            const path = try std.fmt.bufPrintZ(&buf, "shots/{s}.png", .{name});
            if (!rl.exportImage(capture, path)) return error.ScreenshotFailed;
            std.debug.print("Captured {s} (kills={d}, xp={d}, choices={})\n", .{ path, run.kills, run.xp, run.choosing });
        }
        rl.endDrawing();
    }
}

test {
    _ = @import("math.zig");
    _ = @import("world.zig");
    _ = @import("flight.zig");
    _ = @import("survivors.zig");
    _ = @import("controls.zig");
    _ = @import("menu.zig");
}
