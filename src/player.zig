const std = @import("std");

const game = @import("scenes/game.zig");

pub const Pos = ?@Vector(2, u8);

pub const startingPos: Pos = null;
pub const endingPos: Pos = @splat(
  std.math.maxInt(@typeInfo(@typeInfo(Pos).optional.child).vector.child));

pos: Pos,

exchangeTokens: game.TokenType = 0,
coldStorageTokens: game.TokenType = 0,
lostTokens: game.TokenType = 0,

