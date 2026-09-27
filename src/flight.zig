const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const world = @import("world.zig");
const v = m.v;
pub const STEP: f32 = 1.0 / 120.0;
pub const RADIUS: f32 = 4.6;
pub const SPEED: f32 = 46;

test "jungle ceiling permits lateral flight and terrain stops a dive" {
    const w = world.World{ .level = .jungle, .ground = world.terrain.Terrain.generate(91) };
    var ship = Ship{ .position = v(0, world.terrain.CEILING - RADIUS - 0.1, 70), .pitch = 1.3 };
    for (0..240) |_| ship.tick(.{ .thrust = v(0, 0, -1) }, STEP, &w);
    try std.testing.expect(ship.position.y <= world.terrain.CEILING - RADIUS);
    const before = ship.position;
    for (0..120) |_| ship.tick(.{ .thrust = v(1, 0, 0) }, STEP, &w);
    try std.testing.expect(m.length(m.sub(before, ship.position)) > 40);
    ship.move(v(0, -500, 0), &w);
    try std.testing.expect(w.clear(ship.position, RADIUS));
    const resting = ship.position;
    ship.tick(.{}, STEP, &w);
    try std.testing.expectApproxEqAbs(resting.y, ship.position.y, 0.05);
}
pub const Input = struct {
    thrust: m.V = m.zero,
    look: rl.Vector2 = .{ .x = 0, .y = 0 },
};
pub const Ship = struct {
    position: m.V = v(0, 0, 70),
    velocity: m.V = m.zero,
    orientation: m.Q = m.identity,
    yaw: f32 = 0,
    pitch: f32 = 0,
    bank: f32 = 0,
    contact: f32 = 0,
    travelled: f32 = 0,
    speed_multiplier: f32 = 1,

    pub fn forward(s: Ship) m.V {
        return m.rotate(s.orientation, v(0, 0, -1));
    }
    pub fn right(s: Ship) m.V {
        return m.rotate(s.orientation, v(1, 0, 0));
    }
    pub fn up(s: Ship) m.V {
        return m.rotate(s.orientation, v(0, 1, 0));
    }
    pub fn speed(s: Ship) f32 {
        return m.length(s.velocity);
    }

    pub fn tick(s: *Ship, input: Input, dt: f32, w: *const world.World) void {
        s.yaw = @mod(s.yaw - input.look.x + std.math.pi, std.math.tau) - std.math.pi;
        s.pitch = std.math.clamp(s.pitch - input.look.y, -1.4, 1.4);
        s.orientation = m.qmul(m.axis(v(0, 1, 0), s.yaw), m.axis(v(1, 0, 0), s.pitch));
        const bank_target = std.math.clamp(-input.look.x / dt * 0.16 - input.thrust.x * 0.13, -0.48, 0.48);
        s.bank += (bank_target - s.bank) * (1 - @exp(-12 * dt));
        s.contact = @max(0, s.contact - dt * 2);
        var thrust = input.thrust;
        const mag = m.length(thrust);
        if (mag > 1) thrust = m.scale(thrust, 1 / mag);
        s.velocity = m.scale(m.rotate(s.orientation, thrust), SPEED * s.speed_multiplier);
        // The boundary removes only outward travel; releasing movement always stops the ship.
        var radial = m.sub(s.position, w.boundaryCenter());
        if (w.level == .jungle) {
            radial.y = 0;
            if (s.velocity.y > 0) s.velocity.y *= std.math.clamp((world.terrain.CEILING - RADIUS - s.position.y) / 15, 0, 1);
        }
        const distance = m.length(radial);
        if (distance > w.boundaryRadius()) {
            const n = m.norm(radial);
            s.velocity = m.sub(s.velocity, m.scale(n, @max(0, m.dot(s.velocity, n)) * std.math.clamp((distance - w.boundaryRadius()) / 40, 0, 1)));
        }
        const before = s.position;
        s.move(m.scale(s.velocity, dt), w);
        s.travelled += m.length(m.sub(s.position, before));
    }

    pub fn move(s: *Ship, delta: m.V, w: *const world.World) void {
        w.recover(&s.position, &s.velocity, RADIUS);
        var remaining = delta;
        for (0..5) |_| {
            if (m.length(remaining) < 0.00001) break;
            if (w.cast(s.position, remaining, RADIUS)) |hit| {
                // Stop just before contact on every axis, preserving clearance at simultaneous corners.
                const safe_t = @max(0, hit.t - 0.002 / m.length(remaining));
                s.position = m.add(s.position, m.scale(remaining, safe_t));
                s.position = m.add(s.position, m.scale(hit.normal, 0.002));
                remaining = m.scale(remaining, 1 - hit.t);
                remaining = m.sub(remaining, m.scale(hit.normal, @min(0, m.dot(remaining, hit.normal))));
                const impact = m.dot(s.velocity, hit.normal);
                if (impact < -4) s.contact = @min(1, -impact / SPEED);
                s.velocity = m.sub(s.velocity, m.scale(hit.normal, @min(0, impact)));
            } else {
                s.position = m.add(s.position, remaining);
                break;
            }
        }
    }
};

pub const Camera = struct {
    distance: f32 = 29,
    pub fn view(c: *Camera, s: Ship, dt: f32, w: *const world.World) rl.Camera3D {
        const boom = m.add(m.scale(s.forward(), -28), m.scale(s.up(), 8));
        const total = m.length(boom);
        var allowed = total;
        if (w.cast(s.position, boom, 0.65)) |hit| allowed = @max(0.5, total * hit.t - 0.1);
        if (allowed < c.distance) c.distance = allowed else c.distance = @min(allowed, c.distance + dt * 22);
        return .{
            .position = m.add(s.position, m.scale(m.norm(boom), c.distance)),
            .target = m.add(s.position, m.add(m.scale(s.forward(), 28), m.scale(s.up(), 2.5))),
            .up = s.up(),
            .fovy = 61,
            .projection = .perspective,
        };
    }
};

test "movement responds immediately and release stops without coast" {
    const w = world.World{};
    var s = Ship{};
    s.tick(.{ .thrust = v(0, 0, -1) }, STEP, &w);
    try std.testing.expectEqual(SPEED, s.speed());
    const stop_at = s.position;
    s.tick(.{}, STEP, &w);
    try std.testing.expectEqual(@as(f32, 0), s.speed());
    try std.testing.expectEqual(stop_at, s.position);
}

test "diagonal movement has no speed advantage and reverse is immediate" {
    const w = world.World{};
    var s = Ship{};
    for (0..120) |_| s.tick(.{ .thrust = v(1, 1, -1) }, STEP, &w);
    try std.testing.expect(s.speed() <= SPEED + 0.001);
    s.tick(.{ .thrust = v(0, 0, 1) }, STEP, &w);
    try std.testing.expectEqual(SPEED, s.velocity.z);
}

test "long mouse turns preserve an orthonormal basis and a stable horizon" {
    const w = world.World{};
    var s = Ship{};
    for (0..9000) |_| s.tick(.{ .look = .{ .x = 0.01, .y = 0.012 } }, STEP, &w);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.length(s.forward()), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.dot(s.forward(), s.up()), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.dot(s.right(), s.up()), 0.00001);
    try std.testing.expect(s.up().y > 0);
}

test "swept ship slides along a wall and camera shortens before an obstruction" {
    var w = world.World{};
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(0, 0, 0), .half = v(100, 100, 0.2) }, .tint = rl.Color.white };
    var s = Ship{ .position = v(0, 0, 20), .velocity = v(20, 0, -100) };
    s.move(v(10, 0, -70), &w);
    try std.testing.expect(s.position.z > RADIUS + 0.19);
    try std.testing.expectApproxEqAbs(@as(f32, 10), s.position.x, 0.01);
    try std.testing.expectEqual(@as(f32, 0), s.velocity.z);
    s.position = v(0, 0, -9);
    var camera = Camera{};
    const view = camera.view(s, STEP, &w);
    try std.testing.expect(view.position.z < -0.84);
    try std.testing.expect(w.clear(view.position, 0.65));
}

test "a complete rotated truss pass keeps ship and camera clear" {
    const w = world.World.init();
    const site = w.sites[0];
    const forward = m.rotate(site.rotation, v(0, 0, -1));
    const start = m.add(site.position, m.rotate(site.rotation, v(0, 0, 145)));
    var ship = Ship{ .position = start, .yaw = std.math.atan2(-forward.x, -forward.z), .pitch = std.math.asin(forward.y) };
    var camera = Camera{};
    for (0..720) |_| {
        ship.tick(.{ .thrust = v(0, 0, -1) }, STEP, &w);
        try std.testing.expect(w.clear(ship.position, RADIUS));
        const view = camera.view(ship, STEP, &w);
        try std.testing.expect(w.clear(view.position, 0.65));
    }
    try std.testing.expectApproxEqAbs(@as(f32, 276), m.length(m.sub(ship.position, start)), 0.02);
}

test "diagonal contact at a corner leaves both surfaces solid" {
    var w = world.World{};
    w.count = 2;
    w.solids[0] = .{ .box = .{ .center = v(0, 0, 0), .half = v(100, 100, 0.2) }, .tint = rl.Color.white };
    w.solids[1] = .{ .box = .{ .center = v(-10, 0, 10), .half = v(0.2, 100, 100) }, .tint = rl.Color.white };
    var ship = Ship{ .position = v(10, 0, 20), .velocity = v(-46, 0, -46) };
    ship.move(v(-60, 8, -60), &w);
    try std.testing.expect(w.clear(ship.position, RADIUS));
    try std.testing.expect(ship.position.x > -10 + RADIUS);
    try std.testing.expect(ship.position.z > RADIUS);
    try std.testing.expectApproxEqAbs(@as(f32, 8), ship.position.y, 0.001);
}

test "ship can circle a planet, slide against it, and keep camera outside" {
    var w = world.World{};
    w.body_count = 1;
    w.bodies[0] = .{ .position = m.zero, .radii = v(80, 80, 80), .tint = rl.Color.white, .planet = true };
    var ship = Ship{ .position = v(110, 0, 0) };
    var camera = Camera{};
    for (0..360) |i| {
        const angle = @as(f32, @floatFromInt(i + 1)) * std.math.tau / 360;
        const target = v(@cos(angle) * 110, 0, @sin(angle) * 110);
        ship.move(m.sub(target, ship.position), &w);
        try std.testing.expect(w.clear(ship.position, RADIUS));
        try std.testing.expect(w.clear(camera.view(ship, STEP, &w).position, 0.65));
    }
    ship.move(v(-200, 20, 0), &w);
    try std.testing.expect(w.clear(ship.position, RADIUS));
    try std.testing.expect(m.length(ship.position) >= 84.6);
    try std.testing.expect(w.cast(v(0, 0, 100), v(0, 0, -200), 0) != null);
}
