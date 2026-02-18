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
