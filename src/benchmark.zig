const std = @import("std");
const game = @import("survivors.zig");
const flight = @import("flight.zig");
const world = @import("world.zig");
const m = @import("math.zig");

// Bounded CPU-only stress run; no window, audio, or settings writes.
pub fn run() !void {
    const w = world.World.init();
    var samples: [5]u64 = undefined;
    var kills: u32 = 0;
    var shots: u32 = 0;
    for (&samples) |*sample| {
        var ship = flight.Ship{};
        var state = game.Run{ .spawn_clock = 1000, .hurt = 1000 };
        for ([_]game.Upgrade{ .mine, .rocket, .orbital }) |upgrade| state.ranks[@intFromEnum(upgrade)] = 3;
        state.ranks[@intFromEnum(game.Upgrade.rate)] = 3;
        state.bonuses[@intFromEnum(game.Upgrade.rate)] = 50;
        state.flock(m.add(ship.position, m.v(0, 0, -90)), game.MAX_DRONES, &w);
        var timer = try std.time.Timer.start();
        for (0..600) |_| {
            ship.tick(.{ .thrust = m.v(0.7, 0, -0.7), .look = .{ .x = 0.003, .y = 0 } }, flight.STEP, &w);
            state.tick(&ship, &w, flight.STEP);
            state.xp = 0;
            state.choosing = false;
            if (state.activeCount() < 160) state.flock(m.add(ship.position, m.scale(ship.forward(), 85)), 32, &w);
        }
        sample.* = timer.read();
        kills = state.kills;
        shots = state.shots_fired;
    }
    std.mem.sort(u64, &samples, {}, std.sort.asc(u64));
    std.debug.print("Dense CPU benchmark: median {d:.3} ms/tick, {d} kills, {d} shots (5 x 600 ticks)\n", .{ @as(f64, @floatFromInt(samples[2])) / 600_000_000, kills, shots });
}
