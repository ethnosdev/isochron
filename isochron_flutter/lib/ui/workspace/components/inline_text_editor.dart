import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

class InlineTextEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onComplete;

  const InlineTextEditor({
    super.key,
    required this.initialText,
    required this.onComplete,
  });

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();

    // Save when focus is lost (clicking elsewhere)
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onComplete(_controller.text);
      }
    });

    // Auto focus the text field immediately when it appears
    Future.microtask(() {
      if (mounted) {
        _focusNode.requestFocus();
        // Highlight all text so typing immediately overwrites it
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MacosTextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: 1,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      style: const TextStyle(fontSize: 13),
      // Save when hitting Enter
      onSubmitted: widget.onComplete,
    );
  }
}
