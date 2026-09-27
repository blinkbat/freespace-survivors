const std = @import("std");
const m = @import("math.zig");
const v = m.v;

pub const CELLS = 128;
pub const STEP: f32 = 24;
pub const EXTENT: f32 = CELLS * STEP / 2;
pub const WATER: f32 = 8;
pub const CEILING: f32 = 215;
pub const Surface = struct { height: f32, normal: m.V };

pub const Terrain = struct {
    heights: [CELLS + 1][CELLS + 1]f32 = undefined,
    max_height: f32 = 0,
    max_slope_scale: f32 = 1,

    pub fn generate(seed: u64) Terrain {
        var result: Terrain = undefined;
        result.max_height = -1000;
        result.max_slope_scale = 1;
        const phase = @as(f32, @floatFromInt(seed % 1024)) * 0.013;
        for (&result.heights, 0..) |*row, z| {
            for (row, 0..) |*height, x| {
                const px = coordinate(x);
                const pz = coordinate(z);
                const river = px - riverX(pz);
                const bank = 1 - @exp(-river * river / (130 * 130));
                const hills = 26 + 29 * @sin(px * 0.0035 + phase) * @cos(pz * 0.004) + 18 * @sin(pz * 0.009 + px * 0.003) + 7 * @cos(px * 0.025 + pz * 0.018);
                const ridge = 45 * @exp(-((px + 600) * (px + 600) + (pz + 260) * (pz + 260)) / 350000);
                const basin = -13 + bank * (hills + ridge + 28);
                const launch = @exp(-(px * px + (pz - 70) * (pz - 70)) / 12000);
                height.* = basin * (1 - launch) + 14 * launch;
                result.max_height = @max(result.max_height, height.*);
            }
        }
        for (0..CELLS) |z| {
            for (0..CELLS) |x| {
                for ([_][2]f32{ .{ 0.75, 0.25 }, .{ 0.25, 0.75 } }) |offset| {
                    const sample = result.surface(coordinate(x) + offset[0] * STEP, coordinate(z) + offset[1] * STEP);
                    result.max_slope_scale = @max(result.max_slope_scale, 1 / sample.normal.y);
                }
            }
        }
        return result;
    }
    pub fn vertex(t: *const Terrain, x: usize, z: usize) m.V {
        return v(coordinate(x), t.heights[z][x], coordinate(z));
    }
    pub fn surface(t: *const Terrain, x: f32, z: f32) Surface {
        const ix = cell(x);
        const iz = cell(z);
        const fx = std.math.clamp((x - coordinate(ix)) / STEP, 0, 1);
        const fz = std.math.clamp((z - coordinate(iz)) / STEP, 0, 1);
        const h00 = t.heights[iz][ix];
        const h10 = t.heights[iz][ix + 1];
        const h01 = t.heights[iz + 1][ix];
        const h11 = t.heights[iz + 1][ix + 1];
        const dx = if (fx >= fz) h10 - h00 else h11 - h01;
        const dz = if (fx >= fz) h11 - h10 else h01 - h00;
        return .{ .height = h00 + dx * fx + dz * fz, .normal = m.norm(v(-dx / STEP, 1, -dz / STEP)) };
    }
    pub fn floor(t: *const Terrain, x: f32, z: f32) Surface {
        const ground = t.surface(x, z);
        return if (ground.height < WATER) .{ .height = WATER, .normal = v(0, 1, 0) } else ground;
    }
    pub fn clear(t: *const Terrain, p: m.V, radius: f32) bool {
        const ground = t.floor(p.x, p.z);
        return p.y >= ground.height + radius / ground.normal.y and p.y + radius <= CEILING;
    }
    pub fn recover(t: *const Terrain, position: *m.V, velocity: *m.V, radius: f32) void {
        const ground = t.floor(position.x, position.z);
        const minimum = ground.height + (radius + 0.02) / ground.normal.y;
        if (position.y < minimum) {
            position.y = minimum;
            velocity.* = m.sub(velocity.*, m.scale(ground.normal, @min(0, m.dot(velocity.*, ground.normal))));
        }
        if (position.y > CEILING - radius - 0.02) {
            position.y = CEILING - radius - 0.02;
            velocity.y = @min(velocity.y, 0);
        }
    }
    pub fn cast(t: *const Terrain, from: m.V, delta: m.V, radius: f32) ?m.Hit {
        var closest: ?m.Hit = null;
        const finish = m.add(from, delta);
        if (from.y + radius > CEILING) closest = .{ .t = 0, .normal = v(0, -1, 0) } else if (delta.y > 0 and finish.y + radius >= CEILING) {
            closest = .{ .t = (CEILING - radius - from.y) / delta.y, .normal = v(0, -1, 0) };
        }
        if (from.y < WATER + radius) closest = .{ .t = 0, .normal = v(0, 1, 0) } else if (delta.y < 0 and finish.y < WATER + radius) {
            const time = (WATER + radius - from.y) / delta.y;
            if (closest == null or time < closest.?.t) closest = .{ .t = time, .normal = v(0, 1, 0) };
        }
        if (@min(from.y, finish.y) > t.max_height + radius * t.max_slope_scale) return closest;
        const min_x = cell(@min(from.x, finish.x) - radius);
        const max_x = cell(@max(from.x, finish.x) + radius);
        const min_z = cell(@min(from.z, finish.z) - radius);
        const max_z = cell(@max(from.z, finish.z) + radius);
        for (min_z..max_z + 1) |z| {
            for (min_x..max_x + 1) |x| {
                for (0..2) |triangle| {
                    const a = t.vertex(x, z);
                    const b = if (triangle == 0) t.vertex(x + 1, z + 1) else t.vertex(x, z + 1);
                    const c = if (triangle == 0) t.vertex(x + 1, z) else t.vertex(x + 1, z + 1);
                    const normal = m.norm(m.cross(m.sub(b, a), m.sub(c, a)));
                    const gap = m.dot(m.sub(from, a), normal) - radius;
                    const rate = m.dot(delta, normal);
                    const time: f32 = if (gap < 0) 0 else if (rate < -0.000001) -gap / rate else continue;
                    if (time < 0 or time > 1 or (closest != null and time >= closest.?.t)) continue;
                    const p = m.add(from, m.scale(delta, time));
                    const fx = (p.x - a.x) / STEP;
                    const fz = (p.z - a.z) / STEP;
                    if (fx < -0.00001 or fx > 1.00001 or fz < -0.00001 or fz > 1.00001) continue;
                    if ((triangle == 0 and fx + 0.00001 < fz) or (triangle == 1 and fz + 0.00001 < fx)) continue;
                    closest = .{ .t = time, .normal = normal };
                }
            }
        }
        return closest;
    }
};

pub fn riverX(z: f32) f32 {
    return 190 + 155 * @sin(z * 0.0028) + 48 * @sin(z * 0.009);
}
pub fn coordinate(index: usize) f32 {
    return @as(f32, @floatFromInt(index)) * STEP - EXTENT;
}
fn cell(position: f32) usize {
    return @intFromFloat(std.math.clamp(@floor((position + EXTENT) / STEP), 0, CELLS - 1));
}

test "jungle heightfield matches its triangles and blocks ground water and ceiling" {
    const t = Terrain.generate(91);
    const ground = t.surface(-500, -200);
    try std.testing.expect(t.max_height > ground.height);
    const p = v(-500, ground.height + 30, -200);
    try std.testing.expect(t.clear(p, 4.6));
    const hit = t.cast(p, v(0, -100, 0), 4.6).?;
    try std.testing.expect(hit.normal.y > 0.5);
    var recovered = v(-500, -100, -200);
    var velocity = v(0, -46, 0);
    t.recover(&recovered, &velocity, 4.6);
    try std.testing.expect(t.clear(recovered, 4.6));
    try std.testing.expect(t.cast(v(0, CEILING - 10, 0), v(0, 30, 0), 4.6).?.normal.y < 0);
    try std.testing.expect(!t.clear(v(riverX(500), WATER - 1, 500), 0));
    try std.testing.expect(t.cast(v(0, 160, 0), v(0, -300, 0), 0) != null);
}
