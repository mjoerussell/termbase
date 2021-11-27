const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl2");
const sdl_ttf = @import("sdl_ttf.zig");
const Font = sdl_ttf.Font;

const zdb = @import("zdb");

// @todo - Will be modified as things are done/new tasks are required
// * Move cursor with arrow keys
// * Enter characters where cursor is
// * Get cursor to end of line properly when backspacing past newline
// * Figure out why running 2 queries results in FunctionSequenceError
// * Set up arbitrary db connections
// * Multiple modes - text/command/query

const OdbcTestType = struct {
    id: u32,
    name: []const u8,
    occupation: []const u8,
    age: u32,

    fn deinit(self: *OdbcTestType, allocator: *Allocator) void {
        allocator.free(self.name);
        allocator.free(self.occupation);
    }
};

const TextArea = struct {
    buffer: std.ArrayList(u8),
    rect: sdl.Rectangle,
    cursor_pos: sdl.Rectangle,

    fn init(allocator: *Allocator, x: c_int, y: c_int) TextArea {
        return TextArea{
            .buffer = std.ArrayList(u8).init(allocator),
            .rect = sdl.Rectangle{
                .x = x,
                .y = y,
                .width = 0,
                .height = 0,
            },
            .cursor_pos = sdl.Rectangle{
                .x = 0,
                .y = 0,
                // @note This is hardcoded based on the debug font size - should change in the future
                .width = 7,
                .height = 15,
            },
        };
    }

    fn deinit(text_area: *TextArea) void {
        text_area.buffer.deinit();
    }

    fn render(text_area: *TextArea, renderer: sdl.Renderer, font: Font, active: bool) !void {
        const text_dim = try font.drawText(renderer, text_area.buffer.items, text_area.rect.x, text_area.rect.y);
        text_area.rect.width = text_dim.x - text_area.rect.x;
        text_area.rect.height = text_dim.y - text_area.rect.y;

        if (active) {
            try renderer.setColorRGB(255, 255, 255);
            try renderer.fillRect(sdl.Rectangle{
                .x = text_area.rect.x + text_area.cursor_pos.x,
                .y = text_area.rect.y + text_area.cursor_pos.y,
                .width = text_area.cursor_pos.width,
                .height = text_area.cursor_pos.height,
            });
        }
    }

    fn isInside(text_area: TextArea, x: c_int, y: c_int) bool {
        return x >= text_area.rect.x and x <= text_area.rect.x + text_area.rect.width and y >= text_area.rect.y and y <= text_area.rect.y + text_area.rect.height;
    }

    fn moveCursor(text_area: *TextArea, direction: enum { left, right, up, down }) void {
        switch (direction) {
            .left => text_area.cursor_pos.x -= text_area.cursor_pos.width,
            .right => text_area.cursor_pos.x += text_area.cursor_pos.width,
            .up => text_area.cursor_pos.y -= text_area.cursor_pos.height,
            .down => text_area.cursor_pos.y += text_area.cursor_pos.height,
        }
    }

    fn writer(text_area: *TextArea) std.ArrayList(u8).Writer {
        return text_area.buffer.writer();
    }
};

pub fn main() anyerror!void {
    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit();

    const allocator = std.heap.c_allocator;

    var connection_info = try zdb.ConnectionInfo.initWithConfig(allocator, .{ .driver = "PostgreSQL Unicode(x64)", .dsn = "PostgreSQL35W" });
    defer connection_info.deinit();

    const connection_string = try connection_info.toConnectionString(allocator);
    defer allocator.free(connection_string);

    var connection = try zdb.DBConnection.initWithConnectionString(connection_string);
    defer connection.deinit();

    try connection.setCommitMode(.auto);

    var cursor = try connection.getCursor(allocator);
    defer cursor.deinit() catch {};

    var window = try sdl.createWindow("SDL Test", .{ .centered = {} }, .{ .centered = {} }, 640, 480, .{ .shown = true });
    defer window.destroy();

    var renderer = try sdl.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();

    _ = sdl_ttf.TTF_Init();
    defer sdl_ttf.TTF_Quit();

    var font = try sdl_ttf.Font.openFont(renderer, "fonts\\Inconsolata-g.ttf", 12);
    defer font.destroy();

    var text_areas = std.ArrayList(TextArea).init(allocator);
    defer {
        for (text_areas.items) |*ta| ta.deinit();
        text_areas.deinit();
    }

    try text_areas.append(TextArea.init(allocator, 0, 0));

    var mouse_is_held = false;
    var active_text_area: ?*TextArea = &text_areas.items[0];

    main_loop: while (true) {
        event_loop: while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main_loop,
                .text_input => |text_input_ev| {
                    // @note This is a hack, definitely broken
                    if (active_text_area) |ta| {
                        ta.writer().print("{c}", .{text_input_ev.text[0]}) catch {};
                        ta.moveCursor(.right);
                    }
                },
                .mouse_button_down => |mb_ev| {
                    if (mb_ev.button == sdl.c.SDL_BUTTON_LEFT) {
                        if (!mouse_is_held) {
                            mouse_is_held = true;
                            for (text_areas.items) |*ta| {
                                if (ta.isInside(mb_ev.x, mb_ev.y)) {
                                    active_text_area = ta;
                                    continue :event_loop;
                                }
                            }
                            try text_areas.append(TextArea.init(allocator, mb_ev.x, mb_ev.y));
                            active_text_area = &text_areas.items[text_areas.items.len - 1];
                        }
                    }
                },
                .mouse_button_up => {
                    mouse_is_held = false;
                },
                .mouse_motion => |mm_ev| {
                    if (mouse_is_held) {
                        if (active_text_area) |ta| {
                            ta.rect.x += mm_ev.xrel;
                            ta.rect.y += mm_ev.yrel;
                        }
                    }
                },
                .key_down => |key_ev| {
                    if (active_text_area) |ta| {
                        var writer = ta.writer();
                        switch (key_ev.keycode) {
                            .@"return" => {
                                if (key_ev.modifiers.get(.left_control) or key_ev.modifiers.get(.right_control)) {
                                    // @todo Some modification to executeDirect that doesn't need to know the result type when
                                    // running the query. Without that, it's kind of impossible to run arbitrary queries
                                    var result_set = try cursor.executeDirect(OdbcTestType, .{}, ta.buffer.items);
                                    defer result_set.deinit();

                                    try text_areas.append(TextArea.init(allocator, ta.rect.x, ta.rect.y + ta.rect.height));
                                    active_text_area = &text_areas.items[text_areas.items.len - 1];

                                    var result_writer = active_text_area.?.writer();
                                    result_writer.writeAll("id | name | occupation | age\n") catch {};
                                    while (try result_set.next()) |*item| {
                                        result_writer.print("{} | {s} | {s} | {}\n", .{ item.id, item.name, item.occupation, item.age }) catch {};
                                        item.deinit(allocator);
                                    }
                                } else {
                                    writer.writeAll("\n") catch {};
                                    ta.cursor_pos.x = 0;
                                    ta.moveCursor(.down);
                                }
                            },
                            .tab => {
                                writer.writeAll("  ") catch {};
                                ta.moveCursor(.right);
                                ta.moveCursor(.right);
                            },
                            .backspace => {
                                if (ta.buffer.items.len >= 1) {
                                    const old_char = ta.buffer.pop();
                                    ta.moveCursor(.left);
                                    switch (old_char) {
                                        '\n' => {
                                            ta.moveCursor(.up);
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        try renderer.setColorRGB(0x00, 0x00, 0x00);
        try renderer.clear();

        for (text_areas.items) |*ta| {
            try ta.render(renderer, font, ta == active_text_area);
        }

        renderer.present();
    }
}
