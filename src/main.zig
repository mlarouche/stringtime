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
        var index: usize = 0;

        var start_index: usize = 0;

        var inside_template = false;

        const State = enum {
            Select,
            Literal,
            BeginTemplate,
            InsideTemplate,
            EndTemplate,
        };

        var state: State = .Select;

        while (index < template.len) {
            switch (state) {
                .Select => {
                    if (template[index] == '{') {
                        state = .BeginTemplate;
                    } else {
                        start_index = index;
                        state = .Literal;
                    }
                },
                .Literal => {
                    if (template[index] == '{') {
                        try self.commands.append(CommandKind{ .literal = template[start_index..index] });
                        state = .BeginTemplate;
                    }

                    index += 1;

                    if (index == template.len) {
                        try self.commands.append(CommandKind{ .literal = template[start_index..index] });
                    }
                },
                .BeginTemplate => {
                    if (template[index] == '{') {
                        start_index = index + 1;
                        state = .InsideTemplate;
                    } else {
                        return error.TemplateSyntaxError;
                    }

                    index += 1;
                },
                .InsideTemplate => {
                    if (template[index] == '}') {
                        try self.commands.append(CommandKind{ .substitution = .{ .variable_name = template[start_index..index] } });
                        state = .EndTemplate;
                    }

                    index += 1;
                },
                .EndTemplate => {
                    if (template[index] == '}') {
                        state = .Select;
                    }

                    index += 1;
                },
            }
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
