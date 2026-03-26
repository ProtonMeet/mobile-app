import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class CallQualityForm extends StatefulWidget {
  const CallQualityForm({required this.onLeave, required this.log, super.key});
  final void Function() onLeave;
  final String log;

  @override
  State<CallQualityForm> createState() => _CallQualityFormState();
}

class _CallQualityFormState extends State<CallQualityForm> {
  int _rating = 5;

  Future<void> _submit() async {
    /// to-do: send user feedback to api
    // final uri = Uri(
    //   scheme: 'mailto',
    //   path: 'proton.meet.test@proton.me',
    //   query: Uri.encodeFull(
    //     'subject=Call Quality Feedback&body=Rating: $_rating stars\nLog: ${widget.log}',
    //   ),
    // );
    // try {
    //   if (await canLaunchUrl(uri)) {
    //     await launchUrl(uri);
    //   } else {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(content: Text('Can not open email app')),
    //     );
    //   }
    // } catch (e) {
    //   print(e.toString());
    // }
    if (context.mounted) {
      widget.onLeave();
      Navigator.of(context).pop();
    }
  }

  Widget _buildStar(int index) {
    return IconButton(
      icon: Icon(
        index <= _rating ? Icons.star : Icons.star_border,
        color: Colors.orange,
        size: 52,
      ),
      onPressed: () => setState(() => _rating = index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Center(child: Text('Meeting Quality Feedback')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => _buildStar(index + 1)),
          ),
          const SizedBox(height: 12),
          Text(
            'By submit, you will share the connection log with us via email.',
            style: ProtonStyles.body2Regular(color: context.colors.textNorm),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Skip'),
          onPressed: () {
            widget.onLeave();
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          onPressed: _rating > 0 ? _submit : null,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
