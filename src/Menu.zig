const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const glbs = @import("globals.zig");
const Data = @import("Data.zig");
const Player = @import("Player.zig");
const types = @import("types.zig");

const RebindableAction = union(enum) {
    movement: Player.MoveDirection,
    place_dynamite,
};

const RebindInfo = struct {
    team: types.Team,
    action: RebindableAction,
};

const State = enum {
    menu,
    game,
    settings,
    exit,
};

state: State,
data: *Data,
opt_rebinding_key: ?RebindInfo,
scroll_panel_offset: rl.Vector2,

pub fn init(data_ptr: *Data) @This() {
    return .{
        .state = .menu,
        .data = data_ptr,
        .opt_rebinding_key = null,
        .scroll_panel_offset = .{ .x = 0, .y = 0 },
    };
}

pub fn update(self: *@This()) void {
    if (self.opt_rebinding_key) |rebind| {
        const key_code = rl.getKeyPressed();

        if (key_code != .null) {
            var actions_ptr = self.data.key_bindings.getPtr(rebind.team);

            switch (rebind.action) {
                .movement => |move_dir| actions_ptr.movement.getPtr(move_dir).*.binded_key = key_code,
                .place_dynamite => actions_ptr.place_dynamite.binded_key = key_code,
            }

            self.opt_rebinding_key = null;
        }
    }
}

pub fn draw(self: *@This()) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    self.drawBackground();

    const title_text = "Bomberman Zig";
    const title_font_size = 60;
    const screen_width = rl.getScreenWidth();
    const title_width = rl.measureText(title_text, title_font_size);

    rl.drawText(
        title_text,
        @divTrunc(screen_width - title_width, 2),
        @divTrunc(rl.getScreenHeight(), 10),
        title_font_size,
        .black,
    );

    if (self.state == .settings) rg.lock();
    defer if (self.state == .settings) self.drawSettingsWindow();

    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
    const button_width = 250;
    const button_height = 50;
    const button_x = @divTrunc(@as(f32, @floatFromInt(screen_width)) - button_width, 2);
    const padding_y = 70;

    self.state = if (rg.button(.{ .x = button_x, .y = screen_height * 0.3, .width = button_width, .height = button_height }, "Play"))
        .game
    else if (self.state == .settings or rg.button(.{ .x = button_x, .y = screen_height * 0.3 + padding_y, .width = button_width, .height = button_height }, "Settings"))
        .settings
    else if (rg.button(.{ .x = button_x, .y = screen_height * 0.3 + padding_y * 2, .width = button_width, .height = button_height }, "Exit"))
        .exit
    else
        .menu;

    rg.unlock();
}

fn drawBackground(self: *@This()) void {
    const ground_texture = self.data.textures.get(.ground);
    const cell_size = self.data.cell_size;

    const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));

    const dst = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = screen_width,
        .height = screen_height,
    };

    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = (screen_width / cell_size) * @as(f32, @floatFromInt(ground_texture.width)),
        .height = (screen_height / cell_size) * @as(f32, @floatFromInt(ground_texture.height)),
    };

    rl.drawTexturePro(
        ground_texture,
        src,
        dst,
        rl.Vector2.zero(),
        0,
        .white,
    );
}

fn drawSettingsWindow(self: *@This()) void {
    const screen_w = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screen_h = @as(f32, @floatFromInt(rl.getScreenHeight()));

    rl.drawRectangle(0, 0, @intFromFloat(screen_w), @intFromFloat(screen_h), rl.fade(.black, 0.75));

    const window_width = @min(600, screen_w - 80);
    const window_height = @min(600, screen_h - 80);
    const window_x = (screen_w - window_width) / 2;
    const window_y = (screen_h - window_height) / 2;
    const window_bounds = rl.Rectangle{ .x = window_x, .y = window_y, .width = window_width, .height = window_height };

    if (rg.windowBox(window_bounds, "Settings") != 0) {
        self.state = .menu;
        self.opt_rebinding_key = null;
    }

    const header_height = 30;
    const content_padding = 10;
    const player_count_controls_height = 40;

    const fixed_content_start_x = window_x + content_padding + 10;
    const fixed_content_y = window_y + header_height + content_padding;
    _ = rg.label(.{ .x = fixed_content_start_x, .y = fixed_content_y, .width = 100, .height = 25 }, "Player Count:");
    var temp_player_count: i32 = self.data.player_count;
    _ = rg.spinner(.{ .x = fixed_content_start_x + 120, .y = fixed_content_y, .width = 120, .height = 25 }, "", &temp_player_count, 2, 4, false);
    self.data.player_count = @intCast(temp_player_count);

    const group_height = 180;
    const scroll_panel_y_start = fixed_content_y + player_count_controls_height - content_padding;

    const view_area = rl.Rectangle{
        .x = window_x + 1,
        .y = scroll_panel_y_start,
        .width = window_width - 2,
        .height = (window_y + window_height) - scroll_panel_y_start - 1,
    };

    const content_area = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = window_width - 22,
        .height = (@as(f32, @floatFromInt(self.data.player_count)) * group_height),
    };

    var view: rl.Rectangle = undefined;
    _ = rg.scrollPanel(view_area, "", content_area, &self.scroll_panel_offset, &view);

    rl.beginScissorMode(@intFromFloat(view.x), @intFromFloat(view.y), @intFromFloat(view.width), @intFromFloat(view.height));
    defer rl.endScissorMode();

    var content_current_y = view.y + 10 + self.scroll_panel_offset.y;

    for (0..self.data.player_count) |i| {
        const team = @as(types.Team, @enumFromInt(i));
        self.drawPlayerSettings(team, @intCast(i + 1), view, &content_current_y, group_height);
    }
}

fn drawPlayerSettings(self: *@This(), team: types.Team, player_index: u32, view: rl.Rectangle, current_y: *f32, group_height: f32) void {
    const start_x = view.x + 20 + self.scroll_panel_offset.x;

    var player_name_buffer: [9]u8 = undefined; // HARDCODED to fix exactly "Player X\0"
    const player_name = std.fmt.bufPrintZ(&player_name_buffer, "Player {}", .{player_index}) catch @panic("Failed to format player name!");

    _ = rg.groupBox(.{ .x = start_x, .y = current_y.*, .width = view.width - 40, .height = group_height - 20 }, player_name);
    _ = rg.label(.{ .x = start_x + 20, .y = current_y.* + 30, .width = 100, .height = 25 }, "Team Color:");
    _ = rg.colorPicker(.{ .x = start_x + 120, .y = current_y.* + 20, .width = 100, .height = 100 }, "", self.data.team_colors.getPtr(team));

    const keybind_x = start_x + 250;
    var keybind_y_offset: f32 = 20;

    var movement_iterator = self.data.key_bindings.getPtr(team).movement.iterator();
    while (movement_iterator.next()) |action| {
        self.drawKeybindControl(team, .{ .movement = action.key }, @tagName(action.key), keybind_x, current_y.* + keybind_y_offset);
        keybind_y_offset += 28;
    }

    self.drawKeybindControl(team, .place_dynamite, "dynamite", keybind_x, current_y.* + keybind_y_offset);

    current_y.* += group_height;
}

fn drawKeybindControl(self: *@This(), team: types.Team, action: RebindableAction, label_text: []const u8, x: f32, y: f32) void {
    var label_buffer: [10]u8 = undefined; // HARDCODED to fit exactly "XXXXXXXX:\0"
    const label = std.fmt.bufPrintZ(&label_buffer, "{s}:", .{label_text}) catch @panic("Failed to format label!");
    _ = rg.label(.{ .x = x, .y = y, .width = 50, .height = 25 }, label);

    const button_text = self.getKeybindButtonText(team, action);

    if (rg.button(.{ .x = x + 60, .y = y, .width = 150, .height = 25 }, button_text)) {
        self.opt_rebinding_key = .{ .team = team, .action = action };
    }
}

fn getKeybindButtonText(self: *@This(), team: types.Team, action: RebindableAction) [:0]const u8 {
    if (self.opt_rebinding_key) |rebind| {
        if (rebind.team == team and std.meta.eql(rebind.action, action)) {
            return "...";
        }
    }

    const key_code = switch (action) {
        .movement => |move_dir| self.data.key_bindings.get(team).movement.get(move_dir).binded_key,
        .place_dynamite => self.data.key_bindings.get(team).place_dynamite.binded_key,
    };

    if (key_code == .null) {
        return "Not Bound";
    }

    return @tagName(key_code);
}
