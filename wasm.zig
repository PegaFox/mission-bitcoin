const std = @import("std");
const Module = std.Build.Module;
const LazyPath = std.Build.LazyPath;

const projectZon = @import("build.zig.zon");

pub fn build(b: *std.Build, mod: *Module) void
{
  //const em = b.dependency("emscripten", .{});
  //const emcc = "emcc";
    //em.path("emcc.py").getPath3(b, null);
  const emcmake = "emcmake";
    //em.path("emcmake.py").getPath3(b, null).toString(b.allocator) catch
    //unreachable;
  const emmake = "emmake";
    //em.path("emmake.py").getPath3(b, null).toString(b.allocator) catch
    //unreachable;

  //mod.addIncludePath(em.path("system/lib/libc/musl/include"));
  const emSysroot = "/usr/lib/emsdk/upstream/emscripten/cache/sysroot";
  const emInclude = LazyPath{
    .cwd_relative = "/usr/lib/emsdk/upstream/emscripten/cache/sysroot/include"
  };
  b.sysroot = emSysroot;
  mod.addIncludePath(emInclude);

  const sdl = b.dependency("sdl", .{
    .optimize = mod.optimize,
    .target = mod.resolved_target,
    //.system_include_path = emInclude
    .default_target_config = false,
  }).builder.dependency("sdl", .{});
  mod.addIncludePath(sdl.path("include"));

  const cmakeOptimizeArg = switch (mod.optimize.?)
  {
    .Debug => "-DCMAKE_BUILD_TYPE=Debug",
    .ReleaseSafe => "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
    .ReleaseFast => "-DCMAKE_BUILD_TYPE=Release",
    .ReleaseSmall => "-DCMAKE_BUILD_TYPE=MinSizeRel",
  };
    
  const sdlBuild = b.addSystemCommand(&.{
    emcmake,
    "cmake",
    "--debug-output",
    "-DCMAKE_C_FLAGS=\"-pthread\"",
    cmakeOptimizeArg,
  });
  sdlBuild.addArg("-S");
  sdlBuild.addDirectoryArg(sdl.path("."));
  sdlBuild.addArg("-B");
  const sdlBuildPath = sdlBuild.addOutputDirectoryArg("build");

  const sdlMake = b.addSystemCommand(&.{emmake, "make", "-C"});
  sdlMake.addDirectoryArg(sdlBuildPath);
  sdlMake.step.dependOn(&sdlBuild.step);

  const image = b.dependency("SDL_image", .{
    .optimize = mod.optimize,
    .target = mod.resolved_target,
  }).builder.dependency("SDL_image", .{});
  mod.addIncludePath(image.path("include"));
  const imageBuild = b.addSystemCommand(&.{
    emcmake,
    "cmake",
    "--debug-output",
    "-DCMAKE_C_FLAGS=\"-pthread\"",
    cmakeOptimizeArg,
  });
  imageBuild.step.dependOn(&sdlMake.step);

  var io = std.Io.Threaded.init(std.mem.Allocator.failing, .{});
  defer io.deinit();

  const cwdPath =
    std.Io.Dir.cwd().realPathFileAlloc(io.io(), ".", b.allocator) catch
      unreachable;
  defer b.allocator.free(cwdPath);
  const prefix =
    std.mem.concat(b.allocator, u8, &.{"-DSDL3_DIR=", cwdPath, "/"}) catch
      unreachable;
  defer b.allocator.free(prefix);
  imageBuild.addPrefixedDirectoryArg(
    //"-DCMAKE_PREFIX_PATH=", sdlBuildPath
    prefix, sdlBuildPath
  );
  imageBuild.addArg("-S");
  imageBuild.addDirectoryArg(image.path("."));
  imageBuild.addArg("-B");
  const imageBuildPath = imageBuild.addOutputDirectoryArg("build");

  const imageMake = b.addSystemCommand(&.{emmake, "make", "-C"});
  imageMake.addDirectoryArg(imageBuildPath);
  imageMake.step.dependOn(&imageBuild.step);

  //const ttf = b.dependency("SDL_ttf", .{
  //  .optimize = mod.optimize,
  //  .target = mod.resolved_target,
  //}).builder.dependency("SDL_ttf", .{});
  //mod.addIncludePath(ttf.path("include"));
  //  
  //const ttfBuild = b.addSystemCommand(&.{emcmake, "cmake"});
  //ttfBuild.addPrefixedDirectoryArg(
  //  prefix, sdlBuildPath
  //);
  //ttfBuild.addArg("-S");
  //ttfBuild.addDirectoryArg(ttf.path("."));
  //ttfBuild.addArg("-B");
  //const ttfBuildPath = ttfBuild.addOutputDirectoryArg("build");

  //const ttfMake = b.addSystemCommand(&.{emmake, "make", "-C"});
  //ttfMake.addDirectoryArg(ttfBuildPath);
  //ttfMake.step.dependOn(&ttfBuild.step);

  //std.debug.print("SDL emscripten build: {s}\n", .{
  //  sdlBuildPath.getPath3(b, &sdlMake.step).toString(b.allocator) catch
  //    unreachable
  //});

  //const imageLib

  const obj = b.addObject(.{
    .name = @tagName(projectZon.name),
    .root_module = mod,
  });

  const htmlName = std.mem.concat(
    b.allocator,
    u8,
    &.{obj.name, ".html"}) catch "em.html";
  const jsName = std.mem.concat(
    b.allocator,
    u8,
    &.{obj.name, ".js"}) catch "em.js";
  const wasmName = std.mem.concat(
    b.allocator,
    u8,
    &.{obj.name, ".wasm"}) catch "em.wasm";

  const emLink = b.addSystemCommand(&.{
    "emcc",
    "-g",
    "-v",
    // Explicitely enable concurrency
    "-pthread",
    "-sPTHREAD_POOL_SIZE=3",
    "-sWASM_WORKERS",
    std.fmt.comptimePrint("-sINITIAL_MEMORY={}", .{1024*64*1024}),
    //"-sUSE_SDL=3",
    //"-sUSE_SDL_IMAGE=3",
    "-sUSE_SDL_TTF=3",
    "--embed-file", "assets"
  });
  emLink.step.dependOn(&sdlMake.step);
  emLink.step.dependOn(&imageMake.step);
  //emLink.step.dependOn(&ttfMake.step);
  emLink.addArtifactArg(obj);
  emLink.addPrefixedDirectoryArg("-L", sdlBuildPath);
  emLink.addPrefixedDirectoryArg("-L", imageBuildPath);
  //emLink.addPrefixedDirectoryArg("-L", ttfBuildPath);
  emLink.addArgs(&.{"-lSDL3", "-lSDL3_image"});
  emLink.addArg(switch (mod.optimize.?)
  {
    .Debug => "-O0",
    .ReleaseSafe => "-O0",
    .ReleaseSmall => "-Os",
    .ReleaseFast => "-O3",
  });
  emLink.addArg("-o");
  const htmlOut = emLink.addOutputFileArg(htmlName);
  const jsOut = htmlOut.dirname().path(b, jsName);
  const wasmOut = htmlOut.dirname().path(b, wasmName);

  const htmlInstall = b.addInstallBinFile(htmlOut, htmlName);
  htmlInstall.step.dependOn(&emLink.step);

  //b.installArtifact(exe);
  b.getInstallStep().dependOn(&htmlInstall.step);
  b.getInstallStep().dependOn(&b.addInstallBinFile(jsOut, jsName).step);
  b.getInstallStep().dependOn(&b.addInstallBinFile(wasmOut, wasmName).step);
}
