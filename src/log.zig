const std = @import("std");
const log = std.log;

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;
const stdio = mainspace.stdio;

var logBuffer = [1024 * 1024]u8{};

pub fn logFn(comptime message_level: log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void
{
  _ = scope;

  const prefixStr = "[" ++ switch (message_level)
  {
    .err => "ERROR",
    .warn => "WARNING",
    .info => "INFO",
    .debug => "DEBUG",
  } ++ "] ";

  var stderrBuffer: [64]u8 = undefined;
  const stderrWriter = std.debug.lockStderrWriter(&stderrBuffer);
  defer std.debug.unlockStderrWriter();

  const currentTime =
    @as(i64, @intCast(std.time.nanoTimestamp())) - mainspace.startTime;
  stderrWriter.print("({D})", .{
    currentTime,
  }) catch
  {
    return;
  };

  //_ = stdio.printf(prefixStr ++ format);
  stderrWriter.print(prefixStr ++ format, args) catch
  {
    return;
  };
}

pub fn flushLogBuffers() void {}
