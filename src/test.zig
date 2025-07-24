const std = @import("std");
const testing = std.testing;
const ts = @import("root.zig");

extern fn tree_sitter_json() *const ts.Language;

test "Language" {
    const language = tree_sitter_json();
    defer language.destroy();

    try testing.expectEqual(14, language.abiVersion());
    try testing.expectEqual(null, language.metadata());
    try testing.expect(language.nodeKindCount() > 1);
    try testing.expect(language.fieldCount() > 1);
    try testing.expect(language.parseStateCount() > 1);
    try testing.expect(language.fieldIdForName("key") > 0);
    try testing.expect(language.fieldNameForId(1) != null);
    try testing.expectEqual(15, language.idForNodeKind("document", true));
    try testing.expectEqualStrings("string", language.nodeKindForId(20) orelse "");
    try testing.expect(language.nodeKindIsNamed(20));
    try testing.expect(language.nodeKindIsVisible(1));
    try testing.expect(!language.nodeKindIsSupertype(1));
    try testing.expect(language.nextState(1, 20) > 1);

    const copy = language.dupe();
    try testing.expectEqual(language, copy);
    copy.destroy();
}

test "LookaheadIterator" {
    const language = tree_sitter_json();
    defer language.destroy();

    const state = language.nextState(1, 161);
    const lookahead = language.lookaheadIterator(state).?;
    defer lookahead.destroy();

    try testing.expectEqual(language, lookahead.language());
    try testing.expectEqual(0xFFFF, lookahead.currentSymbol());
    try testing.expectEqualStrings("ERROR", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(0, lookahead.currentSymbol());
    try testing.expectEqualStrings("end", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expect(lookahead.resetState(state));

    try testing.expect(lookahead.next());
    try testing.expect(lookahead.reset(language, state));
}

test "Parser" {
    const language = tree_sitter_json();
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
    const language = tree_sitter_json();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source =
        \\{
        \\  "x": 1234,
        \\  "y": []
        \\}
    ;

    const tree = parser.parseStringEncoding(source, null, .UTF_8).?;
    defer tree.destroy();
    try testing.expectEqual(language, tree.getLanguage());
    try testing.expectEqual(26, tree.rootNode().endByte());
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
        .end_point = .{ .row = 3, .column = 1 },
        .start_byte = 0,
        .end_byte = 22,
    };
    ranges = old_tree.getChangedRanges(new_tree);
    try testing.expectEqualSlices(ts.Range, &.{range}, ranges);
    ts.Tree.freeRanges(ranges);
}

test "TreeCursor" {
    const language = tree_sitter_json();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source =
        \\{
        \\  "x": 1234,
        \\  "y": []
        \\}
    ;

    const tree = parser.parseStringEncoding(source, null, .UTF_8).?;
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
    try testing.expectEqualStrings("object", cursor.node().kind());
    try testing.expectEqual(1, cursor.depth());

    try testing.expect(cursor.gotoFirstChild());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expectEqualStrings("pair", cursor.node().kind());

    try testing.expect(cursor.gotoFirstChild());
    try testing.expectEqualStrings("string", cursor.node().kind());
    try testing.expectEqualStrings("key", cursor.fieldName() orelse "");

    try testing.expect(cursor.gotoNextSibling());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expectEqualStrings("number", cursor.node().kind());
    try testing.expectEqualStrings("value", cursor.fieldName() orelse "");

    try testing.expect(cursor.gotoParent());
    try testing.expectEqualStrings("pair", cursor.node().kind());
    try testing.expectEqual(0, cursor.fieldId());

    try testing.expect(cursor.gotoPreviousSibling());
    try testing.expect(!cursor.gotoPreviousSibling());
    try testing.expectEqualStrings("{", cursor.node().kind());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expect(cursor.gotoNextSibling());
    try testing.expect(!cursor.gotoNextSibling());
    try testing.expectEqualStrings("}", cursor.node().kind());

    cursor.gotoDescendant(2);
    try testing.expectEqual(2, cursor.descendantIndex());
    cursor.reset(root_node);

    try testing.expectEqual(0, cursor.gotoFirstChildForByte(1));
    try testing.expectEqual(1, cursor.gotoFirstChildForPoint(.{ .row = 0, .column = 5 }));
    try testing.expectEqualStrings("pair", cursor.node().kind());
}

test "Node" {
    const language = tree_sitter_json();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source =
        \\{
        \\  "x": 1234,
        \\  "y": []
        \\}
    ;

    const tree = parser.parseStringEncoding(source, null, .UTF_8).?;
    defer tree.destroy();
    var node = tree.rootNode();

    try testing.expectEqual(tree, node.tree);
    try testing.expectEqual(tree.getLanguage(), node.getLanguage());

    try testing.expectEqual(15, node.kindId());
    try testing.expectEqual(15, node.grammarId());
    try testing.expectEqualStrings("document", node.kind());
    try testing.expectEqualStrings("document", node.grammarKind());

    try testing.expect(node.isNamed());
    try testing.expect(!node.isExtra());
    try testing.expect(!node.isError());
    try testing.expect(!node.isMissing());

    try testing.expectEqual(0, node.parseState());
    try testing.expectEqual(0, node.nextParseState());

    try testing.expectEqual(0, node.startByte());
    try testing.expectEqual(26, node.endByte());
    try testing.expectEqual(0, node.startPoint().column);
    try testing.expectEqual(1, node.endPoint().column);

    const range = node.range();
    try testing.expectEqual(0, range.start_byte);
    try testing.expectEqual(26, range.end_byte);
    try testing.expectEqual(0, range.start_point.column);
    try testing.expectEqual(1, range.end_point.column);

    try testing.expectEqual(1, node.childCount());
    try testing.expectEqual(1, node.namedChildCount());
    try testing.expectEqual(21, node.descendantCount());

    node = node.child(0).?.namedChild(0).?;
    try testing.expectEqualStrings("number", node.namedChild(1).?.kind());
    try testing.expectEqual(node.child(0), node.childByFieldId(1));
    try testing.expectEqualStrings("string", node.childByFieldName("key").?.kind());

    try testing.expectEqualStrings(":", node.child(0).?.nextSibling().?.kind());
    try testing.expectEqualStrings("number", node.child(0).?.nextNamedSibling().?.kind());
    try testing.expectEqualStrings(":", node.child(2).?.prevSibling().?.kind());
    try testing.expectEqualStrings("string", node.child(2).?.prevNamedSibling().?.kind());

    try testing.expectEqualStrings("number", node.descendantForByteRange(11, 12).?.kind());
    try testing.expectEqualStrings("number", node.namedDescendantForByteRange(11, 12).?.kind());

    const points: [2]ts.Point = .{ .{ .row = 0, .column = 4 }, .{ .row = 0, .column = 8 } };
    try testing.expectEqualStrings("pair", node.descendantForPointRange(points[0], points[1]).?.kind());
    try testing.expectEqualStrings("pair", node.namedDescendantForPointRange(points[0], points[1]).?.kind());

    try testing.expectEqualStrings("value", node.fieldNameForChild(2).?);
    try testing.expectEqualStrings("key", node.fieldNameForNamedChild(0) orelse "");

    const sexp = node.toSexp();
    defer ts.Node.freeSexp(sexp);
    try testing.expectStringStartsWith(sexp, "(pair key: (string (string");

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

test "Query" {
    const language = tree_sitter_json();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    var error_offset: u32 = 0;
    try testing.expectError(error.InvalidNodeType, ts.Query.create(language, "(foo) @foo", &error_offset));
    try testing.expectEqual(1, error_offset);

    const source =
        \\(pair) @pair
        \\["{" "}" "[" "]"] @punctuation
        \\((pair)
        \\   key: (string) @key
        \\   value: (number) @value
        \\ (#eq? @key "x"))
    ;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    try testing.expectEqual(3, query.patternCount());
    try testing.expectEqual(4, query.captureCount());
    try testing.expectEqual(2, query.stringCount());

    try testing.expectEqual(13, query.startByteForPattern(1));
    try testing.expectEqual(44, query.endByteForPattern(1));

    try testing.expect(query.isPatternRooted(0));
    try testing.expect(!query.isPatternNonLocal(2));
    try testing.expect(!query.isPatternGuaranteedAtStep(9));

    try testing.expectEqualStrings("punctuation", query.captureNameForId(1).?);
    try testing.expectEqual(.One, query.captureQuantifierForId(0, 0).?);
    try testing.expectEqualStrings("x", query.stringValueForId(1).?);

    const steps: [4]ts.Query.PredicateStep = .{
        .{ .type = .String, .value_id = 0 },
        .{ .type = .Capture, .value_id = 2 },
        .{ .type = .String, .value_id = 1 },
        .{ .type = .Done, .value_id = 0 },
    };
    try testing.expectEqualSlices(ts.Query.PredicateStep, &steps, query.predicatesForPattern(2));
}

test "QueryCursor" {
    const language = tree_sitter_json();
    defer language.destroy();

    const source =
        \\ (array (number) @number)
    ;
    var error_offset: u32 = 0;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseStringEncoding("[1,2,3]", null, .UTF_8).?;
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
    try testing.expectEqualStrings("number", match.captures[0].node.kind());

    match = cursor.nextCapture().?[1];
    try testing.expectEqual(1, match.id);
    try testing.expectEqual(0, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(0, match.captures[0].index);
    try testing.expectEqualStrings("number", match.captures[0].node.kind());
}
