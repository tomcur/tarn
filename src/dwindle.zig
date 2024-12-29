// This is an implementation of a dwindling layout for River. Layouting
// progresses by splitting the available screen space horizontally, then
// splitting the remaining space vertically, then horizontally, etc. The
// dwindle ratio for horizontal and vertical splits can be adjusted separately.
//
// Copyright 2024 Tom Churchman
//
// See https://codeberg.org/river/river.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.
//
// With 5 views, the layout looks something like this:
//
// +-----------------+-----------------+
// |                 |                 |
// |                 |                 |
// |                 |                 |
// |                 |                 |
// |                 |                 |
// |                 |                 |
// |                 +--------+--------+
// |                 |        |        |
// |                 |        |        |
// |                 |        +--------+
// |                 |        |        |
// +-----------------+--------+--------+

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const math = std.math;
const os = std.os;
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const flags = @import("flags");

const usage =
    \\usage: tarn-dwindle [options]
    \\
    \\  -h                 Print this help message and exit.
    \\  -version           Print the version number and exit.
    \\  -view-padding      Set the padding around views in pixels. (Default 6)
    \\  -outer-padding     Set the padding around the edge of the layout area in
    \\                     pixels. (Default 6)
    \\  -horizontal-ratio  Set the dwindle ratio for horizontal splits (Default 0.5)
    \\  -vertical-ratio    Set the dwindle ratio for vertical splits (Default: 0.5)
    \\
;

const Command = enum {
    @"horizontal-ratio",
    @"vertical-ratio",
};

const DwindleAxis = enum {
    vertical,
    horizontal,
};

// Configured through command line options
var view_padding: u31 = 6;
var outer_padding: u31 = 6;
var default_horizontal_ratio: f64 = 0.5;
var default_vertical_ratio: f64 = 0.5;

/// We don't free resources on exit, only when output globals are removed.
const gpa = std.heap.c_allocator;

const Context = struct {
    initialized: bool = false,
    layout_manager: ?*river.LayoutManagerV3 = null,
    outputs: std.TailQueue(Output) = .{},

    fn addOutput(context: *Context, registry: *wl.Registry, name: u32) !void {
        const wl_output = try registry.bind(name, wl.Output, 3);
        errdefer wl_output.release();
        const node = try gpa.create(std.TailQueue(Output).Node);
        errdefer gpa.destroy(node);
        try node.data.init(context, wl_output, name);
        context.outputs.append(node);
    }
};

const Output = struct {
    wl_output: *wl.Output,
    name: u32,

    horizontal_ratio: f64,
    vertical_ratio: f64,

    layout: *river.LayoutV3 = undefined,

    fn init(output: *Output, context: *Context, wl_output: *wl.Output, name: u32) !void {
        output.* = .{
            .wl_output = wl_output,
            .name = name,
            .horizontal_ratio = default_horizontal_ratio,
            .vertical_ratio = default_vertical_ratio,
        };
        if (context.initialized) try output.getLayout(context);
    }

    fn getLayout(output: *Output, context: *Context) !void {
        assert(context.initialized);
        output.layout = try context.layout_manager.?.getLayout(output.wl_output, "tarn-dwindle");
        output.layout.setListener(*Output, layoutListener, output);
    }

    fn deinit(output: *Output) void {
        output.wl_output.release();
        output.layout.destroy();
    }

    fn layoutListener(layout: *river.LayoutV3, event: river.LayoutV3.Event, output: *Output) void {
        switch (event) {
            .namespace_in_use => fatal("namespace 'tarn-dwindle' already in use.", .{}),

            .user_command => |ev| {
                var it = mem.tokenize(u8, mem.span(ev.command), " ");
                const raw_cmd = it.next() orelse {
                    std.log.err("not enough arguments", .{});
                    return;
                };
                const raw_arg = it.next() orelse {
                    std.log.err("not enough arguments", .{});
                    return;
                };
                if (it.next() != null) {
                    std.log.err("too many arguments", .{});
                    return;
                }
                const cmd = std.meta.stringToEnum(Command, raw_cmd) orelse {
                    std.log.err("unknown command: {s}", .{raw_cmd});
                    return;
                };
                switch (cmd) {
                    .@"horizontal-ratio" => {
                        const arg = fmt.parseFloat(f64, raw_arg) catch |err| {
                            std.log.err("failed to parse argument: {}", .{err});
                            return;
                        };
                        switch (raw_arg[0]) {
                            '+', '-' => {
                                output.horizontal_ratio = math.clamp(output.horizontal_ratio + arg, 0.1, 0.9);
                            },
                            else => output.horizontal_ratio = math.clamp(arg, 0.1, 0.9),
                        }
                    },
                    .@"vertical-ratio" => {
                        const arg = fmt.parseFloat(f64, raw_arg) catch |err| {
                            std.log.err("failed to parse argument: {}", .{err});
                            return;
                        };
                        switch (raw_arg[0]) {
                            '+', '-' => {
                                output.vertical_ratio = math.clamp(output.vertical_ratio + arg, 0.1, 0.9);
                            },
                            else => output.vertical_ratio = math.clamp(arg, 0.1, 0.9),
                        }
                    },
                }
            },

            .layout_demand => |ev| {
                assert(ev.view_count > 0);

                const usable_width = saturatingCast(u31, ev.usable_width) -| (2 *| outer_padding);
                const usable_height = saturatingCast(u31, ev.usable_height) -| (2 *| outer_padding);

                const horizontal_ratio: u31 = @intFromFloat(output.horizontal_ratio * 100);
                const vertical_ratio: u31 = @intFromFloat(output.vertical_ratio * 100);

                var xmin: u31 = 0;
                var ymin: u31 = 0;
                var remaining_width: u31 = usable_width;
                var remaining_height: u31 = usable_height;

                var dwindle_axis: DwindleAxis = .horizontal;

                var i: u31 = 0;
                while (i < ev.view_count) : (i += 1) {
                    var width = remaining_width;
                    var height = remaining_height;
                    if (i + 1 < ev.view_count) {
                        switch (dwindle_axis) {
                            .horizontal => {
                                width = remaining_width *| horizontal_ratio / 100 -| view_padding / 2;
                            },
                            .vertical => {
                                height = remaining_height *| vertical_ratio / 100 -| view_padding / 2;
                            },
                        }
                    }

                    layout.pushViewDimensions(
                        xmin +| outer_padding,
                        ymin +| outer_padding,
                        width,
                        height,
                        ev.serial,
                    );

                    switch (dwindle_axis) {
                        .horizontal => {
                            dwindle_axis = .vertical;
                            remaining_width = (remaining_width - width) -| view_padding;
                            xmin +|= width +| view_padding;
                        },
                        .vertical => {
                            dwindle_axis = .horizontal;
                            remaining_height = (remaining_height - height) -| view_padding;
                            ymin +|= height +| view_padding;
                        },
                    }
                }

                layout.commit("tarn-dwindle", ev.serial);
            },
            .user_command_tags => {},
        }
    }
};

pub fn main() !void {
    const result = flags.parser([*:0]const u8, &[_]flags.Flag{
        .{ .name = "h", .kind = .boolean },
        .{ .name = "version", .kind = .boolean },
        .{ .name = "view-padding", .kind = .arg },
        .{ .name = "outer-padding", .kind = .arg },
        .{ .name = "horizontal-ratio", .kind = .arg },
        .{ .name = "vertical-ratio", .kind = .arg },
    }).parse(os.argv[1..]) catch {
        try std.io.getStdErr().writeAll(usage);
        std.process.exit(1);
    };
    if (result.flags.h) {
        try std.io.getStdOut().writeAll(usage);
        std.process.exit(0);
    }
    if (result.args.len != 0) fatalPrintUsage("unknown option '{s}'", .{result.args[0]});

    if (result.flags.version) {
        try std.io.getStdOut().writeAll(@import("build_options").version ++ "\n");
        std.process.exit(0);
    }
    if (result.flags.@"view-padding") |raw| {
        view_padding = fmt.parseUnsigned(u31, raw, 10) catch
            fatalPrintUsage("invalid value '{s}' provided to -view-padding", .{raw});
    }
    if (result.flags.@"outer-padding") |raw| {
        outer_padding = fmt.parseUnsigned(u31, raw, 10) catch
            fatalPrintUsage("invalid value '{s}' provided to -outer-padding", .{raw});
    }
    if (result.flags.@"horizontal-ratio") |raw| {
        default_horizontal_ratio = fmt.parseFloat(f64, raw) catch {
            fatalPrintUsage("invalid value '{s}' provided to -horizontal-ratio", .{raw});
        };
        if (default_horizontal_ratio < 0.1 or default_horizontal_ratio > 0.9) {
            fatalPrintUsage("invalid value '{s}' provided to -horizontal-ratio", .{raw});
        }
    }
    if (result.flags.@"vertical-ratio") |raw| {
        default_vertical_ratio = fmt.parseFloat(f64, raw) catch {
            fatalPrintUsage("invalid value '{s}' provided to -vertical-ratio", .{raw});
        };
        if (default_vertical_ratio < 0.1 or default_vertical_ratio > 0.9) {
            fatalPrintUsage("invalid value '{s}' provided to -vertical-ratio", .{raw});
        }
    }

    const display = wl.Display.connect(null) catch {
        std.debug.print("Unable to connect to Wayland server.\n", .{});
        std.process.exit(1);
    };
    defer display.disconnect();

    var context: Context = .{};

    const registry = try display.getRegistry();
    registry.setListener(*Context, registryListener, &context);
    if (display.roundtrip() != .SUCCESS) fatal("initial roundtrip failed", .{});

    if (context.layout_manager == null) {
        fatal("wayland compositor does not support river-layout-v3.\n", .{});
    }

    context.initialized = true;

    var it = context.outputs.first;
    while (it) |node| : (it = node.next) {
        const output = &node.data;
        try output.getLayout(&context);
    }

    while (true) {
        if (display.dispatch() != .SUCCESS) fatal("failed to dispatch wayland events", .{});
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, river.LayoutManagerV3.interface.name) == .eq) {
                context.layout_manager = registry.bind(global.name, river.LayoutManagerV3, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                context.addOutput(registry, global.name) catch |err| fatal("failed to bind output: {}", .{err});
            }
        },
        .global_remove => |ev| {
            var it = context.outputs.first;
            while (it) |node| : (it = node.next) {
                const output = &node.data;
                if (output.name == ev.name) {
                    context.outputs.remove(node);
                    output.deinit();
                    gpa.destroy(node);
                    break;
                }
            }
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

fn fatalPrintUsage(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.io.getStdErr().writeAll(usage) catch {};
    std.process.exit(1);
}

fn saturatingCast(comptime T: type, x: anytype) T {
    return @max(math.minInt(T), @min(math.maxInt(T), x));
}
