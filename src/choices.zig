const std = @import("std");
const rl = @import("raylib");
const game = @import("survivors.zig");
const m = @import("math.zig");
const hud = @import("hud.zig");
const icons = @import("icons.zig");

// These are gameplay decisions between stretches of play, never labels over entities.
pub fn draw(run: *const game.Run) void {
    drawSelected(run, 0);
}

pub fn drawSelected(run: *const game.Run, selected: usize) void {
    rl.clearBackground(m.color(7, 11, 17));
    const width = rl.getScreenWidth();
    const height = rl.getScreenHeight();
    const left = @divTrunc(width, 2) - 245;
    const top = @divTrunc(height, 2) - 150;
    if (run.dead) {
        rl.drawText("Destroyed", left, top + 35, 30, m.color(229, 192, 176));
        var buf: [100]u8 = undefined;
        const summary = std.fmt.bufPrintZ(&buf, "{d:.0}s survived   {d} kills   Level {d}", .{ run.elapsed, run.kills, run.level }) catch unreachable;
        rl.drawText(summary, left, top + 95, 19, m.color(163, 176, 187));
        rl.drawText("Enter / A to start again", left, top + 160, 22, m.color(222, 231, 235));
        return;
    }
    rl.drawText("Choose an upgrade", left, top, 28, m.color(222, 231, 235));
    hud.loadout(run);
    for (run.choices[0..run.choice_count], 0..) |choice, i| {
        const rect = rowRect(i);
        const y: i32 = @as(i32, @intFromFloat(rect.y)) + 8;
        const tier = run.choiceTier(i);
        const tier_color = game.rarity.color(tier);
        rl.drawRectangleRec(rect, m.color(12, 19, 26));
        if (i == selected) rl.drawRectangleRec(rect, m.color(23, 38, 45));
        rl.drawRectangle(left - 12, y - 8, 3, @intFromFloat(rect.height), tier_color);
        const name = game.definition(choice).name;
        var buf: [80]u8 = undefined;
        const rank = run.rank(choice);
        const label = if (rank == 0)
            std.fmt.bufPrintZ(&buf, "{s}  -  NEW", .{name}) catch unreachable
        else
            std.fmt.bufPrintZ(&buf, "{s}  {d}", .{ name, @as(u16, rank) + 1 }) catch unreachable;
        icons.draw(icons.upgrade(choice), @floatFromInt(left + 3), @floatFromInt(y + 7), 29);
        rl.drawText(label, left + 48, y, 23, tier_color);
        const tier_name = game.rarity.name(tier);
        rl.drawText(tier_name, left + 524 - rl.measureText(tier_name, 12), y + 4, 12, tier_color);
        var description_buf: [120]u8 = undefined;
        rl.drawText(run.choiceDescription(i, &description_buf), left + 48, y + 31, 17, m.color(174, 188, 198));
        var key_buf: [4]u8 = undefined;
        const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{i + 1}) catch unreachable;
        rl.drawText(key, left + 12, y + 42, 12, m.color(128, 144, 156));
    }
}

pub fn pick(run: *const game.Run, selected: *usize, accept: bool) ?usize {
    const mouse = rl.getMousePosition();
    const delta = rl.getMouseDelta();
    const click = rl.isMouseButtonPressed(.left);
    for (0..run.choice_count) |i| {
        if (rl.checkCollisionPointRec(mouse, rowRect(i))) {
            if (click or delta.x != 0 or delta.y != 0) selected.* = i;
            if (click) return i;
        }
    }
    return if (accept) selected.* else null;
}

fn rowRect(index: usize) rl.Rectangle {
    return .{
        .x = @floatFromInt(@divTrunc(rl.getScreenWidth(), 2) - 257),
        .y = @floatFromInt(@divTrunc(rl.getScreenHeight(), 2) - 88 + @as(i32, @intCast(index)) * 80),
        .width = 550,
        .height = 72,
    };
}
