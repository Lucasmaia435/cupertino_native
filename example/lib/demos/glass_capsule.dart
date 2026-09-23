import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:cupertino_native/cupertino_native.dart';

class GlassCapsuleDemoPage extends StatefulWidget {
  const GlassCapsuleDemoPage({super.key});

  @override
  State<GlassCapsuleDemoPage> createState() => _GlassCapsuleDemoPageState();
}

class _GlassCapsuleDemoPageState extends State<GlassCapsuleDemoPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Glass Capsule')),
      child: SafeArea(
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // A single-item capsule: a round glass button, e.g. a back control.
              const SizedBox(
                width: CNGlassCapsule.width,
                height: CNGlassCapsule.width,
                child: CNGlassCapsule(
                  items: [CNGlassCapsuleItem(icon: CNSymbol('chevron.left'), label: 'Back')],
                  onTap: _noop,
                ),
              ),
              // A group of plain actions sharing one capsule.
              SizedBox(
                width: CNGlassCapsule.width,
                height: CNGlassCapsule.actionsHeight(3),
                child: CNGlassCapsule(
                  items: const [
                    CNGlassCapsuleItem(icon: CNSymbol('square.and.arrow.up'), label: 'Share'),
                    CNGlassCapsuleItem(icon: CNSymbol('pencil'), label: 'Edit'),
                    CNGlassCapsuleItem(icon: CNSymbol('trash'), label: 'Delete', tint: CupertinoColors.systemRed),
                  ],
                  onTap: (i) => debugPrint('tapped action $i'),
                ),
              ),
              // A capsule with a selection, behaving as a vertical tab bar.
              SizedBox(
                width: CNGlassCapsule.width,
                height: CNGlassCapsule.tabsHeight(3),
                child: CNGlassCapsule(
                  items: const [
                    CNGlassCapsuleItem(icon: CNSymbol('house'), label: 'Home'),
                    CNGlassCapsuleItem(icon: CNSymbol('heart'), label: 'Favorites', badgeCount: 3),
                    CNGlassCapsuleItem(icon: CNSymbol('gearshape'), label: 'Settings'),
                  ],
                  selectedIndex: _tabIndex,
                  inset: CNGlassCapsule.tabsInset,
                  onTap: (i) => setState(() => _tabIndex = i),
                ),
              ),
              // A capsule using flutterIcon: Material icons rendered natively,
              // for glyphs that have no SF Symbol equivalent.
              SizedBox(
                width: CNGlassCapsule.width,
                height: CNGlassCapsule.actionsHeight(2),
                child: CNGlassCapsule(
                  items: const [
                    CNGlassCapsuleItem(flutterIcon: Icon(Icons.emoji_food_beverage), label: 'Beverage'),
                    CNGlassCapsuleItem(flutterIcon: Icon(Icons.local_pizza), label: 'Pizza'),
                  ],
                  onTap: (i) => debugPrint('tapped flutterIcon action $i'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop(int _) {}
