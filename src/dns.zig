const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const HostName = Io.net.HostName;

const Endian = std.builtin.Endian;

pub const Message = struct
{
  header: Header,

  questions: []Record.Basic = &.{},
  answers: []Record = &.{},
  authorityRecords: []Record = &.{},
  otherRecords: []Record = &.{},

  pub fn minBufferSize(self: Message) usize
  {
    var result: usize = @bitSizeOf(Header)/8;

    for (self.questions) |question|
    {
      result += question.minBufferSize();
    }

    return result;
  }

  pub fn serialize(self: Message, buffer: []u8)
    error{BufferOverflow}![]u8
  {
    if (buffer.len < self.minBufferSize())
    {
      return error.BufferOverflow;
    }

    var len: usize = 0;

    var endianHeader = self.header;
    if (Endian.native != .big)
    {
      std.mem.byteSwapAllFields(Header, &endianHeader);
    }

    const headerSize = @bitSizeOf(Header)/8;
    @memcpy(
      buffer[0..headerSize],
      std.mem.asBytes(&endianHeader)[0..headerSize]
    );
    len += headerSize;

    for (self.questions) |question|
    {
      len += (try question.serialize(buffer[len..])).len;
    }
    
    return buffer[0..self.minBufferSize()];
  }

  /// Question and record arrays are owned by the caller. Consider passing in an arena as the allocator
  pub fn deserialize(allocator: Allocator, reader: *Io.Reader) !Message
  {
    var result = Message{
      .header = try reader.takeStruct(Header, .big),
    };

    result.questions =
      try allocator.alloc(Record.Basic, result.header.questionCount);
    errdefer allocator.free(result.questions);
    result.answers =
      try allocator.alloc(Record, result.header.answerCount);
    errdefer allocator.free(result.answers);
    result.authorityRecords =
      try allocator.alloc(Record, result.header.authorityRecordCount);
    errdefer allocator.free(result.authorityRecords);
    result.otherRecords =
      try allocator.alloc(Record, result.header.otherRecordCount);
    errdefer allocator.free(result.otherRecords);

    for (result.questions) |*question|
    {
      question.* = try Record.Basic.deserialize(allocator, reader, result);
    }
    for (result.answers) |*answer|
    {
      answer.* = try Record.deserialize(allocator, reader, result);
    }
    for (result.authorityRecords) |*record|
    {
      record.* = try Record.deserialize(allocator, reader, result);
    }
    for (result.otherRecords) |*record|
    {
      record.* = try Record.deserialize(allocator, reader, result);
    }

    return result;
  }
};

pub const Header = packed struct(u96)
{
  otherRecordCount: u16 = 0,

  authorityRecordCount: u16 = 0,

  answerCount: u16 = 0,
  
  questionCount: u16 = 0,

  err: enum (u4)
  {
    None = 0,
    Format = 1,
    Server = 2,
    NoDomain = 3,
    _
  } = .None,
  /// In a query, indicates that non-verified data is acceptable in a response.
  unsafe: bool = true,
  /// In a response, indicates if the replying DNS server verified the data.
  verified: bool = false,
  zero: u1 = 0,
  /// In a response, indicates if the replying DNS server supports recursion.
  recursive: bool = false,

  /// Indicates if the client means a recursive query.
  recursion: bool = false,
  /// Indicates that this message was truncated due to excessive length.
  truncated: bool = false,
  /// In a response, indicates if the DNS server is authoritative for the queried hostname.
  authoritative: bool = false,
  opcode: enum (u4)
  {
    Query = 0,
    InverseQuery = 1,
    Status = 2,
  },
  reply: bool,

  transactionID: u16,
};

pub const Record = struct
{
  pub const Basic = struct
  {
    name: HostName,
    type: HostName.DnsRecord,
    class: u16,
  
    pub fn minBufferSize(self: Basic) usize
    {
      return self.name.bytes.len+6;
    }
  
    pub fn serialize(self: Basic, buffer: []u8)
      error{BufferOverflow}![]u8
    {
      if (buffer.len < self.minBufferSize())
      {
        return error.BufferOverflow;
      }
  
      var nameIdx: u8 = 0;
      while (
        if (nameIdx < self.name.bytes.len)
          std.mem.find(u8, self.name.bytes[nameIdx..], ".") orelse
            self.name.bytes.len - nameIdx
        else null
      ) |pos|
      {
        buffer[nameIdx] = @intCast(pos);
        @memcpy(
          buffer[nameIdx+1..nameIdx+1+pos],
          self.name.bytes[nameIdx..nameIdx+pos]
        );
        nameIdx += @intCast(pos+1);
      }
      // Null termination
      buffer[nameIdx] = 0;
  
      buffer[nameIdx+1] = 0;
      buffer[nameIdx+2] = @intFromEnum(self.type);
  
      buffer[nameIdx+3] = @intCast(self.class >> 8);
      buffer[nameIdx+4] = @truncate(self.class);
      
      return buffer[0..self.minBufferSize()];
    }

    pub fn deserialize(
      allocator: Allocator,
      reader: *Io.Reader,
      parent: Message
    ) !Basic
    {
      var nameBuffer: [HostName.max_len]u8 = undefined;
      var name: []u8 = nameBuffer[0..0];
      var len = try reader.takeByte();
      nameLoop: while (len > 0)
      {
        if (len & 0xC0 == 0)
        {
          const start = name.len;
          name.len += len;
          try reader.readSliceAll(name[start..]);

          len = try reader.takeByte();

          // Add period seperator
          if (len != 0)
          {
            name.len += 1;
            name[name.len-1] = '.';
          }
        } else
        {
          const pos = @as(u16, len) << 8 & 0x3FFF | try reader.takeByte();

          var searchPos: u16 = 12;
          for (parent.questions) |question|
          {
            std.log.debug("{} + {}\n", .{searchPos, question.minBufferSize()});
            if (pos == searchPos)
            {
              name.len = question.name.bytes.len;
              @memcpy(name, question.name.bytes);
              break:nameLoop;
            }

            searchPos += @intCast(question.minBufferSize());
          }

          return error.InvalidName;
        }
      }

      return .{
        .name = try HostName.init(try allocator.dupe(u8, name)),
        .type = @enumFromInt(try reader.takeInt(u16, .big)),
        .class = try reader.takeInt(u16, .big),
      };
    }
  };

  basic: Basic,
  /// Seconds until the record is invalid
  /// Wikipedia says maximum is 2^31-1 so I'm interpreting it as signed
  lifetime: i32,
  /// Base structure stores length as a u16, but this is more convenient here
  data: []u8,

  pub fn deserialize(allocator: Allocator, reader: *Io.Reader, parent: Message)
    !Record
  {
    const result = Record{
      .basic = try Basic.deserialize(allocator, reader, parent),
      .lifetime = try reader.takeInt(i32, .big),
      .data = try allocator.alloc(u8, try reader.takeInt(u16, .big)-1),
    };
    reader.toss(1);

    try reader.readSliceAll(result.data);

    return result;
  }
};
