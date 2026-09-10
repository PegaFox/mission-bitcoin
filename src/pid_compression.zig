const std = @import("std");
const Io = std.Io;
const IpAddress = Io.net.IpAddress;
const Allocator = std.mem.Allocator;

/// 2048 == 11 bits
const words: std.StaticStringMap(void) =
  .initComptime(@as([]const struct {[]const u8}, @import("words/english.zon")));
comptime {std.debug.assert(words.keys().len == 2048);}

/// Uses bip39 wordlist to make a hex string more readable
/// Only the base slice must be deallocated, the strings are stored in global memory
pub fn toPhrase(allocator: Allocator, input: []const u8) ![]const []const u8
{
  const wordCount: usize = @ceil(@as(f32, @floatFromInt(input.len))*8 / 11);
  const result = try allocator.alloc([]const u8, wordCount);
  var resultLen: usize = 0;

  var index: u11 = 0;
  var bitOffset: u5 = 0;
  for (input) |byte|
  {
    index |= @as(u11, byte) << @intCast(bitOffset);
    const bitsUsed = @min(8, 11 - bitOffset);

    bitOffset += bitsUsed;

    if (bitOffset >= 11)
    {
      bitOffset %= 11;
      
      result[resultLen] = words.keys()[index];
      resultLen += 1;

      index = if (bitsUsed < 8) byte >> @intCast(bitsUsed) else 0;
      bitOffset += 8 - bitsUsed;
    }
  }
  if (index != 0)
  {
    result[result.len-1] = words.keys()[index];
  }

  return result;
}

pub fn fromPhrase(input: []const []const u8)
  error{Overflow, UnknownWord}!struct {buffer: [18]u8, len: u5}
{
  var result: [18]u8 = @splat(0);

  var inputIndex: u8 = 0;
  var index: u11 =
    @intCast(words.getIndex(input[inputIndex]) orelse return error.UnknownWord);
  var bitOffset: u4 = 0;
  for (0.., &result) |b, *byte|
  {
    byte.* |= @truncate(index >> bitOffset);
    const bitsUsed = @min(8, 11 - bitOffset);

    bitOffset += bitsUsed;

    if (bitOffset >= 11)
    {
      bitOffset %= 11;
      
      if (inputIndex == input.len-1)
      {
        return .{
          .buffer = result,
          .len = @intCast(b),
        };
      }
      inputIndex += 1;
      index = @intCast(
        words.getIndex(input[inputIndex]) orelse return error.UnknownWord
      );

      byte.* |= @truncate(index << bitsUsed);
      bitOffset += 8 - bitsUsed;
    }
  }

  return error.Overflow;
}

pub fn compress(address: IpAddress) struct {buffer: [18]u8, len: u5}
{
  const addressBuffer: [18]u8 = switch (address)
  {
    .ip4 => |ip4|
      ip4.bytes ++
      [2]u8{@intCast(ip4.port >> 8), @truncate(ip4.port)} ++
      @as([12]u8, undefined),
    .ip6 => |ip6|
      ip6.bytes ++
      [2]u8{@intCast(ip6.port >> 8), @truncate(ip6.port)},
  };
  const uncompressed: []const u8 = switch (address)
  {
    .ip4 => addressBuffer[0..6],
    .ip6 => addressBuffer[0..18],
  };

  const BufferSlice = struct
  {
    index: u4,
    len: u4
  };
  // Chungus style variable name
  var longestSequentialZeroes = BufferSlice{.index = 0, .len = 0};
  var sequentialZeroes = BufferSlice{.index = 0, .len = 0};
  for (0.., uncompressed) |b, byte|
  {
    if (byte == 0)
    {
      if (sequentialZeroes.len == 0 and b < 16)
      {
        sequentialZeroes.index = @intCast(b);
      }
      sequentialZeroes.len += 1;

      if (sequentialZeroes.len > longestSequentialZeroes.len)
      {
        longestSequentialZeroes = sequentialZeroes;
      }
    } else
    {
      sequentialZeroes.len = 0;
    }
  }

  if (longestSequentialZeroes.len > 1)
  {
    var result: [18]u8 = undefined;
    var resultTop: [*]u8 = @ptrCast(&result[0]);

    resultTop[0] =
      (@as(u8, longestSequentialZeroes.index) << 4) |
      longestSequentialZeroes.len;
    resultTop += 1;

    @memcpy(resultTop, uncompressed[0..longestSequentialZeroes.index]);
    resultTop += longestSequentialZeroes.index;

    @memcpy(
      resultTop,
      uncompressed[longestSequentialZeroes.index+longestSequentialZeroes.len..]
    );

    return .{
      .buffer = result,
      .len = @intCast(uncompressed.len - longestSequentialZeroes.len + 1)
    };
  } else
  {
    return .{
      .buffer = addressBuffer,
      .len = @intCast(uncompressed.len)
    };
  }
}

pub fn decompress(compressed: []const u8) IpAddress
{
  var resultBuffer: [18]u8 = undefined;

  if (compressed.len == 18)
  {
    resultBuffer = compressed[0..18].*;
  } else
  {
    const zeroPos = compressed[0] >> 4;
    const zeroLen = compressed[0] & 0xF;

    @memcpy(resultBuffer[0..zeroPos], compressed[1..zeroPos+1]);
    @memset(resultBuffer[zeroPos..zeroPos+zeroLen], 0);
    @memcpy(resultBuffer[zeroPos+zeroLen..], compressed[zeroPos+1..]);
  }

  return .{.ip6 = .{
    .bytes = resultBuffer[0..16].*,
    .port = @as(u16, resultBuffer[16]) << 8 | resultBuffer[17]
  }};
}
