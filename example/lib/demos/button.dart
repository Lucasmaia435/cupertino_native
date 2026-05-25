import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cupertino_native/style/mesh_gradient.dart';

const _glassGradient = LinearGradient(colors: [Color(0xBFE9135F), Color(0xBF9108BF), Color(0xBF8083FF)], stops: [0.11, 0.50, 0.90], begin: Alignment.topLeft, end: Alignment.bottomRight);

class ButtonDemoPage extends StatefulWidget {
  const ButtonDemoPage({super.key});

  @override
  State<ButtonDemoPage> createState() => _ButtonDemoPageState();
}

class _ButtonDemoPageState extends State<ButtonDemoPage> {
  String _last = 'None';

  void _set(String what) => setState(() => _last = what);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Button')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Text buttons'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CNButton(label: 'Plain', style: CNButtonStyle.plain, onPressed: () => _set('Plain'), shrinkWrap: true),
                CNButton(label: 'Gray', style: CNButtonStyle.gray, onPressed: () => _set('Gray'), shrinkWrap: true),
                CNButton(label: 'Tinted', style: CNButtonStyle.tinted, onPressed: () => _set('Tinted'), shrinkWrap: true),
                CNButton(label: 'Bordered', style: CNButtonStyle.bordered, onPressed: () => _set('Bordered'), shrinkWrap: true),
                CNButton(label: 'BorderedProminent', style: CNButtonStyle.borderedProminent, onPressed: () => _set('BorderedProminent'), shrinkWrap: true),
                CNButton(label: 'Filled', style: CNButtonStyle.filled, onPressed: () => _set('Filled'), shrinkWrap: true),
                CNButton(label: 'Glass', style: CNButtonStyle.glass, tint: CupertinoColors.white, backgroundGradient: _glassGradient, onPressed: () => _set('Glass'), shrinkWrap: true),
                CNButton(label: 'ProminentGlass', style: CNButtonStyle.prominentGlass, tint: CupertinoColors.white, backgroundGradient: _glassGradient, onPressed: () => _set('ProminentGlass'), shrinkWrap: true),
                CNButton(label: 'Disabled', style: CNButtonStyle.bordered, onPressed: null, shrinkWrap: true),
              ],
            ),
            const SizedBox(height: 48),
            const Text('Icon buttons'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.plain, onPressed: () => _set('Icon Plain')),
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.gray, onPressed: () => _set('Icon Gray')),
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.tinted, onPressed: () => _set('Icon Tinted')),
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.bordered, onPressed: () => _set('Icon Bordered')),
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.borderedProminent, onPressed: () => _set('Icon BorderedProminent')),
                CNButton.icon(icon: const CNSymbol('heart.fill', size: 18), style: CNButtonStyle.filled, onPressed: () => _set('Icon Filled')),
                CNButton.icon(
                  icon: const CNSymbol('heart.fill', size: 18, color: CupertinoColors.white),
                  style: CNButtonStyle.glass,
                  meshGradient: CNButtonMeshGradient(colors: [const Color(0xFFE9135F), const Color(0xFF9108BF), const Color(0xFF8083FF)], animationSpeed: 10),

                  onPressed: () => _set('Icon Glass'),
                ),
                CNButton.icon(
                  icon: const CNSymbol('heart.fill', size: 18, color: CupertinoColors.white),
                  style: CNButtonStyle.prominentGlass,
                  tint: CupertinoColors.transparent,
                  meshGradient: CNButtonMeshGradient(colors: [const Color(0xFFE9135F), const Color(0xFF9108BF), const Color(0xFF8083FF)], animationSpeed: 10),
                  onPressed: () => _set('Icon ProminentGlass'),
                ),
                CNButton.icon(
                  flutterIcon: const Icon(Icons.favorite_outline, size: 60, fill: 1, color: Colors.white),
                  // icon: const CNSymbol('heart.fill', size: 18, color: CupertinoColors.destructiveRed),
                  style: CNButtonStyle.prominentGlass,
                  tint: CupertinoColors.transparent,
                  meshGradient: CNButtonMeshGradient(colors: [const Color(0xFFE9135F), const Color(0xFF9108BF), const Color(0xFF8083FF)], animationSpeed: 100),
                  onPressed: () => _set('IconData Favorite'),
                  size: 120,
                ),
              ],
            ),
            const SizedBox(height: 48),
            Center(child: Text('Last pressed: $_last')),
          ],
        ),
      ),
    );
  }
}
