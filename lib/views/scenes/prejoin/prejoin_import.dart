import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class ImportUrlDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final void Function(String value) onSubmitted;

  const ImportUrlDialog({
    required this.title,
    required this.hintText,
    required this.onSubmitted,
    super.key,
  });

  @override
  State<ImportUrlDialog> createState() => _ImportUrlDialogState();
}

class _ImportUrlDialogState extends State<ImportUrlDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // cancel
          child: Text(context.local.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSubmitted(_controller.text.trim());
            Navigator.of(context).pop();
          },
          child: Text(context.local.ok),
        ),
      ],
    );
  }
}
