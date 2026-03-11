import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';

class SearchBarDemoPage extends StatefulWidget {
  const SearchBarDemoPage({super.key});

  @override
  State<SearchBarDemoPage> createState() => _SearchBarDemoPageState();
}

class _SearchBarDemoPageState extends State<SearchBarDemoPage> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _coloredController = TextEditingController(
    text: 'Cupertino',
  );
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _bottomChatController = TextEditingController();

  String _lastSubmitted = 'None';
  String _lastTrailingAction = 'None';
  String _lastTap = 'None';
  bool _enabled = true;
  bool _showsCancelAction = true;
  bool _excludeFocus = false;

  @override
  void dispose() {
    _queryController.dispose();
    _coloredController.dispose();
    _chatController.dispose();
    _bottomChatController.dispose();
    super.dispose();
  }

  void _submitChat(TextEditingController controller) {
    final value = controller.text.trim();
    setState(() {
      _lastSubmitted = value.isEmpty ? 'Empty' : value;
      controller.clear();
    });
  }

  Widget _iconAction({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    double size = 20,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(28, 28),
      onPressed: onPressed,
      child: Icon(icon, size: size, color: color),
    );
  }

  Widget _sendAction({
    required BuildContext context,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final tint = CupertinoTheme.of(context).primaryColor;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: enabled ? onPressed : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? tint : tint.withValues(alpha: 0.28),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.arrow_up,
          size: 16,
          color: CupertinoColors.white.withValues(alpha: enabled ? 1 : 0.72),
        ),
      ),
    );
  }

  List<Widget> _buildSearchTrailing(BuildContext context) {
    final query = _queryController.text;
    final placeholderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.placeholderText,
      context,
    );

    if (query.isNotEmpty) {
      return [
        _iconAction(
          icon: CupertinoIcons.clear_circled_solid,
          color: placeholderColor,
          onPressed: () {
            setState(() {
              _queryController.clear();
              _lastTrailingAction = 'Cleared query';
            });
          },
        ),
        if (_showsCancelAction) ...[
          const SizedBox(width: 6),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(28, 28),
            onPressed: () {
              setState(() {
                _queryController.clear();
                _lastSubmitted = 'Cancelled';
              });
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: CupertinoTheme.of(context).primaryColor,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ];
    }

    return [
      _iconAction(
        icon: CupertinoIcons.qrcode_viewfinder,
        color: placeholderColor,
        onPressed: () {
          setState(() => _lastTrailingAction = 'Scanner tapped');
        },
      ),
      const SizedBox(width: 4),
      _iconAction(
        icon: CupertinoIcons.slider_horizontal_3,
        color: placeholderColor,
        onPressed: () {
          setState(() => _lastTrailingAction = 'Filter tapped');
        },
      ),
      if (_showsCancelAction) ...[
        const SizedBox(width: 8),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(28, 28),
          onPressed: () {
            setState(() => _lastSubmitted = 'Cancelled');
          },
          child: Text(
            'Cancel',
            style: TextStyle(
              color: CupertinoTheme.of(context).primaryColor,
              fontSize: 16,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildComposerTrailing(
    BuildContext context,
    TextEditingController controller,
  ) {
    final hasText = controller.text.trim().isNotEmpty;
    return [
      _iconAction(
        icon: CupertinoIcons.photo,
        color: CupertinoTheme.of(context).primaryColor,
        onPressed: () {
          setState(() => _lastTrailingAction = 'Photo tapped');
        },
      ),
      const SizedBox(width: 6),
      _iconAction(
        icon: CupertinoIcons.mic,
        color: CupertinoTheme.of(context).primaryColor,
        onPressed: () {
          setState(() => _lastTrailingAction = 'Mic tapped');
        },
      ),
      const SizedBox(width: 8),
      _sendAction(
        context: context,
        enabled: hasText,
        onPressed: () => _submitChat(controller),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final placeholderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.placeholderText,
      context,
    );

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
                  child: CNTextField(
                    controller: _queryController,
                    placeholder: 'Search',
                    enabled: _enabled,
                    leading: Icon(
                      CupertinoIcons.search,
                      color: placeholderColor,
                      size: 20,
                    ),
                    trailing: _buildSearchTrailing(context),
                    onChanged: (_) => setState(() {}),
                    onTap: () => setState(() => _lastTap = 'Tapped'),
                    onSubmitted: (value) {
                      setState(() {
                        _lastSubmitted = value.isEmpty ? 'Empty' : value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current text: ${_queryController.text.isEmpty ? 'Empty' : _queryController.text}',
                ),
                Text('Last submitted: $_lastSubmitted'),
                Text('Trailing action: $_lastTrailingAction'),
                Text('Last tap: $_lastTap'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('Enabled'),
                    const Spacer(),
                    CupertinoSwitch(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Show cancel action'),
                    const Spacer(),
                    CupertinoSwitch(
                      value: _showsCancelAction,
                      onChanged: (value) {
                        setState(() => _showsCancelAction = value);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Exclude focus'),
                    const Spacer(),
                    CupertinoSwitch(
                      value: _excludeFocus,
                      onChanged: (value) {
                        setState(() => _excludeFocus = value);
                      },
                    ),
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
                        message: const Text(
                          'The text field keeps the native surface while accessories are built in Flutter.',
                        ),
                        actions: [
                          CupertinoActionSheetAction(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Dismiss'),
                          ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text('Tinted Search'),
                const SizedBox(height: 8),
                CNTextField(
                  controller: _coloredController,
                  placeholder: 'Search components',
                  style: const CNTextFieldStyle(
                    tint: CupertinoColors.systemBlue,
                  ),
                  leading: const Icon(
                    CupertinoIcons.search,
                    color: CupertinoColors.systemGrey,
                    size: 20,
                  ),
                  trailing: [
                    _iconAction(
                      icon: CupertinoIcons.clear_circled_solid,
                      color: CupertinoColors.systemGrey,
                      onPressed: () {
                        setState(() {
                          _coloredController.clear();
                          _lastTrailingAction = 'Cleared tinted search';
                        });
                      },
                    ),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    setState(() {
                      _lastSubmitted = value.isEmpty ? 'Empty' : value;
                    });
                  },
                ),
                const SizedBox(height: 24),
                const Text('Composer'),
                const SizedBox(height: 8),
                CNTextField(
                  controller: _chatController,
                  placeholder: 'Type a message',
                  enabled: _enabled,
                  layout: const CNTextFieldLayout(maxVisibleLines: 4),
                  style: const CNTextFieldStyle(
                    tint: CupertinoColors.systemBlue,
                  ),
                  trailing: _buildComposerTrailing(context, _chatController),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitChat(_chatController),
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
                          _coloredController.clear();
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
                child: CNTextField(
                  controller: _bottomChatController,
                  placeholder: 'What should I eat next?',
                  enabled: _enabled,
                  layout: const CNTextFieldLayout(maxVisibleLines: 4),
                  style: const CNTextFieldStyle(
                    tint: CupertinoColors.systemBlue,
                  ),
                  trailing: _buildComposerTrailing(
                    context,
                    _bottomChatController,
                  ),
                  onChanged: (_) => setState(() {}),
                  onTap: () => setState(() => _lastTap = 'Tapped'),
                  onSubmitted: (_) => _submitChat(_bottomChatController),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
