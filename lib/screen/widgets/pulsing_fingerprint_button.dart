import 'package:flutter/material.dart';

class PulsingFingerprintButton extends StatelessWidget {
  final bool isClockedIn;
  final bool isLoading;
  final Animation<double> pulseAnimation;
  final VoidCallback onTap;

  const PulsingFingerprintButton({
    super.key,
    required this.isClockedIn,
    required this.isLoading,
    required this.pulseAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color greenColor = Color(0xFF10B981); // Vibrant Emerald Green
    const Color redColor = Color(0xFFF43F5E); // Premium Coral Rose

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Column(
          children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Layer 1: Outer Breathing Radial Glow Shadow
                  Transform.scale(
                    scale: pulseAnimation.value,
                    child: Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: isClockedIn
                                ? redColor.withValues(alpha: 0.20)
                                : greenColor.withValues(alpha: 0.20),
                            blurRadius: 28 * pulseAnimation.value,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Layer 2: Glowing Translucent Outer Ring
                  Transform.scale(
                    scale: pulseAnimation.value,
                    child: Container(
                      width: 196,
                      height: 196,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isClockedIn
                              ? redColor.withValues(alpha: 0.3)
                              : greenColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Layer 3: Tactile Holographic Fingerprint Button (Static Core for Premium Feeling)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLoading ? null : onTap,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 172,
                        height: 172,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isClockedIn
                                ? [
                                    redColor,
                                    const Color(
                                      0xFFD946EF,
                                    ), // Soft Violet/Magenta
                                  ]
                                : [
                                    greenColor,
                                    const Color(0xFF14B8A6), // Premium Teal
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isClockedIn ? redColor : greenColor)
                                  .withValues(alpha: 0.4),
                              blurRadius: 18 * pulseAnimation.value,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isLoading)
                              const SizedBox(
                                width: 54,
                                height: 54,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3.5,
                                ),
                              )
                            else
                              const Icon(
                                Icons.fingerprint_rounded,
                                size: 64,
                                color: Colors.white,
                              ),
                            const SizedBox(height: 10),
                            Text(
                              isLoading
                                  ? "LOADING..."
                                  : (isClockedIn ? "CLOCK OUT" : "CLOCK IN"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // PREMIUM STATUS CHIP (GLASSMORPHIC ACTIVE INDICATOR PILL WITH BREATHING NEON GLOW)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isClockedIn
                    ? redColor.withValues(alpha: 0.08)
                    : greenColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: (isClockedIn ? redColor : greenColor).withValues(
                    alpha: 0.2,
                  ),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing indicator dot (Breathing animation)
                  Container(
                    width: 8 * pulseAnimation.value,
                    height: 8 * pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isClockedIn ? redColor : greenColor,
                      boxShadow: [
                        BoxShadow(
                          color: isClockedIn ? redColor : greenColor,
                          blurRadius: 8 * pulseAnimation.value,
                          spreadRadius: 2 * pulseAnimation.value,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isClockedIn ? "ACTIVE SHIFT TRACKING" : "OFF DUTY",
                    style: TextStyle(
                      color: isClockedIn ? redColor : greenColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
