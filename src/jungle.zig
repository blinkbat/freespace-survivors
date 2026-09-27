const std = @import("std");
const world = @import("world.zig");
const m = @import("math.zig");
const v = m.v;

pub fn populate(w: *world.World, seed: u64) void {
    var rng = std.Random.DefaultPrng.init(seed ^ 0x4a554e474c45);
    const random = rng.random();
    for (0..12) |i| {
        var x: f32 = 0;
        var z: f32 = -140;
        if (i > 0) {
            const angle = @as(f32, @floatFromInt(i)) * 2.399;
            const distance = 330 + random.float(f32) * 850;
            x = @cos(angle) * distance;
            z = @sin(angle) * distance;
        }
        const site = world.Landmark{
            .position = v(x, w.floorHeight(x, z), z),
            .rotation = m.axis(v(0, 1, 0), if (i == 0) 0 else random.float(f32) * std.math.tau),
            .tint = if (i % 3 == 0) m.color(77, 240, 199) else if (i % 3 == 1) m.color(159, 179, 255) else m.color(242, 192, 94),
            .kind = i % 4,
        };
        w.sites[w.site_count] = site;
        w.site_count += 1;
        const first = w.count;
        ruin(w, site, random);
        w.finishGroup(first, site.position);
    }
    // Half-buried colonnades trace the river, with gaps wide enough to weave through.
    for (0..18) |i| {
        const z = -1060 + @as(f32, @floatFromInt(i)) * 119;
        const x = world.terrain.riverX(z) + (if (i % 2 == 0) @as(f32, -42) else 47);
        const site = world.Landmark{ .position = v(x, -12, z), .rotation = m.axis(v(0, 0, 1), (random.float(f32) - 0.5) * 0.34), .tint = m.color(84, 224, 194), .kind = 0 };
        const first = w.count;
        const h = 57 + random.float(f32) * 65;
        w.part(site, v(0, h / 2, 0), v(17, h, 20), m.identity, m.color(112, 139, 117), .stone);
        w.part(site, v(0, h, 0), v(27, 9, 30), m.identity, m.color(142, 161, 130), .stone);
        rune(w, site, v(0, h * 0.65, 10.3), 4);
        w.finishGroup(first, site.position);
    }
    for (0..1800) |_| {
        if (w.tree_count == w.trees.len) break;
        const x = (random.float(f32) - 0.5) * 2750;
        const z = (random.float(f32) - 0.5) * 2750;
        const ground = w.ground.surface(x, z);
        if (ground.height < world.terrain.WATER + 3 or ground.normal.y < 0.82) continue;
        if (x * x + (z - 70) * (z - 70) < 85 * 85) continue;
        if (@abs(x) < 46 and z > -230 and z < 170) continue;
        var blocked = false;
        for (w.sites[0..w.site_count]) |site| {
            const delta = m.sub(v(x, site.position.y, z), site.position);
            if (m.dot(delta, delta) < 78 * 78) blocked = true;
        }
        for (w.trees[0..w.tree_count]) |tree| {
            const dx = x - tree.position.x;
            const dz = z - tree.position.z;
            if (dx * dx + dz * dz < 35 * 35) blocked = true;
        }
        if (blocked) continue;
        const height = @min(145 + random.float(f32) * 30, world.terrain.CEILING - ground.height - 22);
        const tree = world.Tree{ .position = v(x, ground.height - 2, z), .height = height, .radius = 3 + random.float(f32) * 3, .angle = random.float(f32) * std.math.tau, .tint = m.color(@intFromFloat(32 + random.float(f32) * 28), @intFromFloat(85 + random.float(f32) * 42), @intFromFloat(52 + random.float(f32) * 28)) };
        w.trees[w.tree_count] = tree;
        w.tree_count += 1;
        const first = w.count;
        const site = world.Landmark{ .position = tree.position, .rotation = m.identity, .tint = tree.tint, .kind = 0 };
        // Trunk collider; foliage is soft cover and remains fly-through.
        w.part(site, v(0, height * 0.43, 0), v(tree.radius * 1.4, height * 0.86, tree.radius * 1.4), m.identity, m.color(57, 64, 39), .bark);
        w.finishGroup(first, tree.position);
    }
}

fn rune(w: *world.World, site: world.Landmark, center: m.V, scale: f32) void {
    // Broken angular sigils, sunk into the front face of a standing stone.
    for ([_]f32{ -1, 1 }) |side| {
        w.part(site, m.add(center, v(side * scale * 0.42, 0, 0)), v(scale * 0.16, scale * 1.5, 0.24), m.axis(v(0, 0, 1), side * 0.48), site.tint, .glow);
    }
    w.part(site, m.add(center, v(0, -scale * 0.95, 0)), v(scale * 0.7, scale * 0.16, 0.24), m.identity, site.tint, .glow);
    w.part(site, m.add(center, v(0, scale * 1.15, 0)), v(scale * 0.23, scale * 0.32, 0.24), m.identity, site.tint, .glow);
}

fn ruin(w: *world.World, site: world.Landmark, random: std.Random) void {
    const stone = m.color(91, 117, 103);
    const moss = m.color(60, 88, 66);
    const pale = m.color(146, 158, 130);
    const q = m.identity;
    switch (site.kind) {
        0 => {
            // Voussoirs form a true arch, 150 metres wide, above the old gate.
            for ([_]f32{ -1, 1 }) |side| {
                w.part(site, v(side * 70, 33, -23), v(20, 70, 25), q, stone, .stone);
                w.part(site, v(side * 70, 0, -23), v(31, 12, 35), q, moss, .stone);
                rune(w, site, v(side * 70, 42, -9.9), 7);
            }
            for (0..13) |j| {
                const a = (@as(f32, @floatFromInt(j)) + 0.5) * std.math.pi / 13;
                w.part(site, v(@cos(a) * 70, 66 + @sin(a) * 70, -23), v(19, 20, 25), m.axis(v(0, 0, 1), a - std.math.pi / 2.0), if (j % 3 == 0) pale else stone, .stone);
            }
            // A monumental broken gate with two small passages beside the central opening.
            for ([_]f32{ -1, 1 }) |side| {
                w.part(site, v(side * 29, 25, 0), v(14, 54, 17), m.axis(v(0, 0, 1), side * 0.07), stone, .stone);
                w.part(site, v(side * 29, 53, 0), v(21, 8, 23), q, pale, .stone);
                w.part(site, v(side * 46, 10, 6), v(13, 23, 21), m.axis(v(0, 0, 1), -side * 0.15), moss, .stone);
                rune(w, site, v(side * 28, 30, 9.2), 5);
            }
            w.part(site, v(-8, 61, 0), v(48, 12, 17), m.axis(v(0, 0, 1), 0.07), stone, .stone);
            w.part(site, v(22, 60, 0), v(13, 10, 17), m.axis(v(0, 0, 1), -0.16), pale, .stone);
            for (0..5) |j| w.part(site, v(-46 + @as(f32, @floatFromInt(j)) * 21, -2, 18), v(16, 6, 23), q, moss, .stone);
        },
        1 => {
            for (0..4) |tier| {
                const n: f32 = @floatFromInt(tier);
                w.part(site, v(0, n * 6, 0), v(90 - n * 17, 8, 72 - n * 13), q, if (tier % 2 == 0) stone else moss, .stone);
            }
            for ([_]f32{ -1, 1 }) |side| {
                w.part(site, v(side * 17, 43, 0), v(9, 45, 13), q, pale, .stone);
                rune(w, site, v(side * 17, 46, 6.8), 3);
            }
            w.part(site, v(0, 68, 0), v(48, 11, 20), m.axis(v(0, 0, 1), -0.05), stone, .stone);
        },
        2 => {
            // An ancient seated, horned alien guardian; luminous eyes and chest sigil.
            w.part(site, v(0, 3, 0), v(47, 10, 40), q, moss, .stone);
            w.part(site, v(0, 25, -3), v(23, 39, 19), q, stone, .stone);
            w.part(site, v(0, 52, -1), v(25, 23, 20), m.axis(v(0, 1, 0), 0.08), pale, .stone);
            for ([_]f32{ -1, 1 }) |side| {
                w.part(site, v(side * 19, 28, 3), v(13, 29, 14), m.axis(v(0, 0, 1), side * 0.3), stone, .stone);
                w.part(site, v(side * 10, 12, 12), v(15, 16, 23), q, stone, .stone);
                w.part(site, v(side * 12, 70, -1), v(6, 21, 9), m.axis(v(0, 0, 1), -side * 0.3), stone, .stone);
                w.part(site, v(side * 6.5, 54, 10), v(7, 1.2, 0.6), m.axis(v(0, 0, 1), side * 0.22), site.tint, .glow);
            }
            rune(w, site, v(0, 31, 7), 5);
        },
        else => {
            for (0..7) |j| {
                const angle = @as(f32, @floatFromInt(j)) * std.math.tau / 7.0;
                const p = v(@cos(angle) * 38, 0, @sin(angle) * 38);
                const height = 20 + random.float(f32) * 42;
                w.part(site, m.add(p, v(0, height / 2, 0)), v(10, height, 12), m.axis(v(0, 0, 1), (random.float(f32) - 0.5) * 0.24), stone, .stone);
                w.part(site, m.add(p, v(0, height + 1, 0)), v(15, 6, 17), q, pale, .stone);
                rune(w, site, m.add(p, v(0, height * 0.6, 6.8)), 2.8);
            }
        },
    }
}
