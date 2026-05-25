import 'package:flutter/widgets.dart';

/// Configuration for the real-time animated mesh gradient background on
/// [CNButton].
///
/// On iOS 18+ the gradient renders via SwiftUI `MeshGradient` + `TimelineView`
/// at up to 120 fps (ProMotion). On older iOS a pair of animated
/// `CAGradientLayer`s driven by `CADisplayLink` delivers a comparable effect.
///
/// ```dart
/// CNButton(
///   label: 'Get started',
///   meshGradient: CNButtonMeshGradient(
///     colors: [Colors.black, Color(0xFF3D0066), Color(0xFFD43500)],
///   ),
///   onPressed: () {},
/// )
/// ```
class CNButtonMeshGradient {
  /// Creates a mesh gradient configuration.
  ///
  /// At least **two** [colors] are required.
  ///
  /// [animationSpeed] is a multiplier on the animation clock:
  ///   - `0.0` → completely frozen (no motion at all)
  ///   - `100` → default speed, suitable for most use cases.
  ///
  /// Values above `1.0` are accepted but may feel too energetic for most
  /// premium UI contexts.
  const CNButtonMeshGradient({required this.colors, this.animationSpeed = 100}) : assert(colors.length >= 2, 'CNButtonMeshGradient requires at least 2 colors.');

  /// Color palette the mesh cycles between.
  ///
  /// All [Color] types are supported, including [CupertinoDynamicColor].
  /// The native renderer spreads these across the 3×3 mesh vertices and
  /// interpolates between them over time.
  final List<Color> colors;

  /// How fast the mesh animation runs.
  ///
  /// This multiplies the animation clock — it simultaneously slows the spatial
  /// drift of the mesh control points **and** the rate at which colours evolve,
  /// so the whole animation stays coherent at any speed.
  ///
  /// Default is `0.35` for a barely-perceptible, cinematic ambient feel.
  final double animationSpeed;
}
