const std = @import("std");

pub const Type = enum
{
  Default,
  ColdStorage,
  ExchangeHack,
  OrangePill,
  Exec6102,

  pub inline fn toSnakeStr(comptime self: Type) [:0]const u8
  {
    const enumStr = @tagName(self);
    if (enumStr.len == 0) return enumStr;

    comptime var outBuffer: [enumStr.len*2 :0]u8 = @splat(0);
    comptime var bufferLen: usize = 1;

    comptime for (0..enumStr.len) |c|
    {
      if (
        std.ascii.isDigit(enumStr[c]) and
        c > 0 and
        !std.ascii.isDigit(enumStr[c-1]))
      {
        outBuffer[bufferLen-1] = '_';
        bufferLen += 1;
      }

      if (std.ascii.isUpper(enumStr[c]))
      {
        if (c > 0)
        {
          outBuffer[bufferLen-1] = '_';
          bufferLen += 1;
        }

        outBuffer[bufferLen-1] = std.ascii.toLower(enumStr[c]);
        bufferLen += 1;
      } else
      {
        outBuffer[bufferLen-1] = enumStr[c];
        bufferLen += 1;
      }
    };

    const result = outBuffer;
    return result[0..bufferLen :0];
  }
};

reroll: bool,
hasToken: ?bool = null,
type: Type,
jumpIndex: ?u8 = null,

