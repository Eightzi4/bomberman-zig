const std = @import("std");
const rl = @import("raylib");
const b2 = glbs.b2;

const glbs = @import("globals.zig");
const funcs = @import("functions.zig");
const Game = @import("Game.zig");
const types = @import("types.zig");

pub const MoveDirection = enum {
    left,
    right,
    up,
    down,
};

pub const MoveAction = struct {
    binded_key: rl.KeyboardKey,
    cached_input: bool = false,
    last_pressed: f32 = -1,
};

pub const Actions = struct {
    movement: std.enums.EnumArray(
        MoveDirection,
        MoveAction,
    ),
    place_dynamite: struct {
        binded_key: rl.KeyboardKey,
        cached_input: bool = false,
    },
};

score: u16,
dynamite_count: u8,
explosion_radius: u8,
health: u8,
invincibility_timer: f32,
teleport_cooldown: f32,
teleport_timer: f32,
speed: f32,
old_position: b2.b2Vec2,
body_id: b2.b2BodyId,
textures: *const types.PlayerTextures,
actions: Actions,
facing_direction: MoveDirection,
animation_timer: f32,
is_moving: bool,
teleport_request: ?MoveDirection,

pub fn init(position: b2.b2Vec2, world_id: b2.b2WorldId, actions: Actions, textures: *const types.PlayerTextures) @This() {
    const pos = b2.b2Vec2{ .x = glbs.PHYSICS_UNIT * position.x, .y = glbs.PHYSICS_UNIT * position.y };

    return .{
        .score = 0,
        .explosion_radius = 2,
        .dynamite_count = 1,
        .health = glbs.START_HEALTH,
        .invincibility_timer = 0,
        .teleport_cooldown = glbs.INITIAL_TELEPORT_COOLDOWN,
        .teleport_timer = std.math.floatMax(f32),
        .speed = glbs.PHYSICS_UNIT * 5,
        .old_position = pos,
        .body_id = D: {
            var body_def = b2.b2DefaultBodyDef();
            body_def.position = pos;
            body_def.type = b2.b2_dynamicBody;
            body_def.motionLocks = .{ .angularZ = true };
            body_def.linearDamping = 10;

            const body_id = b2.b2CreateBody(world_id, &body_def);

            _ = b2.b2CreateCircleShape(body_id, &b2.b2DefaultShapeDef(), &b2.b2Circle{ .radius = glbs.PHYSICS_UNIT / 2 });

            break :D body_id;
        },
        .actions = actions,
        .textures = textures,
        .facing_direction = .down,
        .animation_timer = 0,
        .is_moving = false,
        .teleport_request = null,
    };
}

pub fn update(self: *@This()) void {
    for (&self.actions.movement.values) |*action| action.cached_input = rl.isKeyDown(action.binded_key);

    self.actions.place_dynamite.cached_input = self.actions.place_dynamite.cached_input or rl.isKeyPressed(self.actions.place_dynamite.binded_key);

    var movement_iterator = self.actions.movement.iterator();
    while (movement_iterator.next()) |action| {
        if (rl.isKeyPressed(action.value.binded_key)) {
            const current_time = rl.getTime();
            const time_since_last_press = current_time - action.value.last_pressed;

            if (self.teleport_timer <= 0 and time_since_last_press < 0.25) {
                self.teleport_request = action.key;
                action.value.last_pressed = -1;
            } else action.value.last_pressed = @floatCast(current_time);
        }
    }

    self.old_position = b2.b2Body_GetPosition(self.body_id);
}

pub fn fixedUpdate(self: *@This()) void {
    self.invincibility_timer -= glbs.PHYSICS_TIMESTEP;
    self.teleport_timer -= glbs.PHYSICS_TIMESTEP;

    const velocity = b2.b2Body_GetLinearVelocity(self.body_id);
    const current_speed = b2.b2Length(velocity);

    self.is_moving = current_speed > 0.1;

    if (self.is_moving) {
        if (@abs(velocity.y) > @abs(velocity.x))
            self.facing_direction = if (velocity.y > 0) .down else .up
        else
            self.facing_direction = if (velocity.x > 0) .right else .left;
    }

    if (self.is_moving) {
        const anim_speed_factor = current_speed / self.speed;

        self.animation_timer += anim_speed_factor * glbs.PHYSICS_TIMESTEP * glbs.ANIMATION_PLAYBACK_SPEED;
        self.animation_timer = @mod(self.animation_timer, 1);
    } else self.animation_timer = 0;

    handleMovement(self.body_id, self.speed, self.actions.movement);
}

pub fn draw(self: *@This(), alpha: f32, cell_size: f32) void {
    const body_pos = b2.b2Body_GetPosition(self.body_id);
    const pos = funcs.physPosToScreenPos(.{
        .x = (self.old_position.x * (1 - alpha) + body_pos.x * alpha),
        .y = (self.old_position.y * (1 - alpha) + body_pos.y * alpha),
    }, cell_size);

    var texture_to_draw: rl.Texture2D = undefined;
    var flip_horizontally: bool = false;

    if (!self.is_moving) {
        texture_to_draw = switch (self.facing_direction) {
            .up => self.textures.up[0],
            .down => self.textures.down[0],
            else => self.textures.side[0],
        };
        flip_horizontally = (self.facing_direction == .right);
    } else {
        const animation_step = @as(u2, @intFromFloat(self.animation_timer * 4));

        switch (self.facing_direction) {
            .left, .right => {
                texture_to_draw = self.textures.side[glbs.PLAYER_ANIMATION_SEQUENCE[animation_step]];
                flip_horizontally = (self.facing_direction == .right);
            },
            .up, .down => {
                const texture_array = if (self.facing_direction == .up) self.textures.up else self.textures.down;

                texture_to_draw = texture_array[if (animation_step % 2 == 1) 0 else 1];

                flip_horizontally = animation_step == 2;
            },
        }
    }

    funcs.drawTexturePos(texture_to_draw, cell_size, pos, 0, flip_horizontally);
}

pub fn hurt(self: *@This()) void {
    if (self.invincibility_timer <= 0) {
        self.health -= 1;

        if (self.health == 0) b2.b2DestroyBody(self.body_id) else self.invincibility_timer = glbs.INVINCIBILITY_DURATION;
    }
}

pub fn heal(self: *@This()) void {
    self.health += 1;
}

fn handleMovement(body_id: b2.b2BodyId, speed: f32, movement_actions: std.enums.EnumArray(MoveDirection, MoveAction)) void {
    var input_vector = b2.b2Vec2{
        .x = @floatFromInt(@as(i2, @intFromBool(movement_actions.get(.right).cached_input)) - @as(i2, @intFromBool(movement_actions.get(.left).cached_input))),
        .y = @floatFromInt(@as(i2, @intFromBool(movement_actions.get(.down).cached_input)) - @as(i2, @intFromBool(movement_actions.get(.up).cached_input))),
    };
    const position = b2.b2Body_GetPosition(body_id);

    if (input_vector.x == 0 and input_vector.y != 0) {
        const grid_position_x = @divFloor(position.x, glbs.PHYSICS_UNIT);
        const offset = position.x - grid_position_x * glbs.PHYSICS_UNIT;

        input_vector.x = if (@rem(grid_position_x, 2) == 0)
            if (offset < 0) -1 else 1
        else if (offset < -glbs.PHYSICS_UNIT / 5) 1 else if (offset > glbs.PHYSICS_UNIT / 5) -1 else 0;
    } else if (input_vector.y == 0 and input_vector.x != 0) {
        const grid_position_y = @divFloor(position.y, glbs.PHYSICS_UNIT);
        const offset = position.y - grid_position_y * glbs.PHYSICS_UNIT;

        input_vector.y = if (@rem(grid_position_y, 2) == 0)
            if (offset < 0) -1 else 1
        else if (offset < -glbs.PHYSICS_UNIT / 5) 1 else if (offset > glbs.PHYSICS_UNIT / 5) -1 else 0;
    }

    b2.b2Body_SetLinearVelocity(body_id, b2.b2MulSV(speed, input_vector));
}
