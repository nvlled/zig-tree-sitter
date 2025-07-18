# tree-sitter-json

This is a stripped-down [tree-sitter-json](https://github.com/tree-sitter/tree-sitter),
used only for testing the zig bindings. Previously, tree-sitter-c was used
as an external dependency. But tree-sitter-json is smaller (28Kb vs 3.7Mb),
so it can just be vendored as an internal package. This avoids the circular
dependency between zig-tree-sitter and tree-sitter-c, which aside from
being conceptually confusing, it also made fixing future breaking updates
more difficult.
