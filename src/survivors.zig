const std = @import("std");
const m = @import("math.zig");
const flight = @import("flight.zig");
const world = @import("world.zig");
pub const rarity = @import("rarity.zig");
const v = m.v;
pub const MAX_DRONES = 192;
pub const WAVE_SECONDS: f32 = 30;
pub const HIT_FLASH_TIME: f32 = 0.32;
pub const ENEMY_FLASH_TIME: f32 = 0.12;
pub const XP_FLASH_TIME: f32 = 0.20;
pub const BOLT_SPEED: f32 = 230;
pub fn flockSize(wave: u32) usize {
    return @min(24, 4 + @as(usize, wave) * 2);
}
pub fn spawnPeriod(wave: u32) f32 {
    return @max(1.4, 6.0 - @as(f32, @floatFromInt(wave)) * 0.45);
}
pub const Drone = struct { active: bool = false, position: m.V = m.zero, velocity: m.V = m.zero, hp: f32 = 2, wave: u32 = 0, flash: f32 = 0, phase: f32 = 0 };
pub const Bolt = struct { active: bool = false, position: m.V = m.zero, velocity: m.V = m.zero, life: f32 = 0, damage: f32 = 1, critical: bool = false, orbital: bool = false };
pub const Mine = struct {
    pub const ARM_TIME: f32 = 0.7;
    pub const FADE_TIME: f32 = 8;
    pub const LIFETIME: f32 = 9;
    pub const BASE_RADIUS: f32 = 20;
    pub const RADIUS_PER_RANK: f32 = 3;
    active: bool = false,
    position: m.V = m.zero,
    velocity: m.V = m.zero,
    age: f32 = 0,
    damage: f32 = 4,
    radius: f32 = BASE_RADIUS,
};
pub const Rocket = struct { active: bool = false, position: m.V = m.zero, velocity: m.V = m.zero, age: f32 = 0, damage: f32 = 8, target_id: ?usize = null, trail: [12]m.V = [_]m.V{m.zero} ** 12, trail_clock: f32 = 0 };
pub const Orbital = struct { position: m.V = m.zero, aim: m.V = v(0, 0, -1), fire_clock: f32 = 0, visible: bool = false };
pub const Gem = struct { active: bool = false, position: m.V = m.zero, value: u32 = 1 };
pub const Burst = struct { position: m.V = m.zero, age: f32 = 2, size: f32 = 1, kind: enum { explosion, pickup, hit, level } = .explosion };
pub const Upgrade = enum { mine, rocket, orbital, damage, hull, crit, speed, rate, leech };
pub const UPGRADE_COUNT = std.meta.fields(Upgrade).len;
pub const Definition = struct { name: [:0]const u8, cap: u8, weapon: bool = false, gains: [4]f32 };
pub fn definition(upgrade: Upgrade) Definition {
    return switch (upgrade) {
        .mine => .{ .name = "Proximity mine", .cap = 5, .weapon = true, .gains = .{ 1, 2, 4, 8 } },
        .rocket => .{ .name = "Homing rocket", .cap = 5, .weapon = true, .gains = .{ 3, 5, 8, 14 } },
        .orbital => .{ .name = "Orbital drone", .cap = 3, .weapon = true, .gains = .{ 0.25, 0.5, 1, 2 } },
        .damage => .{ .name = "Attack damage", .cap = 9, .gains = .{ 10, 20, 35, 60 } },
        .hull => .{ .name = "HP", .cap = 255, .gains = .{ 1, 2, 3, 5 } },
        .crit => .{ .name = "Crit chance", .cap = 8, .gains = .{ 2, 4, 7, 12 } },
        .speed => .{ .name = "Move speed", .cap = 5, .gains = .{ 1, 2, 5, 10 } },
        .rate => .{ .name = "Attack rate", .cap = 8, .gains = .{ 5, 10, 18, 30 } },
        .leech => .{ .name = "Life leech", .cap = 5, .gains = .{ 1, 2, 3, 5 } },
    };
}
pub const caps = blk: {
    var result: [UPGRADE_COUNT]u8 = undefined;
    for (&result, 0..) |*cap, i| cap.* = definition(@enumFromInt(i)).cap;
    break :blk result;
};
const initial_ranks = [_]u8{0} ** caps.len;
pub const MAX_WEAPONS = 4;
pub const MAX_SYSTEMS = 4;
pub fn isWeapon(upgrade: Upgrade) bool {
    return definition(upgrade).weapon;
}

pub fn statGain(upgrade: Upgrade, tier: rarity.Tier) f32 {
    return definition(upgrade).gains[@intFromEnum(tier)];
}

pub const Run = struct {
    drones: [MAX_DRONES]Drone = [_]Drone{.{}} ** MAX_DRONES,
    bolts: [128]Bolt = [_]Bolt{.{}} ** 128,
    mines: [32]Mine = [_]Mine{.{}} ** 32,
    rockets: [24]Rocket = [_]Rocket{.{}} ** 24,
    orbitals: [3]Orbital = [_]Orbital{.{}} ** 3,
    gems: [768]Gem = [_]Gem{.{}} ** 768,
    bursts: [96]Burst = [_]Burst{.{}} ** 96,
    burst_next: usize = 0,
    rng: std.Random.DefaultPrng = std.Random.DefaultPrng.init(0x53555256),
    elapsed: f32 = 0,
    wave: u32 = 0,
    spawn_clock: f32 = 6,
    fire_clock: f32 = 0,
    mine_clock: f32 = 0,
    rocket_clock: f32 = 0,
    launch_side: f32 = 1,
    leech_credit: f32 = 0,
    hurt: f32 = 0,
    hit_flash: f32 = 0,
    xp_flash: f32 = 0,
    hp: u32 = 5,
    max_hp: u32 = 5,
    kills: u32 = 0,
    xp: u32 = 0,
    level: u32 = 1,
    ranks: [caps.len]u8 = initial_ranks,
    bonuses: [caps.len]f32 = .{0} ** caps.len,
    choosing: bool = false,
    choices: [3]Upgrade = .{ .mine, .rocket, .orbital },
    choice_tiers: [3]rarity.Tier = .{ .rare, .rare, .rare },
    choice_count: usize = 0,
    dead: bool = false,
    shots_fired: u32 = 0,
    hits_taken: u32 = 0,

    pub fn init(ship: flight.Ship, w: *const world.World, seed: u64) Run {
        var run = Run{ .rng = std.Random.DefaultPrng.init(seed) };
        const front = m.add(ship.position, m.scale(ship.forward(), 120));
        run.flock(front, 6, w);
        return run;
    }

    pub fn need(r: *const Run) u32 {
        const n = r.level - 1;
        return 60 + n * 30 + n * n * 6;
    }
    pub fn rank(r: *const Run, upgrade: Upgrade) u8 {
        return r.ranks[@intFromEnum(upgrade)];
    }
    pub fn bonus(r: *const Run, upgrade: Upgrade) f32 {
        return r.bonuses[@intFromEnum(upgrade)];
    }
    pub fn choiceTier(r: *const Run, index: usize) rarity.Tier {
        return if (r.rank(r.choices[index]) == 0) .rare else r.choice_tiers[index];
    }
    pub fn choiceGain(r: *const Run, index: usize) f32 {
        const upgrade = r.choices[index];
        const gain = statGain(upgrade, r.choiceTier(index));
        return if (upgrade == .crit) @min(gain, @max(0, 60 - r.bonus(.crit))) else gain;
    }
    pub fn choiceDescription(r: *const Run, index: usize, buf: []u8) [:0]const u8 {
        const upgrade = r.choices[index];
        if (r.rank(upgrade) == 0 and isWeapon(upgrade)) return switch (upgrade) {
            .mine => "Launch mines that wait, then blast nearby foes",
            .rocket => "Slow volleys, wide homing arcs, heavy damage",
            .orbital => "An orbiting drone fires at nearby foes",
            else => unreachable,
        };
        const gain = r.choiceGain(index);
        return switch (upgrade) {
            .mine => std.fmt.bufPrintZ(buf, "+{d} mine damage, +{d}m blast radius", .{ gain, Mine.RADIUS_PER_RANK }),
            .rocket => std.fmt.bufPrintZ(buf, "+{d} rocket damage; faster launches", .{gain}),
            .orbital => std.fmt.bufPrintZ(buf, "+{d} drone damage; add one drone", .{gain}),
            .damage => std.fmt.bufPrintZ(buf, "+{d}% base damage for every weapon", .{gain}),
            .hull => std.fmt.bufPrintZ(buf, "+{d} maximum HP and fully repair", .{gain}),
            .crit => std.fmt.bufPrintZ(buf, "+{d}% critical chance for every weapon", .{gain}),
            .speed => std.fmt.bufPrintZ(buf, "+{d} m/s movement speed", .{gain}),
            .rate => std.fmt.bufPrintZ(buf, "+{d}% attack rate for every weapon", .{gain}),
            .leech => std.fmt.bufPrintZ(buf, "Recover +{d}% of damage dealt as HP", .{gain}),
        } catch unreachable;
    }
    pub fn installedCount(r: *const Run, weapons: bool) usize {
        var count: usize = if (weapons) 1 else 0; // The starting laser occupies one weapon slot.
        for (r.ranks, 0..) |value, i| {
            if (value > 0 and isWeapon(@enumFromInt(i)) == weapons) count += 1;
        }
        return count;
    }
    pub fn available(r: *const Run, upgrade: Upgrade) bool {
        const id = @intFromEnum(upgrade);
        if (upgrade == .crit and r.bonus(.crit) >= 60) return false;
        if (r.ranks[id] >= caps[id] and upgrade != .hull) return false;
        if (r.ranks[id] > 0) return true;
        const weapon = isWeapon(upgrade);
        return r.installedCount(weapon) < @as(usize, if (weapon) MAX_WEAPONS else MAX_SYSTEMS);
    }
    pub fn pickupRadius(_: *const Run) f32 {
        return 18;
    }
    pub fn attackRate(r: *const Run) f32 {
        return 1 + r.bonus(.rate) / 100;
    }
    pub fn speedMultiplier(r: *const Run) f32 {
        return 1 + r.bonus(.speed) / flight.SPEED;
    }
    pub fn damageMultiplier(r: *const Run) f32 {
        return 1 + r.bonus(.damage) / 100;
    }
    pub fn critChance(r: *const Run, laser: bool) f32 {
        return @min(0.85, @as(f32, if (laser) 0.25 else 0.05) + r.bonus(.crit) / 100);
    }
    pub fn period(r: *const Run) f32 {
        return 0.16 / r.attackRate();
    }
    pub fn activeCount(r: *const Run) usize {
        var count: usize = 0;
        for (r.drones) |d| if (d.active) {
            count += 1;
        };
        return count;
    }

    pub fn tick(r: *Run, ship: *flight.Ship, w: *const world.World, dt: f32) void {
        if (r.choosing) return;
        for (&r.bursts) |*b| b.age += dt;
        r.hit_flash = @max(0, r.hit_flash - dt);
        r.xp_flash = @max(0, r.xp_flash - dt);
        if (r.dead) return;
        r.elapsed += dt;
        const next_wave: u32 = @intFromFloat(r.elapsed / WAVE_SECONDS);
        const new_wave = next_wave > r.wave;
        if (new_wave) {
            r.wave = next_wave;
            r.spawn_clock = 0;
        }
        r.hurt = @max(0, r.hurt - dt);
        r.spawn_clock -= dt;
        if (r.spawn_clock <= 0) {
            r.spawn_clock += spawnPeriod(r.wave);
            const random = r.rng.random();
            const angle = random.float(f32) * std.math.tau;
            const radius = 185 + random.float(f32) * 40;
            const center = m.add(ship.position, v(@cos(angle) * radius, (random.float(f32) - 0.5) * 120, @sin(angle) * radius));
            const reinforcements: usize = if (new_wave) @min(6, @as(usize, r.wave) + 2) else 0;
            r.flock(center, flockSize(r.wave) + reinforcements, w);
        }
        for (&r.drones, 0..) |*d, i| {
            if (!d.active) continue;
            d.flash = @max(0, d.flash - dt);
            const toward = m.sub(ship.position, d.position);
            const distance = m.length(toward);
            if (distance > 600) {
                d.active = false;
                continue;
            }
            var direction = m.norm(toward);
            // Local repulsion preserves individual silhouettes inside flocks.
            var repel = m.zero;
            for (r.drones, 0..) |other, j| {
                if (!other.active or i == j) continue;
                const delta = m.sub(d.position, other.position);
                const sq = m.dot(delta, delta);
                if (sq < 36 and sq > 0.01) repel = m.add(repel, m.scale(delta, (36 - sq) / (36 * sq)));
            }
            direction = m.norm(m.add(direction, m.scale(repel, 2.8)));
            const probe = m.scale(direction, 12);
            if (w.cast(d.position, probe, 1.7)) |hit| {
                var tangent = m.sub(direction, m.scale(hit.normal, m.dot(direction, hit.normal)));
                if (m.length(tangent) < 0.2) tangent = if (@abs(hit.normal.y) < 0.8) v(0, 1, 0) else v(1, 0, 0);
                direction = m.norm(m.add(tangent, m.scale(hit.normal, 0.3)));
            }
            const speed = @min(50, 42 + @as(f32, @floatFromInt(d.wave)) * 0.8) + @sin(d.phase) * 1.5;
            // Opening flocks are escapable; later pursuit still commits momentum through turns.
            d.velocity = m.mix(d.velocity, m.scale(direction, speed), 1 - @exp(-2.4 * dt));
            const delta = m.scale(d.velocity, dt);
            if (w.cast(d.position, delta, 1.7)) |hit| {
                d.position = m.add(d.position, m.scale(delta, @max(0, hit.t - 0.01)));
                d.velocity = m.sub(d.velocity, m.scale(hit.normal, @min(0, m.dot(d.velocity, hit.normal))));
            } else d.position = m.add(d.position, delta);
            const contact = m.sub(ship.position, d.position);
            if (m.dot(contact, contact) < (flight.RADIUS + 1.8) * (flight.RADIUS + 1.8) and r.hurt == 0 and w.cast(d.position, contact, 0) == null) {
                r.hp -= 1;
                r.hits_taken +%= 1;
                r.hurt = 1.05;
                r.hit_flash = HIT_FLASH_TIME;
                r.burst(ship.position, .hit, 1);
                d.active = false;
                r.burst(d.position, .explosion, 0.7);
                if (r.hp == 0) {
                    r.dead = true;
                    ship.velocity = m.zero;
                    r.burst(ship.position, .explosion, 4);
                    return;
                }
            }
        }
        r.fire_clock -= dt;
        if (r.fire_clock <= 0) {
            r.fire_clock += r.period();
            const muzzle = m.add(ship.position, m.scale(ship.forward(), 4));
            if (w.cast(ship.position, m.sub(muzzle, ship.position), 0.12) == null)
                r.shoot(muzzle, ship.forward(), 1, false);
        }
        r.tickWeapons(ship.*, w, dt);
        for (&r.bolts) |*b| {
            if (!b.active) continue;
            const delta = m.scale(b.velocity, dt);
            const wall = w.cast(b.position, delta, 0.12);
            var nearest: f32 = if (wall) |h| h.t else 1.1;
            var victim: ?usize = null;
            for (r.drones, 0..) |d, i| {
                if (!d.active) continue;
                if (sphereHit(b.position, delta, d.position, 2.0)) |t| {
                    if (t < nearest) {
                        nearest = t;
                        victim = i;
                    }
                }
            }
            b.position = m.add(b.position, m.scale(delta, @min(nearest, 1)));
            b.life -= dt;
            if (victim) |i| {
                b.active = false;
                r.damageEnemy(i, b.damage);
            } else if (wall != null or b.life <= 0) b.active = false;
        }
        for (&r.gems) |*g| {
            if (!g.active) continue;
            const delta = m.sub(ship.position, g.position);
            const distance = m.length(delta);
            if (distance < r.pickupRadius() and w.cast(g.position, delta, 0) == null) {
                if (distance <= 5 + dt * 95) {
                    r.xp += g.value;
                    g.active = false;
                    r.xp_flash = XP_FLASH_TIME;
                    r.burst(g.position, .pickup, 0.5);
                } else g.position = m.add(g.position, m.scale(m.norm(delta), dt * 95));
            }
        }
        r.offer();
    }

    pub fn target(r: *const Run, position: m.V, w: *const world.World, skip: ?usize) ?usize {
        var best: f32 = 105 * 105;
        var found: ?usize = null;
        for (r.drones, 0..) |d, i| {
            if (!d.active or (skip != null and skip.? == i)) continue;
            const delta = m.sub(d.position, position);
            const sq = m.dot(delta, delta);
            if (sq < best and w.cast(position, delta, 0.2) == null) {
                best = sq;
                found = i;
            }
        }
        return found;
    }

    fn shoot(r: *Run, position: m.V, direction: m.V, damage: f32, orbital: bool) void {
        for (&r.bolts) |*b| {
            if (b.active) continue;
            const critical = r.rng.random().float(f32) < r.critChance(!orbital);
            b.* = .{ .active = true, .position = position, .velocity = m.scale(direction, BOLT_SPEED), .life = 0.85, .damage = damage * r.damageMultiplier() * @as(f32, if (critical) 2 else 1), .critical = critical, .orbital = orbital };
            r.shots_fired +%= 1;
            return;
        }
    }

    fn damageEnemy(r: *Run, index: usize, damage: f32) void {
        const d = &r.drones[index];
        if (!d.active) return;
        const dealt = @min(d.hp, damage);
        d.hp -= damage;
        d.flash = ENEMY_FLASH_TIME;
        if (r.hp < r.max_hp and !r.dead) {
            r.leech_credit += dealt * r.bonus(.leech) / 100;
            const healed: u32 = @intFromFloat(r.leech_credit);
            r.hp += @min(r.max_hp - r.hp, healed);
            r.leech_credit -= @as(f32, @floatFromInt(healed));
        }
        if (r.hp == r.max_hp) r.leech_credit = 0;
        if (d.hp <= 0) r.kill(index) else r.burst(d.position, .hit, 0.3);
    }

    fn blast(r: *Run, position: m.V, radius: f32, damage: f32, w: *const world.World) void {
        r.burst(position, .explosion, radius / 5);
        for (r.drones, 0..) |d, i| {
            if (!d.active) continue;
            const delta = m.sub(d.position, position);
            if (m.dot(delta, delta) > radius * radius or w.cast(position, delta, 0) != null) continue;
            const critical = r.rng.random().float(f32) < r.critChance(false);
            r.damageEnemy(i, damage * @as(f32, if (critical) 2 else 1));
        }
    }

    fn tickWeapons(r: *Run, ship: flight.Ship, w: *const world.World, dt: f32) void {
        if (r.rank(.mine) > 0) {
            r.mine_clock -= dt;
            if (r.mine_clock <= 0) {
                r.mine_clock += 2.4 / r.attackRate();
                for (&r.mines) |*mine| {
                    if (mine.active) continue;
                    const direction = m.norm(m.add(m.scale(ship.right(), r.launch_side), m.scale(ship.forward(), -0.7)));
                    r.launch_side *= -1;
                    mine.* = .{ .active = true, .position = ship.position, .velocity = m.scale(direction, 42), .damage = (4 + r.bonus(.mine)) * r.damageMultiplier(), .radius = Mine.BASE_RADIUS + Mine.RADIUS_PER_RANK * @as(f32, @floatFromInt(r.rank(.mine) - 1)) };
                    break;
                }
            }
        }
        for (&r.mines) |*mine| {
            if (!mine.active) continue;
            mine.age += dt;
            if (mine.age >= Mine.LIFETIME) {
                mine.active = false;
                continue;
            }
            if (mine.age < Mine.ARM_TIME) {
                const delta = m.scale(mine.velocity, dt);
                if (w.cast(mine.position, delta, 0.8)) |hit| {
                    mine.position = m.add(mine.position, m.scale(delta, @max(0, hit.t - 0.01)));
                    mine.velocity = m.zero;
                } else mine.position = m.add(mine.position, delta);
                mine.velocity = m.scale(mine.velocity, @exp(-3 * dt));
                continue;
            }
            if (mine.age > Mine.FADE_TIME) continue;
            for (r.drones) |d| {
                if (!d.active) continue;
                const delta = m.sub(d.position, mine.position);
                if (m.dot(delta, delta) <= 12 * 12 and w.cast(mine.position, delta, 0) == null) {
                    mine.active = false;
                    r.blast(mine.position, mine.radius, mine.damage, w);
                    break;
                }
            }
        }
        if (r.rank(.rocket) > 0) {
            r.rocket_clock -= dt;
            if (r.rocket_clock <= 0) {
                if (r.target(ship.position, w, null)) |target_id| {
                    r.rocket_clock = 3.6 / (r.attackRate() * (1 + 0.1 * @as(f32, @floatFromInt(r.rank(.rocket) - 1))));
                    for ([_]f32{ -1, 1 }) |side| {
                        for (&r.rockets) |*rocket| {
                            if (rocket.active) continue;
                            const direction = m.norm(m.add(m.scale(ship.right(), side), m.add(m.scale(ship.up(), 0.5), m.scale(ship.forward(), 0.2))));
                            rocket.* = .{ .active = true, .position = ship.position, .velocity = m.scale(direction, 80), .target_id = target_id, .damage = (8 + r.bonus(.rocket)) * r.damageMultiplier(), .trail = [_]m.V{ship.position} ** 12 };
                            break;
                        }
                    }
                } else r.rocket_clock = 0.1;
            }
        }
        for (&r.rockets) |*rocket| {
            if (!rocket.active) continue;
            rocket.age += dt;
            if (rocket.age >= 6) {
                rocket.active = false;
                continue;
            }
            if (rocket.target_id == null or !r.drones[rocket.target_id.?].active)
                rocket.target_id = r.target(rocket.position, w, null);
            if (rocket.age > 0.4) {
                if (rocket.target_id) |id| {
                    const aim = m.add(r.drones[id].position, m.scale(r.drones[id].velocity, 0.12));
                    const delta = m.sub(aim, rocket.position);
                    const turn_rate: f32 = if (rocket.age < 1.1) 2.5 else 6;
                    const direction = turnToward(m.norm(rocket.velocity), m.norm(delta), turn_rate * dt);
                    // Tighten the terminal turn instead of circling a close target forever.
                    const speed = @min(@min(150, 80 + rocket.age * 35), @max(12, m.length(delta) * 2.5));
                    rocket.velocity = m.scale(direction, speed);
                }
            }
            const delta = m.scale(rocket.velocity, dt);
            const wall = w.cast(rocket.position, delta, 0.4);
            var nearest: f32 = if (wall) |hit| hit.t else 1.1;
            var impact = wall != null;
            for (r.drones) |d| {
                if (!d.active) continue;
                if (sphereHit(rocket.position, delta, d.position, 2.6)) |t| {
                    if (t < nearest) {
                        nearest = t;
                        impact = true;
                    }
                }
            }
            // Detonate just before the wall, so blast visibility starts in open space.
            rocket.position = m.add(rocket.position, m.scale(delta, @max(0, @min(nearest - 0.001, 1))));
            rocket.trail_clock -= dt;
            if (rocket.trail_clock <= 0) {
                rocket.trail_clock += 0.04;
                var i: usize = rocket.trail.len - 1;
                while (i > 0) : (i -= 1) rocket.trail[i] = rocket.trail[i - 1];
                rocket.trail[0] = rocket.position;
            }
            if (impact) {
                rocket.active = false;
                r.blast(rocket.position, 10, rocket.damage, w);
            }
        }
        for (&r.orbitals, 0..) |*orbital, i| {
            orbital.visible = i < r.rank(.orbital);
            if (!orbital.visible) continue;
            const angle = r.elapsed * 1.6 + @as(f32, @floatFromInt(i)) * std.math.tau / @as(f32, @floatFromInt(r.rank(.orbital)));
            const offset = m.rotate(ship.orientation, v(@cos(angle) * 10, @sin(angle) * 5 + 2, @sin(angle) * 8));
            const wall = w.cast(ship.position, offset, 1.1);
            orbital.position = m.add(ship.position, m.scale(offset, if (wall) |hit| @max(0, hit.t - 0.03) else 1));
            orbital.visible = m.length(m.sub(orbital.position, ship.position)) > 5 and w.clear(orbital.position, 1);
            orbital.fire_clock -= dt;
            if (orbital.visible and orbital.fire_clock <= 0) {
                if (r.target(orbital.position, w, null)) |id| {
                    const d = r.drones[id];
                    const lead = m.length(m.sub(d.position, orbital.position)) / BOLT_SPEED;
                    orbital.aim = m.norm(m.sub(m.add(d.position, m.scale(d.velocity, lead)), orbital.position));
                    r.shoot(orbital.position, orbital.aim, 1.5 + r.bonus(.orbital), true);
                    orbital.fire_clock = 0.65 / r.attackRate();
                } else orbital.fire_clock = 0.06;
            }
        }
    }

    pub fn flock(r: *Run, center: m.V, count: usize, w: *const world.World) void {
        const random = r.rng.random();
        var made: usize = 0;
        for (&r.drones) |*d| {
            if (d.active) continue;
            if (made == count) break;
            for (0..12) |_| {
                var p = m.add(center, v((random.float(f32) - 0.5) * 38, (random.float(f32) - 0.5) * 26, (random.float(f32) - 0.5) * 34));
                if (w.level == .jungle) p.y = std.math.clamp(p.y, w.floorHeight(p.x, p.z) + 9, world.terrain.CEILING - 9);
                if (!w.clear(p, 2.0)) continue;
                d.* = .{ .active = true, .position = p, .hp = 2 + @as(f32, @floatFromInt(r.wave)) * 2, .wave = r.wave, .phase = random.float(f32) * 6.28 };
                made += 1;
                break;
            }
        }
    }

    fn kill(r: *Run, index: usize) void {
        const position = r.drones[index].position;
        const reward = @as(u32, 2) + @min(r.drones[index].wave, 3);
        r.drones[index].active = false;
        r.kills += 1;
        r.burst(position, .explosion, 1);
        for (&r.gems) |*g| {
            if (!g.active) {
                g.* = .{ .active = true, .position = position, .value = reward };
                return;
            }
        }
        // Preserve every earned XP point at capacity by merging into the nearest existing gem.
        var nearest: usize = 0;
        var distance: f32 = std.math.inf(f32);
        for (r.gems, 0..) |g, i| {
            const d = m.length(m.sub(g.position, position));
            if (d < distance) {
                nearest = i;
                distance = d;
            }
        }
        r.gems[nearest].value += reward;
    }

    pub fn burst(r: *Run, position: m.V, kind: @FieldType(Burst, "kind"), size: f32) void {
        r.bursts[r.burst_next] = .{ .position = position, .age = 0, .kind = kind, .size = size };
        r.burst_next = (r.burst_next + 1) % r.bursts.len;
    }

    fn offer(r: *Run) void {
        if (r.dead or r.choosing or r.xp < r.need()) return;
        r.choosing = true;
        var pool: [caps.len]Upgrade = undefined;
        var count: usize = 0;
        for (0..caps.len) |i| {
            if (r.available(@enumFromInt(i))) {
                pool[count] = @enumFromInt(i);
                count += 1;
            }
        }
        r.rng.random().shuffle(Upgrade, pool[0..count]);
        r.choice_count = @min(count, 3);
        @memcpy(r.choices[0..r.choice_count], pool[0..r.choice_count]);
        for (r.choices[0..r.choice_count], 0..) |upgrade, i| {
            r.choice_tiers[i] = if (r.rank(upgrade) == 0) .rare else rarity.fromRoll(r.rng.random().uintLessThan(u8, 100));
        }
    }

    pub fn choose(r: *Run, index: usize) bool {
        if (!r.choosing or index >= r.choice_count) return false;
        const upgrade = r.choices[index];
        if (!r.available(upgrade)) return false;
        const id = @intFromEnum(upgrade);
        const unlock = r.rank(upgrade) == 0;
        const gain = r.choiceGain(index);
        r.xp -= r.need();
        r.level += 1;
        r.ranks[id] +|= 1;
        if (!unlock or !isWeapon(upgrade)) r.bonuses[id] += gain;
        if (upgrade == .hull) {
            r.max_hp += @as(u32, @intFromFloat(gain));
            r.hp = r.max_hp;
            r.leech_credit = 0;
        }
        r.choosing = false;
        r.hurt = @max(r.hurt, 1.0);
        r.offer();
        return true;
    }
};

fn turnToward(from: m.V, to: m.V, radians: f32) m.V {
    const angle = std.math.acos(std.math.clamp(m.dot(from, to), -1, 1));
    if (angle <= radians) return to;
    var axis = m.cross(from, to);
    if (m.length(axis) < 0.0001) axis = m.cross(from, if (@abs(from.y) < 0.9) v(0, 1, 0) else v(1, 0, 0));
    return m.norm(m.rotate(m.axis(m.norm(axis), radians), from));
}

pub fn sphereHit(origin: m.V, delta: m.V, center: m.V, radius: f32) ?f32 {
    const offset = m.sub(origin, center);
    const c = m.dot(offset, offset) - radius * radius;
    if (c <= 0) return 0;
    const a = m.dot(delta, delta);
    if (a < 0.000001) return null;
    const b = m.dot(offset, delta);
    const discriminant = b * b - a * c;
    if (discriminant < 0) return null;
    const t = (-b - @sqrt(discriminant)) / a;
    return if (t >= 0 and t <= 1) t else null;
}

test "support weapons target nearest visible enemy and structures block targeting" {
    var w = world.World{};
    var r = Run{};
    r.drones[0] = .{ .active = true, .position = v(0, 0, -20) };
    r.drones[1] = .{ .active = true, .position = v(12, 0, 0) };
    try std.testing.expectEqual(@as(?usize, 1), r.target(m.zero, &w, null));
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(6, 0, 0), .half = v(1, 5, 5) }, .tint = m.color(1, 1, 1) };
    try std.testing.expectEqual(@as(?usize, 0), r.target(m.zero, &w, null));
}

test "automatic combat kills, leaves XP, attracts it, and offers an upgrade" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .spawn_clock = 1000, .xp = 54 };
    for (0..3) |i| r.drones[i] = .{ .active = true, .position = v(0, 0, -25 - @as(f32, @floatFromInt(i)) * 15), .hp = 1 };
    for (0..900) |_| {
        if (r.kills == 3) ship.tick(.{ .thrust = v(0, 0, -0.4) }, flight.STEP, &w);
        r.tick(&ship, &w, flight.STEP);
        if (r.choosing) break;
    }
    try std.testing.expectEqual(@as(u32, 3), r.kills);
    try std.testing.expect(r.choosing);
    try std.testing.expectEqual(@as(u32, 60), r.xp);
    const elapsed = r.elapsed;
    r.tick(&ship, &w, 1);
    try std.testing.expectEqual(elapsed, r.elapsed);
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u32, 2), r.level);
}

test "level choices exclude capped upgrades, preserve overflow, and chain" {
    var r = Run{ .xp = 170, .ranks = caps };
    r.offer();
    try std.testing.expectEqual(@as(usize, 1), r.choice_count);
    try std.testing.expectEqual(Upgrade.hull, r.choices[0]);
    try std.testing.expect(!r.choose(2));
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u32, 110), r.xp);
    try std.testing.expect(r.choosing);
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u32, 14), r.xp);
    try std.testing.expect(!r.choosing);
}

test "damage has a grace period and death stops the run" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .hp = 2, .spawn_clock = 1000, .fire_clock = 1000 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, 2) };
    r.drones[1] = .{ .active = true, .position = v(0, 0, -2) };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 1), r.hp);
    for (0..60) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 1), r.hp);
    for (0..70) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expect(r.dead);
    const elapsed = r.elapsed;
    r.tick(&ship, &w, 3);
    try std.testing.expectEqual(elapsed, r.elapsed);
    try std.testing.expectEqual(@as(u32, 0), r.hp);
}

test "walls stop fired bolts and XP does not attract through structures" {
    var w = world.World{};
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(0, 0, -10), .half = v(100, 100, 1) }, .tint = m.color(1, 1, 1) };
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .spawn_clock = 1000, .fire_clock = 1000 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, -18), .hp = 20 };
    r.bolts[0] = .{ .active = true, .position = m.zero, .velocity = v(0, 0, -230), .life = 1, .damage = 9 };
    r.gems[0] = .{ .active = true, .position = v(0, 0, -15), .value = 2 };
    for (0..20) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(f32, 20), r.drones[0].hp);
    try std.testing.expect(!r.bolts[0].active);
    try std.testing.expectEqual(@as(f32, -15), r.gems[0].position.z);
    try std.testing.expectEqual(@as(u32, 0), r.xp);
}

test "full gem pool preserves earned XP and reset clears run progression" {
    var r = Run{ .kills = 7, .level = 3 };
    for (&r.gems) |*gem| gem.* = .{ .active = true, .value = 1 };
    r.drones[0] = .{ .active = true };
    r.kill(0);
    var total: u32 = 0;
    for (r.gems) |gem| total += gem.value;
    try std.testing.expectEqual(@as(u32, 770), total);
    r = Run.init(.{}, &world.World{}, 27);
    try std.testing.expectEqual(@as(u32, 0), r.kills);
    try std.testing.expectEqual(@as(u32, 1), r.level);
    try std.testing.expectEqual(@as(u32, 5), r.hp);
    try std.testing.expectEqual(@as(usize, 6), r.activeCount());
    try std.testing.expect(!r.choosing and !r.dead);
}

test "fast bolts cannot cross a target between ticks" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), sphereHit(v(0, 0, 10), v(0, 0, -20), m.zero, 1).?, 0.00001);
}

test "waves escalate on simulation time and keep existing enemies at their spawn tier" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .elapsed = WAVE_SECONDS - 0.004, .spawn_clock = 100, .fire_clock = 100, .choosing = true };
    r.flock(v(0, 0, -70), 1, &w);
    try std.testing.expectEqual(@as(f32, 2), r.drones[0].hp);
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 0), r.wave);
    r.choosing = false;
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 1), r.wave);
    try std.testing.expectEqual(@as(u32, 0), r.drones[0].wave);
    try std.testing.expectEqual(@as(f32, 2), r.drones[0].hp);
    try std.testing.expectEqual(@as(f32, 4), r.drones[1].hp);
    try std.testing.expectEqual(@as(u32, 1), r.drones[1].wave);
    try std.testing.expectEqual(@as(usize, 10), r.activeCount());
    r.kill(1);
    try std.testing.expectEqual(@as(u32, 3), r.gems[0].value);
    r.elapsed = WAVE_SECONDS * 4;
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 4), r.wave);
    try std.testing.expectEqual(@as(f32, 10), r.drones[1].hp);
}

test "opening drones survive one normal laser bolt" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .spawn_clock = 100, .fire_clock = 100 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, -15) };
    r.bolts[0] = .{ .active = true, .position = v(0, 0, -12), .velocity = v(0, 0, -230), .life = 1 };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expect(r.drones[0].active);
    try std.testing.expectEqual(@as(f32, 1), r.drones[0].hp);
    try std.testing.expectEqual(@as(u32, 0), r.kills);
}

test "pickup feedback fades, freezes during choices, and is separate from damage" {
    const w = world.World{};
    var ship = flight.Ship{};
    var r = Run{ .spawn_clock = 100, .fire_clock = 100 };
    r.gems[0] = .{ .active = true, .position = ship.position };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(f32, 0.20), r.xp_flash);
    try std.testing.expectEqual(@as(f32, 0), r.hit_flash);
    r.choosing = true;
    r.tick(&ship, &w, 1);
    try std.testing.expectEqual(@as(f32, 0.20), r.xp_flash);
    r.choosing = false;
    r.tick(&ship, &w, 0.3);
    try std.testing.expectEqual(@as(f32, 0), r.xp_flash);
    r.drones[0] = .{ .active = true, .position = ship.position };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(HIT_FLASH_TIME, r.hit_flash);
    try std.testing.expectEqual(@as(f32, 0), r.xp_flash);
}

test "progression needs thirty opening kills and costs grow faster than wave rewards" {
    var r = Run{ .xp = 59 };
    r.offer();
    try std.testing.expect(!r.choosing);
    r.xp = 60;
    r.offer();
    try std.testing.expect(r.choosing);
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u32, 96), r.need());
    try std.testing.expectEqual(@as(u32, 0), r.xp);
    r.wave = 100;
    r.drones[0] = .{ .active = true, .wave = 100 };
    r.kill(0);
    try std.testing.expectEqual(@as(u32, 5), r.gems[0].value);
}

test "jungle flocks stay between terrain and ceiling and laser combat earns XP" {
    const w = world.World{ .level = .jungle, .ground = world.terrain.Terrain.generate(91) };
    var ship = flight.Ship{ .position = v(world.terrain.riverX(600), 70, 600) };
    var r = Run{ .spawn_clock = 1000 };
    r.flock(v(-600, -300, -200), 12, &w);
    r.flock(v(0, 900, -200), 12, &w);
    var count: usize = 0;
    for (r.drones) |d| {
        if (!d.active) continue;
        count += 1;
        try std.testing.expect(w.clear(d.position, 1.7));
    }
    try std.testing.expectEqual(@as(usize, 24), count);
    r = .{ .spawn_clock = 1000 };
    r.drones[0] = .{ .active = true, .position = m.add(ship.position, v(0, 0, -26)), .hp = 2 };
    for (0..180) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 1), r.kills);
    try std.testing.expect(r.xp > 0 or r.gems[0].active);
}

test "opening flocks are small and pressure rises with successive waves" {
    const w = world.World{};
    var ship = flight.Ship{};
    var r = Run.init(ship, &w, 91);
    try std.testing.expectEqual(@as(usize, 6), r.activeCount());
    r.fire_clock = 100;
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(usize, 6), r.activeCount());
    try std.testing.expect(r.spawn_clock > 5.9);
    for (0..10) |wave| {
        const tier: u32 = @intCast(wave);
        try std.testing.expect(flockSize(tier + 1) > flockSize(tier));
        try std.testing.expect(spawnPeriod(tier + 1) < spawnPeriod(tier));
    }
}

test "later drones catch straight flight but cannot instantly reverse through a juke" {
    const w = world.World{};
    var ship = flight.Ship{ .position = v(0, 0, 100) };
    var r = Run{ .spawn_clock = 100, .fire_clock = 100 };
    r.wave = 10;
    r.elapsed = 300;
    r.drones[0] = .{ .active = true, .position = m.zero, .velocity = v(0, 0, -50), .wave = 10 };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expect(r.drones[0].velocity.z < -47);
    for (0..180) |_| {
        ship.position.z += flight.SPEED * flight.STEP;
        r.tick(&ship, &w, flight.STEP);
    }
    try std.testing.expect(r.drones[0].velocity.z > flight.SPEED);
    try std.testing.expect(r.drones[0].velocity.z <= 50.001);
}

test "laser fires straight ahead without a target and has higher critical chance" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero, .orientation = m.axis(v(0, 1, 0), 0.7) };
    var r = Run{ .spawn_clock = 100 };
    r.drones[0] = .{ .active = true, .position = v(40, 0, 10) };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 1), r.shots_fired);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.dot(m.norm(r.bolts[0].velocity), ship.forward()), 0.00001);
    try std.testing.expect(r.critChance(true) > r.critChance(false));
    try std.testing.expect(r.period() < 0.2);
    r.drones[0].active = false;
    for (0..120) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expect(r.shots_fired >= 7);
}

test "mines launch, arm, damage a group, respect cover, and expire without damage" {
    var w = world.World{};
    const ship = flight.Ship{ .position = v(0, 0, 50) };
    var r = Run{};
    r.ranks[@intFromEnum(Upgrade.mine)] = 1;
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(r.mines[0].active and m.length(m.sub(r.mines[0].position, ship.position)) > 0);
    r.mine_clock = 100;
    r.mines[0] = .{ .active = true, .position = m.zero, .age = 0.5 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, -5) };
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(r.mines[0].active and r.drones[0].active);
    r.mines[0].age = 1;
    r.drones[1] = .{ .active = true, .position = v(7, 0, -5) };
    r.drones[2] = .{ .active = true, .position = v(0, 0, -16) };
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(0, 0, -12), .half = v(30, 30, 1) }, .tint = m.color(1, 1, 1) };
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 2), r.kills);
    try std.testing.expect(!r.mines[0].active and r.drones[2].active);
    r.mines[0] = .{ .active = true, .position = v(0, 0, -16), .age = 8.99 };
    r.tickWeapons(ship, &w, 0.02);
    try std.testing.expect(!r.mines[0].active and r.drones[2].active);
}

test "rocket volleys arc outward then home, reacquire, and deal heavy damage" {
    const w = world.World{};
    const ship = flight.Ship{ .position = m.zero };
    var r = Run{};
    r.ranks[@intFromEnum(Upgrade.rocket)] = 1;
    r.drones[0] = .{ .active = true, .position = v(0, 0, -70), .hp = 1 };
    r.drones[1] = .{ .active = true, .position = v(0, 0, -80), .hp = 200 };
    for (0..36) |_| r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(@abs(r.rockets[0].position.x) > 18);
    try std.testing.expect(r.rockets[0].position.x * r.rockets[1].position.x < 0);
    r.drones[0].active = false;
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(?usize, 1), r.rockets[0].target_id);
    r.rocket_clock = 100;
    for (0..480) |_| r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(r.drones[1].hp <= 184);
    try std.testing.expect(!r.rockets[0].active and !r.rockets[1].active);
    const reversed = turnToward(v(0, 0, -1), v(0, 0, 1), 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), std.math.acos(-reversed.z), 0.0001);
}

test "orbitals circle the ship, fire independently, and retract against structures" {
    var w = world.World{};
    const ship = flight.Ship{ .position = m.zero };
    var r = Run{};
    r.ranks[@intFromEnum(Upgrade.orbital)] = 2;
    r.drones[0] = .{ .active = true, .position = v(0, 0, -40) };
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 2), r.shots_fired);
    try std.testing.expect(r.bolts[0].orbital and r.orbitals[0].visible and r.orbitals[1].visible);
    const before = r.orbitals[0].position;
    r.elapsed = 1;
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(m.length(m.sub(before, r.orbitals[0].position)) > 5);
    r.elapsed = 0;
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(8, 0, 0), .half = v(1, 30, 30) }, .tint = m.color(1, 1, 1) };
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(w.clear(r.orbitals[0].position, 1));
    try std.testing.expect(r.orbitals[0].position.x < 6);
}

test "four slots include only starting laser and reject a fifth chosen system" {
    var r = Run{ .xp = 60 };
    try std.testing.expectEqual(@as(usize, 1), r.installedCount(true));
    try std.testing.expectEqual(@as(usize, 0), r.installedCount(false));
    for ([_]Upgrade{ .damage, .hull, .crit, .speed, .rate, .leech }) |upgrade| try std.testing.expect(r.available(upgrade));
    r.ranks[@intFromEnum(Upgrade.damage)] = 1;
    r.ranks[@intFromEnum(Upgrade.hull)] = 1;
    r.ranks[@intFromEnum(Upgrade.crit)] = 1;
    r.ranks[@intFromEnum(Upgrade.speed)] = 1;
    r.ranks[@intFromEnum(Upgrade.mine)] = 1;
    r.ranks[@intFromEnum(Upgrade.rocket)] = 1;
    r.ranks[@intFromEnum(Upgrade.orbital)] = 1;
    try std.testing.expectEqual(@as(usize, 4), r.installedCount(true));
    try std.testing.expectEqual(@as(usize, 4), r.installedCount(false));
    try std.testing.expect(!r.available(.rate) and !r.available(.leech));
    try std.testing.expect(r.available(.mine) and r.available(.crit));
    for (0..50) |_| {
        r.choosing = false;
        r.offer();
        for (r.choices[0..r.choice_count]) |choice| try std.testing.expect(choice != .rate and choice != .leech);
    }
    r.choices[0] = .leech;
    try std.testing.expect(!r.choose(0));
    r.choices[0] = .crit;
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u8, 2), r.rank(.crit));
    try std.testing.expectEqual(@as(usize, 4), r.installedCount(false));
}

test "systems apply to damage cadence crit movement and hull upgrades" {
    var r = Run{};
    r.ranks[@intFromEnum(Upgrade.damage)] = 3;
    r.bonuses[@intFromEnum(Upgrade.damage)] = 75;
    r.ranks[@intFromEnum(Upgrade.crit)] = 2;
    r.bonuses[@intFromEnum(Upgrade.crit)] = 10;
    r.ranks[@intFromEnum(Upgrade.rate)] = 2;
    r.bonuses[@intFromEnum(Upgrade.rate)] = 30;
    try std.testing.expectApproxEqAbs(@as(f32, 1.75), r.damageMultiplier(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), r.critChance(true), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), r.critChance(false), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.16 / 1.3), r.period(), 0.0001);
    r.ranks[@intFromEnum(Upgrade.speed)] = 2;
    r.bonuses[@intFromEnum(Upgrade.speed)] = 5;
    var ship = flight.Ship{ .speed_multiplier = r.speedMultiplier() };
    ship.tick(.{ .thrust = v(1, 0, -1) }, flight.STEP, &world.World{});
    try std.testing.expectApproxEqAbs(@as(f32, 51), ship.speed(), 0.001);
    r.ranks[@intFromEnum(Upgrade.speed)] = 0;
    r.hp = 1;
    r.xp = 60;
    r.choosing = true;
    r.choice_count = 1;
    r.choices[0] = .hull;
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(u32, 8), r.hp);
    try std.testing.expectEqual(r.max_hp, r.hp);
}

test "leech uses actual damage, heals fractionally, and cannot bank at full HP or revive" {
    var r = Run{ .hp = 3 };
    r.ranks[@intFromEnum(Upgrade.leech)] = 1;
    r.bonuses[@intFromEnum(Upgrade.leech)] = 3;
    r.drones[0] = .{ .active = true, .hp = 2 };
    r.damageEnemy(0, 100);
    try std.testing.expectEqual(@as(u32, 3), r.hp);
    try std.testing.expectApproxEqAbs(@as(f32, 0.06), r.leech_credit, 0.0001);
    r.drones[0] = .{ .active = true, .hp = 100 };
    r.damageEnemy(0, 40);
    try std.testing.expectEqual(@as(u32, 4), r.hp);
    r.damageEnemy(0, 50);
    try std.testing.expectEqual(@as(u32, 5), r.hp);
    try std.testing.expectEqual(@as(f32, 0), r.leech_credit);
    r.damageEnemy(0, 1);
    try std.testing.expectEqual(@as(f32, 0), r.leech_credit);
    r.dead = true;
    r.hp = 0;
    r.damageEnemy(0, 100);
    try std.testing.expectEqual(@as(u32, 0), r.hp);
}

test "upgrade pause freezes all weapons and reset removes the build" {
    const w = world.World{};
    var ship = flight.Ship{};
    var r = Run{ .choosing = true };
    r.mines[0] = .{ .active = true, .age = 1 };
    r.rockets[0] = .{ .active = true, .age = 1 };
    r.ranks[@intFromEnum(Upgrade.mine)] = 1;
    r.ranks[@intFromEnum(Upgrade.leech)] = 1;
    r.tick(&ship, &w, 2);
    try std.testing.expectEqual(@as(f32, 1), r.mines[0].age);
    try std.testing.expectEqual(@as(f32, 1), r.rockets[0].age);
    r = Run.init(ship, &w, 91);
    try std.testing.expectEqualSlices(u8, &initial_ranks, &r.ranks);
    try std.testing.expect(!r.mines[0].active and !r.rockets[0].active);
}

test "opening drones stay slower than the base ship" {
    const w = world.World{};
    var ship = flight.Ship{ .position = v(0, 0, 300) };
    var r = Run{ .spawn_clock = 100, .fire_clock = 100 };
    r.drones[0] = .{ .active = true, .position = m.zero, .phase = std.math.pi / 2.0 };
    for (0..300) |_| r.tick(&ship, &w, flight.STEP);
    try std.testing.expect(r.drones[0].velocity.z > 42);
    try std.testing.expect(r.drones[0].velocity.z < flight.SPEED);
}

test "new weapons and systems are Rare and first stat unlock applies its gain" {
    var r = Run{ .xp = 60 };
    r.offer();
    for (0..r.choice_count) |i| try std.testing.expectEqual(rarity.Tier.rare, r.choiceTier(i));
    r.choices[0] = .speed;
    r.choice_tiers[0] = .legendary;
    try std.testing.expectEqual(rarity.Tier.rare, r.choiceTier(0));
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(f32, 5), r.bonus(.speed));
    try std.testing.expectEqual(@as(usize, 1), r.installedCount(false));
    try std.testing.expectEqual(@as(u8, 1), r.rank(.speed));
}

test "tiered gains match descriptions and upgrade one occupied slot" {
    for ([_]rarity.Tier{ .common, .uncommon, .rare, .legendary }, [_]f32{ 1, 2, 5, 10 }) |tier, gain| {
        var r = Run{ .xp = 60, .choosing = true, .choice_count = 1 };
        r.ranks[@intFromEnum(Upgrade.speed)] = 1;
        r.bonuses[@intFromEnum(Upgrade.speed)] = 5;
        r.choices[0] = .speed;
        r.choice_tiers[0] = tier;
        var buf: [120]u8 = undefined;
        var expected: [100]u8 = undefined;
        const text = try std.fmt.bufPrint(&expected, "+{d} m/s movement speed", .{gain});
        try std.testing.expectEqualStrings(text, r.choiceDescription(0, &buf));
        try std.testing.expect(r.choose(0));
        try std.testing.expectEqual(5 + gain, r.bonus(.speed));
        try std.testing.expectEqual(@as(usize, 1), r.installedCount(false));
        try std.testing.expectEqual(@as(u8, 2), r.rank(.speed));
    }
    for (0..caps.len) |id| {
        const upgrade: Upgrade = @enumFromInt(id);
        try std.testing.expect(statGain(upgrade, .common) < statGain(upgrade, .uncommon));
        try std.testing.expect(statGain(upgrade, .uncommon) < statGain(upgrade, .rare));
        try std.testing.expect(statGain(upgrade, .rare) < statGain(upgrade, .legendary));
    }
}

test "offer rarity stays fixed while choosing and respects the critical cap" {
    var r = Run{ .xp = 60 };
    r.ranks[@intFromEnum(Upgrade.crit)] = 1;
    r.bonuses[@intFromEnum(Upgrade.crit)] = 57;
    r.offer();
    const tiers = r.choice_tiers;
    r.offer();
    try std.testing.expectEqualSlices(rarity.Tier, &tiers, &r.choice_tiers);
    r.choices[0] = .crit;
    r.choice_tiers[0] = .legendary;
    try std.testing.expectEqual(@as(f32, 3), r.choiceGain(0));
    try std.testing.expect(r.choose(0));
    try std.testing.expectEqual(@as(f32, 60), r.bonus(.crit));
    try std.testing.expect(!r.available(.crit));
    try std.testing.expectApproxEqAbs(@as(f32, 0.85), r.critChance(true), 0.00001);
}

test "contact uses moved positions and cannot damage through a thin wall" {
    var w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .spawn_clock = 100, .fire_clock = 100 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, -6.6), .velocity = v(0, 0, 42) };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 4), r.hp);
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = m.zero, .half = v(50, 50, 0.01) }, .tint = m.color(1, 1, 1) };
    ship.position = v(0, 0, 4.62);
    r = .{ .spawn_clock = 100, .fire_clock = 100 };
    r.drones[0] = .{ .active = true, .position = v(0, 0, -1.72) };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 5), r.hp);
}

test "contact feedback survives same-tick leech healing" {
    const w = world.World{};
    var ship = flight.Ship{ .position = m.zero };
    var r = Run{ .hp = 4, .spawn_clock = 100, .fire_clock = 100 };
    r.bonuses[@intFromEnum(Upgrade.leech)] = 3;
    r.leech_credit = 0.98;
    r.drones[0] = .{ .active = true, .position = v(0, 0, 2) };
    r.drones[1] = .{ .active = true, .position = v(0, 0, -20), .hp = 10 };
    r.bolts[0] = .{ .active = true, .position = v(0, 0, -17), .velocity = v(0, 0, -230), .life = 1 };
    r.tick(&ship, &w, flight.STEP);
    try std.testing.expectEqual(@as(u32, 4), r.hp);
    try std.testing.expectEqual(@as(u32, 1), r.hits_taken);
}

test "orbital visual aim matches its visible firing target" {
    var w = world.World{};
    const ship = flight.Ship{ .position = m.zero };
    var r = Run{};
    r.ranks[@intFromEnum(Upgrade.orbital)] = 1;
    w.count = 1;
    w.solids[0] = .{ .box = .{ .center = v(10, 2, -5), .half = v(2, 4, 1) }, .tint = m.color(1, 1, 1) };
    r.drones[0] = .{ .active = true, .position = v(10, 2, -10) };
    r.drones[1] = .{ .active = true, .position = v(-20, 2, -30) };
    r.tickWeapons(ship, &w, flight.STEP);
    try std.testing.expect(r.bolts[0].active);
    try std.testing.expect(r.orbitals[0].aim.x < -0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.dot(r.orbitals[0].aim, m.norm(r.bolts[0].velocity)), 0.00001);
}
