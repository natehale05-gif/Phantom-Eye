import 'package:flutter/material.dart';

Future<String?> showRouteNameDialog(BuildContext context, {required String defaultName}) {
  final controller = TextEditingController(text: defaultName);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save route'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim().isEmpty ? defaultName : controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
