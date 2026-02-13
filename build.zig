const std = @import("std");
const Target = std.Target;
const ResolvedTarget = std.Build.ResolvedTarget;
const Module = std.Build.Module;
const LazyPath = std.Build.LazyPath;

const projectZon = @import("build.zig.zon");

const TargetInfo = struct {
  target: Target.Query,
  build: *const fn (b: *std.Build, mod: *Module) void,
  name: []const u8,
};

const availableTargets = [_]TargetInfo{
  .{
    .target = .{
      .cpu_arch = .x86_64,
      .os_tag = .linux,
      .abi = .gnu,
    },
    .build = buildPc,
    .name = "linux",
  },
  .{
    .target = .{
      .cpu_arch = .x86_64,
      .os_tag = .windows,
    },
    .build = buildPc,
    .name = "windows",
  },
  .{
    .target = .{
      .cpu_arch = .aarch64,
      .os_tag = .linux,
      .abi = .android,
    },
    .build = buildAndroid,
    .name = "android",
  },
  //.{
  //  .target = .{
  //    .cpu_arch = .wasm32,
  //    .os_tag = .freestanding,
  //  },
  //  .build = buildWasm,
  //  .name = "wasm",
  //},
};

pub fn build(b: *std.Build) void {
  //const target = b.standardTargetOptions(.{});
  const TargetEnum = comptime trgt:
  {
    var Enum = std.builtin.Type.Enum{
      .tag_type = u8,
      .fields = &.{},
      .decls = &.{},
      .is_exhaustive = false,
    };
    for (availableTargets) |target|
    {
      Enum.fields = Enum.fields ++ [1]std.builtin.Type.EnumField{.{
        .name = @ptrCast(target.name),
        .value = Enum.fields.len,
      }};
    }
    break:trgt @Type(.{.@"enum" = Enum});
  };

  const targets: [availableTargets.len]?*const TargetInfo = 
    if (
      b.option([]TargetEnum, "targets", "A list of the targets to build for")
    ) |targetArr|
    trgts:{
      var usageArr: [availableTargets.len]?*const TargetInfo = undefined;
      for (0..usageArr.len) |t|
      {
        if (t < targetArr.len)
        {
          usageArr[t] = &availableTargets[@intFromEnum(targetArr[t])];
        } else
        {
          usageArr[t] = null;
        }
      }
      break:trgts usageArr;
    } else
    trgts:{
      var usageArr: [availableTargets.len]?*const TargetInfo = undefined;
      for (0..usageArr.len) |t|
      {
        usageArr[t] = &availableTargets[t];
      }
      break:trgts usageArr;
    };

  const optimize = b.standardOptimizeOption(.{});

  //const gui_lib = b.dependency("gui_lib", .{
  //  .target = target,
  //  .optimize = optimize,
  //});

  //const sdlTTF = b.dependency("SDL_ttf", .{
  //  .optimize = optimize,
  //  .target = target,
  //});
  //sdlTTF.artifact("SDL3_ttf").root_module.addIncludePath(emInclude);
    
  //const testStep = b.step("test", "Run unit tests");

  const check = b.step("check", "Scan syntax for errors");
  for (targets) |target|
  {
    if (target == null)
    {
      continue;
    }
    std.debug.print("Building for {s}\n", .{target.?.name});

    const mod = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = b.resolveTargetQuery(target.?.target),
      .optimize = optimize,
      .link_libc = true,
      //.link_libcpp = true,
    });

    //exe_mod.addIncludePath(.{.src_path = .{.owner = b, .sub_path = "src/"}});

    //exe_mod.addCSourceFile(.{.file = .{.src_path = .{.owner = b, .sub_path = "src/bitfield_workarounds.c"}}});

    //exe_mod.linkLibrary(sdlTTF.artifact("SDL3_ttf"));
    //exe_mod.linkLibrary(gui_lib.artifact("gui-lib"));

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.

    target.?.build(b, mod);

    // Tests
    //const exe_unit_tests = b.addTest(.{
    //  .root_module = mod,
    //});
    //const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    //testStep.dependOn(&run_exe_unit_tests.step);
  
    // Fast error checking
    const exeCheck = b.addExecutable(.{
      .name = @tagName(projectZon.name),
      .root_module = mod,
    });
    check.dependOn(&exeCheck.step);
  }

  b.installDirectory(.{
    .source_dir = .{.src_path = .{.owner = b, .sub_path = "assets"}},
    .install_dir = .bin,
    .install_subdir = "assets",
  });

  //const run_cmd = b.addRunArtifact(exe);

  //run_cmd.step.dependOn(b.getInstallStep());

  //if (b.args) |args| {
  //  run_cmd.addArgs(args);
  //}

  //const run_step = b.step("run", "Run the app");
  //run_step.dependOn(&run_cmd.step);

}

fn buildPc(b: *std.Build, mod: *Module) void
{
  const sdl = b.dependency("sdl", .{
    .optimize = mod.optimize,
    .target = mod.resolved_target,
  });
    
  const sdlImage = b.dependency("SDL_image", .{
    .optimize = mod.optimize,
    .target = mod.resolved_target,
  });
    
  const sdlTTF = b.dependency("SDL_ttf", .{
    .optimize = mod.optimize,
    .target = mod.resolved_target,
  });

  mod.addIncludePath(sdl.path("include/SDL3"));
  for (sdlImage.artifact("SDL3_image").root_module.include_dirs.items) |dir|
  {
    if (dir == .path and std.mem.eql(u8, dir.path.basename(b, null), "include"))
    {
      mod.addIncludePath(dir.path.path(b, "SDL3_image"));
    }
  }

  for (sdlTTF.artifact("SDL3_ttf").root_module.include_dirs.items) |dir|
  {
    if (dir == .path and std.mem.eql(u8, dir.path.basename(b, null), "include"))
    {
      mod.addIncludePath(dir.path.path(b, "SDL3_ttf"));
    }
  }

  mod.linkLibrary(sdl.artifact("SDL3"));
  mod.linkLibrary(sdlImage.artifact("SDL3_image"));
  mod.linkLibrary(sdlTTF.artifact("SDL3_ttf"));

  const exe = b.addExecutable(.{
    .name = @tagName(projectZon.name),
    .root_module = mod,
  });

  b.installArtifact(exe);
}

fn buildAndroid(b: *std.Build, mod: *Module) void
{
  _ = b;
  _ = mod;
}

fn buildWasm(b: *std.Build, mod: *Module) void
{
  const emInclude = LazyPath{
    .cwd_relative = "/usr/lib/emsdk/upstream/emscripten/cache/sysroot/include"
  };

  mod.addIncludePath(emInclude);
  mod.addIncludePath(emInclude.path(b, "SDL2"));

  const obj = b.addObject(.{
    .name = @tagName(projectZon.name),
    .root_module = mod,
  });

  const htmlName = std.mem.concat(
    b.allocator,
    u8,
    &.{obj.name, ".html"}) catch "em.html";
  const wasmName = std.mem.concat(
    b.allocator,
    u8,
    &.{obj.name, ".wasm"}) catch "em.wasm";

  const emLink = b.addSystemCommand(&.{"emcc"});
  emLink.addArtifactArg(obj);
  emLink.addArg("--use-port=sdl2");
  emLink.addArg(switch (mod.optimize.?)
  {
    .Debug => "-O0",
    .ReleaseSafe => "-O0",
    .ReleaseSmall => "-Os",
    .ReleaseFast => "-O3",
  });
  emLink.addArg("-o");
  const htmlOut = emLink.addOutputFileArg(htmlName);
  const wasmOut = htmlOut.dirname().path(b, wasmName);

  //b.installArtifact(exe);
  b.getInstallStep().dependOn(&b.addInstallBinFile(htmlOut, htmlName).step);
  b.getInstallStep().dependOn(&b.addInstallBinFile(wasmOut, wasmName).step);
}
