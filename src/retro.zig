const rl = @import("raylib");
const std = @import("std");
// Filter intensities are session-only; every launch starts with all filters off.
pub const Filter = enum { pixelate, chroma, posterize, dither, game_boy, cga, palette, sepia, mono, amber, edges, scanlines, curve, vhs, grain };
pub const COUNT = std.meta.fields(Filter).len;
const Definition = struct { name: [:0]const u8, uniform: [:0]const u8, default: f32 = 0 };
const definitions = std.enums.EnumArray(Filter, Definition).init(.{
    .pixelate = .{ .name = "Pixelate", .uniform = "fPixelate" },
    .chroma = .{ .name = "Chroma fringe", .uniform = "fChroma" },
    .posterize = .{ .name = "Posterize", .uniform = "fPosterize" },
    .dither = .{ .name = "Dither", .uniform = "fDither" },
    .game_boy = .{ .name = "Game Boy", .uniform = "fGameBoy" },
    .cga = .{ .name = "CGA", .uniform = "fCGA" },
    .palette = .{ .name = "Palette 16", .uniform = "fPalette" },
    .sepia = .{ .name = "Sepia", .uniform = "fSepia" },
    .mono = .{ .name = "Mono", .uniform = "fMono" },
    .amber = .{ .name = "Amber CRT", .uniform = "fAmber" },
    .edges = .{ .name = "Ink edges", .uniform = "fEdges" },
    .scanlines = .{ .name = "Scanlines", .uniform = "fScanlines" },
    .curve = .{ .name = "CRT curve", .uniform = "fCurve" },
    .vhs = .{ .name = "VHS", .uniform = "fVHS" },
    .grain = .{ .name = "Film grain", .uniform = "fGrain" },
});
pub const names = blk: {
    var result: [COUNT][:0]const u8 = undefined;
    for (definitions.values, 0..) |def, i| result[i] = def.name;
    break :blk result;
};
pub const defaults = blk: {
    var result: [COUNT]f32 = undefined;
    for (definitions.values, 0..) |def, i| result[i] = def.default;
    break :blk result;
};
pub const Preset = enum { ps1, crt, vhs, game_boy, restore, off, back };
pub const preset_names = std.enums.EnumArray(Preset, [:0]const u8).init(.{
    .ps1 = "Preset: PS1",
    .crt = "Preset: CRT",
    .vhs = "Preset: VHS",
    .game_boy = "Preset: Game Boy",
    .restore = "Restore defaults",
    .off = "All off",
    .back = "Back",
}).values;
pub fn preset(values: *[COUNT]f32, selected: Preset) void {
    if (selected == .back) return;
    values.* = .{0} ** COUNT;
    switch (selected) {
        .ps1 => {
            values[@intFromEnum(Filter.pixelate)] = 0.35;
            values[@intFromEnum(Filter.dither)] = 0.55;
            values[@intFromEnum(Filter.posterize)] = 0.25;
        },
        .crt => {
            values[@intFromEnum(Filter.scanlines)] = 0.6;
            values[@intFromEnum(Filter.chroma)] = 0.45;
            values[@intFromEnum(Filter.curve)] = 0.55;
            values[@intFromEnum(Filter.grain)] = 0.25;
        },
        .vhs => {
            values[@intFromEnum(Filter.vhs)] = 0.65;
            values[@intFromEnum(Filter.chroma)] = 0.55;
            values[@intFromEnum(Filter.grain)] = 0.35;
            values[@intFromEnum(Filter.sepia)] = 0.15;
        },
        .game_boy => {
            values[@intFromEnum(Filter.game_boy)] = 1;
            values[@intFromEnum(Filter.pixelate)] = 0.45;
            values[@intFromEnum(Filter.dither)] = 0.4;
        },
        .restore => values.* = defaults,
        .off => {},
        .back => unreachable,
    }
}
pub const Retro = struct {
    shader: rl.Shader,
    target: rl.RenderTexture2D,
    locations: [COUNT]i32,
    resolution_location: i32,
    time_location: i32,
    values: [COUNT]f32 = defaults,
    pub fn init() Retro {
        const shader = rl.loadShaderFromMemory(null, fragment) catch @panic("retro shader");
        if (shader.id == rl.gl.rlGetShaderIdDefault()) @panic("retro shader fallback");
        var locations: [COUNT]i32 = undefined;
        for (definitions.values, 0..) |def, i| locations[i] = rl.getShaderLocation(shader, def.uniform);
        return .{ .shader = shader, .target = rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight()) catch @panic("retro target"), .locations = locations, .resolution_location = rl.getShaderLocation(shader, "resolution"), .time_location = rl.getShaderLocation(shader, "time") };
    }
    pub fn deinit(r: *Retro) void {
        rl.unloadRenderTexture(r.target);
        rl.unloadShader(r.shader);
    }
    pub fn begin(r: *Retro) bool {
        var active = false;
        for (r.values) |value| if (value > 0) {
            active = true;
        };
        if (!active) return false;
        if (r.target.texture.width != rl.getScreenWidth() or r.target.texture.height != rl.getScreenHeight()) {
            rl.unloadRenderTexture(r.target);
            r.target = rl.loadRenderTexture(rl.getScreenWidth(), rl.getScreenHeight()) catch @panic("retro resize");
        }
        rl.beginTextureMode(r.target);
        rl.clearBackground(rl.Color.black);
        return true;
    }
    pub fn end(r: *Retro, time: f32) void {
        rl.endTextureMode();
        const resolution = rl.Vector2{ .x = @floatFromInt(rl.getScreenWidth()), .y = @floatFromInt(rl.getScreenHeight()) };
        rl.setShaderValue(r.shader, r.resolution_location, &resolution, .vec2);
        rl.setShaderValue(r.shader, r.time_location, &time, .float);
        for (r.locations, 0..) |loc, i| rl.setShaderValue(r.shader, loc, &r.values[i], .float);
        rl.beginShaderMode(r.shader);
        rl.drawTexturePro(r.target.texture, .{ .x = 0, .y = 0, .width = resolution.x, .height = -resolution.y }, .{ .x = 0, .y = 0, .width = resolution.x, .height = resolution.y }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.endShaderMode();
    }
};

// Adapted from zig-soulslike/src/gfx/shaders.zig and gfx.zig; all fifteen controls and presets.
pub const fragment =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\uniform sampler2D texture0;
    \\uniform vec2 resolution;
    \\uniform float time;
    \\uniform float fPixelate, fChroma, fPosterize, fDither, fGameBoy;
    \\uniform float fCGA, fPalette, fSepia, fMono, fAmber;
    \\uniform float fEdges, fScanlines, fCurve, fVHS, fGrain;
    \\out vec4 finalColor;
    \\
    \\float hash21(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
    \\float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
    \\// EVERY read of the captured scene goes through this.
    \\const float PIX_BOX = 0.5;
    \\vec2 pixQ = vec2(0.0);
    \\float pixStep = 0.0; // one block's WIDTH in UV, zero when pixelate is off (chroma snaps to it)
    \\vec4 sceneTap(vec2 p){
    \\  vec4 pt = texture(texture0, p);
    \\  if (pixQ.x <= 0.0) return pt;
    \\  vec4 box = 0.25*(texture(texture0, p - pixQ)
    \\                 + texture(texture0, p + vec2( pixQ.x, -pixQ.y))
    \\                 + texture(texture0, p + vec2(-pixQ.x,  pixQ.y))
    \\                 + texture(texture0, p + pixQ));
    \\  return mix(pt, box, PIX_BOX);
    \\}
    \\// 4x4 Bayer matrix, thresholds at +0.5/16 centers.
    \\const float bayer[16] = float[16](
    \\     0.0,  8.0,  2.0, 10.0,
    \\    12.0,  4.0, 14.0,  6.0,
    \\     3.0, 11.0,  1.0,  9.0,
    \\    15.0,  7.0, 13.0,  5.0);
    \\// Classic 4-shade green LCD ramp, dark to light.
    \\const vec3 gbRamp[4] = vec3[4](
    \\    vec3(0.055, 0.149, 0.055),
    \\    vec3(0.188, 0.384, 0.188),
    \\    vec3(0.545, 0.675, 0.059),
    \\    vec3(0.741, 0.890, 0.420));
    \\// CGA mode-4 high intensity: black / cyan / magenta / white.
    \\const vec3 cga4[4] = vec3[4](
    \\    vec3(0.0), vec3(0.333, 1.0, 1.0), vec3(1.0, 0.333, 1.0), vec3(1.0));
    \\// DawnBringer 16 — balanced general-purpose 16-color pixel-art palette.
    \\const vec3 db16[16] = vec3[16](
    \\    vec3(0.078, 0.047, 0.110), vec3(0.267, 0.141, 0.204),
    \\    vec3(0.188, 0.204, 0.427), vec3(0.306, 0.290, 0.306),
    \\    vec3(0.522, 0.298, 0.188), vec3(0.204, 0.396, 0.141),
    \\    vec3(0.816, 0.275, 0.282), vec3(0.459, 0.443, 0.380),
    \\    vec3(0.349, 0.490, 0.808), vec3(0.824, 0.490, 0.173),
    \\    vec3(0.522, 0.584, 0.631), vec3(0.427, 0.667, 0.173),
    \\    vec3(0.824, 0.667, 0.600), vec3(0.427, 0.761, 0.792),
    \\    vec3(0.855, 0.831, 0.369), vec3(0.871, 0.933, 0.839));
    \\void main(){
    \\  vec2 uv = fragTexCoord;
    \\  float crtMask = 1.0;
    \\  // CRT Curve: barrel-warp the UV; blacken past the tube edge, shade the corners.
    \\  if (fCurve > 0.0){
    \\    vec2 cc = uv*2.0 - 1.0;
    \\    cc *= 1.0 + fCurve*0.18*dot(cc, cc);
    \\    uv = cc*0.5 + 0.5;
    \\    vec2 edge = smoothstep(vec2(0.0), vec2(0.02), uv)*(1.0 - smoothstep(vec2(0.98), vec2(1.0), uv));
    \\    crtMask = edge.x*edge.y*(1.0 - fCurve*0.35*pow(dot(cc, cc)*0.5, 1.5));
    \\  }
    \\  // VHS: per-scanline horizontal jitter + a slow roaming tracking tear.
    \\  if (fVHS > 0.0){
    \\    float row = floor(uv.y*resolution.y);
    \\    uv.x += (hash21(vec2(row, floor(time*24.0))) - 0.5)*fVHS*0.006;
    \\    float band = smoothstep(0.986, 1.0, sin(uv.y*7.0 + time*1.6)*0.5 + 0.5);
    \\    uv.x += band*fVHS*0.05*(hash21(vec2(floor(time*13.0), 7.0)) - 0.5)*2.0;
    \\  }
    \\  // Pixelate: quantize the UV onto a coarse grid (1px = off ... 14px = full chunk).
    \\  if (fPixelate > 0.0){
    \\    float blk = max(floor(mix(1.0, 14.0, fPixelate) + 0.5), 1.0);
    \\    vec2 grid = max(resolution/blk, vec2(1.0));
    \\    uv = (floor(uv*grid) + 0.5)/grid;
    \\    // …and arm the box filter (see sceneTap).
    \\    if (blk > 1.0) pixQ = blk/(4.0*resolution);
    \\    pixStep = blk/resolution.x;
    \\  }
    \\  // Chroma fringe: fetch R and B slightly off-axis (worn composite cable).
    \\  vec4 baseTex = sceneTap(uv);
    \\  vec3 col;
    \\  if (fChroma > 0.0){
    \\    // THE OFFSET SNAPS TO WHOLE BLOCKS.
    \\    float off = fChroma*0.0045;
    \\    vec2 o = vec2(off, 0.0);
    \\    if (pixStep > 0.0) o.x = floor(off/pixStep + 0.5)*pixStep;
    \\    col.r = sceneTap(uv + o).r;
    \\    col.g = baseTex.g;
    \\    col.b = sceneTap(uv - o).b;
    \\  } else { col = baseTex.rgb; }
    \\  // Ink edges: Sobel on luminance, applied as a darkening AFTER the color crush.
    \\  float edgeF = 0.0;
    \\  if (fEdges > 0.0){
    \\    vec2 t = 1.5/resolution;
    \\    float tl = luma(texture(texture0, uv + vec2(-t.x, -t.y)).rgb);
    \\    float tc = luma(texture(texture0, uv + vec2( 0.0, -t.y)).rgb);
    \\    float tr = luma(texture(texture0, uv + vec2( t.x, -t.y)).rgb);
    \\    float ml = luma(texture(texture0, uv + vec2(-t.x,  0.0)).rgb);
    \\    float mr = luma(texture(texture0, uv + vec2( t.x,  0.0)).rgb);
    \\    float bl = luma(texture(texture0, uv + vec2(-t.x,  t.y)).rgb);
    \\    float bc = luma(texture(texture0, uv + vec2( 0.0,  t.y)).rgb);
    \\    float br = luma(texture(texture0, uv + vec2( t.x,  t.y)).rgb);
    \\    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    \\    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);
    \\    edgeF = clamp(length(vec2(gx, gy))*2.2, 0.0, 1.0)*fEdges;
    \\  }
    \\  // Posterize: crush the color depth (48 = subtle banding ... 4 = poster).
    \\  if (fPosterize > 0.0){
    \\    float levels = mix(48.0, 4.0, fPosterize);
    \\    col = floor(col*levels + 0.5)/levels;
    \\  }
    \\  // Ordered dither: Bayer-threshold toward a 6-level quantize.
    \\  if (fDither > 0.0){
    \\    int bx = int(mod(gl_FragCoord.x, 4.0));
    \\    int by = int(mod(gl_FragCoord.y, 4.0));
    \\    float th = (bayer[by*4 + bx] + 0.5)/16.0 - 0.5;
    \\    float levels = 6.0;
    \\    vec3 q = floor((col + th*(1.5/levels))*levels + 0.5)/levels;
    \\    col = mix(col, q, fDither);
    \\  }
    \\  // Game Boy: luminance onto the 4-shade green LCD ramp.
    \\  if (fGameBoy > 0.0){
    \\    int gstep = int(clamp(floor(luma(col)*4.0), 0.0, 3.0));
    \\    col = mix(col, gbRamp[gstep], fGameBoy);
    \\  }
    \\  // CGA: nearest of the 4-color mode-4 palette.
    \\  if (fCGA > 0.0){
    \\    vec3 best = cga4[0];
    \\    float bestD = dot(col - cga4[0], col - cga4[0]);
    \\    for (int i = 1; i < 4; i++){
    \\      vec3 d = col - cga4[i];
    \\      float dist = dot(d, d);
    \\      if (dist < bestD){ bestD = dist; best = cga4[i]; }
    \\    }
    \\    col = mix(col, best, fCGA);
    \\  }
    \\  // Palette: snap to the nearest DawnBringer-16 color (hard pixel-art palette).
    \\  if (fPalette > 0.0){
    \\    vec3 best = db16[0];
    \\    float bestD = dot(col - db16[0], col - db16[0]);
    \\    for (int i = 1; i < 16; i++){
    \\      vec3 d = col - db16[i];
    \\      float dist = dot(d, d);
    \\      if (dist < bestD){ bestD = dist; best = db16[i]; }
    \\    }
    \\    col = mix(col, best, fPalette);
    \\  }
    \\  if (fSepia > 0.0){
    \\    float l = luma(col);
    \\    col = mix(col, vec3(l*1.07 + 0.04, l*0.87, l*0.55), fSepia);
    \\  }
    \\  if (fMono > 0.0) col = mix(col, vec3(luma(col)), fMono);
    \\  if (fAmber > 0.0) col = mix(col, vec3(1.0, 0.62, 0.14)*pow(max(luma(col), 0.0), 0.85), fAmber);
    \\  col *= 1.0 - edgeF*0.85;
    \\  // Scanlines: soft CRT line darkening on alternating rows.
    \\  if (fScanlines > 0.0){
    \\    float s = 0.5 + 0.5*sin(gl_FragCoord.y*3.14159265);
    \\    col *= 1.0 - fScanlines*0.45*s;
    \\  }
    \\  // VHS finish: signal noise + a washed-out desaturation.
    \\  if (fVHS > 0.0){
    \\    float n = hash21(vec2(uv.x*731.0, uv.y*913.0 + time*61.0));
    \\    col += (n - 0.5)*fVHS*0.12;
    \\    col = mix(col, vec3(luma(col)), fVHS*0.25);
    \\  }
    \\  // Film grain: animated per-pixel flicker, HELD on a 24 Hz beat.
    \\  if (fGrain > 0.0){
    \\    float gt = floor(time*24.0);
    \\    float gnoise = hash21(gl_FragCoord.xy + vec2(mod(gt, 97.0)*137.0, mod(gt, 89.0)*291.0));
    \\    col += (gnoise - 0.5)*fGrain*0.18;
    \\  }
    \\  col *= crtMask;
    \\  finalColor = vec4(col, baseTex.a);
    \\}
;
