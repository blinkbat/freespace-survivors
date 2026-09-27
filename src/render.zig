const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const mesh = @import("mesh.zig");
const flight = @import("flight.zig");
const world = @import("world.zig");
const glsl = @import("shaders.zig");
const survivors = @import("survivors.zig");
const retro = @import("retro.zig");
const hud = @import("hud.zig");
const v = m.v;
const SHADOW_SIZE = 2048;
const SHADOW_SLOT = 12;
const sun = m.norm(v(-0.5, 0.8, 0.6));
const Locations = struct {
    flash: i32,
    opacity: i32,
    eye: i32,
    light_vp: i32,
    light_pos: i32,
    light_color: i32,
    sky_forward: i32,
    sky_right: i32,
    sky_up: i32,
    sky_lens: i32,
    texel: i32,
    scene_time: i32,
    fn init(scene: rl.Shader, sky: rl.Shader, post: rl.Shader) Locations {
        return .{
            .flash = rl.getShaderLocation(scene, "flash"),
            .opacity = rl.getShaderLocation(scene, "opacity"),
            .eye = rl.getShaderLocation(scene, "eye"),
            .light_vp = rl.getShaderLocation(scene, "lightVP"),
            .light_pos = rl.getShaderLocation(scene, "lightPos"),
            .light_color = rl.getShaderLocation(scene, "lightColor"),
            .sky_forward = rl.getShaderLocation(sky, "forward"),
            .sky_right = rl.getShaderLocation(sky, "right"),
            .sky_up = rl.getShaderLocation(sky, "up"),
            .sky_lens = rl.getShaderLocation(sky, "lens"),
            .texel = rl.getShaderLocation(post, "texel"),
            .scene_time = rl.getShaderLocation(scene, "time"),
        };
    }
};

pub const Renderer = struct {
    scene: rl.Shader,
    depth: rl.Shader,
    sky: rl.Shader,
    post: rl.Shader,
    structures: rl.Model,
    craft: rl.Model,
    drones: [4]rl.Model,
    gem: rl.Model,
    orbital: rl.Model,
    mine: rl.Model,
    rocket: rl.Model,
    shadows: rl.RenderTexture2D,
    target: rl.RenderTexture2D,
    white: rl.Texture2D,
    light_vp: rl.Matrix = undefined,
    locations: Locations,
    sites: [world.SITE_COUNT]world.Landmark,
    site_count: usize,
    filters: retro.Retro,

    pub fn init(w: *const world.World) Renderer {
        const scene = compile(glsl.scene_vs, glsl.scene_fs);
        const depth = compile(glsl.depth_vs, glsl.depth_fs);
        const sky = compile(null, glsl.sky_fs);
        const post = compile(null, glsl.post_fs);
        var b = mesh.Builder{};
        for (w.items()) |s| {
            if (s.mat == .bark) continue;
            b.material = @floatFromInt(@intFromEnum(s.mat));
            b.origin = s.box.center;
            b.rotation = s.rotation;
            b.box(m.zero, m.scale(s.box.half, 2), s.tint);
        }
        for (w.bodies[0..w.body_count], 0..) |body, i| {
            b.origin = body.position;
            b.rotation = m.identity;
            b.celestial(body.radii, body.tint, body.planet, i);
        }
        if (w.level == .jungle) @import("jungle_mesh.zig").build(&b, w);
        const jungle: f32 = if (w.level == .jungle) 1 else 0;
        uniform(scene, "jungle", &jungle, .float);
        uniform(sky, "jungle", &jungle, .float);
        const fbo = rl.gl.rlLoadFramebuffer();
        const depth_texture = rl.gl.rlLoadTextureDepth(SHADOW_SIZE, SHADOW_SIZE, false);
        rl.gl.rlFramebufferAttach(fbo, depth_texture, 100, 100, 0);
        rl.gl.rlEnableFramebuffer(fbo);
        if (!rl.gl.rlFramebufferComplete(fbo)) @panic("shadow framebuffer incomplete");
        rl.gl.rlDisableFramebuffer();
        const shadow: rl.RenderTexture2D = .{
            .id = fbo,
            .texture = .{ .id = 0, .width = SHADOW_SIZE, .height = SHADOW_SIZE, .mipmaps = 1, .format = .uncompressed_grayscale },
            .depth = .{ .id = depth_texture, .width = SHADOW_SIZE, .height = SHADOW_SIZE, .mipmaps = 1, .format = .uncompressed_grayscale },
        };
        const pixel = rl.genImageColor(1, 1, rl.Color.white);
        defer rl.unloadImage(pixel);
        const white = rl.loadTextureFromImage(pixel) catch @panic("white texture");
        var slot: i32 = SHADOW_SLOT;
        uniform(scene, "shadowMap", &slot, .int);
        uniform(scene, "sun", &sun, .vec3);
        const opacity: f32 = 1;
        uniform(scene, "opacity", &opacity, .float);
        return .{
            .scene = scene,
            .sites = w.sites,
            .site_count = w.site_count,
            .filters = retro.Retro.init(),
            .locations = Locations.init(scene, sky, post),
            .depth = depth,
            .sky = sky,
            .post = post,
            .structures = b.finish(scene),
            .craft = mesh.ship(scene),
            .drones = .{ mesh.drone(scene, 0), mesh.drone(scene, 1), mesh.drone(scene, 2), mesh.drone(scene, 3) },
            .gem = mesh.gem(scene),
            .orbital = mesh.orbital(scene),
            .mine = mesh.mine(scene),
            .rocket = mesh.rocket(scene),
            .shadows = shadow,
            .target = makeTarget(),
            .white = white,
        };
    }

    pub fn deinit(r: *Renderer) void {
        r.filters.deinit();
        rl.unloadModel(r.structures);
        rl.unloadModel(r.craft);
        for (r.drones) |drone| rl.unloadModel(drone);
        rl.unloadModel(r.gem);
        rl.unloadModel(r.orbital);
        rl.unloadModel(r.mine);
        rl.unloadModel(r.rocket);
        rl.unloadRenderTexture(r.target);
        rl.unloadRenderTexture(r.shadows);
        rl.unloadTexture(r.white);
        for ([_]rl.Shader{ r.scene, r.depth, r.sky, r.post }) |s| rl.unloadShader(s);
    }

    pub fn draw(r: *Renderer, ship: flight.Ship, camera: rl.Camera3D, time: f32, run: ?*const survivors.Run) void {
        rl.setShaderValue(r.scene, r.locations.scene_time, &time, .float);
        const desired_w = @divTrunc(rl.getScreenWidth() * 2, 3);
        const desired_h = @divTrunc(rl.getScreenHeight() * 2, 3);
        if (r.target.texture.width != desired_w or r.target.texture.height != desired_h) {
            rl.unloadRenderTexture(r.target);
            r.target = makeTarget();
        }
        const transform = shipTransform(ship);
        rl.gl.rlSetClipPlanes(10, 1000);
        const light_camera = rl.Camera3D{
            .position = m.add(ship.position, m.scale(sun, 450)),
            .target = ship.position,
            .up = v(0, 1, 0),
            .fovy = 360,
            .projection = .orthographic,
        };
        rl.beginTextureMode(r.shadows);
        rl.clearBackground(rl.Color.white);
        rl.beginMode3D(light_camera);
        r.light_vp = rl.math.matrixMultiply(rl.gl.rlGetMatrixModelview(), rl.gl.rlGetMatrixProjection());
        drawModel(r.structures, r.depth, rl.math.matrixIdentity());
        if (run == null or !run.?.dead) drawModel(r.craft, r.depth, transform);
        rl.endMode3D();
        rl.endTextureMode();
        rl.gl.rlSetClipPlanes(0.15, 10000);

        rl.beginTextureMode(r.target);
        rl.clearBackground(m.color(3, 6, 12));
        r.drawSky(camera);
        rl.beginMode3D(camera);
        rl.gl.rlActiveTextureSlot(SHADOW_SLOT);
        rl.gl.rlEnableTexture(r.shadows.depth.id);
        rl.gl.rlActiveTextureSlot(0);
        rl.setShaderValueMatrix(r.scene, r.locations.light_vp, r.light_vp);
        rl.setShaderValue(r.scene, r.locations.eye, &camera.position, .vec3);
        var positions = [4]m.V{
            m.add(ship.position, m.scale(ship.forward(), -2)),
            v(0, 6, -101),
            m.zero,
            m.zero,
        };
        var colors = [4][4]f32{
            .{ 0.18, 0.75, 1.0, 23 }, .{ 0.14, 0.66, 0.85, 59 }, .{ 1.0, 0.45, 0.12, 62 }, .{ 0.15, 0.65, 0.4, 76 },
        };
        var nearest = [_]f32{std.math.inf(f32)} ** 3;
        for (r.sites[0..r.site_count]) |site| {
            const distance = m.length(m.sub(site.position, ship.position));
            for (0..3) |slot| {
                if (distance >= nearest[slot]) continue;
                var tail: usize = 2;
                while (tail > slot) : (tail -= 1) {
                    nearest[tail] = nearest[tail - 1];
                    positions[tail + 1] = positions[tail];
                    colors[tail + 1] = colors[tail];
                }
                nearest[slot] = distance;
                positions[slot + 1] = m.add(site.position, v(0, 6, 10));
                colors[slot + 1] = .{ @as(f32, @floatFromInt(site.tint.r)) / 255, @as(f32, @floatFromInt(site.tint.g)) / 255, @as(f32, @floatFromInt(site.tint.b)) / 255, 100 };
                break;
            }
        }
        if (run) |state| {
            var best_score: f32 = 0;
            for (state.bursts) |burst| {
                if (burst.kind != .explosion or burst.age > 0.45) continue;
                const score = (1 - burst.age / 0.45) / (1 + m.length(m.sub(burst.position, ship.position)) * 0.02);
                if (score > best_score) {
                    best_score = score;
                    positions[0] = burst.position;
                    colors[0] = .{ 4 * (1 - burst.age / 0.45), 1.3, 0.25, 40 * burst.size };
                }
            }
            for (state.bolts) |bolt| {
                if (!bolt.active) continue;
                positions[3] = bolt.position;
                colors[3] = .{ 0.25, 1.8, 1.2, 27 };
                break;
            }
            if (state.hit_flash > 0 or state.xp_flash > 0) {
                positions[0] = ship.position;
                colors[0] = if (state.hit_flash > 0)
                    .{ state.hit_flash * 9, state.hit_flash * 2.5, 0.1, 24 }
                else
                    .{ 0.1, state.xp_flash * 6, state.xp_flash * 3, 18 };
            }
        }
        rl.setShaderValueV(r.scene, r.locations.light_pos, &positions, .vec3, 4);
        rl.setShaderValueV(r.scene, r.locations.light_color, &colors, .vec4, 4);
        drawModel(r.structures, r.scene, rl.math.matrixIdentity());
        // Close camera obstruction may move the eye inside the craft: hide it at that distance.
        if (m.length(m.sub(camera.position, ship.position)) > 10 and (run == null or !run.?.dead)) {
            const hit = if (run) |state| std.math.clamp(state.hit_flash / survivors.HIT_FLASH_TIME, 0, 1) else 0;
            const white_core = hit * hit * hit * hit;
            const flash: [4]f32 = if (run) |state|
                (if (hit > 0) .{ 1, 0.3 + white_core * 0.65, 0.12 + white_core * 0.83, @sqrt(hit) } else .{ 0.25, 1, 0.63, state.xp_flash / survivors.XP_FLASH_TIME * 0.65 })
            else
                .{ 0, 0, 0, 0 };
            r.drawFlashed(r.craft, transform, flash);
            r.exhaust(ship, transform, time);
        }
        if (run) |state| r.drawCombat(state, ship, time);
        rl.endMode3D();
        rl.endTextureMode();

        const texel = [2]f32{ 1.0 / @as(f32, @floatFromInt(r.target.texture.width)), 1.0 / @as(f32, @floatFromInt(r.target.texture.height)) };
        rl.setShaderValue(r.post, r.locations.texel, &texel, .vec2);
        const filtered = r.filters.begin();
        rl.beginShaderMode(r.post);
        rl.drawTexturePro(r.target.texture, .{ .x = 0, .y = 0, .width = @floatFromInt(r.target.texture.width), .height = -@as(f32, @floatFromInt(r.target.texture.height)) }, .{ .x = 0, .y = 0, .width = @floatFromInt(rl.getScreenWidth()), .height = @floatFromInt(rl.getScreenHeight()) }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.endShaderMode();
        if (filtered) r.filters.end(time);
        if (run) |state| {
            drawDamageFlash(state);
            if (!state.dead) {
                const width = rl.getScreenWidth() - 32;
                rl.drawRectangle(16, 14, width, 6, m.color(20, 30, 38));
                const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(width)) * @min(1, @as(f32, @floatFromInt(state.xp)) / @as(f32, @floatFromInt(state.need()))));
                rl.drawRectangle(16, 14, fill, 6, m.color(102, 221, 163));
                drawHull(state, ship, camera, time);
                hud.loadout(state);
            }
        }
    }

    fn drawCombat(r: *Renderer, run: *const survivors.Run, ship: flight.Ship, time: f32) void {
        for (run.drones) |d| {
            if (!d.active) continue;
            const direction = if (m.length(d.velocity) > 1) m.norm(d.velocity) else m.norm(m.sub(ship.position, d.position));
            const yaw = std.math.atan2(-direction.x, -direction.z);
            const transform = rl.math.matrixMultiply(rl.math.matrixRotateY(yaw), rl.math.matrixTranslate(d.position.x, d.position.y, d.position.z));
            r.drawFlashed(r.drones[d.wave % r.drones.len], transform, .{ 1, 0.91, 0.72, std.math.clamp(d.flash / survivors.ENEMY_FLASH_TIME, 0, 1) });
        }
        for (run.gems, 0..) |g, i| {
            if (!g.active) continue;
            const transform = rl.math.matrixMultiply(rl.math.matrixRotateY(time * 1.5 + @as(f32, @floatFromInt(i))), rl.math.matrixTranslate(g.position.x, g.position.y, g.position.z));
            drawModel(r.gem, r.scene, transform);
        }
        for (run.bolts) |b| {
            if (!b.active) continue;
            const tail = m.sub(b.position, m.scale(m.norm(b.velocity), 5.5));
            const tint = if (b.critical) m.color(255, 217, 97) else if (b.orbital) m.color(64, 195, 255) else m.color(41, 245, 126);
            rl.drawCylinderEx(tail, b.position, if (b.critical) 0.4 else 0.28, 0.23, 5, tint);
            rl.drawCylinderEx(tail, b.position, 0.105, 0.1, 4, m.color(221, 255, 223));
        }
        for (run.mines) |mine| {
            if (!mine.active) continue;
            const opacity = std.math.clamp((survivors.Mine.LIFETIME - mine.age) / (survivors.Mine.LIFETIME - survivors.Mine.FADE_TIME), 0, 1);
            rl.setShaderValue(r.scene, r.locations.opacity, &opacity, .float);
            const transform = rl.math.matrixMultiply(rl.math.matrixRotateY(mine.age * 0.8), rl.math.matrixTranslate(mine.position.x, mine.position.y, mine.position.z));
            drawModel(r.mine, r.scene, transform);
            const solid_opacity: f32 = 1;
            rl.setShaderValue(r.scene, r.locations.opacity, &solid_opacity, .float);
            if (mine.age >= survivors.Mine.ARM_TIME and mine.age < survivors.Mine.FADE_TIME) {
                const pulse = 0.16 + 0.12 * (0.5 + 0.5 * @sin(mine.age * 8));
                rl.drawSphereEx(m.add(mine.position, v(0, 0.72, 0)), pulse, 3, 4, m.color(255, 219, 126));
            }
        }
        for (run.rockets) |rocket| {
            if (!rocket.active) continue;
            const direction = m.norm(rocket.velocity);
            drawModel(r.rocket, r.scene, facingTransform(rocket.position, direction));
            for (rocket.trail[1..], 0..) |point, i| {
                const strength = 1 - @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rocket.trail.len));
                rl.drawCylinderEx(point, rocket.trail[i], 0.18 * strength, 0.22 * strength, 4, m.color(@intFromFloat(90 + 160 * strength), @intFromFloat(65 + 105 * strength), 64));
            }
            rl.drawCylinderEx(m.sub(rocket.position, m.scale(direction, 3.4)), rocket.position, 0.02, 0.25, 4, m.color(255, 207, 103));
        }
        for (run.orbitals) |orbital| {
            if (!orbital.visible or run.dead) continue;
            drawModel(r.orbital, r.scene, facingTransform(orbital.position, orbital.aim));
        }
        for (run.bursts, 0..) |b, index| {
            if (b.age > 0.75) continue;
            const fade = 1 - b.age / 0.75;
            switch (b.kind) {
                .explosion => {
                    if (b.age < 0.28) rl.drawSphereEx(b.position, (1.1 + b.age * 13) * @min(b.size, 1.7), 4, 6, m.color(255, @intFromFloat(100 + fade * 130), 70));
                    for (0..7) |i| {
                        const a = @as(f32, @floatFromInt(i)) * 2.399 + @as(f32, @floatFromInt(index));
                        const dir = m.norm(v(@cos(a), @sin(a * 2.7), @sin(a)));
                        const p = m.add(b.position, m.scale(dir, b.age * 22 * b.size));
                        const fragment = fade * @min(b.size, 1.2);
                        rl.drawCube(p, fragment, fragment, fragment, m.color(255, @intFromFloat(65 + 130 * fade), 52));
                    }
                },
                .pickup, .level => {
                    const life: f32 = if (b.kind == .level) 0.6 else 0.36;
                    if (b.age >= life) continue;
                    const strength = 1 - b.age / life;
                    const count: usize = if (b.kind == .level) 10 else 4;
                    for (0..count) |i| {
                        const a = @as(f32, @floatFromInt(i)) * 2.399 + @as(f32, @floatFromInt(index)) * 1.7;
                        const dir = m.norm(v(@cos(a), @sin(a * 1.7), @sin(a)));
                        const p = m.add(b.position, m.scale(dir, (1.5 + b.age * 10) * @max(b.size, 0.8)));
                        const size = (0.12 + strength * 0.16) * @max(b.size, 0.8);
                        rl.drawCube(p, size, size, size, m.color(115, @intFromFloat(130 + strength * 125), 177));
                    }
                },
                .hit => {
                    if (b.age >= 0.28) continue;
                    const strength = 1 - b.age / 0.28;
                    const player_hit = b.size >= 0.8;
                    const count: usize = if (player_hit) 10 else 6;
                    for (0..count) |i| {
                        const a = @as(f32, @floatFromInt(i)) * 2.399 + @as(f32, @floatFromInt(index));
                        const dir = m.norm(v(@cos(a), @sin(a * 2.1), @sin(a)));
                        const start: f32 = if (player_hit) 3 else 1;
                        const p = m.add(b.position, m.scale(dir, (start + b.age * 26) * @max(b.size, 0.5)));
                        rl.drawCylinderEx(p, m.add(p, m.scale(dir, strength * 0.8)), 0.06 * strength, 0.025, 3, m.color(255, @intFromFloat(140 + 100 * strength), 140));
                    }
                },
            }
        }
        if (run.hp <= 2 and !run.dead) {
            const trail = m.add(ship.position, m.scale(ship.forward(), -4));
            for (0..4) |i| {
                const phase = @mod(time * 2 + @as(f32, @floatFromInt(i)) / 4, 1);
                const p = m.add(trail, v(phase * 2, phase * 5, phase * 3));
                rl.drawSphereEx(p, 0.5 + phase, 3, 4, m.color(54, 40, 42));
            }
        }
    }

    fn drawFlashed(r: *Renderer, model: rl.Model, transform: rl.Matrix, flash: [4]f32) void {
        if (flash[3] <= 0) {
            drawModel(model, r.scene, transform);
            return;
        }
        rl.setShaderValue(r.scene, r.locations.flash, &flash, .vec4);
        drawModel(model, r.scene, transform);
        const off = [4]f32{ 0, 0, 0, 0 };
        rl.setShaderValue(r.scene, r.locations.flash, &off, .vec4);
    }

    fn drawSky(r: *Renderer, cam: rl.Camera3D) void {
        const forward = m.norm(m.sub(cam.target, cam.position));
        const right = m.norm(m.cross(forward, cam.up));
        const up = m.cross(right, forward);
        const lens = [2]f32{ @as(f32, @floatFromInt(r.target.texture.width)) / @as(f32, @floatFromInt(r.target.texture.height)), @tan(cam.fovy * std.math.pi / 360.0) };
        rl.setShaderValue(r.sky, r.locations.sky_forward, &forward, .vec3);
        rl.setShaderValue(r.sky, r.locations.sky_right, &right, .vec3);
        rl.setShaderValue(r.sky, r.locations.sky_up, &up, .vec3);
        rl.setShaderValue(r.sky, r.locations.sky_lens, &lens, .vec2);
        rl.beginShaderMode(r.sky);
        rl.drawTexturePro(r.white, .{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{ .x = 0, .y = 0, .width = @floatFromInt(r.target.texture.width), .height = @floatFromInt(r.target.texture.height) }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.endShaderMode();
    }

    fn exhaust(_: *Renderer, ship: flight.Ship, transform: rl.Matrix, time: f32) void {
        const power = std.math.clamp(ship.speed() / flight.SPEED, 0, 1);
        const length = 0.7 + power * (2.1 + @sin(time * 31) * 0.25);
        for ([_]f32{ -1.3, 1.3 }) |x| {
            const a = rl.math.vector3Transform(v(x, -0.05, 3.04), transform);
            const b = rl.math.vector3Transform(v(x, -0.05, 3.04 + length), transform);
            rl.drawCylinderEx(a, b, 0.26, 0.02, 5, m.color(86, 209, 250));
            rl.drawCylinderEx(a, m.mix(a, b, 0.6), 0.17, 0.02, 5, m.color(213, 250, 255));
        }
    }
};

fn compile(vs: ?[:0]const u8, fs: [:0]const u8) rl.Shader {
    const shader = rl.loadShaderFromMemory(vs, fs) catch @panic("shader compilation failed");
    if (shader.id == rl.gl.rlGetShaderIdDefault()) @panic("shader fell back to default");
    return shader;
}

fn drawHull(run: *const survivors.Run, ship: flight.Ship, camera: rl.Camera3D, time: f32) void {
    const width: i32 = 92;
    const height: i32 = 6;
    const screen_w = rl.getScreenWidth();
    const screen_h = rl.getScreenHeight();
    var anchor = rl.getWorldToScreen(m.add(ship.position, m.scale(camera.up, -2.8)), camera);
    if (m.length(m.sub(camera.position, ship.position)) <= 10) {
        anchor = .{ .x = @as(f32, @floatFromInt(screen_w)) * 0.5, .y = @as(f32, @floatFromInt(screen_h)) * 0.78 };
    }
    const x: i32 = @intFromFloat(std.math.clamp(anchor.x - @as(f32, @floatFromInt(width)) / 2, 16, @as(f32, @floatFromInt(screen_w - width - 16))));
    const y: i32 = @intFromFloat(std.math.clamp(anchor.y + 8, 32, @as(f32, @floatFromInt(screen_h - 24))));
    const fraction = std.math.clamp(@as(f32, @floatFromInt(run.hp)) / @as(f32, @floatFromInt(@max(run.max_hp, 1))), 0, 1);
    const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(width)) * fraction);
    const hit = std.math.clamp(run.hit_flash / survivors.HIT_FLASH_TIME, 0, 1);
    var tint = if (fraction <= 0.4) m.color(246, 88, 65) else if (fraction <= 0.6) m.color(244, 181, 87) else m.color(120, 218, 188);
    if (fraction <= 0.4) tint.a = @intFromFloat(205 + 50 * (0.5 + 0.5 * @sin(time * 5)));
    rl.drawRectangle(x - 2, y - 2, width + 4, height + 4, m.color(7, 11, 17));
    rl.drawRectangle(x, y, width, height, m.color(43, 48, 53));
    if (hit > 0) {
        const previous = @min(1, fraction + 1 / @as(f32, @floatFromInt(@max(run.max_hp, 1))));
        const lost: i32 = @intFromFloat(@as(f32, @floatFromInt(width)) * previous);
        rl.drawRectangle(x + fill, y, lost - fill, height, .{ .r = 255, .g = 186, .b = 126, .a = @intFromFloat(hit * 230) });
        if (hit > 0.7) tint = m.color(255, 235, 210);
    }
    rl.drawRectangle(x, y, fill, height, tint);
}

fn drawDamageFlash(run: *const survivors.Run) void {
    const strength = std.math.clamp(run.hit_flash / survivors.HIT_FLASH_TIME, 0, 1);
    if (strength <= 0) return;
    const width = rl.getScreenWidth();
    const height = rl.getScreenHeight();
    const depth = @divTrunc(@min(width, height), 9);
    const edge = rl.Color{ .r = 255, .g = 65, .b = 35, .a = @intFromFloat(strength * strength * 46) };
    const clear = rl.Color{ .r = 255, .g = 65, .b = 35, .a = 0 };
    rl.drawRectangleGradientH(0, 0, depth, height, edge, clear);
    rl.drawRectangleGradientH(width - depth, 0, depth, height, clear, edge);
    rl.drawRectangleGradientV(0, 0, width, depth, edge, clear);
    rl.drawRectangleGradientV(0, height - depth, width, depth, clear, edge);
}
fn makeTarget() rl.RenderTexture2D {
    const target = rl.loadRenderTexture(@divTrunc(rl.getScreenWidth() * 2, 3), @divTrunc(rl.getScreenHeight() * 2, 3)) catch @panic("scene target");
    rl.setTextureFilter(target.texture, .point);
    return target;
}
fn uniform(shader: rl.Shader, name: [:0]const u8, data: *const anyopaque, kind: rl.ShaderUniformDataType) void {
    rl.setShaderValue(shader, rl.getShaderLocation(shader, name), data, kind);
}
fn drawModel(model: rl.Model, shader: rl.Shader, transform: rl.Matrix) void {
    var material = model.materials[0];
    material.shader = shader;
    rl.drawMesh(model.meshes[0], material, transform);
}
fn shipTransform(ship: flight.Ship) rl.Matrix {
    const orientation = m.qmul(ship.orientation, m.axis(v(0, 0, 1), ship.bank));
    return rl.math.matrixMultiply(rl.math.quaternionToMatrix(orientation), rl.math.matrixTranslate(ship.position.x, ship.position.y, ship.position.z));
}

fn facingTransform(position: m.V, direction: m.V) rl.Matrix {
    const yaw = std.math.atan2(-direction.x, -direction.z);
    const pitch = std.math.asin(std.math.clamp(direction.y, -1, 1));
    const rotation = m.qmul(m.axis(v(0, 1, 0), yaw), m.axis(v(1, 0, 0), pitch));
    return rl.math.matrixMultiply(rl.math.quaternionToMatrix(rotation), rl.math.matrixTranslate(position.x, position.y, position.z));
}
