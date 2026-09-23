import 'package:flutter/cupertino.dart';
import 'package:cupertino_native/cupertino_native.dart';

class ScaffoldDemoPage extends StatefulWidget {
  const ScaffoldDemoPage({super.key});

  @override
  State<ScaffoldDemoPage> createState() => _ScaffoldDemoPageState();
}

class _ScaffoldDemoPageState extends State<ScaffoldDemoPage> {
  int _index = 0;

  static const _titles = ['Home', 'Favorites', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return CupertinoNativeScaffold(
      title: _titles[_index],
      actions: [
        CNToolbarAction(icon: const CNSymbol('magnifyingglass', size: 18), onPressed: () {}),
        CNToolbarAction(
          icon: const CNSymbol('plus', size: 18),
          label: 'Add',
          prominent: true,
          onPressed: () {
            Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const _DetailPage()));
          },
        ),
      ],
      tabs: const [
        CNTabBarItem(label: 'Home', icon: CNSymbol('house', size: 18)),
        CNTabBarItem(label: 'Favorites', icon: CNSymbol('heart', size: 18), showBadge: true, badgeLabel: '3'),
        CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape', size: 18)),
      ],
      currentTabIndex: _index,
      onTabChange: (i) => setState(() => _index = i),
      children: [
        _DemoPage(title: _titles[0], color: CupertinoColors.systemBlue),
        _DemoPage(title: _titles[1], color: CupertinoColors.systemPink),
        _DemoPage(title: _titles[2], color: CupertinoColors.systemGrey),
      ],
    );
  }
}

class _DemoPage extends StatelessWidget {
  const _DemoPage({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: 30,
        itemBuilder: (context, index) => CupertinoListTile(
          title: Text('$title row $index'),
          leading: Icon(CupertinoIcons.circle_fill, color: color, size: 16),
        ),
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    return CupertinoNativeScaffold(
      title: 'Detail',
      children: const [SafeArea(child: Center(child: Text('Pushed with the auto back button')))],
    );
  }
}
