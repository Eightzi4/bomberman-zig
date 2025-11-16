const std = @import("std");
const rl = @import("raylib");
const b2 = glbs.b2;

const glbs = @import("globals.zig");
const Data = @import("Data.zig");
const funcs = @import("functions.zig");
const Player = @import("Player.zig");
const types = @import("types.zig");

world_id: b2.b2WorldId,
cell_grid: [glbs.GRID_SIZE.y][glbs.GRID_SIZE.x]types.Cell,
team_textures: std.enums.EnumArray(types.Team, types.TeamTextures),
opt_players: std.enums.EnumArray(types.Team, ?Player),
accumulator: f32,
textures: *const std.enums.EnumArray(types.Texture, rl.Texture2D),
cell_size: *const f32,
data: *Data,

pub fn init(data: *Data) @This() {
    var world_def = b2.b2DefaultWorldDef();
    world_def.gravity = b2.b2Vec2_zero;

    const world_id = b2.b2CreateWorld(&world_def);

    return .{
        .world_id = world_id,
        .cell_grid = generateCellGrid(data.prng.random(), world_id),
        .team_textures = createTeamTextures(data),
        .opt_players = .initFill(null),
        .accumulator = 0,
        .textures = &data.textures,
        .cell_size = &data.cell_size,
        .data = data,
    };
}

pub fn deinit(self: *@This()) void {
    b2.b2DestroyWorld(self.world_id);

    const deinit_textures = struct {
        fn deinit_textures(textures_struct: anytype) void {
            inline for (@typeInfo(@TypeOf(textures_struct)).@"struct".fields) |field| {
                if (@typeInfo(field.type) == .@"struct")
                    deinit_textures(@field(textures_struct, field.name))
                else for (@field(textures_struct, field.name)) |texture| rl.unloadTexture(texture);
            }
        }
    }.deinit_textures;

    for (self.team_textures.values[0..self.data.player_count]) |team_textures| deinit_textures(team_textures);
}

pub fn update(self: *@This()) void {
    const delta_time = rl.getFrameTime();

    self.accumulator += delta_time;

    while (self.accumulator >= glbs.PHYSICS_TIMESTEP) {
        fixedUpdate(self);

        self.accumulator -= glbs.PHYSICS_TIMESTEP;
    }

    for (&self.opt_players.values) |*opt_player| if (opt_player.*) |*player| if (player.health > 0) {
        player.update();
    };

    checkPlayerPositions(self);
}

fn fixedUpdate(self: *@This()) void {
    var iterator = self.opt_players.iterator();

    while (iterator.next()) |opt_player| if (opt_player.value.*) |*player| if (player.health > 0) {
        player.fixedUpdate();

        if (player.teleport_request) |direction| {
            player.teleport_request = null;

            const current_pos = b2.b2Body_GetPosition(player.body_id);
            const direction_vector = glbs.DIRECTIONS[@intFromEnum(direction)];
            const dst_phys_pos = b2.b2Vec2{
                .x = current_pos.x + @as(f32, @floatFromInt(direction_vector.x * 2 * glbs.PHYSICS_UNIT)),
                .y = current_pos.y + @as(f32, @floatFromInt(direction_vector.y * 2 * glbs.PHYSICS_UNIT)),
            };
            const grid_pos = b2.b2Vec2{
                .x = @round(dst_phys_pos.x / glbs.PHYSICS_UNIT),
                .y = @round(dst_phys_pos.y / glbs.PHYSICS_UNIT),
            };

            if (grid_pos.x >= 0 and grid_pos.x < glbs.GRID_SIZE.x and grid_pos.y >= 0 and grid_pos.y < glbs.GRID_SIZE.y) {
                const dst_cell = self.cell_grid[@intFromFloat(grid_pos.y)][@intFromFloat(grid_pos.x)];

                if (dst_cell.tag != .wall and dst_cell.tag != .death_wall and dst_cell.tag != .barrel) {
                    b2.b2Body_SetTransform(player.body_id, .{ .x = grid_pos.x * glbs.PHYSICS_UNIT, .y = grid_pos.y * glbs.PHYSICS_UNIT }, .{ .c = 1, .s = 0 });
                    player.teleport_timer = player.teleport_cooldown;
                }
            }
        }

        if (player.actions.place_dynamite.cached_input) {
            player.actions.place_dynamite.cached_input = false;

            if (player.dynamite_count > 0) {
                const position = b2.b2Body_GetPosition(player.body_id);
                const grid_pos = types.Vec2(usize){
                    .x = @intFromFloat(@round(position.x / glbs.PHYSICS_UNIT)),
                    .y = @intFromFloat(@round(position.y / glbs.PHYSICS_UNIT)),
                };
                const cell = &self.cell_grid[grid_pos.y][grid_pos.x];

                if (cell.tag != .dynamite and cell.tag != .dynamite_exploding) {
                    cell.* = .initDynamite(opt_player.key, player.explosion_radius);
                    player.dynamite_count -= 1;
                }
            }
        }
    };

    decayExplosions(self);
    updateDynamitesAndExplosions(self);
    b2.b2World_Step(self.world_id, glbs.PHYSICS_TIMESTEP, glbs.PHYSICS_SUBSTEP_COUNT);
}

pub fn draw(self: *@This()) void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.gray);

    self.drawBackground();

    const alpha = self.accumulator / glbs.PHYSICS_TIMESTEP;

    for (&self.opt_players.values) |*opt_player| if (opt_player.*) |*player| if (player.health > 0) {
        player.draw(alpha, self.cell_size.*);
    };

    drawGui(self);
}

fn drawGui(self: *@This()) void {
    var alive_count: u32 = 0;
    var winner: ?*const Player = null;
    var winner_team: ?types.Team = null;

    var check_iterator = self.opt_players.iterator();
    while (check_iterator.next()) |opt_player| if (opt_player.value.*) |*p| {
        if (p.health > 0) {
            alive_count += 1;
            winner = p;
            winner_team = opt_player.key;
        }
    };

    if (alive_count <= 1) {
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();

        rl.drawRectangle(0, 0, screen_width, screen_height, rl.fade(.black, 0.75));

        var main_text_buffer: [32]u8 = undefined; // HARDCODED to fit exactly "Player XXXXX wins!\nScore: XXXXX\0"
        const font_size: i32 = 60;

        const main_text = if (alive_count == 1)
            std.fmt.bufPrintZ(&main_text_buffer, "Player {s} wins!\nScore: {}", .{
                @tagName(winner_team.?),
                winner.?.score,
            }) catch @panic("Failed to format win text!")
        else
            "No players left!";

        const text_size = rl.measureTextEx(rl.getFontDefault() catch @panic("Failed to load default font!"), main_text, @floatFromInt(font_size), 1);
        const text_pos_x = @as(f32, @floatFromInt(screen_width)) / 2 - text_size.x / 2;
        const text_pos_y = @as(f32, @floatFromInt(screen_height)) / 2 - text_size.y / 2;
        rl.drawText(main_text, @intFromFloat(text_pos_x), @intFromFloat(text_pos_y), font_size, .white);

        const return_text = "Return to the menu by pressing ESC.";
        const return_font_size: i32 = 20;
        const return_text_size = rl.measureTextEx(rl.getFontDefault() catch @panic("Failed to load default font!"), return_text, @floatFromInt(return_font_size), 1);

        const return_pos_x = @as(f32, @floatFromInt(screen_width)) / 2 - return_text_size.x / 2;
        const return_pos_y = text_pos_y + text_size.y + 20;
        rl.drawText(return_text, @intFromFloat(return_pos_x), @intFromFloat(return_pos_y), return_font_size, .light_gray);

        return;
    }

    const cell_size = self.cell_size.*;
    const gui_pixel_width = glbs.GUI_SIZE * cell_size;
    const padding = @as(i32, @intFromFloat(gui_pixel_width / 20));
    const window_height = cell_size * glbs.GRID_SIZE.y;
    const card_height = @as(i32, @intFromFloat(window_height / 4));

    const player_gui_size = types.Vec2(i32){
        .x = @as(i32, @intFromFloat(gui_pixel_width)) - padding * 2,
        .y = card_height - padding * 2,
    };

    rl.drawRectangle(0, 0, @intFromFloat(gui_pixel_width), @intFromFloat(window_height), .gray);

    const esc_text = "Press ESC to exit";
    const esc_font_size = @as(i32, @intFromFloat(@max(10, cell_size * 0.4)));
    const esc_text_width = rl.measureText(esc_text, esc_font_size);
    const esc_pos_x = @as(i32, @intFromFloat(gui_pixel_width / 2)) - @divTrunc(esc_text_width, 2);
    const esc_pos_y = @as(i32, @intFromFloat(window_height)) - padding - esc_font_size;
    rl.drawText(esc_text, esc_pos_x, esc_pos_y, esc_font_size, .light_gray);

    var iterator = self.opt_players.iterator();
    while (iterator.next()) |opt_player| if (opt_player.value.*) |*player| {
        const team = opt_player.key;

        const card_pos = types.Vec2(i32){
            .x = padding,
            .y = padding + card_height * @as(i32, @intCast((iterator.index - 1))),
        };

        const card_bg_color = if (player.health > 0) self.data.team_colors.get(team) else rl.Color.dark_gray;

        funcs.drawRectangleWithOutline(
            .{ .x = @floatFromInt(card_pos.x), .y = @floatFromInt(card_pos.y) },
            .{ .x = @floatFromInt(player_gui_size.x), .y = @floatFromInt(player_gui_size.y) },
            card_bg_color,
            cell_size / 20,
            .black,
        );

        const player_texture = self.team_textures.get(team).player_textures.down[0];
        const icon_size = @as(f32, @floatFromInt(player_gui_size.y)) / 2;
        const icon_dest_rect = rl.Rectangle{
            .x = @floatFromInt(card_pos.x + padding),
            .y = @floatFromInt(card_pos.y + padding),
            .width = icon_size,
            .height = icon_size,
        };
        rl.drawCircleV(.{ .x = icon_dest_rect.x + icon_size / 2, .y = icon_dest_rect.y + icon_size / 2 }, icon_size / 2 + 2, .white);
        rl.drawTexturePro(player_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(player_texture.width), .height = @floatFromInt(player_texture.height) }, icon_dest_rect, .{ .x = 0, .y = 0 }, 0, .white);

        const text_area_x = @as(i32, @intFromFloat(icon_dest_rect.x + icon_dest_rect.width)) + padding;
        const text_area_width = card_pos.x + player_gui_size.x - padding - text_area_x;

        const name = @tagName(opt_player.key);
        var name_font_size = @as(i32, @intFromFloat(@max(12, cell_size / 2)));
        while (rl.measureText(name, name_font_size) > text_area_width and name_font_size > 8) {
            name_font_size -= 1;
        }

        const name_pos_y = @as(i32, @intFromFloat(icon_dest_rect.y));

        rl.drawText(name, text_area_x, name_pos_y, name_font_size, .black);

        var score_buf: [13]u8 = undefined; // HARDCODED to fit exactly "Score: XXXXX\0"
        const score_text = std.fmt.bufPrintZ(&score_buf, "Score: {}", .{player.score}) catch @panic("Failed to format score!");
        const score_font_size = @as(i32, @intFromFloat(@max(10, cell_size * 0.4)));
        const score_pos_y = name_pos_y + name_font_size + @divTrunc(padding, 2);

        rl.drawText(score_text, text_area_x, score_pos_y, score_font_size, .light_gray);

        const stats_area_y = icon_dest_rect.y + icon_dest_rect.height + @as(f32, @floatFromInt(padding)) / 2;
        const stats_available_width = @as(f32, @floatFromInt(player_gui_size.x));

        const hearth_texture = if (player.invincibility_timer > 0) self.textures.get(.invincible_hearth) else self.textures.get(.hearth);
        const heart_icon_size = cell_size * 0.4;
        const heart_spacing = heart_icon_size * 0.15;
        const num_heart_spaces = @max(0, @as(i32, @intCast(player.health)) - 1);
        const total_hearts_width = @as(f32, @floatFromInt(player.health)) * heart_icon_size + @as(f32, @floatFromInt(num_heart_spaces)) * heart_spacing;
        const hearts_start_x = @as(f32, @floatFromInt(card_pos.x)) + (stats_available_width - total_hearts_width) / 2;

        for (0..player.health) |j| {
            const heart_pos = rl.Vector2{
                .x = hearts_start_x + @as(f32, @floatFromInt(j)) * (heart_icon_size + heart_spacing),
                .y = stats_area_y,
            };

            rl.drawCircleV(.{ .x = heart_pos.x + heart_icon_size / 2, .y = heart_pos.y + heart_icon_size / 2 }, heart_icon_size / 2 + 1, .white);
            rl.drawTextureEx(hearth_texture, heart_pos, 0, heart_icon_size / @as(f32, @floatFromInt(hearth_texture.width)), .white);
        }

        const dynamite_texture = self.team_textures.get(team).dynamite_textures[0];
        const dynamites_y = stats_area_y + heart_icon_size + @as(f32, @floatFromInt(padding)) / 2;
        const dynamite_icon_size = cell_size * 0.35;
        const dynamite_spacing = dynamite_icon_size * 0.15;
        const num_dynamite_spaces = @max(0, @as(i32, @intCast(player.dynamite_count)) - 1);
        const total_dynamites_width = @as(f32, @floatFromInt(player.dynamite_count)) * dynamite_icon_size + @as(f32, @floatFromInt(num_dynamite_spaces)) * dynamite_spacing;
        const dynamites_start_x = @as(f32, @floatFromInt(card_pos.x)) + (stats_available_width - total_dynamites_width) / 2;

        for (0..player.dynamite_count) |j| {
            const dynamite_pos = rl.Vector2{
                .x = dynamites_start_x + @as(f32, @floatFromInt(j)) * (dynamite_icon_size + dynamite_spacing),
                .y = dynamites_y,
            };
            rl.drawCircleV(.{ .x = dynamite_pos.x + dynamite_icon_size / 2, .y = dynamite_pos.y + dynamite_icon_size / 2 }, dynamite_icon_size / 2 + 1, .white);
            rl.drawTextureEx(dynamite_texture, dynamite_pos, 0, dynamite_icon_size / @as(f32, @floatFromInt(dynamite_texture.width)), .white);
        }
    };
}

fn generateCellGrid(random: std.Random, world_id: b2.b2WorldId) [glbs.GRID_SIZE.y][glbs.GRID_SIZE.x]types.Cell {
    var cell_grid: [glbs.GRID_SIZE.y][glbs.GRID_SIZE.x]types.Cell = @splat(@splat(.initGround()));

    for (&cell_grid, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (y % (glbs.GRID_SIZE.y - 1) == 0 or x % (glbs.GRID_SIZE.x - 1) == 0 or x % 2 == 0 and y % 2 == 0) {
                cell.* = .initWall(world_id, .{ .x = @intCast(x), .y = @intCast(y) });
            } else {
                const max_y = glbs.GRID_SIZE.y - y - 1;
                const max_x = glbs.GRID_SIZE.x - x - 1;

                if (!(@min(x, max_x) < 4 and @min(y, max_y) < 4 and @min(x, max_x) + @min(y, max_y) < 5) and (random.boolean() or random.boolean())) {
                    cell.* = .initBarrel(world_id, .{ .x = @intCast(x), .y = @intCast(y) });
                }
            }
        }
    }

    return cell_grid;
}

fn createTeamTextures(data: *const Data) std.enums.EnumArray(types.Team, types.TeamTextures) {
    const textures = data.textures;
    var team_textures = std.enums.EnumArray(types.Team, types.TeamTextures).initUndefined();
    const shader = rl.loadShaderFromMemory(null, @import("resources").SHADER) catch @panic("Failed to load shader!");
    defer rl.unloadShader(shader);

    for (std.enums.values(types.Team)[0..data.player_count]) |team| {
        const color = data.team_colors.get(team);
        const dynamite_textures = [_]rl.Texture2D{
            applyShaderToTexture(shader, color, textures.get(.dynamite)),
            applyShaderToTexture(shader, color, textures.get(.dynamite_exploding)),
        };
        const explosion_textures = [_]rl.Texture2D{
            applyShaderToTexture(shader, color, textures.get(.explosion)),
            applyShaderToTexture(shader, color, textures.get(.explosion_crossed)),
        };
        const player_textures = types.PlayerTextures{
            .side = .{
                applyShaderToTexture(shader, color, textures.get(.player_idle_side)),
                applyShaderToTexture(shader, color, textures.get(.player_walking_side)),
                applyShaderToTexture(shader, color, textures.get(.player_walking_side2)),
            },
            .down = .{
                applyShaderToTexture(shader, color, textures.get(.player_idle_down)),
                applyShaderToTexture(shader, color, textures.get(.player_walking_down)),
            },
            .up = .{
                applyShaderToTexture(shader, color, textures.get(.player_idle_up)),
                applyShaderToTexture(shader, color, textures.get(.player_walking_up)),
            },
        };

        team_textures.set(team, .{ .dynamite_textures = dynamite_textures, .explosion_textures = explosion_textures, .player_textures = player_textures });
    }

    return team_textures;
}

fn applyShaderToTexture(shader: rl.Shader, color: rl.Color, texture: rl.Texture2D) rl.Texture2D {
    const target = rl.loadRenderTexture(texture.width, texture.height) catch @panic("Failed to load render texture!");
    defer rl.unloadRenderTexture(target);

    rl.beginTextureMode(target);
    rl.clearBackground(.blank);
    rl.beginShaderMode(shader);
    rl.setShaderValue(shader, rl.getShaderLocation(shader, "color"), &color.normalize(), rl.ShaderUniformDataType.vec4);
    rl.drawTexture(texture, 0, 0, .white);
    rl.endShaderMode();
    rl.endTextureMode();

    var image = rl.loadImageFromTexture(target.texture) catch @panic("Failed to load image from texture!");
    defer rl.unloadImage(image);
    image.flipVertical();

    return rl.loadTextureFromImage(image) catch @panic("Failed to load texture from image!");
}

fn drawBackground(self: *@This()) void {
    const cell_size = self.cell_size.*;
    const ground_texture = self.textures.get(.ground);

    const dst = rl.Rectangle{
        .x = glbs.GUI_SIZE * cell_size,
        .y = 0,
        .width = glbs.GRID_SIZE.x * cell_size,
        .height = glbs.GRID_SIZE.y * cell_size,
    };

    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(glbs.GRID_SIZE.x * ground_texture.width),
        .height = @floatFromInt(glbs.GRID_SIZE.y * ground_texture.height),
    };

    rl.drawTexturePro(ground_texture, src, dst, rl.Vector2.zero(), 0, .white);

    for (0..glbs.GRID_SIZE.y) |y| {
        for (0..glbs.GRID_SIZE.x) |x| {
            const cell = self.cell_grid[y][x];
            const active_tag = cell.tag;

            var texture: rl.Texture = undefined;
            var rotation: f32 = 0;

            switch (active_tag) {
                .ground => continue,
                .wall, .death_wall, .barrel, .upgrade_dynamite, .upgrade_heal, .upgrade_radius, .upgrade_speed, .upgrade_teleport => {
                    texture = self.textures.get(active_tag);
                },
                .explosion, .explosion_crossed => {
                    texture = self.team_textures.get(cell.variant.explosion.team).explosion_textures[@intFromBool(cell.variant.explosion.variant == .crossed)];
                    rotation = if (cell.variant.explosion.variant == .vertical) 90 else 0;
                },
                .dynamite, .dynamite_exploding => {
                    texture = self.team_textures.get(cell.variant.dynamite.team).dynamite_textures[@intFromBool(active_tag == .dynamite_exploding)];
                },
                else => unreachable,
            }

            funcs.drawTextureCoords(texture, cell_size, .{ .x = x, .y = y }, rotation, false);
        }
    }
}

fn checkPlayerPositions(self: *@This()) void {
    var iterator = self.opt_players.iterator();
    while (iterator.next()) |opt_player| if (opt_player.value.*) |*player| if (player.health > 0) {
        const pos = b2.b2Body_GetPosition(player.body_id);
        const cell = &self.cell_grid[@intFromFloat(@round(pos.y / glbs.PHYSICS_UNIT))][@intFromFloat(@round(pos.x / glbs.PHYSICS_UNIT))];

        switch (cell.tag) {
            .ground, .dynamite, .dynamite_exploding => {},
            .explosion, .explosion_crossed => {
                const damaging_team = cell.variant.explosion.team;

                if (damaging_team != opt_player.key) {
                    if (self.opt_players.getPtr(damaging_team).*) |*damaging_player| {
                        if (player.invincibility_timer < 0) damaging_player.score += 25;
                    }
                }

                player.hurt();
            },
            .upgrade_dynamite => {
                player.score += 2;
                player.dynamite_count += 1;
                cell.* = .initGround();
            },
            .upgrade_heal => {
                player.score += 2;
                player.heal();
                cell.* = .initGround();
            },
            .upgrade_radius => {
                player.score += 2;
                player.explosion_radius += 1;
                cell.* = .initGround();
            },
            .upgrade_speed => {
                player.score += 2;
                player.speed += glbs.PHYSICS_UNIT;
                cell.* = .initGround();
            },
            .upgrade_teleport => {
                player.score += 2;
                player.teleport_timer = 0;

                if (player.teleport_cooldown > 2) player.teleport_cooldown -= 0.5;

                cell.* = .initGround();
            },
            else => unreachable,
        }
    };
}

fn updateDynamitesAndExplosions(self: *@This()) void {
    for (1..glbs.GRID_SIZE.y - 1) |y| {
        for (1..glbs.GRID_SIZE.x - 1) |x| {
            var cell = &self.cell_grid[y][x];
            const active_tag = cell.tag;

            switch (active_tag) {
                .dynamite_exploding => {
                    if (cell.variant.dynamite.timer > 0) {
                        cell.variant.dynamite.update();

                        break;
                    }

                    for (glbs.DIRECTIONS, 0..) |dir, i| {
                        for (1..cell.variant.dynamite.radius) |offset| {
                            const grid_pos = types.Vec2(usize){
                                .x = @intCast(@as(i32, @intCast(x)) + dir.x * @as(i32, @intCast(offset))),
                                .y = @intCast(@as(i32, @intCast(y)) + dir.y * @as(i32, @intCast(offset))),
                            };

                            var cell_in_radius = &self.cell_grid[grid_pos.y][grid_pos.x];
                            const cell_in_radius_active_tag = cell_in_radius.tag;

                            switch (cell_in_radius_active_tag) {
                                .wall, .death_wall, .explosion_crossed => break,
                                .ground => {
                                    cell_in_radius.* = .initExplosion(
                                        cell.variant.dynamite.team,
                                        D: {
                                            const variant: types.ExplosionVariant = if (i < 2) .horizontal else .vertical;

                                            if (cell_in_radius_active_tag == .explosion and cell_in_radius.variant.explosion.team == cell.variant.dynamite.team and cell_in_radius.variant.explosion.variant != variant)
                                                break :D .crossed;

                                            break :D variant;
                                        },
                                        .none,
                                    );
                                },
                                .explosion => {
                                    cell_in_radius.* = .initExplosion(
                                        cell.variant.dynamite.team,
                                        D: {
                                            const variant: types.ExplosionVariant = if (i < 2) .horizontal else .vertical;

                                            if (cell_in_radius_active_tag == .explosion and cell_in_radius.variant.explosion.team == cell.variant.dynamite.team and cell_in_radius.variant.explosion.variant != variant)
                                                break :D .crossed;

                                            break :D variant;
                                        },
                                        cell_in_radius.variant.explosion.upgrade_underneath,
                                    );
                                },
                                .barrel => {
                                    if (self.opt_players.getPtr(cell.variant.dynamite.team).*) |*player| player.score += 5;

                                    b2.b2DestroyBody(cell_in_radius.variant.barrel.body_id);

                                    var random = self.data.prng.random();

                                    cell_in_radius.* = .initExplosion(
                                        cell.variant.dynamite.team,
                                        D: {
                                            const variant: types.ExplosionVariant = if (i < 2) .horizontal else .vertical;

                                            if (cell_in_radius_active_tag == .explosion and cell_in_radius.variant.explosion.team == cell.variant.dynamite.team and cell_in_radius.variant.explosion.variant != variant)
                                                break :D .crossed;

                                            break :D variant;
                                        },
                                        if (random.boolean()) random.enumValue(types.UpgradeUnderneath) else .none,
                                    );

                                    break;
                                },
                                .dynamite, .dynamite_exploding => {
                                    cell_in_radius.variant.dynamite.timer = 0;

                                    break;
                                },
                                .upgrade_dynamite, .upgrade_heal, .upgrade_radius, .upgrade_speed, .upgrade_teleport => {
                                    cell_in_radius.* = .initExplosion(
                                        cell.variant.dynamite.team,
                                        D: {
                                            const variant: types.ExplosionVariant = if (i < 2) .horizontal else .vertical;

                                            if (cell_in_radius_active_tag == .explosion and cell_in_radius.variant.explosion.team == cell.variant.dynamite.team and cell_in_radius.variant.explosion.variant != variant)
                                                break :D .crossed;

                                            break :D variant;
                                        },
                                        @enumFromInt(@intFromEnum(cell_in_radius_active_tag) - @intFromEnum(types.Texture.upgrade_dynamite)),
                                    );
                                },
                                else => unreachable,
                            }
                        }
                    }

                    if (self.opt_players.getPtr(cell.variant.dynamite.team).*) |*player| player.dynamite_count += 1;

                    cell.* = .initExplosion(cell.variant.dynamite.team, .crossed, .none);
                },
                .dynamite => {
                    cell.variant.dynamite.update();

                    if (cell.variant.dynamite.timer < 1) cell.tag = .dynamite_exploding;
                },
                else => continue,
            }
        }
    }
}

fn decayExplosions(self: *@This()) void {
    for (0..glbs.GRID_SIZE.y) |y| {
        for (0..glbs.GRID_SIZE.x) |x| {
            var cell = &self.cell_grid[y][x];

            if (cell.tag == .explosion or cell.tag == .explosion_crossed) {
                cell.variant.explosion.timer -= glbs.PHYSICS_TIMESTEP;

                if (cell.variant.explosion.timer < 0) {
                    cell.* = if (cell.variant.explosion.upgrade_underneath != .none)
                        .initUpgrade(cell.variant.explosion.upgrade_underneath)
                    else
                        .initGround();
                }
            }
        }
    }
}
