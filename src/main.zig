const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Copy of std.ArrayList for now, with items renamed to str.
// In the future, maybe it will a more optimized data structure for mutable string buffer
pub const StringBuffer = struct {
    const Self = @This();

    /// Content of the ArrayList
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

    pub fn init(allocator: *Allocator, template: []const u8) !Self {
        var result = Self{
            .commands = CommandList.init(allocator),
        };

        try result.parse(template);

        return result;
    }

    pub fn deinit(self: Self) void {
        self.commands.deinit();
    }

    pub fn render(self: Self, allocator: *Allocator, context: anytype) !StringBuffer {
        var result = StringBuffer.init(allocator);
        errdefer result.deinit();

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

        return result;
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
    defer result.deinit();

    testing.expectEqualStrings("Hi Zig stringtime!", result.str);
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
    defer result.deinit();

    testing.expectEqualStrings("Hi Michael Larouche, welcome to Zig.", result.str);
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
    defer first_result.deinit();
    testing.expectEqualStrings("Hi Zig stringtime!", first_result.str);

    const second_result = try parsed_template.render(testing.allocator, second_context);
    defer second_result.deinit();
    testing.expectEqualStrings("Hi second context!", second_result.str);
}

test "Render C-style code properly" {
    const Template = "fn {{fn_name}}() { std.log.info(\"Hello World!\"); }";

    var context = .{
        .fn_name = "testFunction",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();
    testing.expectEqualStrings("fn testFunction() { std.log.info(\"Hello World!\"); }", result.str);
}

test "Render unicode aware" {
    const Template = "こんにちは,{{first_name}}！Allô!";

    var context = .{
        .first_name = "Étoilé星ホシ",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();
    testing.expectEqualStrings("こんにちは,Étoilé星ホシ！Allô!", result.str);
}
