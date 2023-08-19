pub fn Formatter(
    comptime Impl: type,
    comptime Writer: type,
    comptime methods: struct {
        writeBool: ?fn (Impl, Writer, bool) Writer.Error!void = null,
        writeCharEscape: ?fn (Impl, Writer, u21) Writer.Error!void = null,
        writeInt: ?fn (Impl, Writer, anytype) Writer.Error!void = null,
        writeFloat: ?fn (Impl, Writer, anytype) Writer.Error!void = null,
        writeNull: ?fn (Impl, Writer) Writer.Error!void = null,
        writeNumberString: ?fn (Impl, Writer, []const u8) Writer.Error!void = null,
        writeRawFragment: ?fn (Impl, Writer, []const u8) Writer.Error!void = null,
        writeStringFragment: ?fn (Impl, Writer, []const u8) Writer.Error!void = null,

        beginArray: ?fn (Impl, Writer) Writer.Error!void = null,
        beginArrayValue: ?fn (Impl, Writer, bool) Writer.Error!void = null,
        beginObject: ?fn (Impl, Writer) Writer.Error!void = null,
        beginObjectKey: ?fn (Impl, Writer, bool) Writer.Error!void = null,
        beginObjectValue: ?fn (Impl, Writer) Writer.Error!void = null,
        beginString: ?fn (Impl, Writer) Writer.Error!void = null,

        endArray: ?fn (Impl, Writer) Writer.Error!void = null,
        endArrayValue: ?fn (Impl, Writer) Writer.Error!void = null,
        endString: ?fn (Impl, Writer) Writer.Error!void = null,
        endObject: ?fn (Impl, Writer) Writer.Error!void = null,
        endObjectKey: ?fn (Impl, Writer) Writer.Error!void = null,
        endObjectValue: ?fn (Impl, Writer) Writer.Error!void = null,
    },
) type {
    return struct {
        pub const @"json.ser.Formatter" = struct {
            impl: Impl,

            const Self = @This();

            /// Writes a `null` value to the specified writer.
            pub fn writeNull(self: Self, w: Writer) Writer.Error!void {
                if (methods.writeNull) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("writeNull is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Writes `true` or `false` to the specified writer.
            pub fn writeBool(self: Self, w: Writer, v: bool) Writer.Error!void {
                if (methods.writeBool) |f| {
                    try f(self.impl, w, v);
                } else {
                    @compileError("writeBool is not implemented by type: " ++ @typeName(Impl));
                }
            }

            // Writes an floating point value to the specified writer.
            pub fn writeFloat(self: Self, w: Writer, v: anytype) Writer.Error!void {
                if (methods.writeFloat) |f| {
                    switch (@typeInfo(@TypeOf(v))) {
                        .ComptimeFloat, .Float => try f(self.impl, w, v),
                        else => @compileError("expected float, found " ++ @typeName(@TypeOf(v))),
                    }
                } else {
                    @compileError("writeFloat is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Writes an integer value to the specified writer.
            pub fn writeInt(self: Self, w: Writer, v: anytype) Writer.Error!void {
                if (methods.writeInt) |f| {
                    switch (@typeInfo(@TypeOf(v))) {
                        .ComptimeInt, .Int => try f(self.impl, w, v),
                        else => @compileError("expected integer, found " ++ @typeName(@TypeOf(v))),
                    }
                } else {
                    @compileError("writeInt is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Writes a number that has already been rendered into a string.
            ///
            /// TODO: Check that the string is actually an integer when parsed.
            pub fn writeNumberString(self: Self, w: Writer, v: []const u8) Writer.Error!void {
                if (methods.writeNumberString) |f| {
                    try f(self.impl, w, v);
                } else {
                    @compileError("writeNumberString is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Called before each series of `write_string_fragment` and
            /// `write_char_escape`.  Writes a `"` to the specified writer.
            pub fn beginString(self: Self, w: Writer) Writer.Error!void {
                if (methods.beginString) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("beginString is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Called after each series of `write_string_fragment` and
            /// `write_char_escape`.  Writes a `"` to the specified writer.
            pub fn endString(self: Self, w: Writer) Writer.Error!void {
                if (methods.endString) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endString is not implemented by type: " ++ @typeName(Impl));
                }
            }

            /// Writes a string fragment that doesn't need any escaping to the
            /// specified writer.
            pub fn writeStringFragment(self: Self, w: Writer, v: []const u8) Writer.Error!void {
                if (methods.writeStringFragment) |f| {
                    try f(self.impl, w, v);
                } else {
                    @compileError("writeStringFragment is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn writeCharEscape(self: Self, w: Writer, v: u21) Writer.Error!void {
                if (methods.writeCharEscape) |f| {
                    try f(self.impl, w, v);
                } else {
                    @compileError("writeCharEscape is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn beginArray(self: Self, w: Writer) Writer.Error!void {
                if (methods.beginArray) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("beginArray is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn endArray(self: Self, w: Writer) Writer.Error!void {
                if (methods.endArray) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endArray is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn beginArrayValue(self: Self, w: Writer, first: bool) Writer.Error!void {
                if (methods.beginArrayValue) |f| {
                    try f(self.impl, w, first);
                } else {
                    @compileError("beginArrayValue is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn endArrayValue(self: Self, w: Writer) Writer.Error!void {
                if (methods.endArrayValue) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endArrayValue is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn beginObject(self: Self, w: Writer) Writer.Error!void {
                if (methods.beginObject) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("beginObject is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn endObject(self: Self, w: Writer) Writer.Error!void {
                if (methods.endObject) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endObject is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn beginObjectKey(self: Self, w: Writer, first: bool) Writer.Error!void {
                if (methods.beginObjectKey) |f| {
                    try f(self.impl, w, first);
                } else {
                    @compileError("beginObjectKey is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn endObjectKey(self: Self, w: Writer) Writer.Error!void {
                if (methods.endObjectKey) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endObjectKey is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn beginObjectValue(self: Self, w: Writer) Writer.Error!void {
                if (methods.beginObjectValue) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("beginObjectValue is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn endObjectValue(self: Self, w: Writer) Writer.Error!void {
                if (methods.endObjectValue) |f| {
                    try f(self.impl, w);
                } else {
                    @compileError("endObjectValue is not implemented by type: " ++ @typeName(Impl));
                }
            }

            pub fn writeRawFragment(self: Self, w: Writer, v: []const u8) Writer.Error!void {
                if (methods.writeRawFragment) |f| {
                    try f(self.impl, w, v);
                } else {
                    @compileError("writeRawFragment is not implemented by type: " ++ @typeName(Impl));
                }
            }
        };

        pub fn formatter(impl: Impl) @"json.ser.Formatter" {
            return .{ .impl = impl };
        }
    };
}
