const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");

pub const Tier = enum { common, uncommon, rare, legendary };
pub fn name(tier: Tier) [:0]const u8 {
    return switch (tier) {
        .common => "COMMON",
        .uncommon => "UNCOMMON",
        .rare => "RARE",
        .legendary => "LEGENDARY",
    };
}
pub fn color(tier: Tier) rl.Color {
    return switch (tier) {
        .common => m.color(234, 239, 242),
        .uncommon => m.color(137, 211, 255),
        .rare => m.color(237, 108, 227),
        .legendary => m.color(255, 204, 77),
    };
}

// Sixty common, twenty-five uncommon, twelve rare, three legendary per hundred rolls.
pub fn fromRoll(roll: u8) Tier {
    return if (roll < 60) .common else if (roll < 85) .uncommon else if (roll < 97) .rare else .legendary;
}

test "higher tiers are progressively rarer" {
    var counts = [_]usize{0} ** 4;
    for (0..100) |roll| counts[@intFromEnum(fromRoll(@intCast(roll)))] += 1;
    try std.testing.expectEqualSlices(usize, &.{ 60, 25, 12, 3 }, &counts);
}
