import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SearchBarDemoPage extends StatefulWidget {
  const SearchBarDemoPage({super.key});

  @override
  State<SearchBarDemoPage> createState() => _SearchBarDemoPageState();
}

class _SearchBarDemoPageState extends State<SearchBarDemoPage> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _bottomChatController = TextEditingController();
  final TextEditingController _coloredController = TextEditingController(text: 'Cupertino');

  String _lastSubmitted = 'None';
  String _lastTrailingAction = 'None';
  String _lastTap = 'None';
  bool _enabled = true;
  bool _showsCancelButton = true;
  bool _excludeFocus = false;

  @override
  void dispose() {
    _queryController.dispose();
    _chatController.dispose();
    _bottomChatController.dispose();
    _coloredController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Text Field')),
      child: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                const Text('Search'),
                const SizedBox(height: 8),
                ExcludeFocus(
                  excluding: _excludeFocus,
                  child: CNTextField.search(
                    controller: _queryController,
                    placeholder: 'Search',
                    enabled: _enabled,
                    showsCancelButton: _showsCancelButton,
                    actions: [
                      CNTextFieldAction(
                        icon: const Icon(Icons.qr_code_scanner, color: CupertinoColors.black, size: 24),
                        onPressed: () {
                          setState(() => _lastTrailingAction = 'Scanner tapped');
                        },
                      ),
                      CNTextFieldAction(
                        icon: const Icon(Icons.abc, size: 24, color: CupertinoColors.black),
                        onPressed: () {
                          setState(() => _lastTrailingAction = 'Filter tapped');
                        },
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    onTap: () => setState(() => _lastTap = 'Tapped'),
                    onSubmitted: (value) => setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value),
                    onCancelled: () {
                      setState(() {
                        _queryController.clear();
                        _lastSubmitted = 'Cancelled';
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text('Current text: ${_queryController.text.isEmpty ? 'Empty' : _queryController.text}'),
                Text('Last submitted: $_lastSubmitted'),
                Text('Trailing action: $_lastTrailingAction'),
                Text('Last tap: $_lastTap'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('Enabled'),
                    const Spacer(),
                    CupertinoSwitch(value: _enabled, onChanged: (value) => setState(() => _enabled = value)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Show cancel button'),
                    const Spacer(),
                    CupertinoSwitch(value: _showsCancelButton, onChanged: (value) => setState(() => _showsCancelButton = value)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Exclude focus'),
                    const Spacer(),
                    CupertinoSwitch(value: _excludeFocus, onChanged: (value) => setState(() => _excludeFocus = value)),
                  ],
                ),
                const SizedBox(height: 12),
                CNButton(
                  label: 'Show Sheet',
                  style: CNButtonStyle.gray,
                  shrinkWrap: true,
                  onPressed: () {
                    showCupertinoModalPopup<void>(
                      context: context,
                      builder: (context) => CupertinoActionSheet(
                        title: const Text('Text Field Overlay'),
                        message: const Text('The text field stays clean underneath this sheet and keeps Flutter focus behavior.'),
                        actions: [CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop(), child: const Text('Dismiss'))],
                        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text('Tinted Search'),
                const SizedBox(height: 8),
                CNTextField.search(controller: _coloredController, placeholder: 'Search components', onChanged: (_) => setState(() {}), onSubmitted: (value) => setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value)),
                const SizedBox(height: 24),
                const Text('Chat'),
                const SizedBox(height: 8),
                CNTextField.chat(
                  controller: _chatController,
                  placeholder: 'Type a message',
                  enabled: _enabled,
                  tint: CupertinoColors.systemBlue,
                  sendButtonBackgroundColor: CupertinoColors.systemBlue,
                  actions: [
                    CNTextFieldAction(
                      icon: const Icon(CupertinoIcons.photo, color: CupertinoColors.systemBlue, size: 20),
                      onPressed: () {
                        setState(() => _lastTrailingAction = 'Photo tapped');
                      },
                    ),
                    CNTextFieldAction(
                      icon: const Icon(CupertinoIcons.mic, color: CupertinoColors.systemBlue, size: 20),
                      onPressed: () {
                        setState(() => _lastTrailingAction = 'Mic tapped');
                      },
                    ),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value);
                    _chatController.clear();
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CNButton(
                      label: 'Set Cupertino',
                      style: CNButtonStyle.gray,
                      shrinkWrap: true,
                      onPressed: () {
                        setState(() {
                          _queryController.text = 'Cupertino';
                          _lastSubmitted = 'None';
                        });
                      },
                    ),
                    CNButton(
                      label: 'Clear',
                      style: CNButtonStyle.gray,
                      shrinkWrap: true,
                      onPressed: () {
                        setState(() {
                          _queryController.clear();
                          _chatController.clear();
                          _bottomChatController.clear();
                          _lastSubmitted = 'None';
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CNTextField.chat(
                  controller: _bottomChatController,
                  placeholder: 'What should I eat next?',
                  enabled: _enabled,
                  tint: CupertinoColors.systemBlue,
                  sendButtonBackgroundColor: CupertinoColors.systemBlue,
                  actions: [
                    CNTextFieldAction(
                      icon: const Icon(Icons.camera, color: CupertinoColors.black, size: 20),
                      onPressed: () {
                        setState(() => _lastTrailingAction = 'Photo tapped');
                      },
                    ),
                    // CNTextFieldAction(
                    //   icon: const Icon(CupertinoIcons.sparkles, color: CupertinoColors.systemBlue, size: 20),
                    //   onPressed: () {
                    //     setState(() => _lastTrailingAction = 'Magic tapped');
                    //   },
                    // ),
                  ],
                  onChanged: (_) => setState(() {}),
                  onTap: () => setState(() => _lastTap = 'Tapped'),
                  onSubmitted: (value) {
                    setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value);
                    _bottomChatController.clear();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
