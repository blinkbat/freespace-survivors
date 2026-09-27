const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const mesh = @import("mesh.zig");
const world = @import("world.zig");
const terrain = world.terrain;
const v = m.v;

pub fn build(b: *mesh.Builder, w: *const world.World) void {
    b.origin = m.zero;
    b.rotation = m.identity;
    for (0..terrain.CELLS) |z| {
        for (0..terrain.CELLS) |x| {
            const a = w.ground.vertex(x, z);
            const c = w.ground.vertex(x + 1, z);
            const d = w.ground.vertex(x + 1, z + 1);
            const e = w.ground.vertex(x, z + 1);
            b.material = 9;
            const h = (a.y + c.y + d.y + e.y) / 4;
            const tint = if (h < 15) m.color(107, 121, 78) else if (h > 90) m.color(80, 107, 70) else m.color(57, 103, 61);
            b.triangle(a, d, c, tint);
            b.triangle(a, e, d, tint);
            if (@min(@min(a.y, c.y), @min(d.y, e.y)) < terrain.WATER) {
                b.material = 10;
                const aa = v(a.x, terrain.WATER, a.z);
                const cc = v(c.x, terrain.WATER, c.z);
                const dd = v(d.x, terrain.WATER, d.z);
                const ee = v(e.x, terrain.WATER, e.z);
                b.triangle(aa, dd, cc, m.color(41, 132, 119));
                b.triangle(aa, ee, dd, m.color(41, 132, 119));
            }
        }
    }
    var rng = std.Random.DefaultPrng.init(w.seed ^ 0x42414e59414e);
    const random = rng.random();
    for (w.trees[0..w.tree_count]) |tree| {
        b.origin = tree.position;
        b.material = 7;
        const bark = m.color(99, 103, 70);
        stem(b, m.zero, v(0, tree.height * 0.83, 0), tree.radius, tree.radius * 0.6, bark);
        for (0..6) |i| {
            const angle = tree.angle + @as(f32, @floatFromInt(i)) * std.math.tau / 6;
            const direction = v(@cos(angle), 0, @sin(angle));
            stem(b, m.scale(direction, tree.radius * 3.5), v(0, 15, 0), tree.radius * 0.35, tree.radius * 0.7, bark);
            const branch = m.add(m.scale(direction, 24 + random.float(f32) * 14), v(0, tree.height * (0.73 + random.float(f32) * 0.14), 0));
            stem(b, v(0, tree.height * 0.57, 0), branch, tree.radius * 0.65, 1.4, bark);
            // Aerial roots hang from the spreading crown, some reaching the forest floor.
            for (0..3) |j| {
                const anchor = m.add(m.scale(direction, 12 + @as(f32, @floatFromInt(j)) * 9), v(0, branch.y - 3, 0));
                const bottom = m.add(anchor, v(2 * @sin(angle * 3), -35 - random.float(f32) * (branch.y - 35), 2 * @cos(angle)));
                stem(b, bottom, anchor, 0.35, 0.65, m.color(68, 88, 55));
            }
            b.material = 8;
            crown(b, branch, 24 + random.float(f32) * 13, 9 + random.float(f32) * 5, tree.tint);
            b.material = 7;
        }
        b.material = 8;
        crown(b, v(0, tree.height * 0.92, 0), 33, 13, tree.tint);
    }
    b.rotation = m.identity;
    for (0..1500) |_| {
        const x = (random.float(f32) - 0.5) * 2800;
        const z = (random.float(f32) - 0.5) * 2800;
        const h = w.ground.surface(x, z).height;
        if (h < terrain.WATER + 2) continue;
        b.origin = v(x, h - 0.5, z);
        b.material = 8;
        const size = 3 + random.float(f32) * 6;
        for (0..7) |i| {
            const a = @as(f32, @floatFromInt(i)) * std.math.tau / 7.0;
            const tip = v(@cos(a) * size, size * 0.7, @sin(a) * size);
            const mid = v(tip.x * 0.5, size, tip.z * 0.5);
            const side = v(-@sin(a) * size * 0.18, 0, @cos(a) * size * 0.18);
            const tint = m.color(64, 136, 76);
            b.prism(m.zero, m.add(mid, side), tip, 0.1, tint);
            b.prism(m.zero, tip, m.sub(mid, side), 0.1, tint);
        }
        if (random.float(f32) < 0.12) {
            b.material = 3;
            crown(b, v(0, size * 0.8, 0), 0.8, 0.8, m.color(128, 210, 199));
        }
    }
    b.origin = m.zero;
}

fn stem(b: *mesh.Builder, from: m.V, to: m.V, r0: f32, r1: f32, tint: rl.Color) void {
    const axis = m.norm(m.sub(to, from));
    const right = m.norm(m.cross(axis, if (@abs(axis.y) < 0.9) v(0, 1, 0) else v(1, 0, 0)));
    const up = m.cross(axis, right);
    for (0..7) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.tau / 7.0;
        const c = a + std.math.tau / 7.0;
        const n0 = m.add(m.scale(right, @cos(a)), m.scale(up, @sin(a)));
        const n1 = m.add(m.scale(right, @cos(c)), m.scale(up, @sin(c)));
        const p0 = m.add(from, m.scale(n0, r0));
        const p1 = m.add(from, m.scale(n1, r0));
        const p2 = m.add(to, m.scale(n1, r1));
        const p3 = m.add(to, m.scale(n0, r1));
        b.triangle(p0, p1, p2, tint);
        b.triangle(p0, p2, p3, tint);
        b.triangle(to, p3, p2, tint);
    }
}

fn crown(b: *mesh.Builder, center: m.V, radius: f32, height: f32, tint: rl.Color) void {
    for (0..9) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.tau / 9.0;
        const c = a + std.math.tau / 9.0;
        const p0 = m.add(center, v(@cos(a) * radius, 0, @sin(a) * radius));
        const p1 = m.add(center, v(@cos(c) * radius, 0, @sin(c) * radius));
        const q0 = m.add(center, v(@cos(a) * radius * 0.55, height * 0.8, @sin(a) * radius * 0.55));
        const q1 = m.add(center, v(@cos(c) * radius * 0.55, height * 0.8, @sin(c) * radius * 0.55));
        b.triangle(p0, q0, q1, tint);
        b.triangle(p0, q1, p1, tint);
        b.triangle(q0, m.add(center, v(0, height, 0)), q1, tint);
        b.triangle(p0, p1, m.add(center, v(0, -height * 0.3, 0)), tint);
    }
}
