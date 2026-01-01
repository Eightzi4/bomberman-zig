const rl = @import("raylib");

const Data = @import("Data.zig");

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1000, 650, "Bomberman Zig");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(rl.getCurrentMonitor()));
    rl.setExitKey(.delete);

    var data = Data.init();
    defer data.deinit();

    data.run();
}
