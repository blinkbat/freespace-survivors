const rl = @import("raylib");
const std = @import("std");
const game = @import("survivors.zig");
const m = @import("math.zig");
const icons = @import("icons.zig");

pub fn loadout(run: *const game.Run) void {
    const top = rl.getScreenHeight() - 88;
    for (0..2) |row| {
        const weapons = row == 0;
        const y = top + @as(i32, @intCast(row)) * 38;
        rl.drawText(if (weapons) "WPN" else "SYS", 16, y + 10, 10, m.color(124, 141, 150));
        const slots: usize = if (weapons) game.MAX_WEAPONS else game.MAX_SYSTEMS;
        var ids: [@max(game.MAX_WEAPONS, game.MAX_SYSTEMS)]?game.Upgrade = @splat(null);
        var count: usize = if (weapons) 1 else 0;
        for (run.ranks, 0..) |rank, id| {
            if (rank == 0 or game.isWeapon(@enumFromInt(id)) != weapons or count == slots) continue;
            ids[count] = @enumFromInt(id);
            count += 1;
        }
        for (ids[0..slots], 0..) |id, slot| {
            const x = 47 + @as(i32, @intCast(slot)) * 43;
            rl.drawRectangle(x, y, 39, 30, .{ .r = 9, .g = 16, .b = 22, .a = 210 });
            const laser = weapons and slot == 0;
            if (!laser and id == null) {
                rl.drawText("-", x + 16, y + 9, 12, m.color(52, 68, 77));
                continue;
            }
            rl.drawRectangle(x, y + 28, 39, 2, game.rarity.color(.rare));
            icons.draw(if (laser) .laser else icons.upgrade(id.?), @floatFromInt(x + 4), @floatFromInt(y + 3), 22);
            var buf: [8]u8 = undefined;
            const rank = if (laser) @as(u8, 1) else run.rank(id.?);
            const text = std.fmt.bufPrintZ(&buf, "{d}", .{rank}) catch unreachable;
            rl.drawText(text, x + 32 - @divTrunc(rl.measureText(text, 10), 2), y + 16, 10, m.color(198, 211, 213));
        }
    }
}
