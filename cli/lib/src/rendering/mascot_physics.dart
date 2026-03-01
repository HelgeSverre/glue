/// Physics constants and enums for the mascot animation system.
///
/// Centralizes tunable parameters for liquid simulation, particle effects,
/// and drip behavior to make tweaking the animation easier.
library;

/// Physics parameters for liquid simulation wave equation.
class LiquidSimPhysics {
  /// Damping factor (0–1). Lower = longer-lasting ripples.
  static const double damping = 0.92;

  /// Threshold for considering a cell "active" during simulation.
  static const double activeThreshold = 0.01;

  /// Accumulated disturbance threshold before mascot explodes.
  static const double explodeThreshold = 60.0;

  LiquidSimPhysics._(); // Prevent instantiation
}

/// Particle system parameters for explosion effect.
class MascotParticles {
  /// Probability of sampling a sprite pixel (for performance).
  static const double samplingRate = 0.4;

  /// Probability of a landed particle spawning a drip trail.
  static const double dripSpawnChance = 0.3;

  /// Probability of an active drip stopping each frame.
  static const double dripStopChance = 0.15;

  /// Maximum cells a drip trail can extend.
  static const int maxDripLength = 6;

  /// Gravity acceleration per frame.
  static const double gravity = 0.15;

  /// Velocity drag coefficient (0–1) per frame.
  static const double drag = 0.96;

  /// Initial speed of ejected particles.
  static const double baseSpeed = 1.5;

  /// Random speed variance multiplier.
  static const double speedVariance = 2.5;

  /// Random horizontal velocity perturbation.
  static const double horizontalPerturbation = 0.8;

  /// Random vertical velocity perturbation.
  static const double verticalPerturbation = 1.5;

  /// Radius of ripple impulse.
  static const int impulseRadius = 3;

  /// Base strength of ripple impulse.
  static const double impulseStrength = 6.0;

  /// Number of frames before explosion is considered "done".
  static const int settleFrames = 10;

  /// Random delay before drip starts (0–8 frames + 2).
  static const int maxDripDelay = 8;
  static const int minDripDelay = 2;

  MascotParticles._(); // Prevent instantiation
}

/// Characters rendered for gooey drip effects.
enum GooChar {
  /// Period/dot character.
  dot(46, '.'),

  /// Comma character.
  comma(44, ','),

  /// Semicolon character.
  semicolon(59, ';'),

  /// Lowercase 'o' for gooey appearance.
  orb(111, 'o');

  final int charCode;
  final String display;

  const GooChar(this.charCode, this.display);
}
