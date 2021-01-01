const std = @import("std");
const testing = std.testing;
const stringtime = @import("stringtime");
const StringTime = stringtime.StringTime;

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

    var parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings("Hi Zig stringtime!", result.str);
}

test "Malformated template delimiter" {
    var context = .{
        .name = "Zig stringtime",
    };

    const Inputs = [_][]const u8{
        "Hi {{user_name}!",
        "Hi {user_name}}!",
        "Hi {{user_name",
        "Hi user_name}}!",
    };

    for (Inputs) |input| {
        var parsed_template = StringTime.init(testing.allocator, input);
        testing.expectError(error.MismatchedTemplateDelimiter, parsed_template);
    }
}

test "Variable name not found" {
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

test "Start with template" {
    const Template = "{{playable_character}}, you must choose wisely.";

    var context = .{
        .playable_character = "Crono",
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings("Crono, you must choose wisely.", result.str);
}

test "for range loop action" {
    const Template =
        \\{{ for(0..4) }}Hello World!
        \\{{ end }}
    ;

    const Expected =
        \\Hello World!
        \\Hello World!
        \\Hello World!
        \\Hello World!
        \\
    ;

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, .{});
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "Output integer in template" {
    const Template = "i32={{signed_int}},u64={{unsigned_long}},unicode_codepoint={{codepoint}}";

    const Expected = "i32=-123456,u64=987654321,unicode_codepoint=33609";

    const Context = struct {
        signed_int: i32,
        unsigned_long: u64,
        codepoint: u21,
    };

    var context = Context{
        .signed_int = -123456,
        .unsigned_long = 987654321,
        .codepoint = '草',
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "Output bool in template" {
    const Template = "first={{first}},second={{second}}";

    const Expected = "first=true,second=false";

    var context = .{
        .first = true,
        .second = false,
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "Output float in template" {
    const Template = "pi={{pi}},tau={{tau}}";

    const Expected = "pi=3.141592653589793e+00,tau=6.283185307179586e+00";

    var context = .{
        .pi = std.math.pi,
        .tau = std.math.tau,
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "Output enum in template" {
    const Template = "Crono={{crono}}, Marle={{marle}}, Lucca={{lucca}}, Magus={{magus}}";

    const Expected = "Crono=Lightning, Marle=Water, Lucca=Fire, Magus=Shadow";

    const Magic = enum {
        Lightning,
        Water,
        Fire,
        Shadow,
    };

    var context = .{
        .crono = Magic.Lightning,
        .marle = Magic.Water,
        .lucca = Magic.Fire,
        .magus = Magic.Shadow,
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "for range loop with index variable" {
    const Template =
        \\{{ for(0..4) |i| }}Index #{{i}}
        \\{{ end }}
    ;

    const Expected =
        \\Index #0
        \\Index #1
        \\Index #2
        \\Index #3
        \\
    ;

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, .{});
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "foreach loop with static array of strings " {
    const Template =
        \\{{ for(list) |item| }}<li>{{item}}</li>
        \\{{ end }}
    ;

    const Expected =
        \\<li>First</li>
        \\<li>Second</li>
        \\<li>Third</li>
        \\
    ;

    var context = .{
        .list = [_][]const u8{
            "First",
            "Second",
            "Third",
        },
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}

test "foreach loop with index" {
    const Template =
        \\{{ for(list) |item, i| }}<li>{{item}} at index {{i}}</li>
        \\{{ end }}
    ;

    const Expected =
        \\<li>First at index 0</li>
        \\<li>Second at index 1</li>
        \\<li>Third at index 2</li>
        \\
    ;

    var context = .{
        .list = [_][]const u8{
            "First",
            "Second",
            "Third",
        },
    };

    const parsed_template = try StringTime.init(testing.allocator, Template);
    defer parsed_template.deinit();

    const result = try parsed_template.render(testing.allocator, context);
    defer result.deinit();

    testing.expectEqualStrings(Expected, result.str);
}
