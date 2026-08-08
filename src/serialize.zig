const std = @import("std");

/// Returns a type with well-defined memory layout for serialization
pub fn Type(T: type) type
{
  const info = @typeInfo(T);
  return switch (info)
  {
    // Round size up to nearest byte
    .int => |int| @Int(int.signedness, (int.bits-1 >> 3)+1 << 3),
    .vector => |vec| @Vector(vec.len, Type(vec.child)),
    .array => |arr| if (arr.sentinel_ptr) |s|
      [arr.len:s]Type(arr.child)
    else
      [arr.len]Type(arr.child),
    .@"struct" => |str| s:{
      const FieldAttrs = std.builtin.Type.StructField.Attributes;

      var types: [str.fields.len]type = undefined;
      var attrs: [str.fields.len]FieldAttrs = undefined;
      for (0.., str.fields) |f, field|
      {
        types[f] = Type(field.type);
        attrs[f] = .{
          .@"comptime" = field.is_comptime,
          .@"align" = field.alignment,
          .default_value_ptr = if (field.default_value_ptr) |default|
            &serialize(@as(*const field.type, @alignCast(@ptrCast(default))).*)
          else
            null,
        };
      }

      break:s @Struct(.@"extern", null, std.meta.fieldNames(T), &types, &attrs);
    },
    .optional => |opt| @Struct(
      .@"extern",
      null,
      &.{"value", "exists"},
      &.{Type(opt.child), bool},
      &@splat(.{})
    ),
    .@"union" => |uni| u:{
      const FieldAttrs = std.builtin.Type.StructField.Attributes;

      var types: [uni.fields.len+1]type = undefined;
      var attrs: [uni.fields.len+1]FieldAttrs = undefined;
      for (0.., uni.fields) |f, field|
      {
        types[f] = Type(field.type);
        attrs[f] = .{
          .@"align" = field.alignment,
        };
      }
      types[types.len-1] = Type(std.math.IntFittingRange(0, types.len-2));
      attrs[attrs.len-1] = .{};

      break:u @Struct(
        .@"extern",
        null,
        std.meta.fieldNames(T) ++ .{"_serialize_union_tag"},
        &types,
        &attrs
      );
    },
    .undefined => return T,
    else => @compileError("Unknown type: " ++ @typeName(T))
  };
}

/// Serializes value to a platform-agnostic form
pub fn serialize(value: anytype) Type(@TypeOf(value))
{
  const StartType = @TypeOf(value);
  const ResultType = Type(StartType);

  return switch (@typeInfo(StartType))
  {
    .vector => |vec| v:{
      var result: ResultType = undefined;

      inline for (0.., @as([vec.len]vec.child, value)) |e, element|
      {
        result[e] = serialize(element);
      }

      break:v result;
    },
    .array => a:{
      var result: ResultType = undefined;

      for (0.., value) |e, element|
      {
        result[e] = serialize(element);
      }

      break:a result;
    },
    .@"struct" => |str| s:{
      var result: ResultType = undefined;

      inline for (str.fields) |field|
      {
        @field(result, field.name) = serialize(@field(value, field.name));
      }

      break:s result;
    },
    .optional => .{
      .exists = value != null,
      .value = serialize(value orelse undefined)
    },
    .@"union" => |uni| u:{
      if (uni.tag_type == null)
      {
        @compileError("Could not determine active union field");
      }

      var result: ResultType = undefined;

      inline for (uni.fields) |field|
      {
        if (value == @field(uni.tag_type.?, field.name))
        {
          @field(result, field.name) = serialize(@field(value, field.name));
          result._serialize_union_tag = @intFromEnum(value);
          break;
        }
      }

      break:u result;
    },
    .int => value,
    else => @compileError("Unknown type: " ++ @typeName(StartType))
  };
}

/// Returns serialized value to its original form
pub fn deserialize(T: type, value: anytype) T
{
  return switch (@typeInfo(T))
  {
    .vector => |vec| v:{
      var result: T = undefined;

      inline for (0.., @as([vec.len]vec.child, value)) |e, element|
      {
        result[e] = deserialize(vec.child, element);
      }

      break:v result;
    },
    .array => |arr| a:{
      var result: T = undefined;

      for (0.., value) |e, element|
      {
        result[e] = deserialize(arr.child, element);
      }

      break:a result;
    },
    .@"struct" => |str| s:{
      var result: T = undefined;

      inline for (str.fields) |field|
      {
        @field(result, field.name) =
          deserialize(field.type, @field(value, field.name));
      }

      break:s result;
    },
    .optional => |opt|
      if (value.exists) deserialize(opt.child, value.value) else null,
    .@"union" => |uni| u:{
      var result: T = undefined;

      inline for (uni.fields) |field|
      {
        const tag = @field(uni.tag_type.?, field.name);
        if (value._serialize_union_tag == @intFromEnum(tag))
        {
          @field(result, field.name) =
            deserialize(field.type, @field(value, field.name));
          break;
        }
      }

      break:u result;
    },
    .int => @intCast(value),
    else => @compileError("Unknown type: " ++ @typeName(T))
  };
}
