import 'package:dart_markdown_parser/dart_markdown_parser.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:nocterm/nocterm.dart';

/// Maps highlight.js token class names to terminal text styles.
///
/// Token classes: keyword, string, comment, number, built_in, title,
/// type, literal, attr, meta, tag, name, selector-class, etc.
class SyntaxTheme {
  const SyntaxTheme({
    this.keyword =
        const TextStyle(color: Colors.magenta, fontWeight: FontWeight.bold),
    this.string = const TextStyle(color: Colors.green),
    this.comment =
        const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
    this.number = const TextStyle(color: Colors.cyan),
    this.builtIn = const TextStyle(color: Colors.blue),
    this.title =
        const TextStyle(color: Colors.brightBlue, fontWeight: FontWeight.bold),
    this.type =
        const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
    this.literal = const TextStyle(color: Colors.cyan),
    this.attr = const TextStyle(color: Colors.cyan),
    this.meta = const TextStyle(color: Colors.grey),
    this.tag = const TextStyle(color: Colors.red),
    this.name = const TextStyle(color: Colors.red),
    this.operator = const TextStyle(color: Colors.white),
    this.punctuation = const TextStyle(color: Colors.grey),
    this.variable = const TextStyle(color: Colors.brightRed),
    this.symbol = const TextStyle(color: Colors.cyan),
    this.fallback,
  });

  final TextStyle keyword;
  final TextStyle string;
  final TextStyle comment;
  final TextStyle number;
  final TextStyle builtIn;
  final TextStyle title;
  final TextStyle type;
  final TextStyle literal;
  final TextStyle attr;
  final TextStyle meta;
  final TextStyle tag;
  final TextStyle name;
  final TextStyle operator;
  final TextStyle punctuation;
  final TextStyle variable;
  final TextStyle symbol;

  /// Fallback style for unrecognized token classes (null = inherit).
  final TextStyle? fallback;

  TextStyle? styleFor(String className) => switch (className) {
        'keyword' || 'selector-tag' => keyword,
        'string' || 'regexp' || 'addition' => string,
        'comment' || 'quote' || 'deletion' => comment,
        'number' => number,
        'built_in' || 'builtin-name' => builtIn,
        'title' || 'function' => title,
        'type' || 'class' => type,
        'literal' => literal,
        'attr' || 'attribute' || 'selector-attr' => attr,
        'meta' || 'meta-string' => meta,
        'tag' => tag,
        'name' || 'selector-id' || 'selector-class' => name,
        'operator' || 'code' => operator,
        'punctuation' || 'template-tag' || 'template-variable' => punctuation,
        'variable' || 'params' => variable,
        'symbol' || 'bullet' || 'link' => symbol,
        _ => fallback,
      };
}

/// Stylesheet for rendering markdown AST nodes as terminal rich text.
class MDownStyleSheet {
  const MDownStyleSheet({
    this.h1Style =
        const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
    this.h2Style =
        const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
    this.h3Style =
        const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
    this.h4Style = const TextStyle(fontWeight: FontWeight.bold),
    this.h5Style = const TextStyle(fontWeight: FontWeight.bold),
    this.h6Style = const TextStyle(
        fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
    this.boldStyle = const TextStyle(fontWeight: FontWeight.bold),
    this.italicStyle = const TextStyle(fontStyle: FontStyle.italic),
    this.strikethroughStyle =
        const TextStyle(decoration: TextDecoration.lineThrough),
    this.codeStyle =
        const TextStyle(color: Colors.yellow, backgroundColor: Colors.black),
    this.codeBlockStyle =
        const TextStyle(color: Colors.green, backgroundColor: Colors.black),
    this.blockquoteStyle =
        const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
    this.linkStyle = const TextStyle(
        color: Colors.blue, decoration: TextDecoration.underline),
    this.hashtagStyle =
        const TextStyle(color: Colors.magenta, fontWeight: FontWeight.bold),
    this.mentionStyle =
        const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
    this.mathStyle =
        const TextStyle(color: Colors.yellow, fontStyle: FontStyle.italic),
    this.footnoteRefStyle =
        const TextStyle(color: Colors.blue, fontWeight: FontWeight.dim),
    this.listBullet = '• ',
    this.orderedListSeparator = '. ',
    this.horizontalRule = '─',
    this.horizontalRuleWidth = 40,
    this.taskChecked = '◉ ',
    this.taskUnchecked = '◎ ',
    this.syntaxTheme = const SyntaxTheme(),
    this.diffAddStyle = const TextStyle(color: Colors.green),
    this.diffDeleteStyle = const TextStyle(color: Colors.red),
    this.diffImportantStyle = const TextStyle(color: Colors.yellow),
    this.diffCommentStyle =
        const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
    this.diffContextStyle,
  });

  final TextStyle h1Style;
  final TextStyle h2Style;
  final TextStyle h3Style;
  final TextStyle h4Style;
  final TextStyle h5Style;
  final TextStyle h6Style;
  final TextStyle boldStyle;
  final TextStyle italicStyle;
  final TextStyle strikethroughStyle;
  final TextStyle codeStyle;
  final TextStyle codeBlockStyle;
  final TextStyle blockquoteStyle;
  final TextStyle linkStyle;
  final TextStyle hashtagStyle;
  final TextStyle mentionStyle;
  final TextStyle mathStyle;
  final TextStyle footnoteRefStyle;
  final String listBullet;
  final String orderedListSeparator;
  final String horizontalRule;
  final int horizontalRuleWidth;
  final String taskChecked;
  final String taskUnchecked;
  final SyntaxTheme syntaxTheme;
  final TextStyle diffAddStyle;
  final TextStyle diffDeleteStyle;
  final TextStyle diffImportantStyle;
  final TextStyle diffCommentStyle;

  /// Fallback style for unchanged diff context lines (null = codeBlockStyle).
  final TextStyle? diffContextStyle;

  TextStyle headerStyle(int level) => switch (level) {
        1 => h1Style,
        2 => h2Style,
        3 => h3Style,
        4 => h4Style,
        5 => h5Style,
        _ => h6Style,
      };
}

/// Converts dart_markdown_parser AST nodes into nocterm InlineSpan trees.
class MDownRenderer {
  MDownRenderer({this.styleSheet = const MDownStyleSheet()});

  final MDownStyleSheet styleSheet;
  int _listDepth = 0;

  /// Renders a list of top-level AST nodes into InlineSpan list.
  List<InlineSpan> renderNodes(List<MarkdownNode> nodes) {
    return [for (final node in nodes) ...renderNode(node)];
  }

  /// Renders a single node, returning one or more spans.
  List<InlineSpan> renderNode(MarkdownNode node) => switch (node) {
        TextNode n => [TextSpan(text: n.content)],
        HeaderNode n => _renderHeader(n),
        ParagraphNode n => _renderParagraph(n),
        BoldNode n => [
            TextSpan(
                children: renderNodes(n.children), style: styleSheet.boldStyle)
          ],
        ItalicNode n => [
            TextSpan(
                children: renderNodes(n.children),
                style: styleSheet.italicStyle)
          ],
        StrikethroughNode n => [
            TextSpan(
                children: renderNodes(n.children),
                style: styleSheet.strikethroughStyle)
          ],
        InlineCodeNode n => [
            TextSpan(text: n.code, style: styleSheet.codeStyle)
          ],
        CodeBlockNode n => _renderCodeBlock(n),
        LinkNode n => _renderLink(n),
        ImageNode n => [
            TextSpan(
              text: '[Image: ${n.alt}]',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ListNode n => _renderList(n),
        ListItemNode n => _renderListItem(n, 0, false),
        BlockquoteNode n => _renderBlockquote(n),
        HorizontalRuleNode() => _renderHorizontalRule(),
        TableNode n => _renderTable(n),
        InlineMathNode n => [
            TextSpan(text: '\$${n.latex}\$', style: styleSheet.mathStyle)
          ],
        BlockMathNode n => [
            TextSpan(
                text: '\$\$${n.latex}\$\$\n\n', style: styleSheet.mathStyle)
          ],
        FootnoteReferenceNode n => [
            TextSpan(text: '[^${n.label}]', style: styleSheet.footnoteRefStyle)
          ],
        FootnoteDefinitionNode n => _renderFootnoteDefinition(n),
        DetailsNode n => _renderDetails(n),
        HashtagNode n => [
            TextSpan(text: '#${n.tag}', style: styleSheet.hashtagStyle)
          ],
        MentionNode n => [
            TextSpan(text: '@${n.username}', style: styleSheet.mentionStyle)
          ],
        _ => [TextSpan(text: node.toString())],
      };

  List<InlineSpan> _renderHeader(HeaderNode node) {
    final style = styleSheet.headerStyle(node.level);
    final prefix = '${'#' * node.level} ';
    final children = node.children != null
        ? renderNodes(node.children!)
        : [TextSpan(text: node.content)];
    return [
      TextSpan(
        children: [
          TextSpan(text: prefix, style: style),
          ...children,
          const TextSpan(text: '\n\n'),
        ],
        style: style,
      ),
    ];
  }

  List<InlineSpan> _renderParagraph(ParagraphNode node) {
    return [
      TextSpan(
        children: [
          ...renderNodes(node.children),
          const TextSpan(text: '\n\n'),
        ],
      ),
    ];
  }

  List<InlineSpan> _renderCodeBlock(CodeBlockNode node) {
    final langLabel = node.language != null
        ? TextSpan(
            text: '  ${node.language}\n',
            style:
                const TextStyle(color: Colors.grey, fontWeight: FontWeight.dim),
          )
        : null;

    final codeSpans = _highlightCode(node.code, node.language);

    return [
      TextSpan(
        children: [
          if (langLabel != null) langLabel,
          ...codeSpans,
          const TextSpan(text: '\n\n'),
        ],
      ),
    ];
  }

  List<InlineSpan> _highlightCode(String code, String? language) {
    if (language == null) {
      return [TextSpan(text: code, style: styleSheet.codeBlockStyle)];
    }

    if (language == 'diff' || language == 'git') {
      return _renderDiff(code);
    }

    try {
      final result = highlight.parse(code, language: language);
      if (result.nodes == null || result.nodes!.isEmpty) {
        return [TextSpan(text: code, style: styleSheet.codeBlockStyle)];
      }
      return _convertNodes(result.nodes!, styleSheet.codeBlockStyle);
    } catch (_) {
      return [TextSpan(text: code, style: styleSheet.codeBlockStyle)];
    }
  }

  List<InlineSpan> _renderDiff(String code) {
    final contextStyle =
        styleSheet.diffContextStyle ?? styleSheet.codeBlockStyle;
    return code.split('\n').map((line) {
      final style = switch (line.isEmpty ? ' ' : line[0]) {
        '+' => styleSheet.diffAddStyle,
        '-' => styleSheet.diffDeleteStyle,
        '!' => styleSheet.diffImportantStyle,
        '#' => styleSheet.diffCommentStyle,
        _ => contextStyle,
      };
      return TextSpan(text: '$line\n', style: style);
    }).toList();
  }

  List<InlineSpan> _convertNodes(List<Node> nodes, TextStyle? parentStyle) {
    return [
      for (final node in nodes)
        if (node.value != null)
          TextSpan(text: node.value, style: parentStyle)
        else if (node.children != null)
          TextSpan(
            children: _convertNodes(
              node.children!,
              node.className != null
                  ? styleSheet.syntaxTheme.styleFor(node.className!)
                  : parentStyle,
            ),
            style: node.className != null
                ? styleSheet.syntaxTheme.styleFor(node.className!)
                : parentStyle,
          ),
    ];
  }

  List<InlineSpan> _renderLink(LinkNode node) {
    final linkText = renderNodes(node.children);
    return [
      TextSpan(
        children: [
          ...linkText.map(
            (s) => s is TextSpan
                ? TextSpan(
                    text: s.text,
                    children: s.children,
                    style: styleSheet.linkStyle)
                : s,
          ),
          TextSpan(
            text: ' [${node.url}]',
            style: styleSheet.linkStyle.copyWith(
                fontWeight: FontWeight.normal, decoration: TextDecoration.none),
          ),
        ],
      ),
    ];
  }

  List<InlineSpan> _renderList(ListNode node) {
    _listDepth++;
    final spans = <InlineSpan>[];
    for (var i = 0; i < node.items.length; i++) {
      final index = node.ordered ? node.startIndex + i : 0;
      spans.addAll(_renderListItem(node.items[i], index, node.ordered));
    }
    _listDepth--;
    if (_listDepth == 0) spans.add(const TextSpan(text: '\n'));
    return spans;
  }

  List<InlineSpan> _renderListItem(ListItemNode item, int index, bool ordered) {
    final indent = '  ' * _listDepth;
    final bullet = item.checked != null
        ? (item.checked! ? styleSheet.taskChecked : styleSheet.taskUnchecked)
        : ordered
            ? '$index${styleSheet.orderedListSeparator}'
            : styleSheet.listBullet;

    // Build child spans; insert \n before any nested ListNode, and omit the
    // trailing \n when the last child is a ListNode (it already ends with \n).
    final childSpans = <InlineSpan>[];
    bool endsWithList = false;
    for (final child in item.children) {
      if (child is ListNode && childSpans.isNotEmpty) {
        childSpans.add(const TextSpan(text: '\n'));
      }
      childSpans.addAll(renderNode(child));
      endsWithList = child is ListNode;
    }

    return [
      TextSpan(
        children: [
          TextSpan(text: indent + bullet),
          ...childSpans,
          if (!endsWithList) const TextSpan(text: '\n'),
        ],
      ),
    ];
  }

  List<InlineSpan> _renderBlockquote(BlockquoteNode node) {
    final inner = renderNodes(node.children);
    // Insert │ prefix after every newline so multiline blockquotes keep the bar
    final prefixed = _prefixNewlines(inner, '│ ');
    return [
      TextSpan(
        children: [
          TextSpan(text: '│ ', style: styleSheet.blockquoteStyle),
          ...prefixed,
        ],
        style: styleSheet.blockquoteStyle,
      ),
    ];
  }

  /// Rewrites TextSpan tree so that every `\n` in text content is followed by [prefix].
  List<InlineSpan> _prefixNewlines(List<InlineSpan> spans, String prefix) {
    return [for (final span in spans) _prefixSpan(span, prefix)];
  }

  InlineSpan _prefixSpan(InlineSpan span, String prefix) {
    if (span is! TextSpan) return span;
    final newText = span.text?.replaceAll('\n', '\n$prefix');
    final newChildren =
        span.children != null ? _prefixNewlines(span.children!, prefix) : null;
    return TextSpan(text: newText, children: newChildren, style: span.style);
  }

  List<InlineSpan> _renderHorizontalRule() {
    return [
      TextSpan(
        text:
            '${styleSheet.horizontalRule * styleSheet.horizontalRuleWidth}\n\n',
        style: const TextStyle(color: Colors.grey),
      ),
    ];
  }

  List<InlineSpan> _renderTable(TableNode node) {
    // Extract all cell texts for width calculation
    final allRows = <List<String>>[];

    // Headers
    final headerTexts = node.headers.map((cell) => _plainText(cell)).toList();
    allRows.add(headerTexts);

    // Data rows
    for (final row in node.rows) {
      allRows.add(row.cells.map((cell) => _plainText(cell)).toList());
    }

    // Calculate column widths
    final colCount =
        allRows.fold(0, (max, row) => row.length > max ? row.length : max);
    final colWidths = List.filled(colCount, 0);
    for (final row in allRows) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].length > colWidths[i]) colWidths[i] = row[i].length;
      }
    }

    final buf = StringBuffer();

    // Top border
    buf.write('┌');
    for (var i = 0; i < colCount; i++) {
      buf.write('─' * (colWidths[i] + 2));
      buf.write(i < colCount - 1 ? '┬' : '┐');
    }
    buf.write('\n');

    // Render rows
    for (var r = 0; r < allRows.length; r++) {
      buf.write('│');
      for (var c = 0; c < allRows[r].length; c++) {
        buf.write(' ');
        buf.write(allRows[r][c].padRight(colWidths[c]));
        buf.write(' │');
      }
      buf.write('\n');

      // Header separator
      if (r == 0 && allRows.length > 1) {
        buf.write('├');
        for (var i = 0; i < colCount; i++) {
          buf.write('─' * (colWidths[i] + 2));
          buf.write(i < colCount - 1 ? '┼' : '┤');
        }
        buf.write('\n');
      }
    }

    // Bottom border
    buf.write('└');
    for (var i = 0; i < colCount; i++) {
      buf.write('─' * (colWidths[i] + 2));
      buf.write(i < colCount - 1 ? '┴' : '┘');
    }
    buf.write('\n\n');

    return [TextSpan(text: buf.toString())];
  }

  List<InlineSpan> _renderFootnoteDefinition(FootnoteDefinitionNode node) {
    return [
      TextSpan(
        children: [
          TextSpan(
              text: '[^${node.label}]: ', style: styleSheet.footnoteRefStyle),
          ...renderNodes(node.children),
          const TextSpan(text: '\n'),
        ],
      ),
    ];
  }

  List<InlineSpan> _renderDetails(DetailsNode node) {
    return [
      TextSpan(
        children: [
          const TextSpan(
            text: '▶ ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...renderNodes(node.summary),
          const TextSpan(text: '\n'),
          if (node.isOpen) ...renderNodes(node.children),
          const TextSpan(text: '\n'),
        ],
      ),
    ];
  }

  String _plainText(List<MarkdownNode> nodes) {
    final buf = StringBuffer();
    for (final node in nodes) {
      switch (node) {
        case TextNode n:
          buf.write(n.content);
        case BoldNode n:
          buf.write(_plainText(n.children));
        case ItalicNode n:
          buf.write(_plainText(n.children));
        case InlineCodeNode n:
          buf.write(n.code);
        case LinkNode n:
          buf.write(_plainText(n.children));
        case HashtagNode n:
          buf.write('#${n.tag}');
        case MentionNode n:
          buf.write('@${n.username}');
        default:
          break;
      }
    }
    return buf.toString();
  }
}

/// Block plugin that correctly parses nested ordered and unordered lists.
///
/// dart_markdown_parser flattens all indented list items to the same level.
/// This plugin intercepts list blocks and builds proper nested [ListNode] trees
/// by tracking indentation.
class NestedListPlugin extends BlockParserPlugin {
  const NestedListPlugin();

  @override
  String get id => 'nested_list';

  @override
  String get name => 'Nested List Plugin';

  @override
  int get priority => 100;

  static final _orderedRe = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');
  static final _unorderedRe = RegExp(r'^(\s*)([-*+])\s+(.*)$');
  static final _taskRe = RegExp(r'^\[([x ])\]\s+(.*)$', caseSensitive: false);

  static Match? _matchItem(String line) =>
      _orderedRe.firstMatch(line) ?? _unorderedRe.firstMatch(line);

  @override
  bool canParse(String line, List<String> lines, int index) =>
      _matchItem(line) != null;

  @override
  BlockParseResult? parse(List<String> lines, int startIndex) {
    final result = _parseList(lines, startIndex, _indentOf(lines[startIndex]));
    return result;
  }

  BlockParseResult? _parseList(List<String> lines, int start, int baseIndent) {
    final items = <ListItemNode>[];
    bool? ordered;
    int startIdx = 1;
    int i = start;

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) break;

      final m = _matchItem(line);
      if (m == null) break;

      final indent = _indentOf(line);
      if (indent != baseIndent) break;

      final isOrdered = _orderedRe.hasMatch(line);
      ordered ??= isOrdered;
      if (ordered != isOrdered) break;
      if (isOrdered && items.isEmpty) {
        startIdx = int.parse(_orderedRe.firstMatch(line)!.group(2)!);
      }

      final rawContent = m.group(3)!;
      final taskM = _taskRe.firstMatch(rawContent);
      final checked =
          taskM != null ? taskM.group(1)!.toLowerCase() == 'x' : null;
      final content = taskM != null ? taskM.group(2)! : rawContent;

      i++;

      // Collect sub-list if next line has greater indent
      final children = <MarkdownNode>[TextNode(content)];
      if (i < lines.length) {
        final nextM = _matchItem(lines[i]);
        if (nextM != null && _indentOf(lines[i]) > baseIndent) {
          final sub = _parseList(lines, i, _indentOf(lines[i]));
          if (sub != null) {
            children.add(sub.node);
            i += sub.linesConsumed;
          }
        }
      }

      items.add(ListItemNode(children: children, checked: checked));
    }

    if (items.isEmpty) return null;

    return BlockParseResult(
      node: ListNode(
          items: items, ordered: ordered ?? false, startIndex: startIdx),
      linesConsumed: i - start,
    );
  }

  int _indentOf(String line) {
    int n = 0;
    for (final ch in line.runes) {
      if (ch == 0x20) {
        n++; // space
      } else if (ch == 0x09) {
        n += 2; // tab counts as 2
      } else {
        break;
      }
    }
    return n;
  }
}

/// A component that renders Markdown content from dart_markdown_parser AST.
class MDown extends StatefulComponent {
  final String markdown;
  final MDownStyleSheet styleSheet;
  final List<ParserPlugin> plugins;

  /// How the text should be aligned horizontally.
  final TextAlign textAlign;

  /// Whether the text should break at soft line breaks.
  final bool softWrap;

  /// How visual overflow should be handled.
  final TextOverflow overflow;

  /// An optional maximum number of lines for the text to span.
  final int? maxLines;

  const MDown(
    this.markdown, {
    super.key,
    this.styleSheet = const MDownStyleSheet(),
    this.plugins = const [],
    this.textAlign = TextAlign.left,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
  });

  @override
  State<MDown> createState() => _MDownState();
}

class _MDownState extends State<MDown> {
  late final ParserPluginRegistry registry;
  late List<MarkdownNode> nodes;
  late List<InlineSpan> spans;

  @override
  void initState() {
    super.initState();
    registry = ParserPluginRegistry();
    registry.register(const NestedListPlugin());
    registry.register(const HashtagPlugin());
    registry.register(const MentionPlugin());
    for (final plugin in component.plugins) {
      registry.register(plugin);
    }

    _parse();
  }

  @override
  void didUpdateComponent(MDown oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.markdown != component.markdown) {
      _parse();
    }
  }

  // dart_markdown_parser doesn't handle ***text*** (bold+italic triple asterisk).
  // It consumes ** for bold, leaving one dangling *. Normalize to **_text_** first.
  static final _tripleAsterisk = RegExp(r'\*{3}(.+?)\*{3}', dotAll: true);

  void _parse() {
    final normalized = component.markdown
        .replaceAllMapped(_tripleAsterisk, (m) => '**_${m[1]}_**');
    final parser = MarkdownParser(plugins: registry);
    nodes = parser.parse(normalized);
    final renderer = MDownRenderer(styleSheet: component.styleSheet);
    spans = renderer.renderNodes(nodes);
  }

  @override
  build(_) => RichText(
        text: TextSpan(children: spans),
        textAlign: component.textAlign,
        softWrap: component.softWrap,
        overflow: component.overflow,
        maxLines: component.maxLines,
      );
}
