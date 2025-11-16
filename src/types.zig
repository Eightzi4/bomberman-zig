const std = @import("std");
const rl = @import("raylib");
const b2 = glbs.b2;

const glbs = @import("globals.zig");
const funcs = @import("functions.zig");
const Player = @import("Player.zig");
pub const Texture = @import("resources").Texture;

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

pub const Team = enum {
    alpha,
    beta,
    gamma,
    delta,
};

pub const ExplosionVariant = enum {
    horizontal,
    vertical,
    crossed,
};

pub const UpgradeUnderneath = enum {
    dynamite,
    heal,
    radius,
    speed,
    teleport,
    none,
};

pub const TeamTextures = struct {
    player_textures: PlayerTextures,
    dynamite_textures: [2]rl.Texture2D,
    explosion_textures: [2]rl.Texture2D,
};

pub const PlayerTextures = struct {
    side: [3]rl.Texture2D,
    down: [2]rl.Texture2D,
    up: [2]rl.Texture2D,
};

pub const Wall = struct {
    body_id: b2.b2BodyId,
};

pub const Barrel = struct {
    body_id: b2.b2BodyId,
};

pub const Explosion = struct {
    team: Team,
    variant: ExplosionVariant,
    timer: f32,
    upgrade_underneath: UpgradeUnderneath,

    pub fn update(self: *@This()) void {
        self.timer -= glbs.PHYSICS_TIMESTEP;
    }
};

pub const Cell = struct {
    tag: Texture,
    variant: CellVariant,

    pub fn initGround() @This() {
        return .{
            .tag = .ground,
            .variant = .{ .ground = {} },
        };
    }

    pub fn initWall(world_id: b2.b2WorldId, coords: Vec2(u8)) @This() {
        return .{
            .tag = .wall,
            .variant = .{ .wall = .{ .body_id = funcs.createCollider(world_id, coords) } },
        };
    }

    pub fn initBarrel(world_id: b2.b2WorldId, coords: Vec2(u8)) @This() {
        return .{
            .tag = .barrel,
            .variant = .{ .barrel = .{ .body_id = funcs.createCollider(world_id, coords) } },
        };
    }

    pub fn initExplosion(team: Team, variant: ExplosionVariant, upgrade_underneath: UpgradeUnderneath) @This() {
        return .{
            .tag = if (variant == .crossed) .explosion_crossed else .explosion,
            .variant = .{ .explosion = .{
                .team = team,
                .variant = variant,
                .timer = glbs.EXPLOSION_DURATION,
                .upgrade_underneath = upgrade_underneath,
            } },
        };
    }

    pub fn initDynamite(team: Team, radius: u8) @This() {
        return .{
            .tag = .dynamite,
            .variant = .{ .dynamite = .init(team, radius) },
        };
    }

    pub fn initUpgrade(upgrade_variant: UpgradeUnderneath) @This() {
        return .{
            .tag = @enumFromInt(@intFromEnum(Texture.upgrade_dynamite) + @intFromEnum(upgrade_variant)),
            .variant = .{ .upgrade_dynamite = {} },
        };
    }
};

pub const CellVariant = union {
    ground: void,
    wall: Wall,
    death_wall: Wall,
    barrel: Barrel,
    dynamite: Dynamite,
    dynamite_exploding: Dynamite,
    explosion: Explosion,
    explosion_crossed: Explosion,
    upgrade_dynamite: void,
    upgrade_heal: void,
    upgrade_radius: void,
    upgrade_speed: void,
    upgrade_teleport: void,
};

pub const Dynamite = struct {
    team: Team,
    timer: f32,
    radius: u8,

    pub fn init(team: Team, radius: u8) @This() {
        return .{
            .team = team,
            .timer = glbs.EXPLOSION_DELAY,
            .radius = radius,
        };
    }

    pub fn update(self: *@This()) void {
        self.timer -= glbs.PHYSICS_TIMESTEP;
    }
};
