const std = @import("std");
const m = @import("math.zig");
const rl = @import("raylib");
pub const terrain = @import("terrain.zig");
const v = m.v;
pub const CENTER = v(0, 0, -120);
pub const RADIUS: f32 = 3600;
pub const SITE_COUNT = 20;
pub const Level = enum { space, jungle };
pub fn levelName(level: Level) [:0]const u8 {
    return switch (level) {
        .space => "Space",
        .jungle => "Jungle Ruins",
    };
}
pub const Material = enum { flat, metal, hazard, glow, rock, planet, stone, bark, foliage, ground, water };
pub const Tree = struct { position: m.V, height: f32, radius: f32, angle: f32, tint: rl.Color };
pub const Solid = struct {
    box: m.Box,
    tint: rl.Color,
    mat: Material = .metal,
    rotation: m.Q = m.identity,
    bound: f32 = 0,
    pub fn local(s: Solid, p: m.V) m.V {
        return m.rotate(m.inverse(s.rotation), m.sub(p, s.box.center));
    }
    pub fn extent(s: Solid) f32 {
        return if (s.bound > 0) s.bound else m.length(s.box.half);
    }
};
pub const Landmark = struct { position: m.V, tint: rl.Color, rotation: m.Q, kind: usize };
pub const Body = struct {
    position: m.V,
    radii: m.V,
    tint: rl.Color,
    planet: bool = false,
    pub fn extent(b: Body) f32 {
        return @max(b.radii.x, @max(b.radii.y, b.radii.z));
    }
};
pub const cyan = m.color(88, 226, 241);
pub const amber = m.color(255, 177, 79);
pub const mint = m.color(142, 237, 175);
const CollisionGroup = struct { first: usize, end: usize, center: m.V, radius: f32 };
pub const World = struct {
    solids: [2048]Solid = undefined,
    count: usize = 0,
    sites: [SITE_COUNT]Landmark = undefined,
    site_count: usize = 0,
    bodies: [180]Body = undefined,
    body_count: usize = 0,
    seed: u64 = 0,
    collision_groups: [384]CollisionGroup = undefined,
    group_count: usize = 0,
    indexed_count: usize = 0,
    level: Level = .space,
    ground: terrain.Terrain = undefined,
    trees: [280]Tree = undefined,
    tree_count: usize = 0,

    pub fn generateLevel(level: Level, seed: u64) World {
        if (level == .space) return generate(seed);
        var w = World{ .seed = seed, .level = .jungle, .ground = terrain.Terrain.generate(seed) };
        @import("jungle.zig").populate(&w, seed);
        return w;
    }
    pub fn spawn(w: *const World) m.V {
        return if (w.level == .space) v(0, 0, 70) else v(0, w.ground.floor(0, 70).height + 32, 70);
    }
    pub fn boundaryCenter(w: *const World) m.V {
        return if (w.level == .space) CENTER else m.zero;
    }
    pub fn boundaryRadius(w: *const World) f32 {
        return if (w.level == .space) RADIUS else 1400;
    }
    pub fn floorHeight(w: *const World, x: f32, z: f32) f32 {
        return if (w.level == .jungle) w.ground.floor(x, z).height else -10000;
    }

    pub fn init() World {
        return generate(0xF123);
    }
    pub fn generate(seed: u64) World {
        var w = World{ .seed = seed };
        var rng = std.Random.DefaultPrng.init(seed);
        const random = rng.random();
        const planet_positions = [_]m.V{ v(1250, 360, -1600), v(-1800, -440, -1100), v(350, 680, 2150) };
        const planet_colors = [_]rl.Color{ m.color(70, 125, 162), m.color(168, 101, 67), m.color(115, 148, 132) };
        for (planet_positions, 0..) |p, i| {
            const radius = 330 + random.float(f32) * 130;
            w.bodies[w.body_count] = .{ .position = m.add(p, v(jitter(random, 200), jitter(random, 110), jitter(random, 200))), .radii = v(radius, radius, radius), .tint = planet_colors[i], .planet = true };
            w.body_count += 1;
        }
        for (0..SITE_COUNT) |i| {
            var center = v(135, 40, -295);
            if (i != 0) {
                var placed = false;
                for (0..200) |_| {
                    const angle = random.float(f32) * std.math.tau;
                    const radius = 480 + random.float(f32) * 2250;
                    center = m.add(CENTER, v(@cos(angle) * radius, jitter(random, 720), @sin(angle) * radius));
                    if (!w.siteClear(center, 220)) continue;
                    placed = true;
                    break;
                }
                if (!placed) break;
            }
            const rotation = m.qmul(m.axis(v(0, 1, 0), random.float(f32) * std.math.tau), m.qmul(m.axis(v(1, 0, 0), jitter(random, 0.65)), m.axis(v(0, 0, 1), jitter(random, 0.85))));
            const tint = ([_]rl.Color{ cyan, amber, mint, m.color(179, 142, 247) })[i % 4];
            const site = Landmark{ .position = center, .rotation = rotation, .tint = tint, .kind = i % 4 };
            w.sites[w.site_count] = site;
            w.site_count += 1;
            const first = w.count;
            w.station(site, random);
            w.finishGroup(first, site.position);
        }
        // Scattered groups, each with its own tilted belt plane and unequal rocks.
        for (0..9) |cluster| {
            const angle = @as(f32, @floatFromInt(cluster)) * 2.399 + random.float(f32);
            const distance: f32 = if (cluster == 0) 650 else 850 + random.float(f32) * 1900;
            const center = m.add(CENTER, v(@cos(angle) * distance, jitter(random, 600), @sin(angle) * distance));
            const rotation = m.qmul(m.axis(v(0, 1, 0), angle), m.axis(v(0, 0, 1), jitter(random, 1)));
            for (0..18) |_| {
                const p = m.add(center, m.rotate(rotation, v(jitter(random, 260), jitter(random, 100), jitter(random, 260))));
                const size = 12 + random.float(f32) * 52;
                if (m.length(m.sub(p, v(0, 0, 70))) < 260 or !w.siteClear(p, size + 35)) continue;
                var overlaps = false;
                for (w.bodies[0..w.body_count]) |body| {
                    if (m.length(m.sub(p, body.position)) < size * 1.3 + body.extent() + 20) overlaps = true;
                }
                if (overlaps) continue;
                w.bodies[w.body_count] = .{
                    .position = p,
                    .radii = v(size, size * (0.65 + random.float(f32) * 0.55), size * (0.7 + random.float(f32) * 0.6)),
                    .tint = ([_]rl.Color{ m.color(121, 109, 99), m.color(100, 114, 132), m.color(134, 117, 99) })[cluster % 3],
                };
                w.body_count += 1;
            }
        }
        return w;
    }

    fn siteClear(w: *const World, p: m.V, margin: f32) bool {
        for (w.sites[0..w.site_count]) |site| if (m.length(m.sub(p, site.position)) < 210 + margin) return false;
        for (w.bodies[0..@min(w.body_count, 3)]) |body| if (m.length(m.sub(p, body.position)) < body.extent() + margin + 80) return false;
        return true;
    }
    fn station(w: *World, site: Landmark, random: std.Random) void {
        const steel = m.color(68, 81, 101);
        const dark = m.color(43, 51, 68);
        const rim = m.color(116, 127, 140);
        const q = m.identity;
        switch (site.kind) {
            0 => {
                // Broken octagonal trusses, staggered modules and offset service booms.
                const radius = 45 + random.float(f32) * 25;
                const rings = random.intRangeAtMost(usize, 2, 4);
                for (0..rings) |ring| {
                    const z = (@as(f32, @floatFromInt(ring)) - @as(f32, @floatFromInt(rings - 1)) / 2) * 48;
                    const twist = @as(f32, @floatFromInt(ring)) * 0.13;
                    for (0..8) |j| {
                        if (ring > 0 and j == 2) continue;
                        const a = @as(f32, @floatFromInt(j)) * std.math.tau / 8 + twist;
                        const rot = m.axis(v(0, 0, 1), a);
                        const p = v(@cos(a) * radius, @sin(a) * radius, z);
                        w.part(site, p, v(9, radius * 0.85, 12), rot, steel, .metal);
                        w.part(site, m.add(p, v(0, 0, 6.2)), v(1.4, radius * 0.69, 0.5), rot, site.tint, .glow);
                    }
                }
                w.part(site, v(-radius - 18, -10, 10), v(24, 35, 100), q, dark, .metal);
                w.part(site, v(-radius - 60, -24, 15), v(95, 7, 9), m.axis(v(0, 0, 1), -0.25), rim, .metal);
                w.part(site, v(-radius - 98, -14, 15), v(20, 27, 25), q, steel, .metal);
            },
            1 => {
                // A crooked spine with unequal branches and independently canted radiator wings.
                w.part(site, v(0, -22, 0), v(185, 12, 18), q, steel, .metal);
                for (0..5) |j| {
                    const x = (@as(f32, @floatFromInt(j)) - 2) * 38;
                    const height = 35 + random.float(f32) * 54;
                    const z = jitter(random, 15);
                    w.part(site, v(x, height / 2 - 22, z), v(6, height, 8), q, rim, .metal);
                    const wing = m.qmul(m.axis(v(0, 1, 0), jitter(random, 0.65)), m.axis(v(0, 0, 1), jitter(random, 0.3)));
                    const p = v(x, height - 25, z);
                    w.part(site, p, v(28, 5, 65 + random.float(f32) * 32), wing, dark, .metal);
                    w.part(site, m.add(p, v(0, 3, 0)), v(22, 0.8, 58), wing, site.tint, .glow);
                }
                w.part(site, v(-88, -18, 0), v(30, 43, 48), q, steel, .metal);
            },
            2 => {
                // Unequal refinery stacks on offset terraces, linked by narrow pipe bridges.
                for (0..4) |j| {
                    const x = (@as(f32, @floatFromInt(j)) - 1.5) * 39;
                    const z = jitter(random, 45);
                    const height = 42 + random.float(f32) * 90;
                    const base = jitter(random, 14) - 35;
                    w.part(site, v(x, base, z), v(33, 7, 48), q, dark, .metal);
                    w.part(site, v(x, base + height / 2, z), v(17, height, 22), q, steel, .metal);
                    for (0..4) |rib| {
                        const y = base + height * (@as(f32, @floatFromInt(rib)) + 0.5) / 4;
                        w.part(site, v(x, y, z), v(23, 3, 28), q, rim, .metal);
                    }
                    w.part(site, v(x, base + height + 2, z), v(18, 3, 23), q, site.tint, .glow);
                    if (j > 0) w.part(site, v(x - 20, base + 12, z), v(40, 5, 6), m.axis(v(0, 1, 0), 0.25), rim, .metal);
                }
            },
            else => {
                // An asymmetric shipyard: two unequal arms and suspended cargo.
                for ([_]f32{ -1, 1 }) |side| {
                    const length = 135 + random.float(f32) * 75;
                    w.part(site, v(side * 48, -25, side * 18), v(16, 19, length), q, steel, .metal);
                    for (0..3) |j| {
                        const z = (@as(f32, @floatFromInt(j)) - 1) * 51 + side * 18;
                        const height = 42 + random.float(f32) * 23;
                        w.part(site, v(side * 48, height / 2 - 25, z), v(8, height, 8), q, rim, .metal);
                        w.part(site, v(side * 37, height - 25, z), v(32, 6, 10), m.axis(v(0, 0, 1), side * 0.2), dark, .metal);
                        w.part(site, v(side * 27, height - 29, z), v(6, 1, 7), q, site.tint, .glow);
                    }
                }
                for (0..5) |_| {
                    const p = v(jitter(random, 85), -53 - random.float(f32) * 40, jitter(random, 85));
                    w.part(site, p, v(21, 19, 32), m.axis(v(0, 1, 0), jitter(random, 0.7)), dark, .metal);
                }
            },
        }
    }
    pub fn part(w: *World, site: Landmark, p: m.V, size: m.V, rotation: m.Q, tint: rl.Color, mat: Material) void {
        std.debug.assert(w.count < w.solids.len);
        const half = m.scale(size, 0.5);
        w.solids[w.count] = .{ .box = .{ .center = m.add(site.position, m.rotate(site.rotation, p)), .half = half }, .rotation = m.qmul(site.rotation, rotation), .bound = m.length(half), .tint = tint, .mat = mat };
        w.count += 1;
    }
    pub fn finishGroup(w: *World, first: usize, position: m.V) void {
        std.debug.assert(w.group_count < w.collision_groups.len);
        var bound: f32 = 0;
        for (w.solids[first..w.count]) |solid| bound = @max(bound, m.length(m.sub(solid.box.center, position)) + solid.extent());
        w.collision_groups[w.group_count] = .{ .first = first, .end = w.count, .center = position, .radius = bound + 0.01 };
        w.group_count += 1;
        w.indexed_count = w.count;
    }
    pub fn items(w: *const World) []const Solid {
        return w.solids[0..w.count];
    }
    // Generation freezes station geometry. Hand-built worlds use the unindexed fallback.
    const Candidates = struct {
        w: *const World,
        index: usize = 0,
        end: usize = 0,
        group: usize = 0,
        fn next(it: *Candidates, from: m.V, reach: f32) ?*const Solid {
            if (it.w.group_count == 0 or it.w.indexed_count != it.w.count) {
                if (it.index == it.w.count) return null;
                defer it.index += 1;
                return &it.w.solids[it.index];
            }
            while (it.index >= it.end) {
                if (it.group == it.w.group_count) return null;
                const group = it.w.collision_groups[it.group];
                it.group += 1;
                const delta = m.sub(from, group.center);
                const bound = group.radius + reach;
                if (m.dot(delta, delta) > bound * bound) continue;
                it.index = group.first;
                it.end = group.end;
            }
            defer it.index += 1;
            return &it.w.solids[it.index];
        }
    };
    pub fn cast(w: *const World, from: m.V, delta: m.V, radius: f32) ?m.Hit {
        var closest: ?m.Hit = null;
        const reach = m.length(delta) + radius;
        var candidates = Candidates{ .w = w };
        while (candidates.next(from, reach)) |s| {
            const diff = m.sub(from, s.box.center);
            const bound = s.extent() + reach;
            if (m.dot(diff, diff) > bound * bound) continue;
            const inv = m.inverse(s.rotation);
            if (m.sweep(m.rotate(inv, diff), m.rotate(inv, delta), .{ .center = m.zero, .half = m.add(s.box.half, v(radius, radius, radius)) })) |hit| {
                if (closest == null or hit.t < closest.?.t) closest = .{ .t = hit.t, .normal = m.rotate(s.rotation, hit.normal) };
            }
        }
        for (w.bodies[0..w.body_count]) |body| {
            const diff = m.sub(from, body.position);
            const bound = body.extent() + reach;
            if (m.dot(diff, diff) > bound * bound) continue;
            if (m.sweepEllipsoid(from, delta, body.position, m.add(body.radii, v(radius, radius, radius)))) |hit| {
                if (closest == null or hit.t < closest.?.t) closest = hit;
            }
        }
        if (w.level == .jungle) {
            if (w.ground.cast(from, delta, radius)) |hit| {
                if (closest == null or hit.t < closest.?.t) closest = hit;
            }
        }
        return closest;
    }
    pub fn clear(w: *const World, p: m.V, radius: f32) bool {
        if (w.level == .jungle and !w.ground.clear(p, radius)) return false;
        var candidates = Candidates{ .w = w };
        while (candidates.next(p, radius)) |s| {
            const diff = m.sub(p, s.box.center);
            const bound = s.extent() + radius;
            if (m.dot(diff, diff) > bound * bound) continue;
            const box = m.Box{ .center = m.zero, .half = m.add(s.box.half, v(radius, radius, radius)) };
            if (box.contains(s.local(p))) return false;
        }
        for (w.bodies[0..w.body_count]) |body| {
            const d = m.divide(m.sub(p, body.position), m.add(body.radii, v(radius, radius, radius)));
            if (m.dot(d, d) < 1) return false;
        }
        return true;
    }
    pub fn recover(w: *const World, position: *m.V, velocity: *m.V, radius: f32) void {
        for (0..3) |_| {
            var candidates = Candidates{ .w = w };
            while (candidates.next(position.*, radius)) |s| {
                const diff = m.sub(position.*, s.box.center);
                const bound = s.extent() + radius;
                if (m.dot(diff, diff) > bound * bound) continue;
                var p = s.local(position.*);
                const half = m.add(s.box.half, v(radius, radius, radius));
                if (!(m.Box{ .center = m.zero, .half = half }).contains(p)) continue;
                const gap = m.sub(half, v(@abs(p.x), @abs(p.y), @abs(p.z)));
                var normal = m.zero;
                if (gap.x <= gap.y and gap.x <= gap.z) {
                    normal.x = std.math.sign(p.x + 0.00001);
                    p.x = normal.x * (half.x + 0.002);
                } else if (gap.y <= gap.z) {
                    normal.y = std.math.sign(p.y + 0.00001);
                    p.y = normal.y * (half.y + 0.002);
                } else {
                    normal.z = std.math.sign(p.z + 0.00001);
                    p.z = normal.z * (half.z + 0.002);
                }
                position.* = m.add(s.box.center, m.rotate(s.rotation, p));
                normal = m.rotate(s.rotation, normal);
                velocity.* = m.sub(velocity.*, m.scale(normal, @min(0, m.dot(velocity.*, normal))));
            }
            for (w.bodies[0..w.body_count]) |body| {
                const radii = m.add(body.radii, v(radius + 0.01, radius + 0.01, radius + 0.01));
                const p = m.divide(m.sub(position.*, body.position), radii);
                if (m.dot(p, p) >= 1) continue;
                const n = if (m.length(p) > 0.00001) m.norm(p) else v(0, 1, 0);
                position.* = m.add(body.position, m.product(n, radii));
                const normal = m.norm(m.divide(n, radii));
                velocity.* = m.sub(velocity.*, m.scale(normal, @min(0, m.dot(velocity.*, normal))));
            }
            if (w.level == .jungle) w.ground.recover(position, velocity, radius);
        }
    }
};
fn jitter(random: std.Random, radius: f32) f32 {
    return (random.float(f32) * 2 - 1) * radius;
}

test "procedural regions reproduce their seed, vary between runs and preserve launch clearance" {
    const a = World.generate(91);
    const b = World.generate(91);
    const c = World.generate(92);
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqual(a.sites[4].position, b.sites[4].position);
    try std.testing.expect(!std.meta.eql(a.sites[4].position, c.sites[4].position));
    for ([_]u64{ 91, 92, 93, 0xF123 }) |seed| {
        const w = World.generate(seed);
        try std.testing.expectEqual(@as(usize, SITE_COUNT), w.site_count);
        try std.testing.expect(w.body_count > 35);
        try std.testing.expect(w.clear(v(0, 0, 70), 4.6));
        try std.testing.expect(w.cast(v(0, 0, 100), v(0, 0, -350), 4.6) == null);
        for (w.bodies[0..w.body_count]) |body| try std.testing.expect(m.length(m.sub(body.position, CENTER)) + body.extent() < RADIUS);
    }
}
test "rotated structures and celestial bodies block swept paths with world normals" {
    var w = World{};
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = m.zero, .half = v(15, 15, 1) }, .rotation = m.axis(v(0, 1, 0), std.math.pi / 4.0), .tint = cyan };
    const hit = w.cast(v(0, 0, 30), v(0, 0, -60), 1).?;
    try std.testing.expect(hit.normal.x > 0.6 and hit.normal.z > 0.6);
    w.count = 0;
    w.body_count = 1;
    w.bodies[0] = .{ .position = m.zero, .radii = v(20, 10, 15), .tint = cyan };
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), w.cast(v(0, 0, 40), v(0, 0, -80), 1).?.t, 0.0001);
    try std.testing.expect(w.cast(v(25, 0, 40), v(0, 0, -80), 1) == null);
    var p = m.zero;
    var velocity = v(0, -1, 0);
    w.recover(&p, &velocity, 4.6);
    try std.testing.expect(w.clear(p, 4.6));
}

test "station broad phase matches unindexed casts clearance and recovery" {
    const w = World.init();
    var reference = w;
    reference.group_count = 0;
    var rng = std.Random.DefaultPrng.init(5921);
    const random = rng.random();
    for (0..1600) |i| {
        const site = w.sites[i % w.site_count];
        const from = m.add(site.position, v(jitter(random, 250), jitter(random, 250), jitter(random, 250)));
        const delta = v(jitter(random, 600), jitter(random, 600), jitter(random, 600));
        const radius = random.float(f32) * 6;
        try std.testing.expectEqualDeep(reference.cast(from, delta, radius), w.cast(from, delta, radius));
        try std.testing.expectEqual(reference.clear(from, radius), w.clear(from, radius));
    }
    for (w.items()) |solid| {
        var position = solid.box.center;
        var expected = position;
        var velocity = v(2, -3, 5);
        var expected_velocity = velocity;
        w.recover(&position, &velocity, 4.6);
        reference.recover(&expected, &expected_velocity, 4.6);
        try std.testing.expectEqualDeep(expected, position);
        try std.testing.expectEqualDeep(expected_velocity, velocity);
    }
}

test "jungle seeds keep the launch clear and index every ruin and banyan" {
    for ([_]u64{ 0, 91, 0xF123, 928147, 18446744073709551615 }) |seed| {
        const w = World.generateLevel(.jungle, seed);
        try std.testing.expectEqual(Level.jungle, w.level);
        try std.testing.expect(w.clear(w.spawn(), 4.6));
        try std.testing.expectEqual(w.count, w.indexed_count);
        try std.testing.expectEqual(@as(usize, 12), w.site_count);
        try std.testing.expect(w.tree_count >= 200);
        try std.testing.expect(w.ground.max_height + 20 < terrain.CEILING);
        const river = v(terrain.riverX(600), 40, 600);
        try std.testing.expect(w.ground.cast(river, v(0, -80, 0), 0) != null);
    }
    const space = World.generateLevel(.space, 91);
    try std.testing.expectEqual(Level.space, space.level);
    try std.testing.expectEqualDeep(v(0, 0, 70), space.spawn());
    try std.testing.expect(space.body_count > 3);
}
