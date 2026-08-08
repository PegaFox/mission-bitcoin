const builtin = @import("builtin");

const std = @import("std");
const log = std.log;

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;
const stdio = mainspace.stdio;

var logBuffer = [1024 * 1024]u8{};

pub fn logFn(
  comptime message_level: log.Level,
  comptime scope: @TypeOf(.enum_literal),
  comptime format: []const u8, args: anytype) void
{
  _ = scope;

  const prefixStr: [:0]const u8 = "[" ++ switch (message_level)
  {
    .err => "ERROR",
    .warn => "WARNING",
    .info => "INFO",
    .debug => "DEBUG",
  } ++ "] ";

  //if (builtin.os.tag != .emscripten)
  {
    var stderrWriter = openWriter() catch return;
    defer closeWriter();

    const currentTime = mainspace.startTime.untilNow(mainspace.io, .awake);
    stderrWriter.print("({f})", .{
      currentTime,
    }) catch
    {
      return;
    };

    stderrWriter.print(prefixStr ++ format, args) catch
    {
      return;
    };
  }// else
  //{
  //  logPrintf(prefixStr ++ format, args) catch {};
  //}
}

var writeBuffer: [64]u8 = undefined;

pub fn openWriter() std.Io.Cancelable!*std.Io.Writer
{
  const locked = try mainspace.io.lockStderr(&writeBuffer, .escape_codes);

  return &locked.file_writer.interface;
}

pub fn closeWriter() void
{
  mainspace.io.unlockStderr();
}

fn logPrintf(comptime format: []const u8, args: anytype) error{PrintfError}!void
{
  comptime var formatIndex: usize = 0;
  comptime var argIndex: usize = 0;
  inline while (comptime std.mem.find(u8, format[formatIndex..], "{")) |i|
  {
    if (format[i+1] == '{')
    {
      formatIndex += i+2;
      continue;
    }

    if (stdio.printf("%.*s", i, format[formatIndex..formatIndex+i].ptr) < 0)
    {
      return error.PrintfError;
    }
    formatIndex += i;
    formatIndex +=
      comptime std.mem.find(u8, format[formatIndex..], "}") orelse continue;
    formatIndex += 1;
    
    const argInfo = @typeInfo(@TypeOf(args)).@"struct".fields[argIndex];
    switch (@typeInfo(argInfo.type))
    {
      .pointer => |ptr| {

        if (ptr.size == .slice and ptr.child == u8)
        {
          if (stdio.printf("%.*s", args[argIndex].len, args[argIndex].ptr) < 0)
          {
            return error.PrintfError;
          }
        }
      },
      .error_set => {
        if (stdio.printf("%s", @errorName(args[argIndex]).ptr) < 0)
        {
          return error.PrintfError;
        }
      },
      else => if (stdio.printf("{%s}", @typeName(argInfo.type)) < 0)
        return error.PrintfError
    }
    argIndex += 1;
  }
  if (stdio.printf(
    "%.*s", format.len - formatIndex, format[formatIndex..].ptr) < 0)
  {
    return error.PrintfError;
  }
}
