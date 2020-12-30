const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("stringtime", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("tests/tests.zig");
    main_tests.linkLibrary(lib);
    main_tests.addPackage(.{
        .name = "stringtime",
        .path = "stringtime.zig",
    });
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
