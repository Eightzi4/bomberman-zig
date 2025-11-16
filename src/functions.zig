const std = @import("std");
const rl = @import("raylib");
const b2 = glbs.b2;

const glbs = @import("globals.zig");
const types = @import("types.zig");

pub fn physPosToScreenPos(phys_pos: b2.b2Vec2, cell_size: f32) b2.b2Vec2 {
    return .{
        .x = phys_pos.x / glbs.PHYSICS_UNIT * cell_size + cell_size / 2 + cell_size * glbs.GUI_SIZE,
        .y = phys_pos.y / glbs.PHYSICS_UNIT * cell_size + cell_size / 2,
    };
}

pub fn drawRectangleWithOutline(pos: b2.b2Vec2, size: b2.b2Vec2, color: rl.Color, outline_thickness: f32, outline_color: rl.Color) void {
    rl.drawRectangle(@intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(size.x), @intFromFloat(size.y), color);
    rl.drawRectangleLinesEx(
        .{ .x = pos.x, .y = pos.y, .width = size.x, .height = size.y },
        outline_thickness,
        outline_color,
    );
}

/// Draw texture at coordinates
pub fn drawTextureCoords(texture: rl.Texture2D, cell_size: f32, coords: types.Vec2(usize), rot: f32, flip_h: bool) void {
    drawTexture(
        texture,
        cell_size,
        .{ .x = glbs.GUI_SIZE * cell_size + cell_size * @as(f32, @floatFromInt(coords.x)) + cell_size / 2, .y = cell_size * @as(f32, @floatFromInt(coords.y)) + cell_size / 2 },
        rot,
        flip_h,
    );
}

/// Draw texture at position
pub fn drawTexturePos(texture: rl.Texture2D, cell_size: f32, pos: b2.b2Vec2, rot: f32, flip_h: bool) void {
    drawTexture(texture, cell_size, pos, rot, flip_h);
}

fn drawTexture(texture: rl.Texture2D, cell_size: f32, pos: b2.b2Vec2, rot: f32, flip_h: bool) void {
    const scale = cell_size / @as(f32, @floatFromInt(texture.width));
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(texture.width * @as(c_int, if (flip_h) -1 else 1)),
        .height = @floatFromInt(texture.height),
    };

    const dst = rl.Rectangle{
        .x = pos.x,
        .y = pos.y,
        .width = @as(f32, @floatFromInt(texture.width)) * scale,
        .height = @as(f32, @floatFromInt(texture.height)) * scale,
    };
    const origin = rl.Vector2{
        .x = @as(f32, @floatFromInt(texture.width)) * scale / 2,
        .y = @as(f32, @floatFromInt(texture.height)) * scale / 2,
    };

    rl.drawTexturePro(texture, src, dst, origin, rot, .white);
}

pub fn createCollider(world_id: b2.b2WorldId, coords: types.Vec2(u8)) b2.b2BodyId {
    var body_def = b2.b2DefaultBodyDef();
    body_def.position = .{
        .x = @floatFromInt(glbs.PHYSICS_UNIT * @as(i32, @intCast(coords.x))),
        .y = @floatFromInt(glbs.PHYSICS_UNIT * @as(i32, @intCast(coords.y))),
    };

    const body_id = b2.b2CreateBody(world_id, &body_def);

    _ = b2.b2CreatePolygonShape(
        body_id,
        &b2.b2DefaultShapeDef(),
        &b2.b2MakeBox(glbs.PHYSICS_UNIT / 2, glbs.PHYSICS_UNIT / 2),
    );

    return body_id;
}
