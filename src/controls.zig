const std = @import("std");
const rl = @import("raylib");

pub fn deadzone(raw: rl.Vector2, threshold: f32) rl.Vector2 {
    const length = @sqrt(raw.x * raw.x + raw.y * raw.y);
    if (length <= threshold) return .{ .x = 0, .y = 0 };
    const scale = (@min(length, 1) - threshold) / ((1 - threshold) * length);
    return .{ .x = raw.x * scale, .y = raw.y * scale };
}

pub const Input = struct {
    pad: ?i32 = null,
    disconnected: bool = false,
    move: rl.Vector2 = .{ .x = 0, .y = 0 },
    look: rl.Vector2 = .{ .x = 0, .y = 0 },
    nav: i32 = 0,
    adjust: i32 = 0,
    accept: bool = false,
    back: bool = false,
    pause: bool = false,
    fullscreen: bool = false,
    held: i32 = 0,
    repeat: f32 = 0,

    pub fn poll(s: *Input, dt: f32, threshold: f32) void {
        s.disconnected = false;
        if (s.pad) |pad| {
            if (!rl.isGamepadAvailable(pad)) {
                s.pad = null;
                s.disconnected = true;
            }
        }
        if (s.pad == null) {
            for (0..4) |i| {
                const pad: i32 = @intCast(i);
                if (rl.isGamepadAvailable(pad)) {
                    s.pad = pad;
                    break;
                }
            }
        }
        s.move = deadzone(.{ .x = s.axis(.left_x), .y = s.axis(.left_y) }, threshold);
        s.look = deadzone(.{ .x = s.axis(.right_x), .y = s.axis(.right_y) }, threshold);
        const alt = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
        s.fullscreen = rl.isKeyPressed(.f11) or (alt and rl.isKeyPressed(.enter));
        s.accept = (!alt and rl.isKeyPressed(.enter)) or s.button(.right_face_down);
        s.back = rl.isKeyPressed(.escape) or s.button(.right_face_right);
        s.pause = s.button(.middle_right);
        s.nav = if (pressed(.up) or s.button(.left_face_up)) -1 else if (pressed(.down) or s.button(.left_face_down)) 1 else 0;
        s.adjust = if (pressed(.left) or s.button(.left_face_left)) -1 else if (pressed(.right) or s.button(.left_face_right)) 1 else 0;
        const direction: i32 = if (@abs(s.move.y) > 0.55) (if (s.move.y < 0) -1 else 1) else if (@abs(s.move.x) > 0.55) (if (s.move.x < 0) -2 else 2) else 0;
        s.repeat -= dt;
        if (direction == 0) {
            s.held = 0;
        } else if (direction != s.held or s.repeat <= 0) {
            s.repeat = if (direction != s.held) 0.35 else 0.14;
            s.held = direction;
            if (@abs(direction) == 1) s.nav = direction else s.adjust = @divTrunc(direction, 2);
        }
    }

    fn axis(s: Input, a: rl.GamepadAxis) f32 {
        return if (s.pad) |p| rl.getGamepadAxisMovement(p, a) else 0;
    }
    fn button(s: Input, b: rl.GamepadButton) bool {
        return if (s.pad) |p| rl.isGamepadButtonPressed(p, b) else false;
    }
};

fn pressed(k: rl.KeyboardKey) bool {
    return rl.isKeyPressed(k) or rl.isKeyPressedRepeat(k);
}

pub fn key(k: rl.KeyboardKey) f32 {
    return if (rl.isKeyDown(k)) 1 else 0;
}

test "radial stick deadzone rejects drift and preserves direction at full deflection" {
    try std.testing.expectEqual(@as(f32, 0), deadzone(.{ .x = 0.1, .y = -0.1 }, 0.18).x);
    const middle = deadzone(.{ .x = 0.59, .y = 0 }, 0.18);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), middle.x, 0.0001);
    const diagonal = deadzone(.{ .x = 1, .y = -1 }, 0.18);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt(diagonal.x * diagonal.x + diagonal.y * diagonal.y), 0.0001);
    try std.testing.expectApproxEqAbs(diagonal.x, -diagonal.y, 0.0001);
}
