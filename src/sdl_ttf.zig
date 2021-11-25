const sdl = @import("sdl2");
const c = @cImport({
    @cInclude("SDL_ttf.h");
});

pub usingnamespace c;

pub const Font = struct {
    ptr: *c.TTF_Font,

    pub fn openFont(font_file: []const u8, font_size: u8) !Font {
        var font_ptr = c.TTF_OpenFont(font_file.ptr, font_size) orelse return error.OpenFontFailed;
        return Font{
            .ptr = font_ptr,
        };
    }

    pub fn destroy(font: *Font) void {
        c.TTF_CloseFont(font.ptr);
    }

    pub fn renderTextShaded(font: *Font, text: []const u8, color: sdl.Color, bg_color: sdl.Color) !sdl.Surface {
        if (c.TTF_RenderText_Shaded(font.ptr, text.ptr, .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a }, .{ .r = bg_color.r, .g = bg_color.g, .b = bg_color.b, .a = bg_color.a })) |surface| {
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
