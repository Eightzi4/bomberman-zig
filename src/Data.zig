const std = @import("std");
const rl = @import("raylib");

const glbs = @import("globals.zig");
const types = @import("types.zig");
const Game = @import("Game.zig");
const Player = @import("Player.zig");
const Menu = @import("Menu.zig");

pub const State = enum {
    menu,
    game,
    quit,
};

prng: std.Random.Xoshiro256,
state: State,
team_colors: std.enums.EnumArray(types.Team, rl.Color),
textures: std.enums.EnumArray(types.Texture, rl.Texture2D),
cell_size: f32,
player_count: u8,
key_bindings: std.enums.EnumArray(types.Team, Player.Actions),

pub fn init() @This() {
    return .{
        .prng = D: {
            var seed: u64 = undefined;
            std.posix.getrandom(std.mem.asBytes(&seed)) catch @panic("Failed to get random seed!");
            break :D std.Random.DefaultPrng.init(seed);
        },
        .state = .menu,
        .team_colors = D: {
            const default_colors = std.enums.EnumFieldStruct(types.Team, rl.Color, null){
                .alpha = .blue,
                .beta = .red,
                .gamma = .green,
                .delta = .yellow,
            };

            break :D std.enums.EnumArray(types.Team, rl.Color).init(default_colors);
        },
        .textures = loadTextures(),
        .cell_size = @as(f32, @floatFromInt(rl.getScreenHeight())) / glbs.GRID_SIZE.y,
        .player_count = 2,
        .key_bindings = .init(.{
            .alpha = .{
                .movement = .init(.{
                    .left = .{ .binded_key = .a },
                    .right = .{ .binded_key = .d },
                    .down = .{ .binded_key = .s },
                    .up = .{ .binded_key = .w },
                }),
                .place_dynamite = .{ .binded_key = .space },
            },
            .beta = .{
                .movement = .init(.{
                    .left = .{ .binded_key = .left },
                    .right = .{ .binded_key = .right },
                    .down = .{ .binded_key = .down },
                    .up = .{ .binded_key = .up },
                }),
                .place_dynamite = .{ .binded_key = .enter },
            },
            .gamma = .{
                .movement = .init(.{
                    .left = .{ .binded_key = .f },
                    .right = .{ .binded_key = .h },
                    .down = .{ .binded_key = .g },
                    .up = .{ .binded_key = .t },
                }),
                .place_dynamite = .{ .binded_key = .y },
            },
            .delta = .{
                .movement = .init(.{
                    .left = .{ .binded_key = .j },
                    .right = .{ .binded_key = .l },
                    .down = .{ .binded_key = .k },
                    .up = .{ .binded_key = .i },
                }),
                .place_dynamite = .{ .binded_key = .o },
            },
        }),
    };
}

pub fn deinit(self: *@This()) void {
    unloadTextures(self.textures);
}

pub fn update(self: *@This()) void {
    if (rl.isWindowResized()) {
        const cell_size_from_width = @as(f32, @floatFromInt(rl.getScreenWidth())) / (glbs.GRID_SIZE.x + glbs.GUI_SIZE);
        const cell_size_from_height = @as(f32, @floatFromInt(rl.getScreenHeight())) / glbs.GRID_SIZE.y;

        self.cell_size = @max(@min(cell_size_from_width, cell_size_from_height), 1);
    }
}

pub fn run(self: *@This()) void {
    while (!rl.windowShouldClose()) {
        self.state = switch (self.state) {
            .menu => self.runMenu(),
            .game => self.runGame(),
            .quit => return,
        };
    }
}

pub fn runMenu(data: *@This()) State {
    var menu = Menu.init(data);

    while (!rl.windowShouldClose() and menu.state != .exit) {
        if (menu.state == .game) return .game;

        data.update();
        menu.update();
        menu.draw();
    }

    return .quit;
}

pub fn runGame(data: *@This()) State {
    var game = Game.init(data);
    defer game.deinit();

    for (0..@intCast(data.player_count)) |i| {
        const team: types.Team = @enumFromInt(i);

        game.opt_players.set(team, .init(
            glbs.PLAYER_START_POSITIONS[i],
            game.world_id,
            data.key_bindings.get(team),
            &game.team_textures.getPtr(team).player_textures,
        ));
    }

    while (!rl.windowShouldClose()) {
        if (rl.isKeyDown(.escape)) return .menu;

        data.update();
        game.update();
        game.draw();
    }

    return .quit;
}

fn loadTextures() std.enums.EnumArray(types.Texture, rl.Texture2D) {
    var textures = std.enums.EnumArray(types.Texture, rl.Texture2D).initUndefined();

    for (std.enums.values(types.Texture)) |texture_variant| {
        const img = rl.loadImageFromMemory(".png", @import("resources").TEXTURES.get(texture_variant)) catch @panic("Failed to load image!");
        defer rl.unloadImage(img);

        const texture = rl.loadTextureFromImage(img) catch @panic("Failed to load texture!");

        rl.setTextureFilter(texture, rl.TextureFilter.point);

        textures.set(texture_variant, texture);
    }

    return textures;
}

fn unloadTextures(textures: std.enums.EnumArray(types.Texture, rl.Texture2D)) void {
    for (textures.values) |texture| rl.unloadTexture(texture);
}
