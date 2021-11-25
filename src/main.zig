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

    var inconsolata_font: *sdl_ttf.TTF_Font = sdl_ttf.TTF_OpenFont("fonts\\Inconsolata-g.ttf", 12) orelse {
        const font_error = sdl_ttf.TTF_GetError();
        std.debug.print("Font open failed: {s}\n", .{font_error});
        return error.FontOpenFailed;
    };
    defer sdl_ttf.TTF_CloseFont(inconsolata_font);

    var text_surface_native = sdl_ttf.TTF_RenderText_Shaded(inconsolata_font, "Sample Text!!!", .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .{ .r = 0, .g = 0, .b = 0, .a = 0 });

    const text_surface = sdl.Surface{
        .ptr = @ptrCast(*sdl.c.SDL_Surface, text_surface_native),
    };
    defer text_surface.destroy();

    const text_texture = try sdl.createTextureFromSurface(renderer, text_surface);
    defer text_texture.destroy();

    // const text_rect = sdl.Rectangle{ .x = 0, .y = 0, .width = 200, .height = 100 };

    main_loop: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main_loop,
                else => {},
            }
        }

        try renderer.setColorRGB(0x00, 0x00, 0x00);
        try renderer.clear();

        try renderer.copy(text_texture, sdl.Rectangle{ .x = 0, .y = 0, .width = 200, .height = 25 }, null);
        renderer.present();
    }
}
