import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

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
  String _lastSubmitted = 'None';
  String _lastTrailingAction = 'None';
  String _lastTap = 'None';
  bool _enabled = true;
  bool _showsCancelButton = true;

  @override
  void dispose() {
    _queryController.dispose();
    _coloredController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Search Bar')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            const Text('Default'),
            const SizedBox(height: 8),
            CNSearchBar(
              controller: _queryController,
              placeholder: 'Search',
              enabled: _enabled,
              showsCancelButton: _showsCancelButton,
              traillingActions: [
                CNSearchBarAction(
                  icon: const Icon(Icons.qr_code_scanner,
                      color: CupertinoColors.black, size: 24),
                  onPressed: () {
                    setState(() => _lastTrailingAction = 'Scanner tapped');
                  },
                ),
                CNSearchBarAction(
                  icon: const Icon(Icons.abc,
                      size: 48, color: CupertinoColors.black),
                  onPressed: () {
                    setState(() => _lastTrailingAction = 'Filter tapped');
                  },
                ),
              ],
              onChanged: (_) => setState(() {}),
              onTap: () => setState(() => _lastTap = 'Tapped'),
              onSubmitted: (value) => setState(
                  () => _lastSubmitted = value.isEmpty ? 'Empty' : value),
              onCancelled: () {
                setState(() {
                  _queryController.clear();
                  _lastSubmitted = 'Cancelled';
                });
              },
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
                    onChanged: (value) => setState(() => _enabled = value)),
              ],
            ),
            Row(
              children: [
                const Text('Show cancel button'),
                const Spacer(),
                CupertinoSwitch(
                    value: _showsCancelButton,
                    onChanged: (value) =>
                        setState(() => _showsCancelButton = value)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Tinted'),
            const SizedBox(height: 8),
            CNSearchBar(
              controller: _coloredController,
              placeholder: 'Search components',
              tint: CupertinoColors.systemPink,
              fieldBackgroundColor: CupertinoColors.systemGrey5,
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) => setState(
                  () => _lastSubmitted = value.isEmpty ? 'Empty' : value),
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
                      _lastSubmitted = 'None';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
