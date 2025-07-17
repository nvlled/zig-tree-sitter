const std = @import("std");
const Allocator = std.mem.Allocator;

const InputEdit = @import("tree.zig").InputEdit;
const Language = @import("language.zig").Language;
const Point = @import("point.zig").Point;
const Range = @import("point.zig").Range;
const Tree = @import("tree.zig").Tree;
const TreeCursor = @import("tree_cursor.zig").TreeCursor;

/// A single node within a syntax tree.
pub const Node = extern struct {
    /// **Internal.** The context of the node.
    context: [4]u32,

    /// The ID of the node.
    ///
    /// Within any given syntax tree, no two nodes have the same ID.
    /// However, if a new tree is created based on an older tree,
    /// and a node from the old tree is reused in the process,
    /// then that node will have the same ID in both trees.
    id: *const anyopaque,

    /// **Internal.** The syntax tree this node belongs to.
    tree: *const Tree,

    /// Check if two nodes are identical.
    pub fn eql(self: Node, other: Node) bool {
        return ts_node_eq(self, other);
    }

    /// Get this node's type as a numerical id.
    pub fn kindId(self: Node) u16 {
        return ts_node_symbol(self);
    }

    /// Get the node's type as a numerical id as it appears in the grammar
    /// ignoring aliases.
    pub fn grammarId(self: Node) u16 {
        return ts_node_grammar_symbol(self);
    }

    /// Get this node's type as a string.
    pub fn kind(self: Node) []const u8 {
        return std.mem.span(ts_node_type(self));
    }

    /// Get this node's symbol name as it appears in the grammar ignoring
    /// aliases as a string.
    pub fn grammarKind(self: Node) []const u8 {
        return std.mem.span(ts_node_grammar_type(self));
    }

    /// Get the language that was used to parse this node's syntax tree.
    pub fn getLanguage(self: Node) *const Language {
        return ts_node_language(self);
    }

    /// Check if this node is *named*.
    ///
    /// Named nodes correspond to named rules in the grammar,
    /// whereas *anonymous* nodes correspond to string literals.
    pub fn isNamed(self: Node) bool {
        return ts_node_is_named(self);
    }

    /// Check if this node is *extra*.
    ///
    /// Extra nodes represent things like comments, which are not required by the
    /// grammar, but can appear anywhere.
    pub fn isExtra(self: Node) bool {
        return ts_node_is_extra(self);
    }

    /// Check if the node has been edited.
    pub fn hasChanges(self: Node) bool {
        return ts_node_has_changes(self);
    }

    /// Check if this node represents a syntax error or contains any syntax
    /// errors anywhere within it.
    pub fn hasError(self: Node) bool {
        return ts_node_has_error(self);
    }

    /// Check if this node represents a syntax error.
    ///
    /// Syntax errors represent parts of the code that could not be incorporated
    /// into a valid syntax tree.
    pub fn isError(self: Node) bool {
        return ts_node_is_error(self);
    }

    /// Check if this node is *missing*.
    ///
    /// Missing nodes are inserted by the parser in order to recover from
    /// certain kinds of syntax errors.
    pub fn isMissing(self: Node) bool {
        return ts_node_is_missing(self);
    }

    /// Get this node's parse state.
    pub fn parseState(self: Node) u16 {
        return ts_node_parse_state(self);
    }

    /// Get the parse state after this node.
    pub fn nextParseState(self: Node) u16 {
        return ts_node_next_parse_state(self);
    }

    /// Get the byte offset where this node starts.
    pub fn startByte(self: Node) u32 {
        return ts_node_start_byte(self);
    }

    /// Get the byte offset where this node ends.
    pub fn endByte(self: Node) u32 {
        return ts_node_end_byte(self);
    }

    /// Get this node's start position in terms of rows and columns.
    pub fn startPoint(self: Node) Point {
        return ts_node_start_point(self);
    }

    /// Get this node's end position in terms of rows and columns.
    pub fn endPoint(self: Node) Point {
        return ts_node_end_point(self);
    }

    /// Get the range of source code that this node represents, both in terms of
    /// raw bytes and of row/column coordinates.
    pub fn range(self: Node) Range {
        return .{
            .start_byte = self.startByte(),
            .end_byte = self.endByte(),
            .start_point = self.startPoint(),
            .end_point = self.endPoint(),
        };
    }

    /// Get the raw string contents that this node represents.
    ///
    /// `source` must be same string that was passed to parser.parseString().
    /// See also `Node.rawChildren()`.
    pub fn raw(self: Node, source: []const u8) []const u8 {
        const i = @min(self.startByte(), source.len);
        const j = @min(self.endByte(), source.len);
        return source[i..j];
    }

    /// Get the raw string contents the children in the given range (inclusive).
    ///
    /// `source` must be same string that was passed to parser.parseString().
    /// See also `Node.raw()`.
    pub fn rawChildren(
        self: Node,
        source: []const u8,
        child_index_start: u32,
        child_index_end: u32,
    ) []const u8 {
        const child_start = self.child(child_index_start) orelse return "";
        const child_end = self.child(child_index_end) orelse return "";
        const i = @min(child_start.startByte(), source.len);
        const j = @min(child_end.endByte(), source.len);
        return source[i..j];
    }

    /// Get the node's child at the given index, where zero represents the first
    /// child.
    ///
    /// This method is fairly fast, but its cost is technically log(i), so if
    /// you might be iterating over a long list of children, you should use
    /// `Node.children()` instead.
    pub fn child(self: Node, child_index: u32) ?Node {
        return ts_node_child(self, child_index).orNull();
    }

    /// Get this node's number of children.
    pub fn childCount(self: Node) u32 {
        return ts_node_child_count(self);
    }

    /// Get this node's *named* child at the given index.
    ///
    /// See also `Node.isNamed()`.
    /// This method is fairly fast, but its cost is technically log(i), so if
    /// you might be iterating over a long list of children, you should use
    /// `Node.namedChildren()` instead.
    pub fn namedChild(self: Node, child_index: u32) ?Node {
        return ts_node_named_child(self, child_index).orNull();
    }

    /// Get this node's number of *named* children.
    ///
    /// See also `Node.isNamed()`.
    pub fn namedChildCount(self: Node) u32 {
        return ts_node_named_child_count(self);
    }

    /// Get the first child with the given field name.
    ///
    /// If multiple children may have the same field name, access them using
    /// `Node.children_by_field_name`.
    pub fn childByFieldName(self: Node, name: []const u8) ?Node {
        return ts_node_child_by_field_name(self, name.ptr, @intCast(name.len)).orNull();
    }

    /// Get this node's child with the given numerical field id.
    ///
    /// See also `Node.childByFieldName()`. You can
    /// convert a field name to an id using `Language.fieldIdForName()`.
    pub fn childByFieldId(self: Node, field_id: u16) ?Node {
        return ts_node_child_by_field_id(self, field_id).orNull();
    }

    /// Get the field name of this node's child at the given index.
    pub fn fieldNameForChild(self: Node, child_index: u32) ?[]const u8 {
        return if (ts_node_field_name_for_child(self, child_index)) |name| std.mem.span(name) else null;
    }

    /// Get the field name of this node's named child at the given index.
    pub fn fieldNameForNamedChild(self: Node, child_index: u32) ?[]const u8 {
        return if (ts_node_field_name_for_named_child(self, child_index)) |name| std.mem.span(name) else null;
    }

    /// Iterate over this node's children.
    ///
    /// A `TreeCursor` is used to retrieve the children efficiently. Obtain
    /// a `TreeCursor` by calling `Tree.walk()` or `Node.walk()`. To avoid
    /// unnecessary allocations, you should reuse the same cursor for
    /// subsequent calls to this method.
    ///
    /// If you're walking the tree recursively, you may want to use the
    /// `TreeCursor` APIs directly instead.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn children(self: Node, cursor: *TreeCursor, allocator: Allocator) !std.ArrayList(Node) {
        var result = try std.ArrayList(Node).initCapacity(allocator, self.childCount());
        errdefer result.deinit();

        cursor.reset(self);
        if (!cursor.gotoFirstChild()) return result;

        try result.append(cursor.node());
        while (cursor.gotoNextSibling()) {
            try result.append(cursor.node());
        }

        return result;
    }

    /// Iterate over this node's named children.
    ///
    /// See also `Node.children()`.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn namedChildren(self: Node, cursor: *TreeCursor, allocator: Allocator) !std.ArrayList(Node) {
        var result = try std.ArrayList(Node).initCapacity(allocator, self.namedChildCount());
        errdefer result.deinit();

        cursor.reset(self);
        if (!cursor.gotoFirstChild()) return result;

        if (cursor.node().isNamed()) {
            try result.append(cursor.node());
        }

        while (cursor.gotoNextSibling()) {
            if (cursor.node().isNamed()) {
                try result.append(cursor.node());
            }
        }

        return result;
    }

    /// Iterate over this node's children with a given field name.
    ///
    /// See also `Node.children()`.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn childrenByFieldName(self: Node, field_name: []const u8, cursor: *TreeCursor, allocator: Allocator) !std.ArrayList(Node) {
        const field_id = self.getLanguage().fieldIdForName(field_name);
        return self.childrenByFieldId(field_id, cursor, allocator);
    }

    /// Iterate over this node's children with a given field id.
    ///
    /// See also `Node.childrenByFieldName()`.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn childrenByFieldId(self: Node, field_id: u32, cursor: *TreeCursor, allocator: Allocator) !std.ArrayList(Node) {
        var result = std.ArrayList(Node).init(allocator);
        errdefer result.deinit();
        if (field_id == 0) {
            return result;
        }

        cursor.reset(self);
        if (!cursor.gotoFirstChild()) {
            return result;
        }

        while (true) {
            if (cursor.fieldId() == field_id) {
                try result.append(cursor.node());
            }
            if (!cursor.gotoNextSibling()) {
                break;
            }
        }

        return result;
    }

    /// Get this node's immediate parent.
    /// Prefer `Node.child_with_descendant()` for iterating over this node's ancestors.
    pub fn parent(self: Node) ?Node {
        return ts_node_parent(self).orNull();
    }

    /// Get the node that contains `descendant`.
    ///
    /// Note that this can return `descendant` itself.
    pub fn childWithDescendant(self: Node, descendant: Node) ?Node {
        return ts_node_child_with_descendant(self, descendant).orNull();
    }

    /// Get this node's next sibling.
    pub fn nextSibling(self: Node) ?Node {
        return ts_node_next_sibling(self).orNull();
    }

    /// Get this node's previous sibling.
    pub fn prevSibling(self: Node) ?Node {
        return ts_node_prev_sibling(self).orNull();
    }

    /// Get this node's next named sibling.
    pub fn nextNamedSibling(self: Node) ?Node {
        return ts_node_next_named_sibling(self).orNull();
    }

    /// Get this node's previous named sibling.
    pub fn prevNamedSibling(self: Node) ?Node {
        return ts_node_prev_named_sibling(self).orNull();
    }

    /// Get this node's first child that contains or starts after the given byte offset.
    pub fn firstChildForByte(self: Node, byte: u32) ?Node {
        return ts_node_first_child_for_byte(self, byte).orNull();
    }

    /// Get this node's first *named* child that contains or starts after the given byte offset.
    pub fn firstNamedChildForByte(self: Node, byte: u32) ?Node {
        return ts_node_first_named_child_for_byte(self, byte).orNull();
    }

    /// Get the node's number of descendants, including one for the node itself.
    pub fn descendantCount(self: Node) u32 {
        return ts_node_descendant_count(self);
    }

    /// Get the smallest node within this node that spans the given byte range.
    pub fn descendantForByteRange(self: Node, start: u32, end: u32) ?Node {
        return ts_node_descendant_for_byte_range(self, start, end).orNull();
    }

    /// Get the smallest *named* node within this node that spans the given byte range.
    pub fn namedDescendantForByteRange(self: Node, start: u32, end: u32) ?Node {
        return ts_node_named_descendant_for_byte_range(self, start, end).orNull();
    }

    /// Get the smallest node within this node that spans the given point range.
    pub fn descendantForPointRange(self: Node, start: Point, end: Point) ?Node {
        return ts_node_descendant_for_point_range(self, start, end).orNull();
    }

    /// Get the smallest *named* node within this node that spans the given point range.
    pub fn namedDescendantForPointRange(self: Node, start: Point, end: Point) ?Node {
        return ts_node_named_descendant_for_point_range(self, start, end).orNull();
    }

    /// Get an S-expression representing the node.
    ///
    /// The caller is responsible for freeing it using `freeSexp`.
    pub fn toSexp(self: Node) [:0]const u8 {
        return std.mem.span(ts_node_string(self));
    }

    /// Free an S-expression allocated with `toSexp()`.
    pub fn freeSexp(sexp: [:0]const u8) void {
        ts_current_free(@ptrCast(@constCast(sexp)));
    }

    /// Creates a JSON representation of the node and writes the output to w.
    /// To get a string instead, use `Node.toJSON()`.
    ///
    /// If `source` is provided, then the `raw` fields are shown for the named leaf nodes.
    /// The `source` must be same string that was passed to parser.parseString().
    /// See also `Node.raw()`.
    pub fn writeJSON(self: Node, w: std.io.AnyWriter, options: struct {
        source: ?[]const u8 = null,
    }) !void {
        try Json.writeJSON(.{ .source = options.source }, self, w);
    }

    /// Get JSON string representation of the node.
    /// See also `Node.writeJSON()`.
    ///
    /// Note: Caller must free the returned string.
    pub fn toJSON(self: Node, allocator: Allocator, options: struct {
        source: ?[]const u8 = null,
    }) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try Json.writeJSON(.{ .source = options.source }, self, buf.writer().any());
        return buf.toOwnedSlice();
    }

    /// Create a new `TreeCursor` starting from this node.
    ///
    /// Note that the given node is considered the root of the cursor,
    /// and the cursor cannot walk outside this node.
    pub fn walk(self: Node) TreeCursor {
        return ts_tree_cursor_new(self);
    }

    /// Creates an iterator for the children of the current node.
    ///
    /// Caller should destroy the iterator if no longer needed.
    ///
    /// Note: Call `ChildIterator.reset()` before reusing the iterator for another loop.
    ///
    /// If the children will be recursively traversed, consider using TreeCursor instead.
    ///
    /// See also `Node.children()` and `Node.walk()`.
    ///
    /// Example usage:
    /// ```
    /// var iterator = node.iterateChildren();
    /// defer iterator.destroy();
    /// while (iterator.next()) |child| { ... }
    /// ```
    ///
    /// Example without iterator:
    /// ```
    /// var cursor = node.walk();
    /// defer cursor.destroy();
    /// if (cursor.gotoFirstChild()) {
    ///     while (true) {
    ///         const child = cursor.node();
    ///         ...
    ///         if (!cursor.nextSibling()) break;
    ///     }
    /// }
    /// ```
    pub fn iterateChildren(self: Node) TreeCursor.ChildIterator {
        return .{ .cursor = self.walk() };
    }

    /// Edit this node to keep it in-sync with source code that has been edited.
    ///
    /// This function is only rarely needed. When you edit a syntax tree with
    /// the `Tree.edit()` method, all of the nodes that you retrieve from
    /// the tree afterward will already reflect the edit. You only need to
    /// use `Node.edit()` when you have a specific `Node` instance that
    /// you want to keep and continue to use after an edit.
    pub fn edit(self: *Node, input_edit: InputEdit) void {
        ts_node_edit(self, &input_edit);
    }

    /// Format the node as a string.
    ///
    /// Use `{s}` to get an S-expression.
    pub fn format(self: Node, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (std.mem.eql(u8, fmt, "s")) {
            const sexp = self.toSexp();
            defer freeSexp(sexp);
            return writer.print("{s}", .{sexp});
        }

        if (fmt.len == 0 or std.mem.eql(u8, fmt, "any")) {
            return writer.print("Node(id=0x{x}, type={s}, start={d}, end={d})", .{
                @intFromPtr(self.id),
                self.kind(),
                self.startByte(),
                self.endByte(),
            });
        }

        return std.fmt.invalidFmtError(fmt, self);
    }

    fn orNull(self: Node) ?Node {
        return if (!ts_node_is_null(self)) self else null;
    }

    /// Json namespace contains functions used internally for Node.writeJSON.
    ///
    /// ## Purpose and comparison
    ///
    /// Json.writeJSON creates a readable JSON string representation of the node,
    /// primarily intended to be read by humans, so it uses a less optimal JSON structure.
    /// The JSON output should serve as a reference on how to
    /// traverse or navigate the constructed node tree.
    ///
    /// Tree-sitter can also output a sexp, but it's not very human readable
    /// by default and omits the unnamed nodes.
    /// Likewise, tree-sitter can also output SVG with dot graphs
    /// which is more readable than the sexp, but still omits some details.
    ///
    /// For comparison, consider the following code:
    /// ```
    /// int x = /*comment*/ 100;
    /// ```
    ///
    /// `Node.toSexp()` would show the following:
    /// ```
    /// (declaration type: (primitive_type) declarator: (init_declarator declarator: (identifier) value: (number_literal)))
    /// ```
    ///
    /// In contrast `Node.toJSON()` would show the following:
    /// JSON output:
    /// ```
    /// {
    ///     "kind_id": "198",
    ///     "kind": "declaration",
    ///     "0": {
    ///         "field": "type",
    ///         "kind_id": "93",
    ///         "kind": "primitive_type",
    ///         "raw": "int"
    ///     },
    ///     "1": {
    ///         "field": "declarator",
    ///         "kind_id": "240",
    ///         "kind": "init_declarator",
    ///         "0": {
    ///             "field": "declarator",
    ///             "kind_id": "1",
    ///             "kind": "identifier",
    ///             "raw": "x"
    ///         },
    ///         "1": "=",
    ///         "2": {
    ///             "kind_id": "160",
    ///             "kind": "comment",
    ///             "raw": "/*comment*/"
    ///         },
    ///         "3": {
    ///             "field": "value",
    ///             "kind_id": "141",
    ///             "kind": "number_literal",
    ///             "raw": "100"
    ///         }
    ///     },
    ///     "2": ";"
    /// }
    /// ```
    ///
    /// ## JSON structure description
    ///
    /// - named nodes are objects: {kind_id: ...}
    ///
    /// - unnamed nodes are strings, for example
    ///   in the above, the unnamed nodes are:
    ///     - "1": "="
    ///     - "2": ";"
    ///   the value is the node kind, for example: ";" == node.kind()
    ///
    /// - number-keyed values are children of a node,
    ///   for example in the above, the root node's children are:
    ///     - "0": { ... },
    ///     - "1": { ... },
    ///     - "2": ";"
    ///   the number represents the child_index
    ///
    /// - non-number keys are properties of the node:
    ///     - "kind"    -> value is node.kind()
    ///     - "kind_id" -> value is node.kind_id()
    ///     - "raw"     -> value is node.raw()
    ///     - "field"   -> value is parent_node.fieldNameForChild(child_index)
    const Json = struct {
        /// This is the same string that was passed to parser.parseString().
        /// Used to get the raw string contents of a node. For instance,
        /// For comment nodes, it would return the actual comment text.
        source: ?[]const u8 = null,
        // Ideally source could be taken directly from the Node or Tree,
        // but from the looks of it, tree-sitter doesn't store that
        // data anywhere, or at least it didn't make it part of the public API.

        const Self = @This();

        pub fn writeJSON(self: Self, node: Node, w: std.io.AnyWriter) !void {
            var cursor = node.walk();
            try doWriteJSON(self, w, &cursor);
            try w.writeAll("\n");
        }

        pub fn doWriteJSON(
            self: Self,
            w: std.io.AnyWriter,
            cursor: *TreeCursor,
        ) !void {
            // a wrapper writer that escapes characters that could break JSON
            const mw = CharMapWriter.create(w, escapeChars);

            const node = cursor.node();
            const level = cursor.depth() + 1;

            try w.writeAll("{\n");
            if (cursor.fieldName()) |name| {
                try writeIndent(w, level);
                try w.print("\"field\": \"{s}\",\n", .{name});
            }

            try writeIndent(w, level);
            try w.print("\"kind_id\": \"{d}\",\n", .{node.kindId()});
            try writeIndent(w, level);
            try w.print("\"kind\": \"{s}\",\n", .{node.kind()});

            if (node.childCount() == 0 and self.source != null) {
                // show raw string of leaf nodes
                try writeIndent(w, level);
                try w.writeAll("\"raw\": \"");

                try mw.writeAll(raw(
                    node,
                    self.source.?,
                ));

                try w.writeAll("\"\n");
            }

            if (cursor.gotoFirstChild()) {
                var i: u32 = 0;
                while (true) {
                    const c = cursor.node();
                    if (!c.isNamed()) {
                        try writeIndent(w, level);
                        try w.print("\"{d}\"", .{i});
                        try w.writeAll(": \"");
                        try mw.writeAll(c.kind());
                        try w.writeAll("\"");
                    } else {
                        try writeIndent(w, level);
                        try w.print("\"{d}\": ", .{i});
                        try doWriteJSON(self, w, cursor);
                    }

                    if (cursor.gotoNextSibling()) {
                        try w.writeAll(",\n");
                    } else {
                        try w.writeAll("\n");
                        break;
                    }

                    i += 1;
                }
                _ = cursor.gotoParent();
            }

            try writeIndent(w, level - 1);
            try w.writeAll("}");
        }

        fn escapeChars(ch: u8) []const u8 {
            return switch (ch) {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\t' => "\\t",
                '\n' => "\\n",
                0x8 => "\\b",
                0xC => "\\f",
                0xD => "\\r",
                else => &.{ch},
            };
        }

        inline fn writeIndent(w: std.io.AnyWriter, level: usize) !void {
            try w.writeByteNTimes(' ', level * 4);
        }
    };

    /// A writer wrapper that converts written characters to another.
    /// Used to escape or prepend certain characters with a backslash.
    ///
    /// Example: convert all " to \" that is written to w
    ///   const mapper = struct {
    ///       fn _(ch: u8) []const u8 {
    ///           return switch (ch) {
    ///               '"' => "\\\"",
    ///               '\\' => "\\\\",
    ///               else => &.{ch},
    ///           };
    ///       }
    ///   }._;
    ///   try EscapedWriter.create(w, mapper).writeAll(child.kind());
    const CharMapWriter = struct {
        const Self = @This();
        const Writer = std.io.GenericWriter(Self, anyerror, write);

        w: std.io.AnyWriter,
        charMap: *const fn (ch: u8) []const u8,

        fn write(self: Self, bytes: []const u8) anyerror!usize {
            for (bytes) |ch| {
                try self.w.writeAll(self.charMap(ch));
            }

            // Returning a number > bytes.len causes a panic,
            // so just return bytes.len, even though one or more added \ characters
            // were written.
            return bytes.len;
        }

        pub fn writer(self: Self) Writer {
            return .{ .context = self };
        }

        pub fn create(w: std.io.AnyWriter, f: *const fn (u8) []const u8) Writer {
            const self = Self{ .w = w, .charMap = f };
            return .{ .context = self };
        }
    };
};

extern var ts_current_free: *const fn ([*]u8) callconv(.C) void;
extern fn ts_node_child(self: Node, child_index: u32) Node;
extern fn ts_node_child_by_field_id(self: Node, field_id: u16) Node;
extern fn ts_node_child_by_field_name(self: Node, name: [*]const u8, name_length: u32) Node;
extern fn ts_node_child_containing_descendant(self: Node, descendant: Node) Node;
extern fn ts_node_child_with_descendant(self: Node, descendant: Node) Node;
extern fn ts_node_child_count(self: Node) u32;
extern fn ts_node_descendant_count(self: Node) u32;
extern fn ts_node_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
extern fn ts_node_descendant_for_point_range(self: Node, start: Point, end: Point) Node;
extern fn ts_node_edit(self: *Node, edit: *const InputEdit) void;
extern fn ts_node_end_byte(self: Node) u32;
extern fn ts_node_end_point(self: Node) Point;
extern fn ts_node_eq(self: Node, other: Node) bool;
extern fn ts_node_field_name_for_child(self: Node, child_index: u32) ?[*:0]const u8;
extern fn ts_node_field_name_for_named_child(self: Node, named_child_index: u32) ?[*:0]const u8;
extern fn ts_node_first_child_for_byte(self: Node, byte: u32) Node;
extern fn ts_node_first_named_child_for_byte(self: Node, byte: u32) Node;
extern fn ts_node_grammar_symbol(self: Node) u16;
extern fn ts_node_grammar_type(self: Node) [*:0]const u8;
extern fn ts_node_has_changes(self: Node) bool;
extern fn ts_node_has_error(self: Node) bool;
extern fn ts_node_is_error(self: Node) bool;
extern fn ts_node_is_extra(self: Node) bool;
extern fn ts_node_is_missing(self: Node) bool;
extern fn ts_node_is_named(self: Node) bool;
extern fn ts_node_is_null(self: Node) bool;
extern fn ts_node_language(self: Node) *const Language;
extern fn ts_node_named_child(self: Node, child_index: u32) Node;
extern fn ts_node_named_child_count(self: Node) u32;
extern fn ts_node_named_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
extern fn ts_node_named_descendant_for_point_range(self: Node, start: Point, end: Point) Node;
extern fn ts_node_next_named_sibling(self: Node) Node;
extern fn ts_node_next_parse_state(self: Node) u16;
extern fn ts_node_next_sibling(self: Node) Node;
extern fn ts_node_parent(self: Node) Node;
extern fn ts_node_parse_state(self: Node) u16;
extern fn ts_node_prev_named_sibling(self: Node) Node;
extern fn ts_node_prev_sibling(self: Node) Node;
extern fn ts_node_start_byte(self: Node) u32;
extern fn ts_node_start_point(self: Node) Point;
extern fn ts_node_string(self: Node) [*c]u8;
extern fn ts_node_symbol(self: Node) u16;
extern fn ts_node_type(self: Node) [*:0]const u8;
extern fn ts_tree_cursor_new(node: Node) TreeCursor;
