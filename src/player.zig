const Self = @This();

const std = @import("std");

const Ring = @import("ring.zig");
const game = @import("scenes/game.zig");

pub const Pos = ?@Vector(2, u8);

pub const startingPos = null;
pub const endingPos: Pos = @splat(
  std.math.maxInt(@typeInfo(@typeInfo(Pos).optional.child).vector.child));

pos: Pos,
entryIndex: u8,

exchangeTokens: game.TokenType = 0,
coldStorageTokens: game.TokenType = 0,
lostTokens: game.TokenType = 0,

/// Returns a list of possible destination positions
pub fn getMoves(self: *Self, parent: []Ring, steps: u8) [4]Pos
{
  var resultBuffer: [4]Pos = @splat(null);
  var result: []Pos = resultBuffer[0..0];

  if (steps == 0)
  {
    resultBuffer[0] = self.pos;
    return resultBuffer;
  }

  const StackElement = struct
  {
    pos: @typeInfo(Pos).optional.child,
    depth: u8,
    direction: i2,
  };

  var stackBuffer: [4]StackElement = undefined;
  var stack: []StackElement = stackBuffer[0..1];

  if (self.pos == startingPos)
  {
    stack[stack.len-1] = .{
      .pos = .{self.entryIndex, 0},
      .depth = steps-1,
      .direction = 0,
    };
  } else
  {
    stack[stack.len-1] = .{
      .pos = self.pos.?,
      .depth = steps,
      .direction = 0,
    };
  }

  while (stack.len > 0)
  {
    const top = stack[stack.len-1];
    stack.len -= 1;

    if (top.depth == 0)
    {
      result.len += 1;
      result[result.len-1] = top.pos;

      continue;
    }

    if (parent[top.pos[1]].tokenCount == 0)
    {
      if (parent[top.pos[1]].spaces[top.pos[0]].jumpIndex) |jumpIndex|
      {
        stack.len += 1;
        stack[stack.len-1] = .{
          .pos = .{
            jumpIndex,
            top.pos[1]+1
          },
          .depth = top.depth-1,
          .direction = 0,
        };
      }
    }

    if (top.direction == 0)
    {
      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])-1,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = -1,
      };

      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])+1,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = 1,
      };
    } else
    {
      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])+top.direction,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = top.direction,
      };
    }
  }

  return resultBuffer;
}

pub fn move(self: *Self, parent: []Ring, pos: Pos) void
{
  self.pos = pos;

  if (pos != null and parent[pos.?[1]].spaces[pos.?[0]].hasToken == true)
  {
    _ = parent[pos.?[1]].removeToken(pos.?[0]);
  }
}
