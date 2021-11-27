const std = @import("std");
const sdl = @import("sdl2");
const sdl_ttf = @import("sdl_ttf.zig");

pub fn main() anyerror!void {
    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit();

    var window = try sdl.createWindow("SDL Test", .{ .centered = {} }, .{ .centered = {} }, 640, 480, .{ .shown = true });
    defer window.destroy();

    var renderer = try sdl.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();

    _ = sdl_ttf.TTF_Init();
    defer sdl_ttf.TTF_Quit();

    var font = try sdl_ttf.Font.openFont(renderer, "fonts\\Inconsolata-g.ttf", 12);
    defer font.destroy();

    var text_buffer = std.ArrayList(u8).init(std.heap.c_allocator);
    defer text_buffer.deinit();

    var writer = text_buffer.writer();

    main_loop: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main_loop,
                .text_input => |text_input_ev| {
                    // @note This is a hack, definitely broken
                    writer.print("{c}", .{text_input_ev.text[0]}) catch {};
                },
                .key_down => |key_ev| {
                    switch (key_ev.keycode) {
                        .@"return" => {
                            writer.writeAll("\n") catch {};
                        },
                        .tab => {
                            writer.writeAll("  ") catch {};
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        try renderer.setColorRGB(0x00, 0x00, 0x00);
        try renderer.clear();

        if (text_buffer.items.len > 0) {
            try font.drawText(renderer, text_buffer.items, 100, 50);
        }

        renderer.present();
    }
}
