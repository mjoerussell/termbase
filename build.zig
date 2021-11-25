const std = @import("std");
const buildZdb = @import("./zdb/build_pkg.zig").buildPkg;
const SdlSdk = @import("./SDL.zig/SDK.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("termbase", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    buildZdb(exe, "zdb");

    const sdk = SdlSdk.init(b);
    sdk.link(exe, .dynamic);

    exe.addPackage(sdk.getWrapperPackage("sdl2"));
    exe.addIncludeDir("sdl_ttf/include/SDL2");
    exe.addObjectFile("sdl_ttf/lib/libSDL2_ttf.dll.a");
    b.installBinFile("sdl_ttf/bin/SDL2_ttf.dll", "SDL2_ttf.dll");
    b.installBinFile("sdl_ttf/bin/libfreetype-6.dll", "libfreetype-6.dll");
    b.installBinFile("sdl_ttf/bin/zlib1.dll", "zlib1.dll");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
