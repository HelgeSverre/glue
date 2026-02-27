// Liquid simulation + ASCII renderer for the Glue mascot splash screen.

import 'dart:math';
import 'mascot_sprite.dart';

const mascotRenderWidth = spriteWidth;
const mascotRenderHeight = spriteHeight;

// Threshold of accumulated disturbance before the mascot explodes.
const _explodeThreshold = 60.0;

class LiquidSim {
  final int width = spriteWidth;
  final int height = spriteHeight;

  // Two displacement buffers for the wave equation.
  late List<double> _curr;
  late List<double> _prev;

  // Damping factor (0–1). Lower = longer-lasting ripples.
  static const _damping = 0.92;

  // Accumulated disturbance energy from clicks.
  double disturbance = 0.0;

  bool get shouldExplode => disturbance >= _explodeThreshold;

  LiquidSim() {
    final n = width * height;
    _curr = List.filled(n, 0.0);
    _prev = List.filled(n, 0.0);
  }

  int _idx(int x, int y) => y * width + x;

  /// Inject a ripple impulse at (cx, cy) in sprite-local coordinates.
  void impulse(int cx, int cy, {double strength = 6.0, int radius = 3}) {
    disturbance += strength;
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

// ---------------------------------------------------------------------------
// Goo explosion particle system
// ---------------------------------------------------------------------------

final _rng = Random();

/// A single goo particle flying outward then dripping down.
class _GooParticle {
  double x, y;
  double vx, vy;
  final int r, g, b;
  final int charCode;
  bool landed = false;

  _GooParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.g,
    required this.b,
    required this.charCode,
  });
}

/// Manages the explosion + drip animation after the mascot is disturbed too much.
class GooExplosion {
  final List<_GooParticle> _particles = [];
  final int viewportWidth;
  final int viewportHeight;
  int _tick = 0;
  static const _gravity = 0.15;
  static const _drag = 0.96;

  // Drip trails that have settled at the bottom and drip further.
  final List<_DripTrail> _drips = [];

  bool get isActive =>
      _particles.any((p) => !p.landed) || _drips.any((d) => d.active);

  bool get isDone => _tick > 10 && !isActive;

  GooExplosion({
    required this.viewportWidth,
    required this.viewportHeight,
    required int originX,
    required int originY,
  }) {
    // Create particles from all non-transparent sprite pixels.
    for (var sy = 0; sy < spriteHeight; sy++) {
      for (var sx = 0; sx < spriteWidth; sx++) {
        final pixel = spriteData[sy * spriteWidth + sx];
        if (pixel == null) continue;

        // Only sample ~40% of pixels to keep it performant.
        if (_rng.nextDouble() > 0.4) continue;

        final px = originX + sx;
        final py = originY + sy;

        // Velocity radiates from center of sprite.
        final cx = originX + spriteWidth / 2;
        final cy = originY + spriteHeight / 2;
        final dx = px - cx;
        final dy = py - cy;
        final dist = sqrt(dx * dx + dy * dy) + 0.1;
        final speed = 1.5 + _rng.nextDouble() * 2.5;

        _particles.add(_GooParticle(
          x: px.toDouble(),
          y: py.toDouble(),
          vx: (dx / dist) * speed + (_rng.nextDouble() - 0.5) * 0.8,
          vy: (dy / dist) * speed - _rng.nextDouble() * 1.5,
          r: pixel[0],
          g: pixel[1],
          b: pixel[2],
          charCode: pixel[3],
        ));
      }
    }
  }

  void step() {
    _tick++;
    for (final p in _particles) {
      if (p.landed) continue;
      p.vy += _gravity;
      p.vx *= _drag;
      p.vy *= _drag;
      p.x += p.vx;
      p.y += p.vy;

      // Hit the bottom — spawn a drip trail and mark as landed.
      if (p.y >= viewportHeight - 1) {
        p.y = viewportHeight - 1;
        p.landed = true;
        // Some particles spawn drip trails that ooze down slowly.
        if (_rng.nextDouble() < 0.3) {
          _drips.add(_DripTrail(
            x: p.x.round().clamp(0, viewportWidth - 1),
            y: p.y.round().clamp(0, viewportHeight - 1),
            r: p.r,
            g: p.g,
            b: p.b,
          ));
        }
      }
      // Off sides — just land.
      if (p.x < 0 || p.x >= viewportWidth) {
        p.landed = true;
      }
    }

    for (final d in _drips) {
      d.step();
    }
  }

  /// Render into a grid of [viewportHeight] lines of [viewportWidth] chars.
  List<String> render() {
    // Build a 2D grid: null = empty, otherwise (r,g,b,char).
    final grid = List<List<List<int>?>>.generate(
      viewportHeight,
      (_) => List<List<int>?>.filled(viewportWidth, null),
    );

    // Place drip trail cells first (background layer).
    for (final d in _drips) {
      for (final cell in d.cells) {
        final cx = cell.x;
        final cy = cell.y;
        if (cx >= 0 && cx < viewportWidth && cy >= 0 && cy < viewportHeight) {
          grid[cy][cx] = [d.r, d.g, d.b, _gooChars[_rng.nextInt(_gooChars.length)]];
        }
      }
    }

    // Place particles on top.
    for (final p in _particles) {
      final px = p.x.round();
      final py = p.y.round();
      if (px >= 0 && px < viewportWidth && py >= 0 && py < viewportHeight) {
        grid[py][px] = [p.r, p.g, p.b, p.charCode];
      }
    }

    // Render to ANSI strings.
    final lines = <String>[];
    for (var y = 0; y < viewportHeight; y++) {
      final buf = StringBuffer();
      for (var x = 0; x < viewportWidth; x++) {
        final cell = grid[y][x];
        if (cell == null) {
          buf.write(' ');
        } else {
          buf.write('\x1b[38;2;${cell[0]};${cell[1]};${cell[2]}m'
              '${String.fromCharCode(cell[3])}\x1b[0m');
        }
      }
      lines.add(buf.toString());
    }
    return lines;
  }
}

// Gooey drip characters.
const _gooChars = [46, 44, 59, 111]; // . , ; o

/// A drip trail that oozes downward from a landing point.
class _DripTrail {
  final int x;
  int y;
  final int r, g, b;
  final List<_DripCell> cells = [];
  int _delay;
  bool active = true;

  _DripTrail({
    required this.x,
    required this.y,
    required this.r,
    required this.g,
    required this.b,
  }) : _delay = _rng.nextInt(8) + 2 {
    cells.add(_DripCell(x, y));
  }

  void step() {
    if (!active) return;
    if (_delay > 0) {
      _delay--;
      return;
    }
    y++;
    cells.add(_DripCell(x, y));
    // Random chance to stop dripping.
    if (_rng.nextDouble() < 0.15 || cells.length > 6) {
      active = false;
    }
  }
}

class _DripCell {
  final int x, y;
  _DripCell(this.x, this.y);
}
