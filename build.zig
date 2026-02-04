const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_windows = target.result.os.tag == .windows;

    // Check if wasmtime libs exist, provide helpful error if not
    const wasmtime_path = if (is_windows)
        "libs/wasmtime-v27.0.0-x86_64-windows-c-api/lib/wasmtime.lib"
    else
        "libs/wasmtime-v27.0.0-x86_64-linux-c-api/lib/libwasmtime.a";

    std.fs.cwd().access(wasmtime_path, .{}) catch {
        std.debug.print(
            \\
            \\ERROR: Wasmtime library not found!
            \\
            \\Run this command to download dependencies:
            \\  ./scripts/download-deps.sh
            \\
            \\
        , .{});
        return;
    };

    const exe = b.addExecutable(.{
        .name = "moon-code",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Enable LTO for release builds
    if (optimize != .Debug) {
        exe.root_module.optimize = .ReleaseFast;
    }

    // stb_truetype implementation
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "src/render/stb_impl.c",
        },
        .flags = &[_][]const u8{},
    });

    // nanosvg implementation
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "src/render/nanosvg_impl.c",
        },
        .flags = if (is_windows)
            &[_][]const u8{"-O2"}
        else
            &[_][]const u8{ "-O2", "-lm" },
    });

    // Header paths
    exe.addIncludePath(b.path("src/render"));

    if (is_windows) {
        // Windows-specific setup

        // Wasmtime C API for Windows
        exe.addIncludePath(b.path("libs/wasmtime-v27.0.0-x86_64-windows-c-api/include"));
        exe.addObjectFile(b.path("libs/wasmtime-v27.0.0-x86_64-windows-c-api/lib/wasmtime.lib"));

        // Windows system libraries
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("kernel32");
        exe.linkSystemLibrary("shell32");

        // Windows C runtime
        exe.linkLibC();
    } else {
        // Linux-specific setup

        // Wayland protocol files
        exe.addCSourceFiles(.{
            .files = &[_][]const u8{
                "protocols/xdg-shell-protocol.c",
                "protocols/xdg-activation-v1-protocol.c",
            },
            .flags = &[_][]const u8{"-O2"},
        });
        exe.addIncludePath(b.path("protocols"));

        // Wasmtime C API (static linking with LTO)
        exe.addIncludePath(b.path("libs/wasmtime-v27.0.0-x86_64-linux-c-api/include"));
        exe.addObjectFile(b.path("libs/wasmtime-v27.0.0-x86_64-linux-c-api/lib/libwasmtime.a"));
        exe.linkSystemLibrary("unwind");
        exe.linkSystemLibrary("gcc_s");

        // Wayland libraries
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-egl");
        exe.linkSystemLibrary("wayland-cursor");

        // EGL/OpenGL ES
        exe.linkSystemLibrary("EGL");
        exe.linkSystemLibrary("GLESv2");

        exe.linkLibC();
    }

    // Increase stack size for large local arrays
    exe.stack_size = 32 * 1024 * 1024; // 32MB stack

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run moon-code");
    run_step.dependOn(&run_cmd.step);
}
