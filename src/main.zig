const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl2");
const sdl_ttf = @import("sdl_ttf.zig");

const zdb = @import("zdb");

const TextArea = @import("text_area.zig").TextArea;

// @todo - Will be modified as things are done/new tasks are required
// * Set up arbitrary db connections
// * Multiple modes - text/command/query
// * Properly space columns
// * Render more glyphs outside of ' ' - 'z' range

pub fn main() anyerror!void {
    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit();

    const allocator = std.heap.c_allocator;

    // @info Change this to update your DB connection info
    var connection_info = try zdb.ConnectionInfo.initWithConfig(allocator, .{ .driver = "PostgreSQL Unicode(x64)", .dsn = "PostgreSQL35W" });
    defer connection_info.deinit();

    const connection_string = try connection_info.toConnectionString(allocator);
    defer allocator.free(connection_string);

    var connection = try zdb.DBConnection.initWithConnectionString(connection_string);
    defer connection.deinit();

    try connection.setCommitMode(.auto);

    var cursor = try connection.getCursor(allocator);

    var window = try sdl.createWindow("Termbase", .{ .centered = {} }, .{ .centered = {} }, 720, 480, .{ .shown = true, .resizable = true });
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
                            // On a left click, if the button is not being held, active a text area or create a new text area if the
                            // mouse is not hovering over any existing text area
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
                        // When dragging the mouse, move the current active text area to a new position
                        // @fixme Creating a new text area, not releasing the mouse button, and dragging seems to create a
                        //        bunch of text areas that eventually black out the screen.
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
                                if (!key_ev.modifiers.get(.left_control) and !key_ev.modifiers.get(.right_control)) {
                                    // Handle regular enter => input newline
                                    writer.writeAll("\n") catch {};
                                    continue;
                                }

                                // Handle Ctrl+Enter => Evaluate cell
                                defer cursor.close() catch {};

                                if (ta.child) |result_ta| {
                                    active_text_area = result_ta;
                                    active_text_area.?.clear();
                                } else {
                                    var child_ta = ta.spawnChild(allocator);
                                    try text_areas.append(child_ta);
                                    active_text_area = &text_areas.items[text_areas.items.len - 1];
                                    ta.child = active_text_area;
                                }

                                var result_writer = active_text_area.?.writer();

                                var result_set = cursor.executeDirect(ta.buffer.items, .{}) catch {
                                    const diag_recs = cursor.getErrors();
                                    defer cursor.allocator.free(diag_recs);

                                    for (diag_recs) |*rec, rec_index| {
                                        result_writer.writeAll(rec.error_message) catch {};
                                        if (rec_index < diag_recs.len - 1) {
                                            result_writer.writeAll("\n") catch {};
                                        }
                                        rec.deinit(cursor.allocator);
                                    }
                                    continue;
                                };

                                var row_iter = try result_set.rowIterator();
                                defer row_iter.deinit();

                                var first_row = true;
                                while (true) {
                                    var next_row = row_iter.next() catch continue;
                                    var row = next_row orelse break;

                                    if (first_row) {
                                        // First time around, print the column headings
                                        for (row.columns) |column, column_index| {
                                            result_writer.print("{s}", .{column.name}) catch {};
                                            if (column_index == row.columns.len - 1) {
                                                result_writer.writeAll("\n") catch {};
                                            } else {
                                                result_writer.writeAll(" | ") catch {};
                                            }
                                        }
                                        first_row = false;
                                    }

                                    var column_index: usize = 1;
                                    while (column_index <= row.columns.len) : (column_index += 1) {
                                        row.printColumnAtIndex(column_index, .{}, result_writer) catch {};
                                        if (column_index == row.columns.len) {
                                            result_writer.writeAll("\n") catch {};
                                        } else {
                                            result_writer.writeAll(" | ") catch {};
                                        }
                                    }
                                }
                            },
                            .tab => {
                                if (key_ev.modifiers.get(.left_control) or key_ev.modifiers.get(.right_control)) {
                                    if (key_ev.modifiers.get(.left_shift) or key_ev.modifiers.get(.right_shift)) {
                                        // Handle Ctrl+Shift+Tab => navigate to cell parent
                                        for (text_areas.items) |*other_ta| {
                                            if (other_ta.child != null and other_ta.child.? == ta) {
                                                active_text_area = other_ta;
                                            }
                                        }
                                    } else {
                                        // Handle Ctrl+Tab => navigate to cell child
                                        if (ta.child) |child| {
                                            active_text_area = child;
                                        }
                                    }
                                } else {
                                    // Handle regular tab => input 2 spaces @todo Make configurable (?)
                                    writer.writeAll("  ") catch {};
                                }
                            },
                            .d => {
                                if (key_ev.modifiers.get(.left_control) or key_ev.modifiers.get(.right_control)) {
                                    // Handle Ctrl+D => Duplicate cell
                                    var ta_dup = TextArea.init(allocator, ta.rect.x + ta.rect.width + 10, ta.rect.y);
                                    ta_dup.writer().writeAll(ta.buffer.items) catch {};

                                    try text_areas.append(ta_dup);
                                    active_text_area = &text_areas.items[text_areas.items.len - 1];
                                }
                            },
                            .backspace => {
                                if (ta.buffer.items.len >= 1) {
                                    if (ta.cursor_pos == ta.buffer.items.len) {
                                        _ = ta.buffer.pop();
                                        ta.cursor_pos -= 1;
                                    } else if (ta.cursor_pos != 0) {
                                        _ = ta.buffer.orderedRemove(ta.cursor_pos - 1);
                                        ta.cursor_pos -= 1;
                                    }
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
