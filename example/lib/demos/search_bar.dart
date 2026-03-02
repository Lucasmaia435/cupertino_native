import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

class SearchBarDemoPage extends StatefulWidget {
  const SearchBarDemoPage({super.key});

  @override
  State<SearchBarDemoPage> createState() => _SearchBarDemoPageState();
}

class _SearchBarDemoPageState extends State<SearchBarDemoPage> {
  final CNSearchBarController _controller = CNSearchBarController();
  String _query = '';
  String _coloredQuery = 'Cupertino';
  String _lastSubmitted = 'None';
  String _lastTrailingAction = 'None';
  bool _enabled = true;
  bool _showsCancelButton = true;

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
              text: _query,
              placeholder: 'Search',
              enabled: _enabled,
              showsCancelButton: _showsCancelButton,
              trailingIcon: Icons.qr_code_scanner_outlined,
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) => setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value),
              onTrailingPressed: () {
                setState(() => _lastTrailingAction = 'Filter tapped');
              },
              onCancelled: () {
                setState(() {
                  _query = '';
                  _lastSubmitted = 'Cancelled';
                });
              },
            ),
            const SizedBox(height: 8),
            Text('Current text: ${_query.isEmpty ? 'Empty' : _query}'),
            Text('Last submitted: $_lastSubmitted'),
            Text('Trailing action: $_lastTrailingAction'),
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
            const SizedBox(height: 24),
            const Text('Tinted'),
            const SizedBox(height: 8),
            CNSearchBar(
              text: _coloredQuery,
              placeholder: 'Search components',
              tint: CupertinoColors.systemPink,
              fieldBackgroundColor: CupertinoColors.systemGrey5,
              onChanged: (value) => setState(() => _coloredQuery = value),
              onSubmitted: (value) => setState(() => _lastSubmitted = value.isEmpty ? 'Empty' : value),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CNButton(label: 'Focus', style: CNButtonStyle.gray, shrinkWrap: true, onPressed: () => _controller.focus()),
                CNButton(label: 'Unfocus', style: CNButtonStyle.gray, shrinkWrap: true, onPressed: () => _controller.unfocus()),
                CNButton(
                  label: 'Clear',
                  style: CNButtonStyle.gray,
                  shrinkWrap: true,
                  onPressed: () {
                    setState(() {
                      _query = '';
                      _lastSubmitted = 'None';
                    });
                    _controller.setText('');
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
