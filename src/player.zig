const Self = @This();

const std = @import("std");

const game = @import("scenes/game.zig");

pub const Pos = ?@Vector(2, u8);

pub const startingPos = null;
pub const endingPos: Pos = @splat(
  std.math.maxInt(@typeInfo(@typeInfo(Pos).optional.child).vector.child));

pos: Pos,

exchangeTokens: game.TokenType = 0,
coldStorageTokens: game.TokenType = 0,
lostTokens: game.TokenType = 0,

/// Returns the new position
pub fn move(self: *Self, offset: i8) Pos
{
  if (self.pos == startingPos)
  {// TODO: Handle ring connections
    self.pos = @typeInfo(Pos).optional.child{0, 0};
  }

  self.pos.?[0] = @intCast(self.pos.?[0] +% @as(i9, offset));

  return self.pos;
}
