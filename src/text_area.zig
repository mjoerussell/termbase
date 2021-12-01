const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl2");

const sdl_ttf = @import("sdl_ttf.zig");
const Font = sdl_ttf.Font;

// @todo Resizable text areas via mouse
// @todo Scrolling text areas?

pub const TextArea = struct {
    // Custom writer that handles writing at the current cursor position and moving the cursor
    // without having to handle that outside of the TextArea context
    pub const Writer = std.io.Writer(*TextArea, error{OutOfMemory}, writeAtCursor);

    buffer: std.ArrayList(u8),
    rect: sdl.Rectangle,

    cursor: sdl.Rectangle,
    cursor_pos: usize,

    child: ?*TextArea = null,

    pub fn init(allocator: Allocator, x: c_int, y: c_int) TextArea {
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

    pub fn deinit(text_area: *TextArea) void {
        text_area.buffer.deinit();
    }

    /// Create a new `TextArea` directly below this current one. Does **not** set this text area's `child`
    /// field to the new text area - that must be done by the caller. 
    pub fn spawnChild(text_area: *TextArea, allocator: Allocator) TextArea {
        return TextArea.init(allocator, text_area.rect.x, text_area.rect.y + text_area.rect.height);
    }

    /// Render the current text area + text content at the current position. The text area will be sized according
    /// to the size of its text.
    pub fn render(text_area: *TextArea, renderer: sdl.Renderer, font: Font, active: bool) !void {
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

        const text_dim = try font.drawText(renderer, text_area.buffer.items, text_area.rect.x + 2, text_area.rect.y + 2);
        text_area.rect.width = text_dim.x - text_area.rect.x + 2;
        text_area.rect.height = text_dim.y - text_area.rect.y + 2;

        if (active) {
            // If this text area is the current active text area, draw the cursor at cursor_pos in the text
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

            // Determine the width of the text between the cursor and the start of the line that the cursor is on
            const text_newline_to_cursor_size = font.sizeText(text_to_cursor[size_start_index..]);
            const cursor_x = text_area.rect.x + text_newline_to_cursor_size.width + text_area.cursor.width;
            const cursor_y = text_area.rect.y + (text_to_cursor_size.height * newline_count_to_cursor) + 2;

            try renderer.fillRect(sdl.Rectangle{
                .x = cursor_x,
                .y = cursor_y,
                .width = text_area.cursor.width,
                .height = text_area.cursor.height,
            });
        }
    }

    /// Determine if the given (x,y) coordinate is inside this text area.
    pub fn isInside(text_area: TextArea, x: c_int, y: c_int) bool {
        return x >= text_area.rect.x and x <= text_area.rect.x + text_area.rect.width and y >= text_area.rect.y and y <= text_area.rect.y + text_area.rect.height;
    }

    /// Try to insert the given bytes at the index indicated by `cursor_pos`.
    pub fn writeAtCursor(text_area: *TextArea, bytes: []const u8) !usize {
        try text_area.buffer.insertSlice(text_area.cursor_pos, bytes);
        text_area.cursor_pos += bytes.len;
        return bytes.len;
    }

    pub fn writer(text_area: *TextArea) Writer {
        return .{ .context = text_area };
    }

    /// Clear the text content.
    pub fn clear(text_area: *TextArea) void {
        text_area.buffer.items.len = 0;
        text_area.cursor_pos = 0;
    }

    /// Moves the cursor one character to the right.
    pub fn moveCursorRight(text_area: *TextArea, span: usize) void {
        if (text_area.buffer.items.len == 0) return;
        text_area.cursor_pos += span;
        if (text_area.cursor_pos > text_area.buffer.items.len) {
            text_area.cursor_pos = text_area.buffer.items.len;
        }
    }

    /// Moves the cursor one character to the left.
    pub fn moveCursorLeft(text_area: *TextArea, span: usize) void {
        if (span > text_area.cursor_pos) {
            text_area.cursor_pos = 0;
        } else {
            text_area.cursor_pos -= span;
        }
    }

    /// Moves the cursor one line up, to a position in that line that is as far to the left as the cursor was
    /// in its original line. If the cursor is already at the first line, do nothing.
    pub fn moveCursorUp(text_area: *TextArea, span: usize) void {
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

    /// Moves the cursor one line down, to a position in that line that is as far to the left as the cursor was
    /// in its original line. If the cursor is already at the last line, do nothing.
    pub fn moveCursorDown(text_area: *TextArea, span: usize) void {
        const current_line_column: usize = blk: {
            var nearest_newline_index: usize = text_area.cursor_pos;
            while (nearest_newline_index >= 0) {
                if (text_area.buffer.items[nearest_newline_index] == '\n') {
                    break :blk text_area.cursor_pos - nearest_newline_index;
                }

                if (nearest_newline_index > 0) {
                    nearest_newline_index -= 1;
                } else {
                    break;
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
