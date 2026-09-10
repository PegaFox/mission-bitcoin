const std = @import("std");
const Target = std.Target;
const ResolvedTarget = std.Build.ResolvedTarget;
const Module = std.Build.Module;
const LazyPath = std.Build.LazyPath;

const android = @import("android");

const projectZon = @import("build.zig.zon");

const wasm = @import("wasm.zig");

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
    .name = "linux_x86",
  },
  .{
    .target = .{
      .cpu_arch = .aarch64,
      .os_tag = .linux,
      .abi = .gnu,
    },
    .build = buildPc,
    .name = "linux_arm",
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
    // buildAndroid currently ignores the target field, but too bad you can't stop me
    .target = .{
      .cpu_arch = .aarch64,
      .os_tag = .linux,
      .abi = .android,
    },
    .build = buildAndroid,
    .name = "android",
  },
  .{
    .target = .{
      .cpu_arch = .wasm32,
      .os_tag = .emscripten,
      .cpu_features_add = feat:{
        var set = Target.Cpu.Feature.Set.empty;

        const features = Target.Cpu.Arch.allFeaturesList(.wasm32);
        for (features) |feat|
        {
          //@compileLog(feat);
          if (
            std.mem.eql(u8, feat.name, "atomics") or
            std.mem.eql(u8, feat.name, "bulk_memory"))
          {
            set.addFeature(feat.index);
          }
        }

        break:feat set;
      },
    },
    .build = wasm.build,
    .name = "wasm",
  },
};

pub fn build(b: *std.Build) void {
  //const target = b.standardTargetOptions(.{});
  const TargetEnum = comptime target:
  {
    const BackingInt = std.math.IntFittingRange(0, availableTargets.len-1);
    var names: [availableTargets.len][]const u8 = undefined;
    var values: [availableTargets.len]BackingInt = undefined;

    for (0..availableTargets.len) |t|
    {
      names[t] = availableTargets[t].name;
      values[t] = t;
    }
    break:target @Enum(BackingInt, .exhaustive, &names, &values);
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
  //  .target = target,
  //  .optimize = optimize,
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
      .link_libcpp = false,
      //.single_threaded = false,
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
    .target = mod.resolved_target,
    .optimize = mod.optimize,
  });
    
  const sdlImage = b.dependency("SDL_image", .{
    .target = mod.resolved_target,
    .optimize = mod.optimize,
  });
    
  const sdlTTF = b.dependency("SDL_ttf", .{
    .target = mod.resolved_target,
    .optimize = mod.optimize,
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
  const targets = android.resolveTargets(b, .{
    // The orelse here should never trigger unless I change something else like an idiot,
    // but since we set all_targets to true, this field doesn't matter anyway
    .default_target = mod.resolved_target orelse undefined,
    .all_targets = false,
    .api_level = .android15,
  });

  const sdk = android.Sdk.create(b, .{});
  const apk = sdk.createApk(.{
    .name = "mission_bitcoin",
    // "37.0.0" will use "$ANDROID_HOME/build-tools/37.0.0" which contains tools like:
    // "aapt2", "zipalign", "apksigner", "d8"
    .build_tools_version = "36.1.0",
    // "27.0.12077973" will is used to access:
    // - Include headers:  $ANDROID_HOME/ndk/27.0.12077973/toolchains/llvm/prebuilt/YOUR_HOST_OS_HERE/sysroot/usr/include
    // - System libraries: $ANDROID_HOME/ndk/27.0.12077973/toolchains/llvm/prebuilt/YOUR_HOST_OS_HERE/sysroot/usr/lib
    .ndk_version = "29.0.14206865",
    // .android15 = 35 (android 15 uses API version 35) decides on:
    // - System libraries:  $ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/$HOST_OS/sysroot/usr/lib/$TARGET_ARCH/$ANDROID_API_LEVEL
    // - Platform tool jar: $ANDROID_HOME/platforms/android-ANDROID_API_LEVEL
    .api_level = .android15,
  });

  apk.setKeyStore(sdk.createKeyStore(.{
    .alias = "mission_bitcoin_android",
    .password = "HumbleStack2140",
    .algorithm = .rsa,
    // in bits, the maximum size of an RSA key supported by the Android keystore is 4096 bits (as of 2024)
    .key_size_in_bits = 4096,
    .validity_in_days = 365*4 + 1,
    // https://stackoverflow.com/questions/3284055/what-should-i-use-for-distinguished-name-in-our-keystore-for-the-android-marke/3284135#3284135
    .distinguished_name = "CN=TBD",
  }));
  apk.setAndroidManifest(b.path("android/android_manifest.xml"));
  apk.addResourceDirectory(b.path("android/resources"));
  //apk.addAssetDirectory();

  for (targets) |target|
  {
    const archMod = b.createModule(.{
      .root_source_file = mod.root_source_file,
      .target = target,
      .optimize = mod.optimize,
      .link_libc = mod.link_libc,
    });

    const sdl = b.dependency("sdl", .{
      .target = target,
      .optimize = mod.optimize,
    });
      
    const sdlImage = b.dependency("SDL_image", .{
      .target = target,
      .optimize = mod.optimize,
    });
    
    const sdlTTF = b.dependency("SDL_ttf", .{
      .target = target,
      .optimize = mod.optimize,
    });

    archMod.linkLibrary(sdl.artifact("SDL3"));
    archMod.linkLibrary(sdlImage.artifact("SDL3_image"));
    archMod.linkLibrary(sdlTTF.artifact("SDL3_ttf"));

    const androidImport = b.dependency("android", .{
      .target = target,
      .optimize = mod.optimize,
    });
    archMod.addImport("android", androidImport.module("android"));

    const exeLib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "main",
      .root_module = archMod,
    });
    apk.addArtifact(exeLib);
  }

  const installed = apk.addInstallApk();
  b.getInstallStep().dependOn(&installed.step);
}
