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

// test "for range loop with index variable" {
//     const Template =
//         \\{{ for(0..4) |index| }}
//         \\Index #{{index}}
//         \\{{ end }}
//     ;

//     const Expected =
//         \\Index #0
//     ;

//     const parsed_template = try StringTime.init(testing.allocator, Template);
//     defer parsed_template.deinit();

//     const result = try parsed_template.render(testing.allocator, .{});
//     defer result.deinit();

//     testing.expectEqualStrings(Expected, result.str);
// }

// test "foreach loop" {
//     const Template =
//         \\{{ for(list) |item| }}
//         \\<li>{{item}}</li>
//         \\{{ end }}
//     ;

//     const Expected =
//         \\<li>First</li>
//         \\<li>Second</li>
//         \\<li>Third</li>
//     ;

//     const parsed_template = try StringTime.init(testing.allocator, Template);
//     defer parsed_template.deinit();

//     const result = try parsed_template.render(testing.allocator, .{});
//     defer result.deinit();

//     testing.expectEqualStrings(Expected, result.str);
// }

// test "foreach loop with index" {
//     const Template =
//         \\{{ for(list) |item, i| }}
//         \\<li>{{item}} at index {{i}}</li>
//         \\{{ end }}
//     ;

//     const Expected =
//         \\<li>First at index 0</li>
//         \\<li>Second at index 1</li>
//         \\<li>Third at index 2</li>
//     ;

//     const parsed_template = try StringTime.init(testing.allocator, Template);
//     defer parsed_template.deinit();

//     const result = try parsed_template.render(testing.allocator, .{});
//     defer result.deinit();

//     testing.expectEqualStrings(Expected, result.str);
// }
