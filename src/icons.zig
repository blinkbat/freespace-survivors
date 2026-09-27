const rl = @import("raylib");
const game = @import("survivors.zig");
const m = @import("math.zig");

pub const Kind = enum { laser, mine, rocket, orbital, damage, hull, crit, speed, rate, leech };
pub fn upgrade(value: game.Upgrade) Kind {
    return switch (value) {
        inline else => |tag| @field(Kind, @tagName(tag)),
    };
}
pub fn tint(kind: Kind) rl.Color {
    return switch (kind) {
        .laser => m.color(102, 242, 169),
        .mine => m.color(245, 191, 87),
        .rocket => m.color(248, 147, 91),
        .orbital => m.color(108, 211, 244),
        .damage => m.color(240, 157, 134),
        .hull => m.color(121, 215, 180),
        .crit => m.color(242, 216, 115),
        .speed => m.color(148, 202, 238),
        .rate => m.color(195, 177, 237),
        .leech => m.color(229, 135, 178),
    };
}

// Shared vector glyphs stay crisp at HUD and menu sizes; no texture atlas to reload.
pub fn draw(kind: Kind, x: f32, y: f32, size: f32) void {
    const p = Pen{ .x = x, .y = y, .scale = size / 24, .color = tint(kind) };
    switch (kind) {
        .laser => {
            p.line(4, 20, 18, 6, 3);
            p.line(2, 14, 10, 6, 1.5);
            p.line(18, 2, 18, 10, 1.5);
            p.line(14, 6, 22, 6, 1.5);
        },
        .mine => {
            p.disc(12, 12, 5);
            p.line(12, 1, 12, 23, 2);
            p.line(1, 12, 23, 12, 2);
            p.line(4, 4, 20, 20, 2);
            p.line(4, 20, 20, 4, 2);
            p.light(12, 12, 2);
        },
        .rocket => {
            p.triangle(7, 10, 14, 17, 22, 2);
            p.triangle(7, 10, 3, 16, 9, 14);
            p.triangle(14, 17, 10, 21, 10, 14);
            p.line(3, 22, 8, 17, 2);
            p.light(15, 9, 1.5);
        },
        .orbital => {
            p.line(4, 7, 11, 2, 1.5);
            p.line(11, 2, 20, 7, 1.5);
            p.line(20, 7, 22, 15, 1.5);
            p.line(20, 19, 12, 22, 1.5);
            p.line(12, 22, 4, 17, 1.5);
            p.line(4, 17, 2, 9, 1.5);
            p.triangle(12, 6, 7, 16, 17, 16);
            p.disc(20, 18, 3);
            p.light(20, 18, 1);
        },
        .damage => {
            p.triangle(12, 1, 8, 10, 16, 10);
            p.triangle(23, 12, 14, 8, 14, 16);
            p.triangle(12, 23, 16, 14, 8, 14);
            p.triangle(1, 12, 10, 16, 10, 8);
            p.disc(12, 12, 5);
            p.light(12, 12, 2);
        },
        .hull => {
            p.line(12, 3, 12, 21, 6);
            p.line(3, 12, 21, 12, 6);
        },
        .crit => {
            p.line(12, 1, 12, 5, 2);
            p.line(12, 19, 12, 23, 2);
            p.line(1, 12, 5, 12, 2);
            p.line(19, 12, 23, 12, 2);
            p.line(12, 6, 18, 12, 2);
            p.line(18, 12, 12, 18, 2);
            p.line(12, 18, 6, 12, 2);
            p.line(6, 12, 12, 6, 2);
            p.light(12, 12, 2);
        },
        .speed => {
            p.line(3, 4, 10, 12, 3);
            p.line(10, 12, 3, 20, 3);
            p.line(13, 4, 21, 12, 3);
            p.line(21, 12, 13, 20, 3);
        },
        .rate => {
            p.line(2, 5, 13, 5, 2);
            p.line(5, 12, 16, 12, 2);
            p.line(2, 19, 13, 19, 2);
            p.triangle(13, 2, 13, 8, 19, 5);
            p.triangle(16, 9, 16, 15, 22, 12);
            p.triangle(13, 16, 13, 22, 19, 19);
        },
        .leech => {
            p.triangle(10, 1, 3, 13, 17, 13);
            p.disc(10, 14, 7);
            p.light(7, 13, 1.5);
            p.line(19, 14, 19, 23, 2.5);
            p.line(15, 19, 23, 19, 2.5);
        },
    }
}

const Pen = struct {
    x: f32,
    y: f32,
    scale: f32,
    color: rl.Color,
    fn point(p: Pen, x: f32, y: f32) rl.Vector2 {
        return .{ .x = p.x + x * p.scale, .y = p.y + y * p.scale };
    }
    fn line(p: Pen, ax: f32, ay: f32, bx: f32, by: f32, width: f32) void {
        rl.drawLineEx(p.point(ax, ay), p.point(bx, by), width * p.scale, p.color);
    }
    fn disc(p: Pen, x: f32, y: f32, radius: f32) void {
        rl.drawCircleV(p.point(x, y), radius * p.scale, p.color);
    }
    fn light(p: Pen, x: f32, y: f32, radius: f32) void {
        rl.drawCircleV(p.point(x, y), radius * p.scale, m.color(240, 249, 233));
    }
    fn triangle(p: Pen, ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) void {
        const a = p.point(ax, ay);
        const b = p.point(bx, by);
        const c = p.point(cx, cy);
        if ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0) rl.drawTriangle(a, b, c, p.color) else rl.drawTriangle(a, c, b, p.color);
    }
};
