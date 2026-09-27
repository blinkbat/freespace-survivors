const std = @import("std");
const rl = @import("raylib");
pub const V = rl.Vector3;
pub const Q = rl.Quaternion;
pub const zero = v(0, 0, 0);
pub const identity: Q = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
pub fn v(x: f32, y: f32, z: f32) V {
    return .{ .x = x, .y = y, .z = z };
}
pub fn add(a: V, b: V) V {
    return v(a.x + b.x, a.y + b.y, a.z + b.z);
}
pub fn sub(a: V, b: V) V {
    return v(a.x - b.x, a.y - b.y, a.z - b.z);
}
pub fn scale(a: V, k: f32) V {
    return v(a.x * k, a.y * k, a.z * k);
}
pub fn dot(a: V, b: V) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
pub fn cross(a: V, b: V) V {
    return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
pub fn length(a: V) f32 {
    return @sqrt(dot(a, a));
}
pub fn norm(a: V) V {
    const n = length(a);
    return if (n > 0.000001) scale(a, 1 / n) else zero;
}
pub fn mix(a: V, b: V, t: f32) V {
    return add(a, scale(sub(b, a), t));
}
pub fn qmul(a: Q, b: Q) Q {
    return rl.math.quaternionMultiply(a, b);
}
pub fn axis(a: V, angle: f32) Q {
    return rl.math.quaternionFromAxisAngle(a, angle);
}
pub fn rotate(q: Q, p: V) V {
    return rl.math.vector3RotateByQuaternion(p, q);
}
pub fn inverse(q: Q) Q {
    return .{ .x = -q.x, .y = -q.y, .z = -q.z, .w = q.w };
}
pub fn divide(a: V, b: V) V {
    return v(a.x / b.x, a.y / b.y, a.z / b.z);
}
pub fn product(a: V, b: V) V {
    return v(a.x * b.x, a.y * b.y, a.z * b.z);
}

pub fn sweepEllipsoid(origin: V, delta: V, center: V, radii: V) ?Hit {
    const p = divide(sub(origin, center), radii);
    const d = divide(delta, radii);
    const c = dot(p, p) - 1;
    if (c < 0) return .{ .t = 0, .normal = if (length(p) > 0.0001) norm(divide(p, radii)) else v(0, 1, 0) };
    const a = dot(d, d);
    if (a < 0.00000000001) return null;
    const b = dot(p, d);
    const disc = b * b - a * c;
    if (disc < 0) return null;
    const t = (-b - @sqrt(disc)) / a;
    if (t < 0 or t > 1) return null;
    return .{ .t = t, .normal = norm(divide(add(p, scale(d, t)), radii)) };
}
pub fn color(r: u8, g: u8, b: u8) rl.Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

pub const Box = struct {
    center: V,
    half: V,
    pub fn expanded(b: Box, r: f32) Box {
        return .{ .center = b.center, .half = add(b.half, v(r, r, r)) };
    }
    pub fn contains(b: Box, p: V) bool {
        const d = sub(p, b.center);
        return @abs(d.x) < b.half.x and @abs(d.y) < b.half.y and @abs(d.z) < b.half.z;
    }
};
pub const Hit = struct { t: f32, normal: V };

pub fn sweep(origin: V, delta: V, box: Box) ?Hit {
    const p = sub(origin, box.center);
    if (box.contains(origin)) {
        const gap = sub(box.half, v(@abs(p.x), @abs(p.y), @abs(p.z)));
        const normal = if (gap.x <= gap.y and gap.x <= gap.z)
            v(if (p.x < 0) -1 else 1, 0, 0)
        else if (gap.y <= gap.z)
            v(0, if (p.y < 0) -1 else 1, 0)
        else
            v(0, 0, if (p.z < 0) -1 else 1);
        return .{ .t = 0, .normal = normal };
    }
    const ps = [3]f32{ p.x, p.y, p.z };
    const ds = [3]f32{ delta.x, delta.y, delta.z };
    const hs = [3]f32{ box.half.x, box.half.y, box.half.z };
    var enter: f32 = 0;
    var leave: f32 = 1;
    var normal = zero;
    for (0..3) |i| {
        if (@abs(ds[i]) < 0.0000001) {
            if (ps[i] < -hs[i] or ps[i] > hs[i]) return null;
            continue;
        }
        const a = (-hs[i] - ps[i]) / ds[i];
        const b = (hs[i] - ps[i]) / ds[i];
        const near = @min(a, b);
        if (near >= enter) {
            enter = near;
            normal = zero;
            const sign: f32 = if (ds[i] > 0) -1 else 1;
            switch (i) {
                0 => normal.x = sign,
                1 => normal.y = sign,
                else => normal.z = sign,
            }
        }
        leave = @min(leave, @max(a, b));
        if (enter > leave) return null;
    }
    if (dot(normal, normal) == 0 or enter > 1 or leave < 0) return null;
    return .{ .t = enter, .normal = normal };
}

test "sweep catches thin walls across large displacements and permits parallel flight" {
    const wall = Box{ .center = zero, .half = v(10, 10, 0.2) };
    const hit = sweep(v(0, 0, 20), v(0, 0, -100), wall.expanded(2)).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.178), hit.t, 0.0001);
    try std.testing.expectEqual(@as(f32, 1), hit.normal.z);
    try std.testing.expect(sweep(v(15, 0, 20), v(0, 0, -100), wall.expanded(2)) == null);
    try std.testing.expect(sweep(v(0, 0, 2.21), v(20, 0, 0), wall.expanded(2)) == null);
}

test "casts starting inside boxes report immediate contact but surface departure is free" {
    const box = Box{ .center = zero, .half = v(2, 3, 4) };
    const hit = sweep(v(1, 0, 0), v(10, 0, 0), box).?;
    try std.testing.expectEqual(@as(f32, 0), hit.t);
    try std.testing.expectEqual(v(1, 0, 0), hit.normal);
    try std.testing.expect(sweep(zero, zero, box) != null);
    try std.testing.expect(sweep(v(2, 0, 0), v(1, 0, 0), box) == null);
}
