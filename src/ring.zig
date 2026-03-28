const Self = @This();

const Space = @import("space.zig");

tokenCount: u8,
spaces: []Space,

// Returns whether a token was removed
pub fn removeToken(self: *Self, index: u8) bool
{
  if (index >= self.spaces.len or self.spaces[index].hasToken != true)
  {
    return false;
  }

  self.spaces[index].hasToken = false;
  self.tokenCount -= 1;

  return true;
}

pub fn distance(self: Self, index1: u8, index2: u8) u8
{
  const space1: i9 = index1;
  const space2: i9 = index2;

  const dis1 = @abs(space1 - space2);
  const dis2 = @abs(space1-@as(i9, @intCast(self.spaces.len)) - space2);

  return @intCast(@min(dis1, dis2));
}
