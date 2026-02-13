const Self = @This();

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;

buttons: [4]union(enum)
{
  none: void,
  key: sdl.SDL_Scancode,
  mButton: @TypeOf(sdl.SDL_BUTTON_LEFT),
  scroll: enum(i2) {up = 1, down = -1},
},

pub fn initFromEvent(event: sdl.SDL_Event) Self
{
  switch (event.type)
  {
    sdl.SDL_EVENT_KEY_DOWN => return
    .{.buttons = .{
      .{.key = event.key.scancode},
      .none,
      .none,
      .none
    }},
    sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => return
    .{.buttons = .{
      .{.mButton = event.button.button},
      .none,
      .none,
      .none
    }},
    sdl.SDL_EVENT_MOUSE_WHEEL => return
    .{.buttons = .{
      .{.scroll = @enumFromInt(event.wheel.integer_y)},
      .none,
      .none,
      .none
    }},
    else => return .{.buttons = .{.none, .none, .none, .none}},
  }
}

const State = enum
{
  off,
  rising,
  on,
  falling,
};

pub fn active(self: @This(), keys: []const bool, mButtons: sdl.SDL_MouseButtonFlags, event: sdl.SDL_Event) State
{
  if (self.buttons[0] == .none)
  {
    return .off;
  }

  for (0..self.buttons.len) |b|
  {
    if (b == self.buttons.len - 1 or self.buttons[b + 1] == .none)
    {
      switch (self.buttons[b])
      {
        .none => unreachable,
        .key => |key|
        {
          if (event.type == sdl.SDL_EVENT_KEY_DOWN and event.key.scancode == key)
          {
            return .rising;
          } else if (event.type == sdl.SDL_EVENT_KEY_UP and event.key.scancode == key)
          {
            return .falling;
          } else if (keys[key])
          {
            return .on;
          } else
          {
            return .off;
          }
        },
        .mButton => |mButton|
        {
          if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == mButton)
          {
            return .rising;
          } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == mButton)
          {
            return .falling;
          } else if (mButtons & (@as(u5, 1) << @as(u3, @intCast(mButton - 1))) > 0)
          {
            return .on;
          } else
          {
            return .off;
          }
        },
        .scroll => |scroll| if (event.type == sdl.SDL_EVENT_MOUSE_WHEEL and @as(@TypeOf(scroll), @enumFromInt(event.wheel.integer_y)) == scroll)
          return .rising
        else
          return .off,
      }
      break;
    }

    switch (self.buttons[b])
    {
      .none, .scroll => continue,
      .key => |key| if (!keys[key]) return .off,
      .mButton => |mButton| if (mButtons & (@as(u5, 1) << @as(u3, @intCast(mButton - 1))) == 0) return .off,
    }
  }

  unreachable;
}

