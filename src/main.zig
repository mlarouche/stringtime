const std = @import("std");
const testing = std.testing;

pub const StringTime = struct {
    commands: CommandList,

    pub const CommandKind = union(enum) {
        literal: []const u8,
        substitution: struct {
            variable_name: []const u8,
        },
    };
    pub const CommandList = std.ArrayList(CommandKind);

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, template: []const u8) !Self {
        var result = Self{
            .commands = CommandList.init(allocator),
        };

        try result.parse(template);

        return result;
    }

    pub fn deinit(self: Self) void {
        self.commands.deinit();
    }

    pub fn render(self: Self, allocator: *std.mem.Allocator, context: anytype) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (self.commands.items) |command| {
            switch (command) {
                .literal => |literal| {
                    try result.appendSlice(literal);
                },
                .substitution => |sub| {
                    var found = false;
                    inline for (std.meta.fields(@TypeOf(context))) |field| {
                        if (std.mem.eql(u8, field.name, sub.variable_name)) {
                            const value = @field(context, field.name);
                            try result.appendSlice(value);
                            found = true;
                        }
                    }

                    if (!found) {
                        return error.VariableNameNotFound;
                    }
                },
            }
        }

        return try allocator.dupe(u8, result.items);
    }

    pub fn parse(self: *Self, template: []const u8) !void {
        var start_index: usize = 0;
        var previous_index: usize = 0;

        const State = enum {
            Literal,
            InsideTemplate,
        };

        var state: State = .Literal;

        var it = (try std.unicode.Utf8View.init(template)).iterator();

        while (it.nextCodepointSlice()) |codepoint| {
            switch (state) {
                .Literal => {
                    if (std.mem.eql(u8, codepoint, "{") and std.mem.eql(u8, it.peek(1), "{")) {
                        try self.commands.append(CommandKind{ .literal = template[start_index..previous_index] });
                        _ = it.nextCodepointSlice();
                        start_index = it.i;

                        state = .InsideTemplate;
                    } else {
                        if (it.peek(1).len == 0) {
                            try self.commands.append(CommandKind{ .literal = template[start_index..] });
                        }
                    }
                },
                .InsideTemplate => {
                    if (std.mem.eql(u8, codepoint, "}") and std.mem.eql(u8, it.peek(1), "}")) {
                        try self.commands.append(CommandKind{ .substitution = .{ .variable_name = template[start_index..previous_index] } });
                        _ = it.nextCodepointSlice();
                        start_index = it.i;
                        state = .Literal;
                    }
                },
            }

            previous_index = it.i;
        }
    }
};

test "Parse basic template" {
    const Template = "Hi {{name}}!";

    var template = try StringTime.init(testing.allocator, Template);
    defer template.deinit();

    testing.expectEqual(@as(usize, 3), template.commands.items.len);

    testing.expect(template.commands.items[0] == .literal);
    testing.expect(template.commands.items[1] == .substitution);
    testing.expect(template.commands.items[2] == .literal);

    testing.expectEqualStrings(template.commands.items[0].literal, "Hi ");
    testing.expectEqualStrings(template.commands.items[1].substitution.variable_name, "name");
    testing.expectEqualStrings(template.commands.items[2].literal, "!");
}

test "Basic substitution" {
    const Template = "Hi {{name}}!";

    const Context = struct {
        name: []const u8,
    };

    var context: Context = .{
        .name = "Zig stringtime",
    };

    var template = try StringTime.init(testing.allocator, Template);
    defer template.deinit();

    const result = try template.render(testing.allocator, context);
    defer testing.allocator.free(result);

    testing.expectEqualStrings("Hi Zig stringtime!", result);
}

test "Variable name not found error" {
    const Template = "Hi {{user_name}}!";

    var context = .{
        .name = "Zig stringtime",
    };

    var template = try StringTime.init(testing.allocator, Template);
    defer template.deinit();

    const result = template.render(testing.allocator, context);
    testing.expectError(error.VariableNameNotFound, result);
}

test "Multiple variable substitution" {
    const Template = "Hi {{first_name}} {{last_name}}, welcome to Zig.";

    var context = .{
        .first_name = "Michael",
        .last_name = "Larouche",
    };

    var template = try StringTime.init(testing.allocator, Template);
    defer template.deinit();

    const result = try template.render(testing.allocator, context);
    defer testing.allocator.free(result);

    testing.expectEqualStrings("Hi Michael Larouche, welcome to Zig.", result);
}

test "Multiple renders with different context" {
    const Template = "Hi {{name}}!";

    var first_context = .{
        .name = "Zig stringtime",
    };

    var second_context = .{
        .name = "second context",
        .dummy = "dummy",
        .jump = "true",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const first_result = try parsed_template.render(testing.allocator, first_context);
    defer testing.allocator.free(first_result);
    testing.expectEqualStrings("Hi Zig stringtime!", first_result);

    const second_result = try parsed_template.render(testing.allocator, second_context);
    defer testing.allocator.free(second_result);
    testing.expectEqualStrings("Hi second context!", second_result);
}

test "Render C-style code properly" {
    const Template = "fn {{fn_name}}() { std.log.info(\"Hello World!\"); }";

    var context = .{
        .fn_name = "testFunction",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer testing.allocator.free(result);
    testing.expectEqualStrings("fn testFunction() { std.log.info(\"Hello World!\"); }", result);
}

test "Render unicode aware" {
    const Template = "こんにちは,{{first_name}}！Allô!";

    var context = .{
        .first_name = "Étoilé星ホシ",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer testing.allocator.free(result);
    testing.expectEqualStrings("こんにちは,Étoilé星ホシ！Allô!", result);
}
