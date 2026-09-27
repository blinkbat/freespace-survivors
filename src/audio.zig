const std = @import("std");
const rl = @import("raylib");
pub const Cue = enum { laser, explosion, pickup, level, hit };
pub const Audio = struct {
    enabled: bool = false,
    sounds: [5]rl.Sound = undefined,
    pub fn init() Audio {
        rl.initAudioDevice();
        var audio = Audio{ .enabled = rl.isAudioDeviceReady() };
        if (!audio.enabled) return audio;
        for (&audio.sounds, 0..) |*sound, i| sound.* = synth(@enumFromInt(i));
        return audio;
    }
    pub fn deinit(a: *Audio) void {
        if (!a.enabled) return;
        for (a.sounds) |sound| rl.unloadSound(sound);
        rl.closeAudioDevice();
    }
    pub fn play(a: *const Audio, cue: Cue) void {
        if (a.enabled) rl.playSound(a.sounds[@intFromEnum(cue)]);
    }
};

fn synth(cue: Cue) rl.Sound {
    const duration: f32 = switch (cue) {
        .laser => 0.095,
        .explosion => 0.3,
        .pickup => 0.11,
        .level => 0.45,
        .hit => 0.2,
    };
    const count: usize = @intFromFloat(duration * 22050);
    const samples = std.heap.page_allocator.alloc(f32, count) catch @panic("audio allocation");
    defer std.heap.page_allocator.free(samples);
    var rng = std.Random.DefaultPrng.init(71);
    var phase: f32 = 0;
    for (samples, 0..) |*sample, i| {
        const t = @as(f32, @floatFromInt(i)) / 22050;
        const life = t / duration;
        const frequency: f32 = switch (cue) {
            .laser => 1300 - life * 950,
            .explosion => 85 - life * 45,
            .pickup => 1200 + life * 900,
            .level => 440 * (1 + @floor(life * 4) * 0.25),
            .hit => 130 - life * 60,
        };
        phase += frequency * std.math.tau / 22050;
        const noise = (rng.random().float(f32) * 2 - 1);
        const wave = switch (cue) {
            .explosion, .hit => @sin(phase) * 0.4 + noise * 0.6,
            else => @sin(phase) * 0.75 + @sin(phase * 2) * 0.15,
        };
        sample.* = wave * (1 - life) * (1 - life) * @min(1, t * 600) * 0.35;
    }
    const sound = rl.loadSoundFromWave(.{ .frameCount = @intCast(count), .sampleRate = 22050, .sampleSize = 32, .channels = 1, .data = samples.ptr });
    rl.setSoundVolume(sound, if (cue == .laser) 0.23 else 0.55);
    return sound;
}
