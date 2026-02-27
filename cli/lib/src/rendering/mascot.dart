// Liquid simulation + ASCII renderer for the Glue mascot splash screen.

import 'dart:math';
import 'mascot_sprite.dart';

const mascotRenderWidth = spriteWidth;
const mascotRenderHeight = spriteHeight;

class LiquidSim {
  final int width = spriteWidth;
  final int height = spriteHeight;

  // Two displacement buffers for the wave equation.
  late List<double> _curr;
  late List<double> _prev;

  // Damping factor (0–1). Lower = longer-lasting ripples.
  static const _damping = 0.92;

  LiquidSim() {
    final n = width * height;
    _curr = List.filled(n, 0.0);
    _prev = List.filled(n, 0.0);
  }

  int _idx(int x, int y) => y * width + x;

  /// Inject a ripple impulse at (cx, cy) in sprite-local coordinates.
  void impulse(int cx, int cy, {double strength = 6.0, int radius = 3}) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        if (x < 0 || x >= width || y < 0 || y >= height) continue;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > radius) continue;
        final falloff = 1.0 - dist / (radius + 1);
        _curr[_idx(x, y)] += strength * falloff;
      }
    }
  }

  /// Advance the simulation one step.
  void step() {
    final next = List.filled(width * height, 0.0);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = _idx(x, y);
        // Wave equation: average of neighbors * 2 - previous.
        final avg = (_curr[i - 1] + _curr[i + 1] +
                _curr[i - width] + _curr[i + width]) /
            2.0;
        next[i] = (avg - _prev[i]) * _damping;
      }
    }
    _prev = _curr;
    _curr = next;
  }

  /// Get the horizontal displacement at (x, y).
  double displacement(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0.0;
    return _curr[_idx(x, y)];
  }

  /// Whether any cell still has significant displacement.
  bool get isActive {
    for (final v in _curr) {
      if (v.abs() > 0.01) return true;
    }
    return false;
  }
}

/// Render the mascot sprite with liquid displacement applied.
/// Returns a list of ANSI-colored lines.
List<String> renderMascot(LiquidSim sim) {
  final lines = <String>[];
  for (var y = 0; y < spriteHeight; y++) {
    final buf = StringBuffer();
    for (var x = 0; x < spriteWidth; x++) {
      // Sample with horizontal displacement.
      final dx = sim.displacement(x, y);
      final sx = (x + dx).round().clamp(0, spriteWidth - 1);
      final pixel = spriteData[y * spriteWidth + sx];
      if (pixel == null) {
        buf.write(' ');
      } else {
        final r = pixel[0];
        final g = pixel[1];
        final b = pixel[2];
        final ch = String.fromCharCode(pixel[3]);
        buf.write('\x1b[38;2;$r;$g;${b}m$ch\x1b[0m');
      }
    }
    lines.add(buf.toString());
  }
  return lines;
}
