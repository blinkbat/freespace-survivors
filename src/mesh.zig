const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const v = m.v;
const alloc = std.heap.raw_c_allocator;

// Adapted from zig-soulslike's Builder; ownership passes to raylib on finish.
pub const Builder = struct {
    pos: std.ArrayList(f32) = std.ArrayList(f32).init(alloc),
    normals: std.ArrayList(f32) = std.ArrayList(f32).init(alloc),
    uv: std.ArrayList(f32) = std.ArrayList(f32).init(alloc),
    uv2: std.ArrayList(f32) = std.ArrayList(f32).init(alloc),
    colors: std.ArrayList(u8) = std.ArrayList(u8).init(alloc),
    material: f32 = 0,
    origin: m.V = m.zero,
    rotation: m.Q = m.identity,

    fn vertex(b: *Builder, p: m.V, n: m.V, c: rl.Color, u: f32, t: f32) void {
        const position = m.add(b.origin, m.rotate(b.rotation, p));
        const normal = m.rotate(b.rotation, n);
        b.pos.appendSlice(&.{ position.x, position.y, position.z }) catch @panic("mesh allocation");
        b.normals.appendSlice(&.{ normal.x, normal.y, normal.z }) catch @panic("mesh allocation");
        b.uv.appendSlice(&.{ u, t }) catch @panic("mesh allocation");
        b.uv2.appendSlice(&.{ b.material, 0 }) catch @panic("mesh allocation");
        b.colors.appendSlice(&.{ c.r, c.g, c.b, c.a }) catch @panic("mesh allocation");
    }
    pub fn triangle(b: *Builder, a: m.V, c: m.V, d: m.V, color: rl.Color) void {
        const n = m.norm(m.cross(m.sub(c, a), m.sub(d, a)));
        b.vertex(a, n, color, 0, 0);
        b.vertex(c, n, color, m.length(m.sub(c, a)), 0);
        b.vertex(d, n, color, 0, m.length(m.sub(d, a)));
    }
    fn quad(b: *Builder, a: m.V, c: m.V, d: m.V, e: m.V, n: m.V, color: rl.Color) void {
        const u = m.length(m.sub(c, a));
        const t = m.length(m.sub(e, a));
        b.vertex(a, n, color, 0, 0);
        b.vertex(c, n, color, u, 0);
        b.vertex(d, n, color, u, t);
        b.vertex(a, n, color, 0, 0);
        b.vertex(d, n, color, u, t);
        b.vertex(e, n, color, 0, t);
    }
    pub fn box(b: *Builder, center: m.V, size: m.V, color: rl.Color) void {
        const lo = m.sub(center, m.scale(size, 0.5));
        const hi = m.add(center, m.scale(size, 0.5));
        b.quad(v(hi.x, lo.y, lo.z), v(hi.x, hi.y, lo.z), v(hi.x, hi.y, hi.z), v(hi.x, lo.y, hi.z), v(1, 0, 0), color);
        b.quad(v(lo.x, lo.y, hi.z), v(lo.x, hi.y, hi.z), v(lo.x, hi.y, lo.z), v(lo.x, lo.y, lo.z), v(-1, 0, 0), color);
        b.quad(v(lo.x, hi.y, lo.z), v(lo.x, hi.y, hi.z), v(hi.x, hi.y, hi.z), v(hi.x, hi.y, lo.z), v(0, 1, 0), color);
        b.quad(v(lo.x, lo.y, hi.z), v(lo.x, lo.y, lo.z), v(hi.x, lo.y, lo.z), v(hi.x, lo.y, hi.z), v(0, -1, 0), color);
        b.quad(v(lo.x, lo.y, hi.z), v(hi.x, lo.y, hi.z), v(hi.x, hi.y, hi.z), v(lo.x, hi.y, hi.z), v(0, 0, 1), color);
        b.quad(v(hi.x, lo.y, lo.z), v(lo.x, lo.y, lo.z), v(lo.x, hi.y, lo.z), v(hi.x, hi.y, lo.z), v(0, 0, -1), color);
    }
    pub fn prism(b: *Builder, a: m.V, c: m.V, d: m.V, thickness: f32, color: rl.Color) void {
        const off = v(0, -thickness, 0);
        const aa = m.add(a, off);
        const cc = m.add(c, off);
        const dd = m.add(d, off);
        b.triangle(a, c, d, color);
        b.triangle(aa, dd, cc, color);
        b.quad(a, aa, cc, c, m.norm(m.cross(m.sub(aa, a), m.sub(cc, a))), color);
        b.quad(c, cc, dd, d, m.norm(m.cross(m.sub(cc, c), m.sub(dd, c))), color);
        b.quad(d, dd, aa, a, m.norm(m.cross(m.sub(dd, d), m.sub(aa, d))), color);
    }
    pub fn finish(b: *Builder, shader: rl.Shader) rl.Model {
        std.debug.assert(b.pos.items.len > 0);
        var mesh = std.mem.zeroes(rl.Mesh);
        mesh.vertexCount = @intCast(b.pos.items.len / 3);
        mesh.triangleCount = @intCast(b.pos.items.len / 9);
        mesh.vertices = (b.pos.toOwnedSlice() catch @panic("mesh allocation")).ptr;
        mesh.normals = (b.normals.toOwnedSlice() catch @panic("mesh allocation")).ptr;
        mesh.texcoords = (b.uv.toOwnedSlice() catch @panic("mesh allocation")).ptr;
        mesh.texcoords2 = (b.uv2.toOwnedSlice() catch @panic("mesh allocation")).ptr;
        mesh.colors = (b.colors.toOwnedSlice() catch @panic("mesh allocation")).ptr;
        rl.uploadMesh(&mesh, false);
        var model = rl.loadModelFromMesh(mesh) catch @panic("model upload");
        model.materials[0].shader = shader;
        return model;
    }

    pub fn celestial(b: *Builder, radii: m.V, tint: rl.Color, planet: bool, seed: usize) void {
        const rings: usize = if (planet) 48 else 12;
        const sides: usize = if (planet) 96 else 20;
        b.material = if (planet) 5 else 4;
        for (0..rings) |y| {
            for (0..sides) |x| {
                const a = spherePoint(x, y, sides, rings);
                const c = spherePoint(x + 1, y, sides, rings);
                const d = spherePoint(x + 1, y + 1, sides, rings);
                const e = spherePoint(x, y + 1, sides, rings);
                if (y > 0) b.bodyTriangle(a, c, d, radii, tint, planet, seed);
                if (y + 1 < rings) b.bodyTriangle(a, d, e, radii, tint, planet, seed);
            }
        }
    }
    fn bodyTriangle(b: *Builder, a: m.V, c: m.V, d: m.V, radii: m.V, tint: rl.Color, planet: bool, seed: usize) void {
        const points = [_]m.V{ m.product(a, radii), m.product(c, radii), m.product(d, radii) };
        const n = m.norm(m.cross(m.sub(points[1], points[0]), m.sub(points[2], points[0])));
        const directions = [_]m.V{ a, c, d };
        for (points, directions) |p, direction| {
            const detail = @sin(direction.x * 11 + @sin(direction.z * 8)) * @cos(direction.y * 13 + @sin(direction.x * 7) + @as(f32, @floatFromInt(seed)));
            var color = tint;
            const factor: f32 = if (planet) (if (detail > 0.12) 1.22 else 0.72 + detail * 0.12) else 0.8 + @abs(detail) * 0.4;
            color.r = @intFromFloat(@min(255, @as(f32, @floatFromInt(tint.r)) * factor));
            color.g = @intFromFloat(@min(255, @as(f32, @floatFromInt(tint.g)) * factor));
            color.b = @intFromFloat(@min(255, @as(f32, @floatFromInt(tint.b)) * factor));
            if (planet and @abs(direction.y) > 0.89) color = m.color(180, 203, 206);
            b.vertex(p, if (planet) m.norm(m.divide(direction, radii)) else n, color, direction.x, direction.y);
        }
    }
};

fn spherePoint(x: usize, y: usize, sides: usize, rings: usize) m.V {
    const a = @as(f32, @floatFromInt(x)) * std.math.tau / @as(f32, @floatFromInt(sides));
    const t = @as(f32, @floatFromInt(y)) * std.math.pi / @as(f32, @floatFromInt(rings));
    return v(@sin(t) * @cos(a), @cos(t), @sin(t) * @sin(a));
}

pub fn ship(shader: rl.Shader) rl.Model {
    var b = Builder{};
    const ivory = m.color(214, 225, 234);
    const grey = m.color(98, 123, 150);
    const blue = m.color(35, 112, 144);
    const orange = m.color(245, 123, 56);
    const nose = v(0, 0, -4.6);
    const top = v(0, 0.8, -0.5);
    const left = v(-0.95, 0, 1.5);
    const right = v(0.95, 0, 1.5);
    const back = v(0, 0.45, 2.4);
    const bottom = v(0, -0.65, 0.3);
    b.triangle(nose, left, top, ivory);
    b.triangle(nose, top, right, ivory);
    b.triangle(top, left, back, grey);
    b.triangle(top, back, right, grey);
    b.triangle(nose, bottom, left, grey);
    b.triangle(nose, right, bottom, grey);
    b.triangle(left, bottom, back, grey);
    b.triangle(right, back, bottom, grey);
    b.prism(v(-0.75, 0.1, -1.4), v(-3.9, 0, 2.2), v(-0.7, 0.1, 1.6), 0.28, ivory);
    b.prism(v(0.75, 0.1, -1.4), v(0.7, 0.1, 1.6), v(3.9, 0, 2.2), 0.28, ivory);
    b.prism(v(-1.4, 0.12, 0), v(-3.9, 0.02, 2.2), v(-2.9, 0.07, 2.03), 0.1, orange);
    b.prism(v(1.4, 0.12, 0), v(2.9, 0.07, 2.03), v(3.9, 0.02, 2.2), 0.1, orange);
    b.triangle(v(0, 0.85, -2.0), v(-0.48, 0.61, -0.15), v(0, 1.14, 0.1), blue);
    b.triangle(v(0, 0.85, -2.0), v(0, 1.14, 0.1), v(0.48, 0.61, -0.15), blue);
    b.triangle(v(-0.48, 0.61, -0.15), v(0.48, 0.61, -0.15), v(0, 1.14, 0.1), blue);
    b.prism(v(0, 0.55, 0.7), v(-0.14, 1.9, 2.2), v(0.14, 1.9, 2.2), 0.35, orange);
    for ([_]f32{ -1.3, 1.3 }) |x| {
        b.box(v(x, -0.05, 1.5), v(0.85, 0.85, 2.5), grey);
        b.box(v(x, -0.05, 2.8), v(0.9, 0.9, 0.4), m.color(25, 37, 53));
        b.material = 3;
        b.box(v(x, -0.05, 3.03), v(0.63, 0.63, 0.06), m.color(75, 224, 255));
        b.material = 0;
    }
    return b.finish(shader);
}

pub fn drone(shader: rl.Shader, tier: usize) rl.Model {
    var b = Builder{};
    const palette = [_][3]rl.Color{
        .{ m.color(240, 75, 72), m.color(116, 28, 59), m.color(252, 143, 87) },
        .{ m.color(247, 183, 48), m.color(134, 71, 22), m.color(255, 220, 114) },
        .{ m.color(180, 102, 245), m.color(74, 34, 127), m.color(225, 156, 255) },
        .{ m.color(79, 179, 249), m.color(26, 66, 132), m.color(156, 222, 255) },
    };
    const colors = palette[tier % palette.len];
    const top = v(0, 1.1, 0);
    const bottom = v(0, -0.8, 0);
    const points = [_]m.V{ v(0, 0, -1.8), v(-1.3, 0, 0), v(0, 0, 1.25), v(1.3, 0, 0) };
    for (points, 0..) |p, i| {
        b.triangle(top, p, points[(i + 1) % 4], colors[0]);
        b.triangle(bottom, points[(i + 1) % 4], p, colors[1]);
    }
    b.box(v(-1.7, 0, 0.25), v(1.0, 0.45, 1.3), colors[2]);
    b.box(v(1.7, 0, 0.25), v(1.0, 0.45, 1.3), colors[2]);
    b.material = 3;
    b.box(v(0, 0.15, -1.15), v(0.65, 0.45, 0.45), m.color(255, 179, 98));
    return b.finish(shader);
}

pub fn gem(shader: rl.Shader) rl.Model {
    var b = Builder{ .material = 3 };
    const ring = [_]m.V{ v(0, 0, -0.65), v(-0.65, 0, 0), v(0, 0, 0.65), v(0.65, 0, 0) };
    for (ring, 0..) |p, i| {
        b.triangle(v(0, 1.1, 0), p, ring[(i + 1) % 4], m.color(70, 249, 156));
        b.triangle(v(0, -1.1, 0), ring[(i + 1) % 4], p, m.color(21, 142, 107));
    }
    return b.finish(shader);
}

pub fn orbital(shader: rl.Shader) rl.Model {
    var b = Builder{};
    b.box(m.zero, v(1.4, 0.65, 1.7), m.color(183, 216, 231));
    for ([_]f32{ -1, 1 }) |side| {
        b.box(v(side * 1.1, 0, 0.2), v(0.65, 0.35, 1.25), m.color(46, 128, 162));
        b.material = 3;
        b.box(v(side * 1.1, 0, 0.85), v(0.45, 0.2, 0.08), m.color(82, 214, 255));
        b.material = 0;
    }
    b.box(v(0, 0, -1.1), v(0.35, 0.35, 0.8), m.color(42, 58, 76));
    b.material = 3;
    b.box(v(0, 0.37, -0.3), v(0.55, 0.1, 0.5), m.color(101, 229, 255));
    return b.finish(shader);
}

pub fn mine(shader: rl.Shader) rl.Model {
    var b = Builder{};
    b.box(m.zero, v(1.5, 0.8, 1.5), m.color(111, 78, 48));
    b.box(m.zero, v(2.6, 0.35, 0.5), m.color(222, 165, 62));
    b.box(m.zero, v(0.5, 0.35, 2.6), m.color(222, 165, 62));
    b.material = 3;
    b.box(v(0, 0.5, 0), v(0.55, 0.25, 0.55), m.color(255, 174, 58));
    return b.finish(shader);
}

pub fn rocket(shader: rl.Shader) rl.Model {
    var b = Builder{};
    b.box(m.zero, v(0.6, 0.6, 2.2), m.color(218, 205, 185));
    b.prism(v(-0.3, 0, -1), v(0, 0, -1.8), v(0.3, 0, -1), 0.4, m.color(241, 126, 52));
    b.box(v(0, 0, 0.7), v(1.6, 0.14, 0.65), m.color(118, 82, 59));
    b.box(v(0, 0, 0.7), v(0.14, 1.4, 0.65), m.color(118, 82, 59));
    return b.finish(shader);
}
