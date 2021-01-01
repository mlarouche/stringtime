const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringTime = struct {
    commands: CommandList,

    const CommandKind = union(enum) {
        literal: []const u8,
        substitution: struct {
            variable_name: []const u8,
        },
        for_range: struct {
            times: usize,
            command_list: CommandList,
            index_name: ?[]const u8 = null,

            pub fn deinit(self: @This()) void {
                self.command_list.deinit();
            }
        },
        foreach: struct {
            list_name: []const u8,
            item_name: []const u8,
            index_name: ?[]const u8 = null,
            command_list: CommandList,

            pub fn deinit(self: @This()) void {
                self.command_list.deinit();
            }
        },

        pub fn deinit(self: @This()) void {
            switch (self) {
                .for_range => |for_range| for_range.deinit(),
                .foreach => |foreach| foreach.deinit(),
                else => {},
            }
        }
    };
    const CommandList = std.ArrayList(CommandKind);

    const ExecutionContext = struct {
        index_name: ?[]const u8 = null,
        item_name: ?[]const u8 = null,
        list_name: ?[]const u8 = null,
        current_index: usize = 0,
    };

    const Self = @This();

    pub fn init(allocator: *Allocator, template: []const u8) !Self {
        var result = Self{
            .commands = CommandList.init(allocator),
        };
        errdefer result.deinit();

        try result.parse(allocator, template);

        return result;
    }

    pub fn deinit(self: Self) void {
        for (self.commands.items) |command| {
            command.deinit();
        }
        self.commands.deinit();
    }

    pub fn render(self: Self, allocator: *Allocator, context: anytype) !StringBuffer {
        var result = StringBuffer.init(allocator);
        errdefer result.deinit();

        var exec_context: ExecutionContext = .{};

        try processCommand(self.commands, &result, &exec_context, context);

        return result;
    }

    fn processCommand(command_list: CommandList, result: *StringBuffer, exec_context: *ExecutionContext, context: anytype) !void {
        const ValuePrint = struct {
            fn print(value: anytype, result_buffer: *StringBuffer) !void {
                switch (@typeInfo(@TypeOf(value))) {
                    .Int => |int_info| {
                        try std.fmt.formatInt(value, 10, false, .{}, result_buffer.writer());
                    },
                    .Array => {},
                    else => {
                        try result_buffer.appendSlice(value);
                    },
                }
            }

            fn findValue(field_name: []const u8) anytype {
                inline for (std.meta.fields(@TypeOf(context))) |field| {
                    if (std.mem.eql(u8, field.name, sub.variable_name)) {
                        return @field(context, field.name);
                    }
                }

                return null;
            }
        };

        for (command_list.items) |command| {
            switch (command) {
                .literal => |literal| {
                    try result.appendSlice(literal);
                },
                .substitution => |sub| {
                    const test_Value = ValuePrint.findValue(sub.variable_name);
                    try ValuePrint.print(test_value, result);

                    // var found = false;
                    // inline for (std.meta.fields(@TypeOf(context))) |field| {
                    //     if (std.mem.eql(u8, field.name, sub.variable_name)) {
                    //         const value = @field(context, field.name);

                    //         try ValuePrint.print(value, result);

                    //         found = true;
                    //     }

                    //     if (exec_context.list_name) |list_name| {
                    //         if (exec_context.item_name) |item_name| {
                    //             if (std.mem.eql(u8, sub.variable_name, item_name)) {
                    //                 if (std.mem.eql(u8, field.name, list_name)) {
                    //                     if (@typeInfo(field.field_type) == .Array) {
                    //                         const list_instance = @field(context, field.name);
                    //                         const list_value = list_instance[exec_context.current_index];

                    //                         try ValuePrint.print(list_value, result);

                    //                         found = true;
                    //                     }
                    //                 }
                    //             }
                    //         }
                    //     }
                    // }

                    if (exec_context.index_name) |index_name| {
                        if (std.mem.eql(u8, sub.variable_name, index_name)) {
                            try std.fmt.formatInt(exec_context.current_index, 10, false, .{}, result.writer());
                            found = true;
                        }
                    }

                    if (!found) {
                        return error.VariableNameNotFound;
                    }
                },
                .for_range => |for_range| {
                    var count: usize = 0;
                    var for_exec_context: ExecutionContext = .{
                        .index_name = for_range.index_name,
                    };

                    while (count < for_range.times) : (count += 1) {
                        for_exec_context.current_index = count;

                        // TODO: Remove that catch unreachable workaround
                        processCommand(for_range.command_list, result, &for_exec_context, context) catch unreachable;
                    }
                },
                .foreach => |foreach| {
                    var count: usize = 0;
                    var for_exec_context: ExecutionContext = .{
                        .item_name = foreach.item_name,
                        .index_name = foreach.index_name,
                        .list_name = foreach.list_name,
                    };

                    inline for (std.meta.fields(@TypeOf(context))) |field| {
                        if (std.mem.eql(u8, field.name, foreach.list_name)) {
                            if (@typeInfo(field.field_type) == .Array) {
                                const list_instance = @field(context, field.name);

                                while (count < list_instance.len) : (count += 1) {
                                    for_exec_context.current_index = count;

                                    // TODO: Remove that catch unreachable workaround
                                    processCommand(foreach.command_list, result, &for_exec_context, context) catch unreachable;
                                }
                            }
                        }
                    }
                },
            }
        }
    }

    fn parse(self: *Self, allocator: *Allocator, template: []const u8) !void {
        var start_index: usize = 0;
        var previous_index: usize = 0;

        const State = enum {
            Literal,
            InsideTemplate,
        };

        var command_stack = std.ArrayList(*CommandList).init(allocator);
        defer command_stack.deinit();

        try command_stack.append(&self.commands);

        var state: State = .Literal;

        var it = (try std.unicode.Utf8View.init(template)).iterator();

        while (it.peek(1).len != 0) {
            switch (state) {
                .Literal => {
                    var codepoint = it.nextCodepointSlice().?;

                    if (std.mem.eql(u8, codepoint, "{") and std.mem.eql(u8, it.peek(1), "{")) {
                        try command_stack.items[command_stack.items.len - 1].append(CommandKind{ .literal = template[start_index..previous_index] });
                        _ = it.nextCodepointSlice();
                        start_index = it.i;

                        state = .InsideTemplate;
                    } else if (std.mem.eql(u8, codepoint, "}") and std.mem.eql(u8, it.peek(1), "}")) {
                        return error.MismatchedTemplateDelimiter;
                    } else {
                        if (it.peek(1).len == 0) {
                            try command_stack.items[command_stack.items.len - 1].append(CommandKind{ .literal = template[start_index..] });
                        }
                    }
                },
                .InsideTemplate => {
                    var parser = Parser.initFromIterator(allocator, it);

                    var expression_opt = try parser.parse();

                    if (expression_opt) |expression| {
                        defer expression.deinit();

                        switch (expression) {
                            .field_qualifier => |var_name| {
                                try command_stack.items[command_stack.items.len - 1].append(CommandKind{ .substitution = .{ .variable_name = var_name } });
                            },
                            .for_loop => |for_expression| {
                                switch (for_expression.expression) {
                                    .field_qualifier => |field| {
                                        if (for_expression.variable_captures.items.len < 0) {
                                            return error.NoItemVariableCapture;
                                        }

                                        var new_command = CommandKind{
                                            .foreach = .{
                                                .list_name = field,
                                                .item_name = for_expression.variable_captures.items[0],
                                                .command_list = CommandList.init(allocator),
                                            },
                                        };

                                        if (for_expression.variable_captures.items.len > 1) {
                                            new_command.foreach.index_name = for_expression.variable_captures.items[1];
                                        }

                                        try command_stack.items[command_stack.items.len - 1].append(new_command);

                                        const command_stack_top = &command_stack.items[command_stack.items.len - 1];
                                        try command_stack.append(&command_stack_top.*.items[command_stack_top.*.items.len - 1].foreach.command_list);
                                    },
                                    .range => |range| {
                                        const times = range.end - range.start;

                                        var new_command = CommandKind{ .for_range = .{ .times = times, .command_list = CommandList.init(allocator) } };

                                        if (for_expression.variable_captures.items.len > 0) {
                                            new_command.for_range.index_name = for_expression.variable_captures.items[0];
                                        }

                                        try command_stack.items[command_stack.items.len - 1].append(new_command);

                                        const command_stack_top = &command_stack.items[command_stack.items.len - 1];
                                        try command_stack.append(&command_stack_top.*.items[command_stack_top.*.items.len - 1].for_range.command_list);
                                    },
                                }
                            },
                            .end => {
                                _ = command_stack.popOrNull();
                            },
                        }
                    }

                    it = parser.lexer.it;
                    start_index = it.i;
                    state = .Literal;
                },
            }

            previous_index = it.i;
        }
    }
};

pub const Lexer = struct {
    it: std.unicode.Utf8Iterator,

    pub const Token = union(enum) {
        comma: void,
        end: void,
        end_template: void,
        for_loop: void,
        identifier: []const u8,
        left_paren: void,
        number: usize,
        range: void,
        right_paren: void,
        vertical_line: void,
    };

    const Self = @This();

    const Keywords = [_]struct {
        keyword: []const u8,
        token: Token,
    }{
        .{
            .keyword = "for",
            .token = Token.for_loop,
        },
        .{
            .keyword = "end",
            .token = Token.end,
        },
    };

    pub fn init(input: []const u8) !Self {
        return Self{
            .it = (try std.unicode.Utf8View.init(input)).iterator(),
        };
    }

    pub fn initFromIterator(it: std.unicode.Utf8Iterator) Self {
        return Self{
            .it = it,
        };
    }

    pub fn next(self: *Self) !?Token {
        // Eat whitespace
        var codepoint = self.it.peek(1);
        while (codepoint.len == 1 and std.ascii.isSpace(codepoint[0])) {
            _ = self.it.nextCodepointSlice();
            codepoint = self.it.peek(1);
        }

        if (std.mem.eql(u8, codepoint, "(")) {
            _ = self.it.nextCodepointSlice();
            return Token.left_paren;
        } else if (std.mem.eql(u8, codepoint, ")")) {
            _ = self.it.nextCodepointSlice();
            return Token.right_paren;
        } else if (std.mem.eql(u8, codepoint, "|")) {
            _ = self.it.nextCodepointSlice();
            return Token.vertical_line;
        } else if (std.mem.eql(u8, codepoint, ",")) {
            _ = self.it.nextCodepointSlice();
            return Token.comma;
        } else if (std.mem.eql(u8, codepoint, ".")) {
            var peek_codepoint = self.it.peek(2);
            if (std.mem.eql(u8, peek_codepoint, "..")) {
                _ = self.it.nextCodepointSlice();
                _ = self.it.nextCodepointSlice();
                return Token.range;
            } else {
                return error.InvalidToken;
            }
        } else if (std.mem.eql(u8, codepoint, "}")) {
            var peek_codepoint = self.it.peek(2);
            if (std.mem.eql(u8, peek_codepoint, "}}")) {
                _ = self.it.nextCodepointSlice();
                _ = self.it.nextCodepointSlice();
                return Token.end_template;
            } else {
                return error.MismatchedTemplateDelimiter;
            }
        } else if (codepoint.len == 1 and std.ascii.isDigit(codepoint[0])) {
            var start_index: usize = self.it.i;

            _ = self.it.nextCodepointSlice();

            var number_codepoint = self.it.peek(1);
            while (number_codepoint.len == 1 and std.ascii.isDigit(number_codepoint[0])) {
                _ = self.it.nextCodepointSlice();
                number_codepoint = self.it.peek(1);
            }

            var number_string = self.it.bytes[start_index..self.it.i];

            var parsed_number: usize = try std.fmt.parseInt(usize, number_string, 10);

            return Token{ .number = parsed_number };
        } else if (codepoint.len == 1 and (std.ascii.isAlpha(codepoint[0]) or codepoint[0] == '_')) {
            var start_index: usize = self.it.i;

            _ = self.it.nextCodepointSlice();

            var identifier_codepoint = self.it.peek(1);
            while (identifier_codepoint.len == 1 and (std.ascii.isAlNum(identifier_codepoint[0]) or identifier_codepoint[0] == '_')) {
                _ = self.it.nextCodepointSlice();
                identifier_codepoint = self.it.peek(1);
            }

            var identifier_string = self.it.bytes[start_index..self.it.i];

            for (Keywords) |keyword| {
                if (std.mem.eql(u8, keyword.keyword, identifier_string)) {
                    return keyword.token;
                }
            }

            return Token{ .identifier = identifier_string };
        } else if (codepoint.len == 1) {
            return error.InvalidToken;
        }

        return null;
    }

    pub fn peek(self: *Self, look_ahead: usize) !?Token {
        var backup_it = self.it;
        defer {
            self.it = backup_it;
        }

        var peek_token: ?Token = null;

        var count: usize = 0;
        while (count < look_ahead) : (count += 1) {
            peek_token = try self.next();
        }

        return peek_token;
    }
};

pub const Parser = struct {
    lexer: Lexer,
    allocator: *Allocator,

    const Expression = union(enum) {
        end: bool,
        field_qualifier: []const u8,
        for_loop: struct {
            expression: ForExpression,
            variable_captures: std.ArrayList([]const u8),
        },

        pub fn deinit(self: @This()) void {
            switch (self) {
                .for_loop => |for_loop| {
                    for_loop.variable_captures.deinit();
                },
                else => {},
            }
        }
    };

    const ForExpression = union(enum) {
        field_qualifier: []const u8,
        range: struct {
            start: usize,
            end: usize,
        },
    };

    const Self = @This();

    pub fn init(allocator: *Allocator, input: []const u8) !Self {
        return Self{
            .lexer = try Lexer.init(input),
            .allocator = allocator,
        };
    }

    pub fn initFromIterator(allocator: *Allocator, it: std.unicode.Utf8Iterator) Self {
        return Self{
            .lexer = Lexer.initFromIterator(it),
            .allocator = allocator,
        };
    }

    // Inside template grammar
    //IDENTIFIER: [_a-zA-Z][0-9a-zA-Z_]+;
    //NUMBER: [0-9]+
    //
    //root: expression '}}'
    //    ;
    //
    //expression: field_qualifier
    //    | 'for' '(' for_expression ')' ('|' IDENTIFIER (',' IDENTIFIER)* '|' )
    //    | 'end'
    //    ;
    //
    //field_qualifier:
    //    IDENTIFIER ('.' IDENTIFIER)*
    //    ;
    //
    //for_expression: field_qualifier
    //    | NUMBER..NUMBER
    //    ;
    pub fn parse(self: *Self) !?Expression {
        var peek_token_opt = try self.lexer.peek(1);

        var expression: ?Expression = null;
        if (peek_token_opt) |peek_token| {
            switch (peek_token) {
                .identifier => {
                    if (try self.lexer.next()) |token| {
                        expression = Expression{ .field_qualifier = token.identifier };
                    }
                },
                .end => {
                    _ = try self.lexer.next();
                    expression = Expression{ .end = true };
                },
                .for_loop => {
                    expression = try self.parseForLoop();
                },
                else => {
                    return error.InvalidToken;
                },
            }

            if (try self.lexer.next()) |next_token| {
                if (next_token != .end_template) {
                    return error.MismatchedTemplateDelimiter;
                }
            } else {
                return error.MismatchedTemplateDelimiter;
            }
        }

        return expression;
    }

    fn parseForLoop(self: *Self) !?Expression {
        // Eat for token
        _ = try self.lexer.next();

        // Eat left paren
        if (try self.lexer.peek(1)) |peek| {
            if (peek != .left_paren) {
                return error.ParseError;
            }
            _ = try self.lexer.next();
        }

        var inner_expression = try self.parseForExpression();

        // Eat right paren
        if (try self.lexer.peek(1)) |peek| {
            if (peek != .right_paren) {
                return error.ParseError;
            }
            _ = try self.lexer.next();
        }

        var variable_captures = std.ArrayList([]const u8).init(self.allocator);
        errdefer variable_captures.deinit();

        // Check if the variable capture section is present
        if (try self.lexer.peek(1)) |peek| {
            if (peek == .vertical_line) {
                _ = try self.lexer.next();

                var peek2 = try self.lexer.peek(1);

                while (peek2 != null and peek2.? != .vertical_line) {
                    if (peek2.? != .identifier) {
                        return error.ParseError;
                    }

                    if (try self.lexer.next()) |token| {
                        try variable_captures.append(token.identifier);
                    }

                    if (try self.lexer.peek(1)) |peek3| {
                        if (peek3 == .comma) {
                            _ = try self.lexer.next();
                        }
                    }

                    peek2 = try self.lexer.peek(1);
                }

                if (peek2 != null and peek2.? == .vertical_line) {
                    _ = try self.lexer.next();
                }
            }
        }

        if (inner_expression) |inner| {
            return Expression{
                .for_loop = .{
                    .expression = inner,
                    .variable_captures = variable_captures,
                },
            };
        }

        return null;
    }

    fn parseForExpression(self: *Self) !?ForExpression {
        var peek_token_opt = try self.lexer.peek(1);

        if (peek_token_opt) |peek_token| {
            switch (peek_token) {
                .identifier => {
                    if (try self.lexer.next()) |token| {
                        return ForExpression{ .field_qualifier = token.identifier };
                    }
                },
                .number => {
                    var start: usize = 0;
                    var end: usize = 0;

                    if (try self.lexer.next()) |token| {
                        start = token.number;
                    }

                    if (try self.lexer.peek(1)) |peek| {
                        if (peek != .range) {
                            return error.ParseError;
                        }
                        _ = try self.lexer.next();
                    }

                    if (try self.lexer.peek(1)) |peek| {
                        if (peek != .number) {
                            return error.ParseError;
                        }
                        if (try self.lexer.next()) |token| {
                            end = token.number;
                        }
                    }

                    return ForExpression{
                        .range = .{
                            .start = start,
                            .end = end,
                        },
                    };
                },
                else => {
                    return error.ParseError;
                },
            }
        }

        return null;
    }
};

// Copy of std.ArrayList for now, with items renamed to str.
// In the future, maybe it will a more optimized data structure for mutable string buffer
pub const StringBuffer = struct {
    const Self = @This();

    /// Content of the string buffer
    str: Slice,
    capacity: usize,
    allocator: *Allocator,

    pub const Slice = []u8;
    pub const SliceConst = []const u8;

    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn init(allocator: *Allocator) Self {
        return Self{
            .str = &[_]u8{},
            .capacity = 0,
            .allocator = allocator,
        };
    }

    /// Initialize with capacity to hold at least num elements.
    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn initCapacity(allocator: *Allocator, num: usize) !Self {
        var self = Self.init(allocator);

        const new_memory = try self.allocator.allocAdvanced(u8, alignment, num, .at_least);
        self.str.ptr = new_memory.ptr;
        self.capacity = new_memory.len;

        return self;
    }

    /// Release all allocated memory.
    pub fn deinit(self: Self) void {
        self.allocator.free(self.allocatedSlice());
    }

    /// ArrayList takes ownership of the passed in slice. The slice must have been
    /// allocated with `allocator`.
    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn fromOwnedSlice(allocator: *Allocator, slice: Slice) Self {
        return Self{
            .str = slice,
            .capacity = slice.len,
            .allocator = allocator,
        };
    }

    /// The caller owns the returned memory. ArrayList becomes empty.
    pub fn toOwnedSlice(self: *Self) Slice {
        const allocator = self.allocator;
        const result = allocator.shrink(self.allocatedSlice(), self.str.len);
        self.* = init(allocator);
        return result;
    }

    /// The caller owns the returned memory. ArrayList becomes empty.
    pub fn toOwnedSliceSentinel(self: *Self, comptime sentinel: u8) ![:sentinel]u8 {
        try self.append(sentinel);
        const result = self.toOwnedSlice();
        return result[0 .. result.len - 1 :sentinel];
    }

    /// Insert `item` at index `n` by moving `list[n .. list.len]` to make room.
    /// This operation is O(N).
    pub fn insert(self: *Self, n: usize, item: u8) !void {
        try self.ensureCapacity(self.str.len + 1);
        self.str.len += 1;

        mem.copyBackwards(u8, self.str[n + 1 .. self.str.len], self.str[n .. self.str.len - 1]);
        self.str[n] = item;
    }

    /// Insert slice `str` at index `i` by moving `list[i .. list.len]` to make room.
    /// This operation is O(N).
    pub fn insertSlice(self: *Self, i: usize, str: SliceConst) !void {
        try self.ensureCapacity(self.str.len + str.len);
        self.str.len += str.len;

        mem.copyBackwards(u8, self.str[i + str.len .. self.str.len], self.str[i .. self.str.len - str.len]);
        mem.copy(u8, self.str[i .. i + str.len], str);
    }

    /// Replace range of elements `list[start..start+len]` with `new_items`
    /// grows list if `len < new_items.len`. may allocate
    /// shrinks list if `len > new_items.len`
    pub fn replaceRange(self: *Self, start: usize, len: usize, new_items: SliceConst) !void {
        const after_range = start + len;
        const range = self.str[start..after_range];

        if (range.len == new_items.len)
            mem.copy(u8, range, new_items)
        else if (range.len < new_items.len) {
            const first = new_items[0..range.len];
            const rest = new_items[range.len..];

            mem.copy(u8, range, first);
            try self.insertSlice(after_range, rest);
        } else {
            mem.copy(u8, range, new_items);
            const after_subrange = start + new_items.len;

            for (self.str[after_range..]) |item, i| {
                self.str[after_subrange..][i] = item;
            }

            self.str.len -= len - new_items.len;
        }
    }

    /// Extend the list by 1 element. Allocates more memory as necessary.
    pub fn append(self: *Self, item: u8) !void {
        const new_item_ptr = try self.addOne();
        new_item_ptr.* = item;
    }

    /// Extend the list by 1 element, but asserting `self.capacity`
    /// is sufficient to hold an additional item.
    pub fn appendAssumeCapacity(self: *Self, item: u8) void {
        const new_item_ptr = self.addOneAssumeCapacity();
        new_item_ptr.* = item;
    }

    /// Remove the element at index `i` from the list and return its value.
    /// Asserts the array has at least one item.
    /// This operation is O(N).
    pub fn orderedRemove(self: *Self, i: usize) u8 {
        const newlen = self.str.len - 1;
        if (newlen == i) return self.pop();

        const old_item = self.str[i];
        for (self.str[i..newlen]) |*b, j| b.* = self.str[i + 1 + j];
        self.str[newlen] = undefined;
        self.str.len = newlen;
        return old_item;
    }

    /// Removes the element at the specified index and returns it.
    /// The empty slot is filled from the end of the list.
    /// This operation is O(1).
    pub fn swapRemove(self: *Self, i: usize) u8 {
        if (self.str.len - 1 == i) return self.pop();

        const old_item = self.str[i];
        self.str[i] = self.pop();
        return old_item;
    }

    /// Append the slice of str to the list. Allocates more
    /// memory as necessary.
    pub fn appendSlice(self: *Self, str: SliceConst) !void {
        try self.ensureCapacity(self.str.len + str.len);
        self.appendSliceAssumeCapacity(str);
    }

    /// Append the slice of str to the list, asserting the capacity is already
    /// enough to store the new str.
    pub fn appendSliceAssumeCapacity(self: *Self, str: SliceConst) void {
        const oldlen = self.str.len;
        const newlen = self.str.len + str.len;
        self.str.len = newlen;
        std.mem.copy(u8, self.str[oldlen..], str);
    }

    pub usingnamespace struct {
        pub const Writer = std.io.Writer(*Self, error{OutOfMemory}, appendWrite);

        /// Initializes a Writer which will append to the list.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        /// Deprecated: use `writer`
        pub const outStream = writer;

        /// Same as `append` except it returns the number of bytes written, which is always the same
        /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
        fn appendWrite(self: *Self, m: []const u8) !usize {
            try self.appendSlice(m);
            return m.len;
        }
    };

    /// Append a value to the list `n` times.
    /// Allocates more memory as necessary.
    pub fn appendNTimes(self: *Self, value: u8, n: usize) !void {
        const old_len = self.str.len;
        try self.resize(self.str.len + n);
        mem.set(u8, self.str[old_len..self.str.len], value);
    }

    /// Append a value to the list `n` times.
    /// Asserts the capacity is enough.
    pub fn appendNTimesAssumeCapacity(self: *Self, value: u8, n: usize) void {
        const new_len = self.str.len + n;
        assert(new_len <= self.capacity);
        mem.set(u8, self.str.ptr[self.str.len..new_len], value);
        self.str.len = new_len;
    }

    /// Adjust the list's length to `new_len`.
    /// Does not initialize added str if any.
    pub fn resize(self: *Self, new_len: usize) !void {
        try self.ensureCapacity(new_len);
        self.str.len = new_len;
    }

    /// Reduce allocated capacity to `new_len`.
    /// Invalidates element pointers.
    pub fn shrink(self: *Self, new_len: usize) void {
        assert(new_len <= self.str.len);

        self.str = self.allocator.realloc(self.allocatedSlice(), new_len) catch |e| switch (e) {
            error.OutOfMemory => { // no problem, capacity is still correct then.
                self.str.len = new_len;
                return;
            },
        };
        self.capacity = new_len;
    }

    /// Reduce length to `new_len`.
    /// Invalidates element pointers.
    /// Keeps capacity the same.
    pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
        assert(new_len <= self.str.len);
        self.str.len = new_len;
    }

    pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
        var better_capacity = self.capacity;
        if (better_capacity >= new_capacity) return;

        while (true) {
            better_capacity += better_capacity / 2 + 8;
            if (better_capacity >= new_capacity) break;
        }

        // TODO This can be optimized to avoid needlessly copying undefined memory.
        const new_memory = try self.allocator.reallocAtLeast(self.allocatedSlice(), better_capacity);
        self.str.ptr = new_memory.ptr;
        self.capacity = new_memory.len;
    }

    /// Increases the array's length to match the full capacity that is already allocated.
    /// The new elements have `undefined` values. This operation does not invalidate any
    /// element pointers.
    pub fn expandToCapacity(self: *Self) void {
        self.str.len = self.capacity;
    }

    /// Increase length by 1, returning pointer to the new item.
    /// The returned pointer becomes invalid when the list is resized.
    pub fn addOne(self: *Self) !*u8 {
        const newlen = self.str.len + 1;
        try self.ensureCapacity(newlen);
        return self.addOneAssumeCapacity();
    }

    /// Increase length by 1, returning pointer to the new item.
    /// Asserts that there is already space for the new item without allocating more.
    /// The returned pointer becomes invalid when the list is resized.
    pub fn addOneAssumeCapacity(self: *Self) *u8 {
        assert(self.str.len < self.capacity);

        self.str.len += 1;
        return &self.str[self.str.len - 1];
    }

    /// Resize the array, adding `n` new elements, which have `undefined` values.
    /// The return value is an array pointing to the newly allocated elements.
    pub fn addManyAsArray(self: *Self, comptime n: usize) !*[n]u8 {
        const prev_len = self.str.len;
        try self.resize(self.str.len + n);
        return self.str[prev_len..][0..n];
    }

    /// Resize the array, adding `n` new elements, which have `undefined` values.
    /// The return value is an array pointing to the newly allocated elements.
    /// Asserts that there is already space for the new item without allocating more.
    pub fn addManyAsArrayAssumeCapacity(self: *Self, comptime n: usize) *[n]u8 {
        assert(self.str.len + n <= self.capacity);
        const prev_len = self.str.len;
        self.str.len += n;
        return self.str[prev_len..][0..n];
    }

    /// Remove and return the last element from the list.
    /// Asserts the list has at least one item.
    pub fn pop(self: *Self) u8 {
        const val = self.str[self.str.len - 1];
        self.str.len -= 1;
        return val;
    }

    /// Remove and return the last element from the list.
    /// If the list is empty, returns `null`.
    pub fn popOrNull(self: *Self) ?u8 {
        if (self.str.len == 0) return null;
        return self.pop();
    }

    // For a nicer API, `str.len` is the length, not the capacity.
    // This requires "unsafe" slicing.
    fn allocatedSlice(self: Self) Slice {
        return self.str.ptr[0..self.capacity];
    }
};
