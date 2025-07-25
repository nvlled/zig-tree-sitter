const std = @import("std");

const Point = @import("point.zig").Point;
const Node = @import("node.zig").Node;
const Tree = @import("tree.zig").Tree;

/// A stateful object for walking a syntax tree efficiently.
pub const TreeCursor = extern struct {
    /// **Internal.** The syntax tree this cursor belongs to.
    tree: *const Tree,

    /// **Internal.** The id of the tree cursor.
    id: *const anyopaque,

    /// **Internal.** The context of the tree cursor.
    context: [3]u32,

    /// Delete the tree cursor, freeing all of the memory that it used.
    pub fn destroy(self: *TreeCursor) void {
        ts_tree_cursor_delete(self);
    }

    /// Create a deep copy of the tree cursor.
    pub fn dupe(self: *const TreeCursor) TreeCursor {
        return ts_tree_cursor_copy(self);
    }

    /// Get the current node of the tree cursor.
    pub fn node(self: *const TreeCursor) Node {
        return ts_tree_cursor_current_node(self);
    }

    /// Get the numerical field id of this tree cursor's current node.
    ///
    /// This returns `0` if the current node doesn't have a field.
    ///
    /// See also `TreeCursor.field_name`.
    pub fn fieldId(self: *const TreeCursor) u16 {
        return ts_tree_cursor_current_field_id(self);
    }

    /// Get the field name of the tree cursor's current node.
    ///
    /// This returns `null` if the current node doesn't have a field.
    pub fn fieldName(self: *const TreeCursor) ?[]const u8 {
        return if (ts_tree_cursor_current_field_name(self)) |name| std.mem.span(name) else null;
    }

    /// Get the depth of the cursor's current node relative to
    /// the original node that the cursor was constructed with.
    pub fn depth(self: *const TreeCursor) u32 {
        return ts_tree_cursor_current_depth(self);
    }

    /// Get the index of the cursor's current node out of all of the
    /// descendants of the original node that the cursor was constructed with.
    pub fn descendantIndex(self: *const TreeCursor) u32 {
        return ts_tree_cursor_current_descendant_index(self);
    }

    /// Move the cursor to the first child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there were no children.
    pub fn gotoFirstChild(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_first_child(self);
    }

    /// Go to the first named child of the current node.
    ///
    /// Note: If there are no named child found,
    /// the cursor will be on the last anonymous child, if there is one.
    ///
    /// See also `TreeCursor.firstChild` and `TreeCursor.gotoFirstChild`.
    pub fn gotoFirstNamedChild(self: *TreeCursor) bool {
        if (!ts_tree_cursor_goto_first_child(self)) return false;
        while (true) {
            const child = self.node();
            if (child.isNamed()) return true;
            if (!ts_tree_cursor_goto_next_sibling(self)) return false;
        }
    }

    /// Move the cursor to the last child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there were no children.
    pub fn gotoLastChild(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_last_child(self);
    }

    /// Go to the last named child of the current node.
    ///
    /// Note: If there are no named child found,
    /// the cursor will be on the first anonymous child if there is one.
    ///
    /// See also `TreeCursor.firstChild` and `TreeCursor.gotoFirstChild`.
    pub fn gotoLastNamedChild(self: *TreeCursor) bool {
        if (!ts_tree_cursor_goto_last_child(self)) return false;
        while (true) {
            const child = self.node();
            if (child.isNamed()) return true;
            if (!ts_tree_cursor_goto_previous_sibling(self)) return false;
        }
    }

    /// Move the cursor to the parent of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there was no parent node.
    pub fn gotoParent(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_parent(self);
    }

    /// Move the cursor to the next sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there was no next sibling node.
    pub fn gotoNextSibling(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_next_sibling(self);
    }

    /// Go to the next named sibling of the current node.
    ///
    /// Note: If there are no next named siblings found,
    /// the cursor will be on the last anonymous node.
    ///
    /// See also `TreeCursor.nextSibling` and `TreeCursor.gotoNextSibling`.
    pub fn gotoNextNamedSibling(self: *TreeCursor) bool {
        while (ts_tree_cursor_goto_next_sibling(self)) {
            const sibling = self.node();
            if (sibling.isNamed()) return true;
        }
        return false;
    }

    /// Move this cursor to the previous sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// and returns `false` if there was no previous sibling node.
    ///
    /// Note, that this function may be slower than `TreeCursor.goto_next_sibling`
    /// due to how node positions are stored. In the worst case, this will
    /// need to iterate through all the children up to the previous sibling node
    /// to recalculate its position. Also note that the node the cursor was
    /// constructed with is considered the root of the cursor, and the cursor
    /// cannot walk outside this node.
    pub fn gotoPreviousSibling(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_previous_sibling(self);
    }

    /// Go to the previous named sibling of the current node.
    ///
    /// Note: If there are no previous named siblings found,
    /// the cursor will be on the first anonymous node.
    ///
    /// See also `TreeCursor.previousSibling` and `TreeCursor.gotoPreviousSibling`.
    pub fn gotoPreviousNamedSibling(self: *TreeCursor) bool {
        while (ts_tree_cursor_goto_previous_sibling(self)) {
            const sibling = self.node();
            if (sibling.isNamed()) return true;
        }
        return false;
    }

    /// Move the cursor to the nth descendant node of the
    /// original node that the cursor was constructed with,
    /// where `0` represents the original node itself.
    pub fn gotoDescendant(self: *TreeCursor, index: u32) void {
        return ts_tree_cursor_goto_descendant(self, index);
    }

    /// Move the cursor to the first child of its current node
    /// that contains or starts after the given byte offset.
    ///
    /// This returns the index of the child node if one was found, or `null`.
    pub fn gotoFirstChildForByte(self: *TreeCursor, byte: u32) ?u32 {
        const index = ts_tree_cursor_goto_first_child_for_byte(self, byte);
        return if (index >= 0) @intCast(index) else null;
    }

    /// Move the cursor to the first child of its current node
    /// that contains or starts after the given point.
    ///
    /// This returns the index of the child node if one was found, or `null`.
    pub fn gotoFirstChildForPoint(self: *TreeCursor, point: Point) ?u32 {
        const index = ts_tree_cursor_goto_first_child_for_point(self, point);
        return if (index >= 0) @intCast(index) else null;
    }

    /// Re-initialize a tree cursor to start at the node it was constructed with.
    pub fn reset(self: *TreeCursor, target: Node) void {
        ts_tree_cursor_reset(self, target);
    }

    /// Re-initialize a tree cursor to the same position as another cursor.
    ///
    /// Unlike `TreeCursor.reset`, this will not lose parent
    /// information and allows reusing already created cursors.
    pub fn resetTo(self: *TreeCursor, other: *const TreeCursor) void {
        ts_tree_cursor_reset_to(self, other);
    }

    /// Get the first child of the current node.
    /// Moves the cursor to that child if found.
    ///
    /// See also `TreeCursor.gotoFirstChild`.
    pub fn firstChild(self: *TreeCursor) ?Node {
        return switch (ts_tree_cursor_goto_first_child(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the last child of the current node.
    /// Moves the cursor to that child if found.
    ///
    /// See also `TreeCursor.gotoLastChild`.
    pub fn lastChild(self: *TreeCursor) ?Node {
        return switch (ts_tree_cursor_goto_last_child(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the next sibling of the current node.
    /// Moves the cursor to that sibling if found.
    ///
    /// See also `TreeCursor.gotoNextSibling`.
    pub fn nextSibling(self: *TreeCursor) ?Node {
        return switch (ts_tree_cursor_goto_next_sibling(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the previous sibling of the current node.
    /// Moves the cursor to that sibling if found.
    ///
    /// See also `TreeCursor.gotoPreviousSibling`.
    pub fn previousSibling(self: *TreeCursor) ?Node {
        return switch (ts_tree_cursor_goto_previous_sibling(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the first named child of the current node.
    /// Moves the cursor to that child if found.
    ///
    /// See also `TreeCursor.firstChild` and `TreeCursor.gotoFirstNamedChild`.
    pub fn firstNamedChild(self: *TreeCursor) ?Node {
        return switch (gotoFirstNamedChild(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the last named child of the current node.
    /// Moves the cursor to that child if found.
    ///
    /// See also `TreeCursor.lastChild` and `TreeCursor.gotoLastNamedChild`.
    pub fn lastNamedChild(self: *TreeCursor) ?Node {
        return switch (gotoLastNamedChild(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the next named sibling of the current node.
    /// Moves the cursor to that sibling if found.
    ///
    /// See also `TreeCursor.nextSibling` and `TreeCursor.gotoNextNamedSibling`.
    pub fn nextNamedSibling(self: *TreeCursor) ?Node {
        return switch (gotoNextNamedSibling(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// Get the previous named sibling of the current node.
    /// Moves the cursor to that sibling if found.
    ///
    /// See also `TreeCursor.previousSibling` and `TreeCursor.gotoPreviousNamedSibling`.
    pub fn previousNamedSibling(self: *TreeCursor) ?Node {
        return switch (gotoPreviousNamedSibling(self)) {
            true => ts_tree_cursor_current_node(self),
            false => null,
        };
    }

    /// ChildIterator is used to simplify the iteration of node children.
    ///
    /// See `Node.iterateChildren` for examples on how to use the iterator.
    ///
    /// `ChildIterator.cursor` is for internal use only.
    /// Explicitly moving the cursor with cursor.goto* methods while
    /// iterator is active will lead to undefined behaviour.
    pub const ChildIterator = struct {
        cursor: TreeCursor,

        initial: bool = true,

        const Self = @This();

        pub fn next(self: *Self) ?Node {
            defer self.initial = false;
            return switch (self.initial) {
                true => self.cursor.firstChild(),
                false => self.cursor.nextSibling(),
            };
        }

        pub fn previous(self: *Self) ?Node {
            defer self.initial = false;
            return switch (self.initial) {
                true => self.cursor.lastChild(),
                false => self.cursor.previousSibling(),
            };
        }

        pub fn nextNamed(self: *Self) ?Node {
            defer self.initial = false;
            return switch (self.initial) {
                true => self.cursor.firstNamedChild(),
                false => self.cursor.nextNamedSibling(),
            };
        }

        pub fn previousNamed(self: *Self) ?Node {
            defer self.initial = false;
            return switch (self.initial) {
                true => self.cursor.lastNamedChild(),
                false => self.cursor.previousNamedSibling(),
            };
        }

        pub fn reset(self: *Self) void {
            self.initial = true;
            _ = self.cursor.gotoParent();
        }

        pub inline fn destroy(self: *Self) void {
            self.cursor.destroy();
        }

        pub inline fn fieldId(self: *const Self) u16 {
            return ts_tree_cursor_current_field_id(&self.cursor);
        }

        pub inline fn fieldName(self: *const Self) ?[]const u8 {
            return if (ts_tree_cursor_current_field_name(&self.cursor)) |name|
                std.mem.span(name)
            else
                null;
        }
    };
};

extern fn ts_tree_cursor_delete(self: *TreeCursor) void;
extern fn ts_tree_cursor_reset(self: *TreeCursor, node: Node) void;
extern fn ts_tree_cursor_reset_to(dst: *TreeCursor, src: *const TreeCursor) void;
extern fn ts_tree_cursor_current_node(self: *const TreeCursor) Node;
extern fn ts_tree_cursor_current_field_name(self: *const TreeCursor) ?[*:0]const u8;
extern fn ts_tree_cursor_current_field_id(self: *const TreeCursor) u16;
extern fn ts_tree_cursor_goto_parent(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_next_sibling(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_previous_sibling(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_first_child(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_last_child(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_descendant(self: *TreeCursor, goal_descendant_index: u32) void;
extern fn ts_tree_cursor_current_descendant_index(self: *const TreeCursor) u32;
extern fn ts_tree_cursor_current_depth(self: *const TreeCursor) u32;
extern fn ts_tree_cursor_goto_first_child_for_byte(self: *TreeCursor, goal_byte: u32) i64;
extern fn ts_tree_cursor_goto_first_child_for_point(self: *TreeCursor, goal_point: Point) i64;
extern fn ts_tree_cursor_copy(cursor: *const TreeCursor) TreeCursor;
