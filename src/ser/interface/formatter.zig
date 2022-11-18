pub fn Formatter(
    comptime Context: type,
    comptime Writer: type,
    comptime impls: struct {
        writeBool: ?fn (Context, Writer, bool) Writer.Error!void = null,
        writeCharEscape: ?fn (Context, Writer, u21) Writer.Error!void = null,
        writeInt: ?fn (Context, Writer, anytype) Writer.Error!void = null,
        writeFloat: ?fn (Context, Writer, anytype) Writer.Error!void = null,
        writeNull: ?fn (Context, Writer) Writer.Error!void = null,
        writeNumberString: ?fn (Context, Writer, []const u8) Writer.Error!void = null,
        writeRawFragment: ?fn (Context, Writer, []const u8) Writer.Error!void = null,
        writeStringFragment: ?fn (Context, Writer, []const u8) Writer.Error!void = null,

        beginArray: ?fn (Context, Writer) Writer.Error!void = null,
        beginArrayValue: ?fn (Context, Writer, bool) Writer.Error!void = null,
        beginObject: ?fn (Context, Writer) Writer.Error!void = null,
        beginObjectKey: ?fn (Context, Writer, bool) Writer.Error!void = null,
        beginObjectValue: ?fn (Context, Writer) Writer.Error!void = null,
        beginString: ?fn (Context, Writer) Writer.Error!void = null,

        endArray: ?fn (Context, Writer) Writer.Error!void = null,
        endArrayValue: ?fn (Context, Writer) Writer.Error!void = null,
        endString: ?fn (Context, Writer) Writer.Error!void = null,
        endObject: ?fn (Context, Writer) Writer.Error!void = null,
        endObjectKey: ?fn (Context, Writer) Writer.Error!void = null,
        endObjectValue: ?fn (Context, Writer) Writer.Error!void = null,
    },
) type {
    const T = struct {
        context: Context,

        const Self = @This();

        /// Writes a `null` value to the specified writer.
        pub fn writeNull(self: Self, writer: Writer) Writer.Error!void {
            if (impls.writeNull) |f| {
                try f(self.context, writer);
            } else {
                @compileError("writeNull is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Writes `true` or `false` to the specified writer.
        pub fn writeBool(self: Self, writer: Writer, value: bool) Writer.Error!void {
            if (impls.writeBool) |f| {
                try f(self.context, writer, value);
            } else {
                @compileError("writeBool is not implemented by type: " ++ @typeName(Context));
            }
        }

        // Writes an floating point value to the specified writer.
        pub fn writeFloat(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            if (impls.writeFloat) |f| {
                switch (@typeInfo(@TypeOf(value))) {
                    .ComptimeFloat, .Float => try f(self.context, writer, value),
                    else => @compileError("expected float, found " ++ @typeName(@TypeOf(value))),
                }
            } else {
                @compileError("writeFloat is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Writes an integer value to the specified writer.
        pub fn writeInt(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            if (impls.writeInt) |f| {
                switch (@typeInfo(@TypeOf(value))) {
                    .ComptimeInt, .Int => try f(self.context, writer, value),
                    else => @compileError("expected integer, found " ++ @typeName(@TypeOf(value))),
                }
            } else {
                @compileError("writeInt is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Writes a number that has already been rendered into a string.
        ///
        /// TODO: Check that the string is actually an integer when parsed.
        pub fn writeNumberString(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            if (impls.writeNumberString) |f| {
                try f(self.context, writer, value);
            } else {
                @compileError("writeNumberString is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Called before each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub fn beginString(self: Self, writer: Writer) Writer.Error!void {
            if (impls.beginString) |f| {
                try f(self.context, writer);
            } else {
                @compileError("beginString is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Called after each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub fn endString(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endString) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endString is not implemented by type: " ++ @typeName(Context));
            }
        }

        /// Writes a string fragment that doesn't need any escaping to the
        /// specified writer.
        pub fn writeStringFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            if (impls.writeStringFragment) |f| {
                try f(self.context, writer, value);
            } else {
                @compileError("writeStringFragment is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn writeCharEscape(self: Self, writer: Writer, value: u21) Writer.Error!void {
            if (impls.writeCharEscape) |f| {
                try f(self.context, writer, value);
            } else {
                @compileError("writeCharEscape is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn beginArray(self: Self, writer: Writer) Writer.Error!void {
            if (impls.beginArray) |f| {
                try f(self.context, writer);
            } else {
                @compileError("beginArray is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn endArray(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endArray) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endArray is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn beginArrayValue(self: Self, writer: Writer, first: bool) Writer.Error!void {
            if (impls.beginArrayValue) |f| {
                try f(self.context, writer, first);
            } else {
                @compileError("beginArrayValue is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn endArrayValue(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endArrayValue) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endArrayValue is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn beginObject(self: Self, writer: Writer) Writer.Error!void {
            if (impls.beginObject) |f| {
                try f(self.context, writer);
            } else {
                @compileError("beginObject is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn endObject(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endObject) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endObject is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn beginObjectKey(self: Self, writer: Writer, first: bool) Writer.Error!void {
            if (impls.beginObjectKey) |f| {
                try f(self.context, writer, first);
            } else {
                @compileError("beginObjectKey is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn endObjectKey(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endObjectKey) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endObjectKey is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn beginObjectValue(self: Self, writer: Writer) Writer.Error!void {
            if (impls.beginObjectValue) |f| {
                try f(self.context, writer);
            } else {
                @compileError("beginObjectValue is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn endObjectValue(self: Self, writer: Writer) Writer.Error!void {
            if (impls.endObjectValue) |f| {
                try f(self.context, writer);
            } else {
                @compileError("endObjectValue is not implemented by type: " ++ @typeName(Context));
            }
        }

        pub fn writeRawFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            if (impls.writeRawFragment) |f| {
                try f(self.context, writer, value);
            } else {
                @compileError("writeRawFragment is not implemented by type: " ++ @typeName(Context));
            }
        }
    };

    return struct {
        pub fn formatter(self: Context) T {
            return .{ .context = self };
        }
    };
}
