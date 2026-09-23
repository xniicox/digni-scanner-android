import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DigniLogo extends StatelessWidget {
  final double width;
  final bool light;

  const DigniLogo({
    super.key,
    this.width = 180,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/digni_logo.svg',
      width: width,
      colorFilter: light
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : null,
      semanticsLabel: 'DIGNI e-ticket',
    );
  }
}
