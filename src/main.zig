const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl2");
const sdl_ttf = @import("sdl_ttf.zig");
const Font = sdl_ttf.Font;

const zdb = @import("zdb");

// @todo - Will be modified as things are done/new tasks are required
// * Move cursor with arrow keys
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
    // Custom writer that handles writing at the current cursor position and moving the cursor
    // without having to handle that outside of the TextArea context
    const Writer = std.io.Writer(*TextArea, error{OutOfMemory}, writeAtCursor);

    buffer: std.ArrayList(u8),
    rect: sdl.Rectangle,

    cursor: sdl.Rectangle,
    cursor_pos: usize,

    fn init(allocator: *Allocator, x: c_int, y: c_int) TextArea {
        return TextArea{
            .buffer = std.ArrayList(u8).init(allocator),
            .rect = sdl.Rectangle{
                .x = x,
                .y = y,
                .width = 0,
                .height = 0,
            },
            .cursor = sdl.Rectangle{
                .x = 0,
                .y = 0,
                // @note This is hardcoded based on the debug font size - should change in the future
                .width = 7,
                .height = 15,
            },
            .cursor_pos = 0,
        };
    }

    fn deinit(text_area: *TextArea) void {
        text_area.buffer.deinit();
    }

    fn render(text_area: *TextArea, renderer: sdl.Renderer, font: Font, active: bool) !void {
        try renderer.setColorRGBA(255, 255, 255, 255);

        try renderer.fillRect(text_area.rect);

        const inner_rect = sdl.Rectangle{
            .x = text_area.rect.x + 2,
            .y = text_area.rect.y + 2,
            .width = text_area.rect.width - 4,
            .height = text_area.rect.height - 4,
        };

        try renderer.setColorRGBA(0, 0, 0, 0);
        try renderer.fillRect(inner_rect);

        try renderer.setColorRGBA(255, 255, 255, 255);

        const text_dim = try font.drawText(renderer, text_area.buffer.items, text_area.rect.x + 1, text_area.rect.y + 1);
        text_area.rect.width = text_dim.x - text_area.rect.x + 2;
        text_area.rect.height = text_dim.y - text_area.rect.y + 2;

        if (active) {
            const text_to_cursor = text_area.buffer.items[0..text_area.cursor_pos];
            const text_to_cursor_size = font.sizeText(text_to_cursor);

            var newline_count_to_cursor: c_int = 0;
            var last_newline_index: usize = 0;
            for (text_to_cursor) |char, char_index| {
                if (char == '\n') {
                    last_newline_index = char_index;
                    newline_count_to_cursor += 1;
                }
            }

            const size_start_index = if (text_area.buffer.items.len > 0 and last_newline_index < text_area.buffer.items.len - 1)
                last_newline_index + 1
            else
                last_newline_index;

            const text_newline_to_cursor_size = font.sizeText(text_to_cursor[size_start_index..]);
            const cursor_x = text_area.rect.x + text_newline_to_cursor_size.width;
            const cursor_y = text_area.rect.y + (text_to_cursor_size.height * newline_count_to_cursor);

            try renderer.setColorRGBA(255, 255, 255, 255);
            try renderer.fillRect(sdl.Rectangle{
                .x = cursor_x,
                .y = cursor_y,
                .width = text_area.cursor.width,
                .height = text_area.cursor.height,
            });
        }
    }

    fn isInside(text_area: TextArea, x: c_int, y: c_int) bool {
        return x >= text_area.rect.x and x <= text_area.rect.x + text_area.rect.width and y >= text_area.rect.y and y <= text_area.rect.y + text_area.rect.height;
    }

    fn writeAtCursor(text_area: *TextArea, bytes: []const u8) !usize {
        try text_area.buffer.insertSlice(text_area.cursor_pos, bytes);
        text_area.cursor_pos += bytes.len;
        return bytes.len;
    }

    fn writer(text_area: *TextArea) Writer {
        return .{ .context = text_area };
    }

    fn moveCursorRight(text_area: *TextArea, span: usize) void {
        if (text_area.buffer.items.len == 0) return;
        text_area.cursor_pos += span;
        if (text_area.cursor_pos >= text_area.buffer.items.len) {
            text_area.cursor_pos = text_area.buffer.items.len - 1;
        }
    }

    fn moveCursorLeft(text_area: *TextArea, span: usize) void {
        if (span > text_area.cursor_pos) {
            text_area.cursor_pos = 0;
        } else {
            text_area.cursor_pos -= span;
        }
    }

    fn moveCursorUp(text_area: *TextArea, span: usize) void {
        var char_index: usize = text_area.cursor_pos;
        if (char_index == text_area.buffer.items.len) {
            char_index -= 1;
        }

        var newlines_seen: usize = 0;
        var current_line_column: usize = 0;
        while (char_index > 0) : (char_index -= 1) {
            if (text_area.buffer.items[char_index] == '\n') {
                if (newlines_seen == 0) {
                    current_line_column = text_area.cursor_pos - char_index;
                }
                newlines_seen += 1;
                if (newlines_seen == span + 1) {
                    text_area.cursor_pos = char_index + current_line_column;
                    return;
                }
            }
        }

        text_area.cursor_pos = current_line_column;
    }

    fn moveCursorDown(text_area: *TextArea, span: usize) void {
        const current_line_column: usize = blk: {
            var nearest_newline_index: usize = text_area.cursor_pos;
            while (nearest_newline_index >= 0) : (nearest_newline_index -= 1) {
                if (text_area.buffer.items[nearest_newline_index] == '\n') {
                    break :blk text_area.cursor_pos - nearest_newline_index;
                }
            }

            break :blk text_area.cursor_pos;
        };

        var newlines_seen: usize = 0;
        var char_index: usize = text_area.cursor_pos;
        while (char_index < text_area.buffer.items.len) : (char_index += 1) {
            if (text_area.buffer.items[char_index] == '\n') {
                newlines_seen += 1;
                if (newlines_seen == span) {
                    text_area.cursor_pos = char_index + current_line_column;
                    if (text_area.cursor_pos >= text_area.buffer.items.len) {
                        text_area.cursor_pos = text_area.buffer.items.len - 1;
                    }
                    return;
                }
            }
        }

        text_area.cursor_pos = text_area.buffer.items.len - 1;
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

    var window = try sdl.createWindow("Termbase", .{ .centered = {} }, .{ .centered = {} }, 640, 480, .{ .shown = true });
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
                        ta.writer().writeAll(&.{text_input_ev.text[0]}) catch {};
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
                                }
                            },
                            .tab => {
                                writer.writeAll("  ") catch {};
                            },
                            .backspace => {
                                if (ta.buffer.items.len >= 1) {
                                    ta.cursor_pos -= 1;
                                    _ = ta.buffer.pop();
                                }
                            },
                            .left => ta.moveCursorLeft(1),
                            .right => ta.moveCursorRight(1),
                            .up => ta.moveCursorUp(1),
                            .down => ta.moveCursorDown(1),
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
