const std = @import("std");

const SHOULD_LEAK = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "Bomberman Zig",
        .root_module = exe_mod,
    });

    if (optimize != .Debug and target.result.os.tag == .windows) exe.subsystem = .Windows;

    // Import resources
    {
        const resources_mod = b.createModule(.{
            .root_source_file = b.path("resources/resources.zig"),
            .target = target,
            .optimize = optimize,
        });

        // 'texture_file_names' build option will be used to generate resources/resources.zig@Texture enum
        {
            const options = b.addOptions();
            options.addOption(
                []const [:0]const u8,
                "texture_file_names",
                D: {
                    const alloc = b.allocator;

                    var file_names = std.ArrayList([:0]const u8){};

                    var dir = std.fs.cwd().openDir("resources/textures", .{ .iterate = true }) catch @panic("Failed to open resources/textures directory!");
                    defer dir.close();

                    var it = dir.iterate();
                    while (it.next() catch @panic("Directory iteration failed!")) |entry| {
                        file_names.append(alloc, alloc.dupeZ(u8, entry.name[0 .. entry.name.len - ".png".len]) catch @panic("Failed to allocate file name!")) catch @panic("Failed to add file to list!");
                    }

                    break :D file_names.toOwnedSlice(alloc) catch @panic("Failed to allocate file list!");
                },
            );

            resources_mod.addOptions("build_options", options);
        }

        exe.root_module.addImport("resources", resources_mod);
    }

    // Import raylib & raygui
    {
        const raylib_dep = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.linkLibrary(raylib_dep.artifact("raylib"));
        exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
        exe.root_module.addImport("raygui", raylib_dep.module("raygui"));
    }

    // Import box2d
    {
        const box2d_dep = b.dependency("box2d", .{});

        const box2d = b.addLibrary(.{
            .name = "box2d",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });

        const files = D: {
            const alloc = b.allocator;

            var file_names = std.ArrayList([:0]const u8){};

            var dir = std.fs.openDirAbsolute(box2d_dep.builder.pathFromRoot("src"), .{ .iterate = true }) catch @panic("Failed to open directory!");
            defer dir.close();

            var it = dir.iterate();
            while (it.next() catch @panic("Directory iteration failed!")) |entry| {
                if (entry.kind == .file and std.mem.eql(u8, std.fs.path.extension(entry.name), ".c"))
                    file_names.append(alloc, alloc.dupeZ(u8, entry.name) catch @panic("Failed to allocate file name!")) catch @panic("Failed to add file to list!");
            }

            break :D file_names.toOwnedSlice(alloc) catch @panic("Failed to allocate file list!");
        };
        defer if (!SHOULD_LEAK) {
            for (files) |file| b.allocator.free(file);
            b.allocator.free(files);
        };

        box2d.root_module.link_libc = true;
        box2d.root_module.addIncludePath(box2d_dep.path("include"));
        box2d.installHeadersDirectory(box2d_dep.path("include"), "", .{});
        box2d.root_module.addCSourceFiles(.{
            .root = box2d_dep.path("src"),
            .flags = &.{"-std=c17"},
            .files = files,
        });

        exe.root_module.linkLibrary(box2d);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
