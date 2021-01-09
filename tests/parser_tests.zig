const std = @import("std");
const testing = std.testing;
const stringtime = @import("stringtime");
const Lexer = stringtime.Lexer;
const Parser = stringtime.Parser;

test "Lex single character token" {
    const TestInput = [_]struct {
        input: []const u8,
        expected: Lexer.Token,
    }{
        .{ .input = "(", .expected = Lexer.Token.left_paren },
        .{ .input = ")", .expected = Lexer.Token.right_paren },
        .{ .input = "|", .expected = Lexer.Token.vertical_line },
        .{ .input = ",", .expected = Lexer.Token.comma },
        .{ .input = ".", .expected = Lexer.Token.dot },
    };

    for (TestInput) |test_input| {
        var lexer = try Lexer.init(test_input.input);

        var token_opt = try lexer.next();
        testing.expect(token_opt != null);

        if (token_opt) |token| {
            testing.expect(std.meta.activeTag(token) == test_input.expected);
        }
    }
}

test "Lex number" {
    const TestInput = [_]struct {
        input: []const u8,
        expected: usize,
    }{
        .{ .input = "0", .expected = 0 },
        .{ .input = "1", .expected = 1 },
        .{ .input = "200", .expected = 200 },
        .{ .input = "1024", .expected = 1024 },
        .{ .input = "2077", .expected = 2077 },
        .{ .input = "1986", .expected = 1986 },
        .{ .input = "       \t\r\n1986", .expected = 1986 },
    };

    for (TestInput) |test_input| {
        var lexer = try Lexer.init(test_input.input);

        var token_opt = try lexer.next();
        testing.expect(token_opt != null);

        if (token_opt) |token| {
            testing.expect(token == .number);

            testing.expectEqual(test_input.expected, token.number);
        }
    }
}

test "Lex identifier" {
    const TestInput = [_][]const u8{
        "name",
        "first_name",
        "last_name",
        "_ident",
        "last01",
        "last_02",
    };

    for (TestInput) |test_input| {
        var lexer = try Lexer.init(test_input);

        var token_opt = try lexer.next();
        testing.expect(token_opt != null);

        if (token_opt) |token| {
            testing.expect(token == .identifier);

            testing.expectEqualStrings(test_input, token.identifier);
        }
    }
}

test "Lex keywords" {
    const TestInput = [_]struct {
        input: []const u8,
        expected: Lexer.Token,
    }{
        .{ .input = "for", .expected = Lexer.Token.for_loop },
        .{ .input = "end", .expected = Lexer.Token.end },
    };

    for (TestInput) |test_input| {
        var lexer = try Lexer.init(test_input.input);

        var token_opt = try lexer.next();
        testing.expect(token_opt != null);

        if (token_opt) |token| {
            testing.expect(std.meta.activeTag(token) == test_input.expected);
        }
    }
}

test "Lex range" {
    var lexer = try Lexer.init("..");

    var token_opt = try lexer.next();
    testing.expect(token_opt != null);

    if (token_opt) |token| {
        testing.expect(token == .range);
    }
}

test "Lex end of template" {
    var lexer = try Lexer.init("}}");

    var token_opt = try lexer.next();
    testing.expect(token_opt != null);

    if (token_opt) |token| {
        testing.expect(token == .end_template);
    }
}

test "Lex for range loop" {
    const Expected = [_]@TagType(Lexer.Token){
        Lexer.Token.for_loop,
        Lexer.Token.left_paren,
        Lexer.Token.number,
        Lexer.Token.range,
        Lexer.Token.number,
        Lexer.Token.right_paren,
        Lexer.Token.end_template,
    };

    var lexer = try Lexer.init("for(0..10) }}");

    var index: usize = 0;

    while (try lexer.next()) |token| {
        testing.expect(std.meta.activeTag(token) == Expected[index]);
        index += 1;
    }

    testing.expectEqual(Expected.len, index);
}

test "Error lexing end_template" {
    var lexer = try Lexer.init("}");

    var token_opt = lexer.next();
    testing.expectError(error.MismatchedTemplateDelimiter, token_opt);
}

test "Error lexing invalid_token" {
    var lexer = try Lexer.init("!");

    var token_opt = lexer.next();
    testing.expectError(error.InvalidToken, token_opt);
}

test "Parse field qualifier expression" {
    const Input = "first_name \t\r\n}}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = try parser.parse();

    testing.expect(result_opt != null);

    if (result_opt) |result| {
        defer result.deinit();

        testing.expect(result == .field_qualifier);

        testing.expectEqualStrings("first_name", result.field_qualifier);
    }
}

test "Parse end statement" {
    const Input = "end}}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = try parser.parse();

    testing.expect(result_opt != null);

    if (result_opt) |result| {
        defer result.deinit();

        testing.expect(result == .end);
    }
}

test "Parse for range loop" {
    const Input = "for (0..4) }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = try parser.parse();

    testing.expect(result_opt != null);

    if (result_opt) |result| {
        defer result.deinit();

        testing.expect(result == .for_loop);

        testing.expect(result.for_loop.expression == .range);

        testing.expectEqual(@as(usize, 0), result.for_loop.expression.range.start);
        testing.expectEqual(@as(usize, 4), result.for_loop.expression.range.end);
    }
}

test "Error on missing terminator" {
    const Input = "for (0..4)";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = parser.parse();

    testing.expectError(error.MismatchedTemplateDelimiter, result_opt);
}

test "Error on missing end of range" {
    const Input = "for (0..) }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = parser.parse();

    testing.expectError(error.ParseError, result_opt);
}

test "Error on missing right parenthesis" {
    const Input = "for (0..4 }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = parser.parse();

    testing.expectError(error.ParseError, result_opt);
}

test "Error on missing left parenthesis" {
    const Input = "for 0..4) }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = parser.parse();

    testing.expectError(error.ParseError, result_opt);
}

test "Parse variable capture" {
    const Input = "for (0..4) |patate| }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = try parser.parse();

    testing.expect(result_opt != null);

    if (result_opt) |result| {
        defer result.deinit();

        testing.expect(result == .for_loop);

        testing.expect(result.for_loop.expression == .range);

        testing.expectEqual(@as(usize, 0), result.for_loop.expression.range.start);
        testing.expectEqual(@as(usize, 4), result.for_loop.expression.range.end);

        testing.expectEqual(@as(usize, 1), result.for_loop.variable_captures.items.len);
        testing.expectEqualStrings("patate", result.for_loop.variable_captures.items[0]);
    }
}

test "Error on missing right vertical line in variable capture" {
    const Input = "for (0..4) |patate }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = parser.parse();

    testing.expectError(error.ParseError, result_opt);
}

test "Parse foreach loop" {
    const Input = "for (list) |item| }}";

    var parser = try Parser.init(testing.allocator, Input);

    var result_opt = try parser.parse();

    testing.expect(result_opt != null);

    if (result_opt) |result| {
        defer result.deinit();

        testing.expect(result == .for_loop);

        testing.expect(result.for_loop.expression == .field_qualifier);

        testing.expectEqualStrings("list", result.for_loop.expression.field_qualifier);

        testing.expectEqual(@as(usize, 1), result.for_loop.variable_captures.items.len);
        testing.expectEqualStrings("item", result.for_loop.variable_captures.items[0]);
    }
}

test "Parse fully qualified struct field access" {
    const TestInput = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "name }}", .expected = "name" },
        .{ .input = "blog.title }}", .expected = "blog.title" },
        .{ .input = "blog.date.created }}", .expected = "blog.date.created" },
        .{ .input = "blog.date.start.current }}", .expected = "blog.date.start.current" },
    };

    for (TestInput) |entry| {
        var parser = try Parser.init(testing.allocator, entry.input);

        var result_opt = try parser.parse();
        testing.expect(result_opt != null);

        if (result_opt) |result| {
            defer result.deinit();

            testing.expect(result == .field_qualifier);

            testing.expectEqualStrings(entry.expected, result.field_qualifier);
        }
    }
}
