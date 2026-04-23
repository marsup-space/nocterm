import 'package:dart_markdown_parser/dart_markdown_parser.dart';
import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/components/markdown_component.dart';
import 'package:test/test.dart';

/// Rich markdown example covering all supported features.
const richMarkdown = '''
# Main Title

## Getting Started

This is a paragraph with **bold text**, *italic text*, and ~~strikethrough~~.
You can also combine ***bold and italic*** together.

### Inline Elements

Here is some `inline code` and a [link to Dart](https://dart.dev "Dart Language").
Check out this image: ![Dart Logo](https://dart.dev/logo.png)

#### Code Block

```dart
void main() {
  print('Hello, World!');
  final x = 42;
}
```

##### Lists

Unordered list:
- First item
- Second item with **bold**
- Third item

Ordered list:
1. Step one
2. Step two
3. Step three

Task list:
- [x] Completed task
- [ ] Pending task
- [x] Another done

###### Blockquote

> This is a blockquote with *emphasis*.
> It can span multiple lines.

---

| Language | Year | Creator    |
|----------|------|------------|
| Dart     | 2011 | Google     |
| Rust     | 2010 | Mozilla    |
| Go       | 2009 | Google     |

We love the #flutter framework and ping @robbie for details!

Here is a footnote reference[^1].

[^1]: This is the footnote content.
''';

void main() {
  group('MDownRenderer', () {
    late MDownRenderer renderer;
    late List<MarkdownNode> nodes;

    setUp(() {
      final registry = ParserPluginRegistry();
      registry.register(const HashtagPlugin());
      registry.register(const MentionPlugin());
      final parser = MarkdownParser(plugins: registry);
      nodes = parser.parse(richMarkdown);
      renderer = MDownRenderer();
    });

    test('parses rich markdown into non-empty AST', () {
      expect(nodes.length, greaterThan(5));
    });

    test('renders all nodes to spans without errors', () {
      final spans = renderer.renderNodes(nodes);
      expect(spans, isNotEmpty);
    });

    test('detects header nodes at multiple levels', () {
      final headers = nodes.whereType<HeaderNode>().toList();
      expect(headers.length, greaterThanOrEqualTo(6));

      final levels = headers.map((h) => h.level).toSet();
      expect(levels, contains(1));
      expect(levels, contains(2));
      expect(levels, contains(3));
      expect(levels, contains(4));
      expect(levels, contains(5));
      expect(levels, contains(6));
    });

    test('renders headers with correct prefix', () {
      final h1 = const HeaderNode(level: 1, content: 'Title', children: [TextNode('Title')]);
      final text = _extractText(renderer.renderNode(h1));
      expect(text, contains('# Title'));
    });

    test('renders h3 with ### prefix', () {
      final h3 = const HeaderNode(level: 3, content: 'Sub', children: [TextNode('Sub')]);
      final text = _extractText(renderer.renderNode(h3));
      expect(text, contains('### Sub'));
    });

    test('detects paragraph nodes', () {
      final paragraphs = nodes.whereType<ParagraphNode>().toList();
      expect(paragraphs, isNotEmpty);
    });

    test('renders bold text with bold style', () {
      final bold = const BoldNode([TextNode('strong')]);
      final spans = renderer.renderNode(bold);
      expect(spans, hasLength(1));
      final ts = spans.first as TextSpan;
      expect(ts.style!.fontWeight, equals(FontWeight.bold));
    });

    test('renders italic text with italic style', () {
      final italic = const ItalicNode([TextNode('emphasis')]);
      final spans = renderer.renderNode(italic);
      final ts = spans.first as TextSpan;
      expect(ts.style!.fontStyle, equals(FontStyle.italic));
    });

    test('renders strikethrough with lineThrough decoration', () {
      final strike = const StrikethroughNode([TextNode('deleted')]);
      final spans = renderer.renderNode(strike);
      final ts = spans.first as TextSpan;
      expect(ts.style!.decoration!.hasLineThrough, isTrue);
    });

    test('renders inline code with code style', () {
      final code = const InlineCodeNode('var x = 1');
      final spans = renderer.renderNode(code);
      final ts = spans.first as TextSpan;
      expect(ts.text, equals('var x = 1'));
      expect(ts.style!.color, equals(Colors.yellow));
      expect(ts.style!.backgroundColor, equals(Colors.black));
    });

    test('renders code block with language label', () {
      final codeBlock = const CodeBlockNode(code: 'print("hi")', language: 'dart');
      final text = _extractText(renderer.renderNode(codeBlock));
      expect(text, contains('dart'));
      expect(text, contains('print("hi")'));
    });

    test('renders code block without language', () {
      final codeBlock = const CodeBlockNode(code: 'raw code');
      final text = _extractText(renderer.renderNode(codeBlock));
      expect(text, contains('raw code'));
    });

    test('renders link with URL in brackets', () {
      final link = const LinkNode(url: 'https://dart.dev', children: [TextNode('Dart')]);
      final text = _extractText(renderer.renderNode(link));
      expect(text, contains('Dart'));
      expect(text, contains('[https://dart.dev]'));
    });

    test('renders image as alt text', () {
      final img = const ImageNode(url: 'https://img.png', alt: 'logo');
      final text = _extractText(renderer.renderNode(img));
      expect(text, contains('[Image: logo]'));
    });

    test('detects unordered list', () {
      final lists = nodes.whereType<ListNode>().where((l) => !l.ordered).toList();
      expect(lists, isNotEmpty);
    });

    test('detects ordered list', () {
      final lists = nodes.whereType<ListNode>().where((l) => l.ordered).toList();
      expect(lists, isNotEmpty);
    });

    test('renders unordered list items with bullet', () {
      final list = ListNode(
        items: [
          const ListItemNode(children: [TextNode('item')]),
        ],
      );
      final text = _extractText(renderer.renderNode(list));
      expect(text, contains('• item'));
    });

    test('renders ordered list items with index', () {
      final list = ListNode(
        ordered: true,
        items: [
          const ListItemNode(children: [TextNode('first')]),
          const ListItemNode(children: [TextNode('second')]),
        ],
      );
      final text = _extractText(renderer.renderNode(list));
      expect(text, contains('1. first'));
      expect(text, contains('2. second'));
    });

    test('renders task list with checkboxes', () {
      final list = ListNode(
        items: [
          const ListItemNode(children: [TextNode('done')], checked: true),
          const ListItemNode(children: [TextNode('todo')], checked: false),
        ],
      );
      final text = _extractText(renderer.renderNode(list));
      expect(text, contains('◉ done'));
      expect(text, contains('◎ todo'));
    });

    test('renders blockquote with pipe prefix', () {
      final bq = const BlockquoteNode([
        ParagraphNode([TextNode('quoted')]),
      ]);
      final text = _extractText(renderer.renderNode(bq));
      expect(text, contains('│ '));
      expect(text, contains('quoted'));
    });

    test('renders multiline blockquote with pipe on every line', () {
      final bq = const BlockquoteNode([
        ParagraphNode([TextNode('line one.\nline two.')]),
      ]);
      final text = _extractText(renderer.renderNode(bq));
      expect(text, contains('│ line one.\n│ line two.'));
    });

    test('renders horizontal rule', () {
      final text = _extractText(renderer.renderNode(const HorizontalRuleNode()));
      expect(text, contains('─' * 40));
    });

    test('detects table node', () {
      final tables = nodes.whereType<TableNode>().toList();
      expect(tables, isNotEmpty);
    });

    test('renders table with borders', () {
      final table = TableNode(
        headers: [
          [const TextNode('Name')],
          [const TextNode('Age')],
        ],
        alignments: [null, null],
        rows: [
          const TableRowNode([
            [TextNode('Alice')],
            [TextNode('30')],
          ]),
        ],
      );
      final text = _extractText(renderer.renderNode(table));
      expect(text, contains('┌'));
      expect(text, contains('┐'));
      expect(text, contains('├'));
      expect(text, contains('┤'));
      expect(text, contains('└'));
      expect(text, contains('┘'));
      expect(text, contains('Name'));
      expect(text, contains('Alice'));
    });

    test('nested ordered list renders correct sub-item indices', () {
      final registry = ParserPluginRegistry();
      registry.register(const NestedListPlugin());
      final parser = MarkdownParser(plugins: registry);
      final nodes = parser.parse(
        '1. première\n2. deuxième\n   1. sous-étape a\n   2. sous-étape b\n3. troisième\n',
      );

      expect(nodes, hasLength(1));
      final list = nodes.first as ListNode;
      expect(list.items, hasLength(3));

      final second = list.items[1];
      final subList = second.children.whereType<ListNode>().first;
      expect(subList.startIndex, equals(1));
      expect(subList.items, hasLength(2));

      final spans = renderer.renderNodes(nodes);
      final text = _extractText(spans);
      expect(text, contains('1. sous-étape a'));
      expect(text, contains('2. sous-étape b'));
      expect(text, contains('3. troisième'));
      expect(text, isNot(contains('3. sous-étape')));
      expect(text, isNot(contains('4. sous-étape')));
    });

    test('nested unordered list renders correct sub-bullets', () {
      final registry = ParserPluginRegistry();
      registry.register(const NestedListPlugin());
      final parser = MarkdownParser(plugins: registry);
      final nodes = parser.parse('- parent\n  - child a\n  - child b\n- other\n');

      final list = nodes.first as ListNode;
      expect(list.items, hasLength(2));
      final sub = list.items[0].children.whereType<ListNode>().first;
      expect(sub.items, hasLength(2));
    });

    test('renders diff code block with line colors', () {
      const diffCode = CodeBlockNode(
        language: 'diff',
        code: '+ ligne ajoutée\n- ligne supprimée\n! ligne importante\n# commentaire neutre\n  context line',
      );
      final spans = renderer.renderNode(diffCode);
      final allSpans = _flattenSpans(spans);

      final addSpan = allSpans.firstWhere((s) => s.text?.startsWith('+') ?? false);
      expect(addSpan.style!.color, equals(Colors.green));

      final delSpan = allSpans.firstWhere((s) => s.text?.startsWith('-') ?? false);
      expect(delSpan.style!.color, equals(Colors.red));

      final impSpan = allSpans.firstWhere((s) => s.text?.startsWith('!') ?? false);
      expect(impSpan.style!.color, equals(Colors.yellow));

      final cmtSpan = allSpans.firstWhere((s) => s.text?.startsWith('#') ?? false);
      expect(cmtSpan.style!.color, equals(Colors.grey));
    });

    test('renders git language as diff', () {
      const gitBlock = CodeBlockNode(language: 'git', code: '+ added\n- removed');
      final spans = renderer.renderNode(gitBlock);
      final allSpans = _flattenSpans(spans);
      final addSpan = allSpans.firstWhere((s) => s.text?.startsWith('+') ?? false);
      expect(addSpan.style!.color, equals(Colors.green));
    });

    test('renders inline math', () {
      final math = const InlineMathNode('E=mc^2');
      final text = _extractText(renderer.renderNode(math));
      expect(text, contains(r'$E=mc^2$'));
    });

    test('renders block math', () {
      final math = const BlockMathNode(r'\sum x_i');
      final text = _extractText(renderer.renderNode(math));
      expect(text, contains(r'$$\sum x_i$$'));
    });

    test('renders footnote reference', () {
      final ref = const FootnoteReferenceNode('1');
      final text = _extractText(renderer.renderNode(ref));
      expect(text, contains('[^1]'));
    });

    test('renders footnote definition', () {
      final def = const FootnoteDefinitionNode(label: '1', children: [TextNode('Footnote content')]);
      final text = _extractText(renderer.renderNode(def));
      expect(text, contains('[^1]: '));
      expect(text, contains('Footnote content'));
    });

    test('renders hashtag with # and magenta style', () {
      final tag = const HashtagNode('flutter');
      final spans = renderer.renderNode(tag);
      final ts = spans.first as TextSpan;
      expect(ts.text, equals('#flutter'));
      expect(ts.style!.color, equals(Colors.magenta));
    });

    test('renders mention with @ and cyan style', () {
      final mention = const MentionNode('robbie');
      final spans = renderer.renderNode(mention);
      final ts = spans.first as TextSpan;
      expect(ts.text, equals('@robbie'));
      expect(ts.style!.color, equals(Colors.cyan));
    });

    test('detects hashtag and mention in parsed AST', () {
      bool hasHashtag = false;
      bool hasMention = false;
      _walkNodes(nodes, (node) {
        if (node is HashtagNode && node.tag == 'flutter') hasHashtag = true;
        if (node is MentionNode && node.username == 'robbie') hasMention = true;
      });
      expect(hasHashtag, isTrue);
      expect(hasMention, isTrue);
    });

    test('renders details node with open content', () {
      final details = const DetailsNode(
        summary: [TextNode('Click me')],
        children: [
          ParagraphNode([TextNode('Hidden')]),
        ],
        isOpen: true,
      );
      final text = _extractText(renderer.renderNode(details));
      expect(text, contains('▶ Click me'));
      expect(text, contains('Hidden'));
    });

    test('renders details node collapsed hides content', () {
      final details = const DetailsNode(
        summary: [TextNode('Collapsed')],
        children: [
          ParagraphNode([TextNode('Secret')]),
        ],
        isOpen: false,
      );
      final text = _extractText(renderer.renderNode(details));
      expect(text, contains('Collapsed'));
      expect(text, isNot(contains('Secret')));
    });

    test('full rich markdown renders to non-trivial span tree', () {
      final spans = renderer.renderNodes(nodes);
      final fullText = _extractText(spans);

      expect(fullText, contains('Main Title'));
      expect(fullText, contains('Getting Started'));
      expect(fullText, contains('inline code'));
      expect(fullText, contains('Hello, World!'));
      expect(fullText, contains('@robbie'));
      expect(fullText, contains('Dart'));
      expect(fullText, contains('─' * 40));
    });

    test('renders bold+italic nesting (BoldNode > ItalicNode)', () {
      // ***text*** is normalized to **_text_** before parsing, producing this AST
      final boldItalic = const BoldNode([
        ItalicNode([TextNode('combined')])
      ]);
      final spans = renderer.renderNode(boldItalic);
      final outer = spans.first as TextSpan;
      expect(outer.style!.fontWeight, equals(FontWeight.bold));
      final inner = outer.children!.first as TextSpan;
      expect(inner.style!.fontStyle, equals(FontStyle.italic));
    });

    test('custom stylesheet is applied', () {
      final custom = MDownStyleSheet(
        h1Style: const TextStyle(color: Colors.red),
        boldStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
      );
      final r = MDownRenderer(styleSheet: custom);
      final h1 = const HeaderNode(level: 1, content: 'Test', children: [TextNode('Test')]);
      final spans = r.renderNode(h1);
      final ts = spans.first as TextSpan;
      expect(ts.style!.color, equals(Colors.red));
    });
  });

  group('MDown component', () {
    test('creates with required markdown', () {
      final mdown = MDown('# Hello');
      expect(mdown.markdown, equals('# Hello'));
    });

    test('accepts custom stylesheet', () {
      final sheet = MDownStyleSheet(h1Style: const TextStyle(color: Colors.red));
      final mdown = MDown('# Test', styleSheet: sheet);
      expect(mdown.styleSheet.h1Style.color, equals(Colors.red));
    });

    test('accepts custom plugins', () {
      final mdown = MDown('test', plugins: [const EmojiPlugin()]);
      expect(mdown.plugins, hasLength(1));
    });
  });

  group('MDownStyleSheet', () {
    test('default styles are set', () {
      const sheet = MDownStyleSheet();
      expect(sheet.h1Style.color, equals(Colors.cyan));
      expect(sheet.h2Style.color, equals(Colors.blue));
      expect(sheet.h3Style.color, equals(Colors.green));
      expect(sheet.boldStyle.fontWeight, equals(FontWeight.bold));
      expect(sheet.italicStyle.fontStyle, equals(FontStyle.italic));
      expect(sheet.listBullet, equals('• '));
    });

    test('headerStyle returns correct style for each level', () {
      const sheet = MDownStyleSheet();
      expect(sheet.headerStyle(1).color, equals(Colors.cyan));
      expect(sheet.headerStyle(2).color, equals(Colors.blue));
      expect(sheet.headerStyle(3).color, equals(Colors.green));
      expect(sheet.headerStyle(6).fontStyle, equals(FontStyle.italic));
    });
  });
}

/// Flattens a span tree into a flat list of leaf TextSpans (those with text).
List<TextSpan> _flattenSpans(List<InlineSpan> spans) {
  final result = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) result.add(span);
      span.children?.forEach(visit);
    }
  }

  spans.forEach(visit);
  return result;
}

/// Recursively extracts all plain text from a list of InlineSpan.
String _extractText(List<InlineSpan> spans) {
  final buf = StringBuffer();
  for (final span in spans) {
    _collectText(span, buf);
  }
  return buf.toString();
}

void _collectText(InlineSpan span, StringBuffer buf) {
  if (span is TextSpan) {
    if (span.text != null) buf.write(span.text);
    if (span.children != null) {
      for (final child in span.children!) {
        _collectText(child, buf);
      }
    }
  }
}

/// Walks all nodes recursively, calling [visitor] on each.
void _walkNodes(List<MarkdownNode> nodes, void Function(MarkdownNode) visitor) {
  for (final node in nodes) {
    visitor(node);
    switch (node) {
      case ParagraphNode n:
        _walkNodes(n.children, visitor);
      case HeaderNode n:
        if (n.children != null) _walkNodes(n.children!, visitor);
      case BoldNode n:
        _walkNodes(n.children, visitor);
      case ItalicNode n:
        _walkNodes(n.children, visitor);
      case StrikethroughNode n:
        _walkNodes(n.children, visitor);
      case LinkNode n:
        _walkNodes(n.children, visitor);
      case ListNode n:
        _walkNodes(n.items, visitor);
      case ListItemNode n:
        _walkNodes(n.children, visitor);
      case BlockquoteNode n:
        _walkNodes(n.children, visitor);
      case FootnoteDefinitionNode n:
        _walkNodes(n.children, visitor);
      case DetailsNode n:
        _walkNodes(n.summary, visitor);
        _walkNodes(n.children, visitor);
      default:
        break;
    }
  }
}
