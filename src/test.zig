const std = @import("std");
const testing = std.testing;
const ts = @import("root.zig");

extern fn tree_sitter_c() *const ts.Language;

test "Language" {
    const language = tree_sitter_c();
    defer language.destroy();

    try testing.expectEqual(14, language.abiVersion());
    try testing.expectEqual(null, language.metadata());
    try testing.expect(language.nodeKindCount() > 1);
    try testing.expect(language.fieldCount() > 1);
    try testing.expect(language.parseStateCount() > 1);
    try testing.expect(language.fieldIdForName("body") > 0);
    try testing.expect(language.fieldNameForId(1) != null);
    try testing.expectEqual(161, language.idForNodeKind("translation_unit", true));
    try testing.expectEqualStrings("identifier", language.nodeKindForId(1) orelse "");
    try testing.expect(language.nodeKindIsNamed(1));
    try testing.expect(language.nodeKindIsVisible(1));
    try testing.expect(!language.nodeKindIsSupertype(1));
    try testing.expect(language.nextState(1, 161) > 1);

    const copy = language.dupe();
    try testing.expectEqual(language, copy);
    copy.destroy();
}

test "LookaheadIterator" {
    const language = tree_sitter_c();
    defer language.destroy();

    const state = language.nextState(1, 161);
    const lookahead = language.lookaheadIterator(state).?;
    defer lookahead.destroy();

    try testing.expectEqual(language, lookahead.language());
    try testing.expectEqual(0xFFFF, lookahead.currentSymbol());
    try testing.expectEqualStrings("ERROR", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(160, lookahead.currentSymbol());
    try testing.expectEqualStrings("comment", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(0, lookahead.currentSymbol());
    try testing.expectEqualStrings("end", lookahead.currentSymbolName());

    try testing.expect(!lookahead.next());
    try testing.expect(lookahead.resetState(state));

    try testing.expect(lookahead.next());
    try testing.expect(lookahead.reset(language, state));
}

test "Parser" {
    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    try testing.expectEqual(language, parser.getLanguage());
    try testing.expectEqual(null, parser.getLogger().log);
    try testing.expectEqual(0, parser.getTimeoutMicros());
    try testing.expectEqual(null, parser.getCancellationFlag());

    try testing.expectEqualSlices(ts.Range, &.{.{}}, parser.getIncludedRanges());
    try testing.expectError(error.IncludedRangesError, parser.setIncludedRanges(&.{ .{ .start_byte = 1 }, .{} }));

    // TODO: more tests
}

test "Tree" {
    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("int main() {}", null, .UTF_8).?;
    defer tree.destroy();
    try testing.expectEqual(language, tree.getLanguage());
    try testing.expectEqual(13, tree.rootNode().endByte());
    try testing.expectEqual(3, tree.rootNodeWithOffset(3, .{ .row = 0, .column = 3 }).startByte());

    var ranges = tree.getIncludedRanges();
    var range: ts.Range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0xFFFFFFFF, .column = 0xFFFFFFFF },
        .start_byte = 0,
        .end_byte = 0xFFFFFFFF,
    };
    try testing.expectEqualSlices(ts.Range, &.{range}, ranges);
    ts.Tree.freeRanges(ranges);

    const old_tree = tree.dupe();
    try testing.expect(tree != old_tree);
    defer old_tree.destroy();

    old_tree.edit(.{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    });
    const new_tree = parser.parseStringEncoding("main() {}", old_tree, .UTF_8).?;
    defer new_tree.destroy();
    range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0, .column = 9 },
        .start_byte = 0,
        .end_byte = 9,
    };
    ranges = old_tree.getChangedRanges(new_tree);
    try testing.expectEqualSlices(ts.Range, &.{range}, ranges);
    ts.Tree.freeRanges(ranges);
}

test "TreeCursor" {
    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("int main() {}", null, .UTF_8).?;
    defer tree.destroy();
    const root_node = tree.rootNode();

    var cursor = root_node.walk();
    defer cursor.destroy();

    var node = cursor.node();
    try testing.expect(node.eql(root_node));
    try testing.expectEqual(node, cursor.node());

    var copy = cursor.dupe();
    try testing.expect(cursor.id != copy.id);
    try testing.expectEqual(cursor.tree, copy.tree);

    cursor.resetTo(&copy);
    try testing.expectEqual(copy.node(), cursor.node());
    copy.destroy();

    try testing.expect(cursor.gotoFirstChild());
    try testing.expectEqualStrings("function_definition", cursor.node().kind());
    try testing.expectEqual(1, cursor.depth());

    try testing.expect(cursor.gotoLastChild());
    try testing.expectEqualStrings("compound_statement", cursor.node().kind());
    try testing.expectEqualStrings("body", cursor.fieldName().?);

    try testing.expect(cursor.gotoParent());
    try testing.expectEqualStrings("function_definition", cursor.node().kind());
    try testing.expectEqual(0, cursor.fieldId());

    try testing.expect(!cursor.gotoNextSibling());
    try testing.expect(!cursor.gotoPreviousSibling());

    cursor.gotoDescendant(2);
    try testing.expectEqual(2, cursor.descendantIndex());
    cursor.reset(root_node);

    try testing.expectEqual(0, cursor.gotoFirstChildForByte(1));
    try testing.expectEqual(1, cursor.gotoFirstChildForPoint(.{ .row = 0, .column = 5 }));
    try testing.expectEqualStrings("declarator", cursor.fieldName().?);
}

test "Node" {
    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("int main() {}", null, .UTF_8).?;
    defer tree.destroy();
    var node = tree.rootNode();

    try testing.expectEqual(tree, node.tree);
    try testing.expectEqual(tree.getLanguage(), node.getLanguage());

    try testing.expectEqual(161, node.kindId());
    try testing.expectEqual(161, node.grammarId());
    try testing.expectEqualStrings("translation_unit", node.kind());
    try testing.expectEqualStrings("translation_unit", node.grammarKind());

    try testing.expect(node.isNamed());
    try testing.expect(!node.isExtra());
    try testing.expect(!node.isError());
    try testing.expect(!node.isMissing());

    try testing.expectEqual(0, node.parseState());
    try testing.expectEqual(0, node.nextParseState());

    try testing.expectEqual(0, node.startByte());
    try testing.expectEqual(13, node.endByte());
    try testing.expectEqual(0, node.startPoint().column);
    try testing.expectEqual(13, node.endPoint().column);

    const range = node.range();
    try testing.expectEqual(0, range.start_byte);
    try testing.expectEqual(13, range.end_byte);
    try testing.expectEqual(0, range.start_point.column);
    try testing.expectEqual(13, range.end_point.column);

    try testing.expectEqual(1, node.childCount());
    try testing.expectEqual(1, node.namedChildCount());
    try testing.expectEqual(11, node.descendantCount());

    node = node.child(0).?;
    try testing.expectEqual(tree.rootNode(), node.parent());
    try testing.expectEqualStrings("function_declarator", node.namedChild(1).?.kind());
    try testing.expectEqual(null, node.childByFieldId(1));
    try testing.expectEqualStrings("primitive_type", node.childByFieldName("type").?.kind());

    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextNamedSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevNamedSibling().?.kind());

    try testing.expectEqual(node, tree.rootNode().childWithDescendant(node));
    try testing.expectEqualStrings("{", node.descendantForByteRange(11, 12).?.kind());
    try testing.expectEqualStrings("compound_statement", node.namedDescendantForByteRange(11, 12).?.kind());

    const points: [2]ts.Point = .{ .{ .row = 0, .column = 4 }, .{ .row = 0, .column = 8 } };
    try testing.expectEqualStrings("identifier", node.descendantForPointRange(points[0], points[1]).?.kind());
    try testing.expectEqualStrings("identifier", node.namedDescendantForPointRange(points[0], points[1]).?.kind());

    try testing.expectEqualStrings("body", node.fieldNameForChild(2).?);
    try testing.expectEqualStrings("body", node.fieldNameForNamedChild(2).?);

    const sexp = node.toSexp();
    defer ts.Node.freeSexp(sexp);
    try testing.expectStringStartsWith(sexp, "(function_definition type:");

    const new_tree = tree.dupe();
    defer new_tree.destroy();
    const edit: ts.InputEdit = .{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    };
    new_tree.edit(edit);
    node = new_tree.rootNode();
    node.edit(edit);

    try testing.expect(node.hasChanges());
    try testing.expect(!node.hasError());
}

test "Node children getter" {
    const allocator = std.testing.allocator;

    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("for (int x = 0; x < 5; x++) {}", null, .UTF_8).?;
    defer tree.destroy();
    const root_node = tree.rootNode();
    const forloop = root_node.child(0) orelse @panic("expected a for-loop node");

    var cursor = root_node.walk();
    defer cursor.destroy();

    // forloop node consists of the following: (4 named, 4 unnamed,  8 total)
    //   [0] "for"
    //   [1] "("
    //   [2] declaration type (named as initializer)
    //   [3] binary_expression (named as condition)
    //   [4] ";"
    //   [5] update_expression (named as update)
    //   [6] ")"
    //   [7] compound_statement (named as body)

    const children = try forloop.children(&cursor, allocator);
    defer children.deinit();

    const named_children = try forloop.namedChildren(&cursor, allocator);
    defer named_children.deinit();

    const init_children = try forloop.childrenByFieldName(
        "initializer",
        &cursor,
        allocator,
    );
    defer init_children.deinit();

    try std.testing.expectEqual(8, children.items.len);
    try std.testing.expectEqual(4, named_children.items.len);
    try std.testing.expectEqual(1, init_children.items.len);
}

test "Node children iteration" {
    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("for (int x = 0; x < 5; x++) {}", null, .UTF_8).?;
    defer tree.destroy();
    const root_node = tree.rootNode();
    const forloop = root_node.child(0) orelse @panic("expected a for-loop node");

    var iter = forloop.iterateChildren();
    defer iter.destroy();

    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(forloop.childCount(), count);

    count = 0;
    iter.reset();
    while (iter.nextNamed()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(forloop.namedChildCount(), count);

    count = 0;
    iter.reset();
    while (iter.previousNamed()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(forloop.namedChildCount(), count);

    iter.reset();
    try std.testing.expectEqualStrings("for", iter.next().?.kind());
    try std.testing.expectEqualStrings("(", iter.next().?.kind());
    try std.testing.expectEqualStrings("declaration", iter.next().?.kind());
    try std.testing.expectEqualStrings("binary_expression", iter.next().?.kind());
    try std.testing.expectEqualStrings(";", iter.next().?.kind());
    try std.testing.expectEqualStrings("update_expression", iter.next().?.kind());
    try std.testing.expectEqualStrings(")", iter.next().?.kind());
    try std.testing.expectEqualStrings("compound_statement", iter.next().?.kind());
    try std.testing.expectEqual(null, iter.next());
    try std.testing.expectEqual(null, iter.next());

    iter.reset();
    try std.testing.expectEqualStrings("compound_statement", iter.previousNamed().?.kind());
    try std.testing.expectEqualStrings("update_expression", iter.previousNamed().?.kind());
    try std.testing.expectEqualStrings("binary_expression", iter.previousNamed().?.kind());
    try std.testing.expectEqualStrings("declaration", iter.previousNamed().?.kind());
    try std.testing.expectEqual(null, iter.previousNamed());
    try std.testing.expectEqual(null, iter.previous());
}

test "Node to JSON" {
    const allocator = std.testing.allocator;

    const language = tree_sitter_c();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source = "for(int x = 0; x < 5; x++) { }";

    const tree = parser.parseStringEncoding(source, null, .UTF_8).?;
    defer tree.destroy();
    const root_node = tree.rootNode();
    const forloop = root_node.child(0) orelse @panic("expected a for-loop node");

    var cursor = root_node.walk();
    defer cursor.destroy();

    const json = try forloop.toJSON(allocator, .{ .source = source });
    defer allocator.free(json);

    const expected =
        \\{
        \\    "kind_id": "273",
        \\    "kind": "for_statement",
        \\    "0": "for",
        \\    "1": "(",
        \\    "2": {
        \\        "field": "initializer",
        \\        "kind_id": "198",
        \\        "kind": "declaration",
        \\        "0": {
        \\            "field": "type",
        \\            "kind_id": "93",
        \\            "kind": "primitive_type",
        \\            "raw": "int"
        \\        },
        \\        "1": {
        \\            "field": "declarator",
        \\            "kind_id": "240",
        \\            "kind": "init_declarator",
        \\            "0": {
        \\                "field": "declarator",
        \\                "kind_id": "1",
        \\                "kind": "identifier",
        \\                "raw": "x"
        \\            },
        \\            "1": "=",
        \\            "2": {
        \\                "field": "value",
        \\                "kind_id": "141",
        \\                "kind": "number_literal",
        \\                "raw": "0"
        \\            }
        \\        },
        \\        "2": ";"
        \\    },
        \\    "3": {
        \\        "field": "condition",
        \\        "kind_id": "290",
        \\        "kind": "binary_expression",
        \\        "0": {
        \\            "field": "left",
        \\            "kind_id": "1",
        \\            "kind": "identifier",
        \\            "raw": "x"
        \\        },
        \\        "1": "<",
        \\        "2": {
        \\            "field": "right",
        \\            "kind_id": "141",
        \\            "kind": "number_literal",
        \\            "raw": "5"
        \\        }
        \\    },
        \\    "4": ";",
        \\    "5": {
        \\        "field": "update",
        \\        "kind_id": "291",
        \\        "kind": "update_expression",
        \\        "0": {
        \\            "field": "argument",
        \\            "kind_id": "1",
        \\            "kind": "identifier",
        \\            "raw": "x"
        \\        },
        \\        "1": "++"
        \\    },
        \\    "6": ")",
        \\    "7": {
        \\        "field": "body",
        \\        "kind_id": "241",
        \\        "kind": "compound_statement",
        \\        "0": "{",
        \\        "1": "}"
        \\    }
        \\}
        \\
    ;

    try std.testing.expectEqualStrings(expected, json);
}

test "Query" {
    const language = tree_sitter_c();
    defer language.destroy();

    var error_offset: u32 = 0;
    try testing.expectError(error.InvalidNodeType, ts.Query.create(language, "(foo) @foo", &error_offset));
    try testing.expectEqual(1, error_offset);

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
    ;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    try testing.expectEqual(3, query.patternCount());
    try testing.expectEqual(3, query.captureCount());
    try testing.expectEqual(2, query.stringCount());

    try testing.expectEqual(23, query.startByteForPattern(1));
    try testing.expectEqual(54, query.endByteForPattern(1));

    try testing.expect(query.isPatternRooted(0));
    try testing.expect(!query.isPatternNonLocal(2));
    try testing.expect(!query.isPatternGuaranteedAtStep(9));

    try testing.expectEqualStrings("punctuation", query.captureNameForId(1).?);
    try testing.expectEqual(.One, query.captureQuantifierForId(0, 0).?);
    try testing.expectEqualStrings("main", query.stringValueForId(1).?);

    const steps: [4]ts.Query.PredicateStep = .{
        .{ .type = .String, .value_id = 0 },
        .{ .type = .Capture, .value_id = 2 },
        .{ .type = .String, .value_id = 1 },
        .{ .type = .Done, .value_id = 0 },
    };
    try testing.expectEqualSlices(ts.Query.PredicateStep, &steps, query.predicatesForPattern(2));
}

test "QueryCursor" {
    const language = tree_sitter_c();
    defer language.destroy();

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
    ;
    var error_offset: u32 = 0;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("int main() {}", null, .UTF_8).?;
    defer tree.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();

    cursor.exec(query, tree.rootNode());

    try testing.expect(!cursor.didExceedMatchLimit());
    try testing.expectEqual(0xFFFFFFFF, cursor.getMatchLimit());
    try testing.expectEqual(0, cursor.getTimeoutMicros());

    var match = cursor.nextMatch().?;
    try testing.expectEqual(0, match.id);
    try testing.expectEqual(0, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(0, match.captures[0].index);
    try testing.expectEqualStrings("identifier", match.captures[0].node.kind());

    _ = cursor.nextMatch();

    match = cursor.nextCapture().?[1];
    try testing.expectEqual(2, match.id);
    try testing.expectEqual(1, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(1, match.captures[0].index);
    try testing.expectEqualStrings("(", match.captures[0].node.kind());
}
