import 'package:flutter/material.dart';

import 'on_device_llm.dart';

void main() => runApp(const ExampleApp());

/// A tiny on-device chat screen. The app itself doesn't use llm_replay_eval —
/// its *tests* do (see `test/chat_replay_test.dart`), which is exactly the
/// point: you test the AI feature deterministically without changing the app.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ChatScreen(llm: FakeGemma()),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.llm});
  final OnDeviceLlm llm;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController(text: 'Capital of France?');
  String _answer = '';
  bool _busy = false;

  Future<void> _ask() async {
    setState(() => _busy = true);
    final reply = await widget.llm.getResponse(_controller.text);
    setState(() {
      _answer = reply;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-device chat')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _controller),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _ask,
              child: Text(_busy ? 'Thinking…' : 'Ask'),
            ),
            const SizedBox(height: 24),
            Text(_answer, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
