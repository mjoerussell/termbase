const std = @import("std");
const sdl = @import("sdl2");
const c = @cImport({
    @cInclude("SDL_ttf.h");
});

pub usingnamespace c;

pub const Font = struct {
    pub const GlyphCount = ('z' - ' ') + 1;

    ptr: *c.TTF_Font,
    texture: sdl.Texture,
    glyphs: [GlyphCount]sdl.Rectangle,

    pub fn openFont(renderer: sdl.Renderer, font_file: []const u8, font_size: u8) !Font {
        const font_texture_size = 512;

        var font: Font = undefined;
        font.ptr = c.TTF_OpenFont(font_file.ptr, font_size) orelse return error.OpenFontFailed;
        font.glyphs = std.mem.zeroes([GlyphCount]sdl.Rectangle);

        var surface = sdl.Surface{
            .ptr = sdl.c.SDL_CreateRGBSurface(0, font_texture_size, font_texture_size, 32, 0, 0, 0, 0xff) orelse return error.CreateSurfaceError,
        };
        defer surface.destroy();

        try surface.setColorKey(sdl.c.SDL_TRUE, sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        var dest_rect = std.mem.zeroes(sdl.Rectangle);

        var char: u8 = ' ';
        while (char <= 'z') : (char += 1) {
            var text_surface = try font.renderUtf8Blended(&.{ char, 0 }, sdl.Color.white);
            defer text_surface.destroy();

            var text_size = font.sizeText(&.{ char, 0 });

            if (dest_rect.x + text_size.width >= font_texture_size) {
                dest_rect.x = 0;
                dest_rect.y += text_size.height + 1;
                if (dest_rect.y + text_size.height >= font_texture_size) {
                    std.log.err("Out of glyph space for texture atlas.", .{});
                    return error.OutOfSpace;
                }
            }

            _ = sdl.c.SDL_BlitSurface(text_surface.ptr, null, surface.ptr, @ptrCast(*sdl.c.SDL_Rect, &dest_rect));

            font.glyphs[char - ' '] = .{
                .x = dest_rect.x,
                .y = dest_rect.y,
                .width = text_size.width,
                .height = text_size.height,
            };

            dest_rect.x += text_size.width;
        }

        font.texture = try sdl.createTextureFromSurface(renderer, surface);
        return font;
    }

    pub fn destroy(font: *Font) void {
        c.TTF_CloseFont(font.ptr);
        font.texture.destroy();
    }

    pub fn drawText(font: Font, renderer: sdl.Renderer, text: []const u8, x: c_int, y: c_int) error{SdlError}!sdl.Rectangle {
        var result_rect = std.mem.zeroes(sdl.Rectangle);
        var render_x = x;
        var render_y = y;
        var previous_glyph = std.mem.zeroes(sdl.Rectangle);
        for (text) |char| {
            if (font.getGlyph(char)) |glyph| {
                var render_dest = sdl.Rectangle{
                    .x = render_x,
                    .y = render_y,
                    .width = glyph.width,
                    .height = glyph.height,
                };

                try renderer.copy(font.texture, render_dest, glyph);
                render_x += glyph.width;
                previous_glyph = glyph;
            } else {
                switch (char) {
                    '\n' => {
                        render_y += previous_glyph.height;
                        render_x = x;
                    },
                    else => {},
                }
            }
            if (render_x > result_rect.x) {
                result_rect.x = render_x;
            }
            if (render_y >= result_rect.y) {
                result_rect.y = render_y + previous_glyph.height;
            }
        }

        return result_rect;
    }

    fn getGlyph(font: Font, character: u8) ?sdl.Rectangle {
        if (character < ' ' or character > 'z') return null;
        return font.glyphs[character - ' '];
    }

    pub fn setTextColor(font: Font, color: sdl.Color) !void {
        try font.texture.setColorMod(color);
    }

    pub fn renderTextShaded(font: *Font, text: []const u8, color: sdl.Color, bg_color: sdl.Color) !sdl.Surface {
        if (c.TTF_RenderText_Shaded(font.ptr, text.ptr, .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a }, .{ .r = bg_color.r, .g = bg_color.g, .b = bg_color.b, .a = bg_color.a })) |surface| {
            return sdl.Surface{ .ptr = @ptrCast(*sdl.c.SDL_Surface, surface) };
        } else {
            return error.RenderFontError;
        }
    }

    pub fn renderUtf8Blended(font: *Font, text: []const u8, color: sdl.Color) !sdl.Surface {
        if (c.TTF_RenderUTF8_Blended(font.ptr, text.ptr, .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a })) |surface| {
            return sdl.Surface{ .ptr = @ptrCast(*sdl.c.SDL_Surface, surface) };
        } else {
            return error.RenderFontError;
        }
    }

    pub fn sizeText(font: *const Font, text: []const u8) sdl.Rectangle {
        var width: c_int = 0;
        var height: c_int = 0;

        _ = c.TTF_SizeText(font.ptr, text.ptr, &width, &height);
        return .{ .x = 0, .y = 0, .width = width, .height = height };
    }
};
