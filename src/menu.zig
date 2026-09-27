const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const controls = @import("controls.zig");
const retro = @import("retro.zig");

pub const Settings = struct {
    fullscreen: bool = false,
    mouse_locked: bool = true,
    mouse_sensitivity: f32 = 1,
    controller_sensitivity: f32 = 1,
    invert_y: bool = false,
    deadzone: f32 = 0.18,
    volume: f32 = 0.8,
    filters: [retro.COUNT]f32 = retro.defaults,

    pub fn sanitize(s: *Settings) void {
        s.mouse_sensitivity = bounded(s.mouse_sensitivity, 0.2, 3, 1);
        s.controller_sensitivity = bounded(s.controller_sensitivity, 0.2, 3, 1);
        s.deadzone = bounded(s.deadzone, 0.05, 0.4, 0.18);
        s.volume = bounded(s.volume, 0, 1, 0.8);
        for (&s.filters) |*value| value.* = bounded(value.*, 0, 1, 0);
    }
    pub fn load() Settings {
        const alloc = std.heap.page_allocator;
        const bytes = std.fs.cwd().readFileAlloc(alloc, "settings.json", 4096) catch return .{};
        defer alloc.free(bytes);
        const parsed = std.json.parseFromSlice(Settings, alloc, bytes, .{ .ignore_unknown_fields = true }) catch return .{};
        defer parsed.deinit();
        var result = parsed.value;
        result.filters = retro.defaults;
        result.sanitize();
        return result;
    }
    pub fn save(s: Settings) void {
        const alloc = std.heap.page_allocator;
        const bytes = std.json.stringifyAlloc(alloc, .{
            .fullscreen = s.fullscreen,
            .mouse_locked = s.mouse_locked,
            .mouse_sensitivity = s.mouse_sensitivity,
            .controller_sensitivity = s.controller_sensitivity,
            .invert_y = s.invert_y,
            .deadzone = s.deadzone,
            .volume = s.volume,
        }, .{ .whitespace = .indent_2 }) catch return;
        defer alloc.free(bytes);
        std.fs.cwd().writeFile(.{ .sub_path = "settings.json", .data = bytes }) catch |err| {
            std.log.warn("Could not save options: {s}", .{@errorName(err)});
        };
    }
};

fn bounded(value: f32, low: f32, high: f32, fallback: f32) f32 {
    return if (std.math.isFinite(value)) std.math.clamp(value, low, high) else fallback;
}

pub const Display = struct {
    width: i32 = 1440,
    height: i32 = 810,
    position: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub fn apply(d: *Display, fullscreen: bool) void {
        if (fullscreen == rl.isWindowFullscreen()) return;
        if (fullscreen) {
            d.width = rl.getScreenWidth();
            d.height = rl.getScreenHeight();
            d.position = rl.getWindowPosition();
            const monitor = rl.getCurrentMonitor();
            rl.setWindowSize(rl.getMonitorWidth(monitor), rl.getMonitorHeight(monitor));
            rl.toggleFullscreen();
        } else {
            rl.toggleFullscreen();
            rl.setWindowSize(d.width, d.height);
            rl.setWindowPosition(@intFromFloat(d.position.x), @intFromFloat(d.position.y));
        }
    }
};

pub const Action = enum { none, resume_game, restart, quit, changed, start_jungle, start_space, main_menu };
pub const Screen = enum { closed, start, pause, options, retro };
const PauseRow = enum { resume_game, options, restart, main_menu, quit };
const start_labels = [_][:0]const u8{ "Jungle Ruins", "Space", "Options", "Quit" };
pub const OptionRow = enum { fullscreen, mouse_locked, mouse_sensitivity, controller_sensitivity, invert_y, deadzone, volume, retro, back };
const pause_labels = std.enums.EnumArray(PauseRow, [:0]const u8).init(.{
    .resume_game = "Resume",
    .options = "Options",
    .restart = "Restart",
    .main_menu = "Main menu",
    .quit = "Quit",
}).values;
const option_labels = std.enums.EnumArray(OptionRow, [:0]const u8).init(.{
    .fullscreen = "Fullscreen",
    .mouse_locked = "Lock mouse",
    .mouse_sensitivity = "Mouse sensitivity",
    .controller_sensitivity = "Controller sensitivity",
    .invert_y = "Invert look Y",
    .deadzone = "Stick deadzone",
    .volume = "Volume",
    .retro = "Retro filters",
    .back = "Back",
}).values;
pub const Menu = struct {
    screen: Screen = .closed,
    selected: usize = 0,
    home: Screen = .pause,

    pub fn start() Menu {
        return .{ .screen = .start, .home = .start };
    }
    fn optionsBack(s: *Menu) void {
        s.screen = s.home;
        s.selected = if (s.home == .start) 2 else @intFromEnum(PauseRow.options);
    }

    pub fn open(s: *Menu) void {
        s.* = .{ .screen = .pause };
    }
    pub fn update(s: *Menu, input: controls.Input, settings: *Settings) Action {
        if (input.back) {
            if (s.screen == .start) return .none;
            if (s.screen == .retro) {
                s.screen = .options;
                s.selected = @intFromEnum(OptionRow.retro);
                return .none;
            }
            if (s.screen == .options) {
                s.optionsBack();
                return .none;
            }
            s.screen = .closed;
            return .resume_game;
        }
        const count = s.rowCount();
        const wheel = rl.getMouseWheelMove();
        navigate(&s.selected, count, input.nav + @as(i32, if (wheel > 0) -1 else if (wheel < 0) 1 else 0));
        const page_size = s.pageSize();
        const first = (s.selected / page_size) * page_size;
        const visible = @min(count, page_size);
        const mouse = rl.getMousePosition();
        const delta = rl.getMouseDelta();
        const click = rl.isMouseButtonPressed(.left);
        var clicked = false;
        var clicked_left = false;
        for (first..@min(first + page_size, count)) |i| {
            const rect = rowRect(i - first, visible);
            if (rl.checkCollisionPointRec(mouse, rect)) {
                if (click or delta.x != 0 or delta.y != 0) s.selected = i;
                clicked = click;
                clicked_left = click and mouse.x >= rect.x + 440 and mouse.x < rect.x + 485;
            }
        }
        const activate = input.accept or clicked;
        if (s.screen == .start) {
            if (!activate) return .none;
            switch (s.selected) {
                0 => return .start_jungle,
                1 => return .start_space,
                2 => {
                    s.screen = .options;
                    s.selected = 0;
                    return .none;
                },
                else => return .quit,
            }
        }
        if (s.screen == .retro) {
            if (!activate and input.adjust == 0) return .none;
            if (s.selected < retro.COUNT) {
                settings.filters[s.selected] += if (input.adjust < 0 or clicked_left) @as(f32, -0.05) else 0.05;
                settings.sanitize();
                return .changed;
            }
            if (!activate) return .none;
            if (s.selected == retro.COUNT + @intFromEnum(retro.Preset.back)) {
                s.screen = .options;
                s.selected = @intFromEnum(OptionRow.retro);
                return .none;
            }
            retro.preset(&settings.filters, @enumFromInt(s.selected - retro.COUNT));
            return .changed;
        }
        if (s.screen == .pause) {
            if (!activate) return .none;
            switch (@as(PauseRow, @enumFromInt(s.selected))) {
                .resume_game => {
                    s.screen = .closed;
                    return .resume_game;
                },
                .options => {
                    s.* = .{ .screen = .options };
                    return .none;
                },
                .restart => {
                    s.screen = .closed;
                    return .restart;
                },
                .quit => return .quit,
                .main_menu => return .main_menu,
            }
        }
        const option: OptionRow = @enumFromInt(s.selected);
        if (option == .retro) {
            if (activate) {
                s.screen = .retro;
                s.selected = 0;
            }
            return .none;
        }
        if (option == .back) {
            if (activate) s.optionsBack();
            return .none;
        }
        if (!activate and input.adjust == 0) return .none;
        const sign: f32 = if (input.adjust < 0 or clicked_left) -1 else 1;
        switch (option) {
            .fullscreen => settings.fullscreen = !settings.fullscreen,
            .mouse_locked => settings.mouse_locked = !settings.mouse_locked,
            .mouse_sensitivity => settings.mouse_sensitivity += sign * 0.1,
            .controller_sensitivity => settings.controller_sensitivity += sign * 0.1,
            .invert_y => settings.invert_y = !settings.invert_y,
            .deadzone => settings.deadzone += sign * 0.01,
            .volume => settings.volume += sign * 0.05,
            .retro, .back => unreachable,
        }
        settings.sanitize();
        return .changed;
    }

    pub fn draw(s: Menu, settings: Settings) void {
        if (s.screen != .retro and s.screen != .start) rl.clearBackground(m.color(7, 11, 17));
        const count = s.rowCount();
        const page_size = s.pageSize();
        const first_index = (s.selected / page_size) * page_size;
        const visible = @min(count, page_size);
        const first = rowRect(0, visible);
        const x: i32 = @intFromFloat(first.x);
        const y: i32 = @intFromFloat(first.y);
        if (s.screen == .retro) rl.drawRectangle(x - 12, y - 65, 624, 460, .{ .r = 7, .g = 11, .b = 17, .a = 235 });
        if (s.screen == .start) {
            rl.drawRectangle(x - 22, y - 105, 644, 346, .{ .r = 7, .g = 18, .b = 20, .a = 225 });
            rl.drawText("FREESPACE SURVIVORS", x + 18, y - 82, 30, m.color(222, 231, 235));
            rl.drawText("Choose a region", x + 18, y - 38, 18, m.color(144, 191, 170));
        } else rl.drawText(if (s.screen == .retro) "Retro filters" else if (s.screen == .options) "Options" else "Paused", x + 18, y - 56, 30, m.color(222, 231, 235));
        for (first_index..@min(first_index + page_size, count)) |i| {
            const rect = rowRect(i - first_index, visible);
            const row_y: i32 = @intFromFloat(rect.y);
            const selected = i == s.selected;
            if (selected) rl.drawRectangleRec(rect, m.color(23, 38, 45));
            const label = if (s.screen == .start) start_labels[i] else if (s.screen == .retro) (if (i < retro.COUNT) retro.names[i] else retro.preset_names[i - retro.COUNT]) else if (s.screen == .options) option_labels[i] else pause_labels[i];
            rl.drawText(label, x + 18, row_y + 10, 22, if (selected) m.color(206, 233, 216) else m.color(150, 167, 178));
            if (s.screen == .start or (s.screen == .options and (i == @intFromEnum(OptionRow.retro) or i == @intFromEnum(OptionRow.back))) or s.screen == .pause or (s.screen == .retro and i >= retro.COUNT)) continue;
            var buf: [32]u8 = undefined;
            const value: [:0]const u8 = if (s.screen == .retro) std.fmt.bufPrintZ(&buf, "{d:.0}%", .{settings.filters[i] * 100}) catch unreachable else switch (@as(OptionRow, @enumFromInt(i))) {
                .fullscreen => if (settings.fullscreen) "On" else "Off",
                .mouse_locked => if (settings.mouse_locked) "On" else "Off",
                .mouse_sensitivity => std.fmt.bufPrintZ(&buf, "{d:.1}x", .{settings.mouse_sensitivity}) catch unreachable,
                .controller_sensitivity => std.fmt.bufPrintZ(&buf, "{d:.1}x", .{settings.controller_sensitivity}) catch unreachable,
                .invert_y => if (settings.invert_y) "On" else "Off",
                .deadzone => std.fmt.bufPrintZ(&buf, "{d:.0}%", .{settings.deadzone * 100}) catch unreachable,
                .volume => std.fmt.bufPrintZ(&buf, "{d:.0}%", .{settings.volume * 100}) catch unreachable,
                .retro, .back => unreachable,
            };
            rl.drawText(value, x + 495, row_y + 10, 22, m.color(206, 233, 216));
            rl.drawText("<", x + 455, row_y + 10, 22, m.color(150, 167, 178));
            rl.drawText(">", x + 570, row_y + 10, 22, m.color(150, 167, 178));
        }
        if (s.screen == .start) rl.drawText(if (s.selected == 1) "Deep space / stations / asteroid fields" else "Ancient arches / river valleys / banyan forests", x + 18, y + 194, 17, m.color(144, 191, 170));
        if (s.screen != .pause and s.screen != .start) {
            var buf: [100]u8 = undefined;
            const footer = if (s.screen == .retro) std.fmt.bufPrintZ(&buf, "Wheel / up-down: more     {d}/{d}", .{ first_index / page_size + 1, (count + page_size - 1) / page_size }) catch unreachable else "Left / right to adjust";
            rl.drawText(footer, x + 18, y + @as(i32, @intCast(visible)) * 44 + 12, 17, m.color(150, 167, 178));
        }
    }
    fn rowCount(s: Menu) usize {
        return switch (s.screen) {
            .retro => retro.COUNT + retro.preset_names.len,
            .options => option_labels.len,
            .start => start_labels.len,
            else => pause_labels.len,
        };
    }
    fn pageSize(s: Menu) usize {
        return if (s.screen == .retro) 8 else option_labels.len;
    }
};

pub fn navigate(selected: *usize, count: usize, direction: i32) void {
    if (count == 0) {
        selected.* = 0;
        return;
    }
    selected.* = @intCast(@mod(@as(i32, @intCast(selected.*)) + direction, @as(i32, @intCast(count))));
}

fn rowRect(index: usize, count: usize) rl.Rectangle {
    return .{
        .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2 - 300,
        .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2 - @as(f32, @floatFromInt(count)) * 22 + 12 + @as(f32, @floatFromInt(index)) * 44,
        .width = 600,
        .height = 42,
    };
}

test "settings clamp corrupt values and menu navigation wraps" {
    var s = Settings{ .mouse_sensitivity = std.math.nan(f32), .deadzone = 1, .volume = -2 };
    s.sanitize();
    try std.testing.expectEqual(@as(f32, 1), s.mouse_sensitivity);
    try std.testing.expectEqual(@as(f32, 0.4), s.deadzone);
    try std.testing.expectEqual(@as(f32, 0), s.volume);
    var selected: usize = 0;
    navigate(&selected, 3, -1);
    try std.testing.expectEqual(@as(usize, 2), selected);
    navigate(&selected, 3, 1);
    try std.testing.expectEqual(@as(usize, 0), selected);
}
