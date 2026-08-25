import 'package:flutter/material.dart';

/// Initials on a colour derived from the person's id.
///
/// Same id, same colour, on every screen and every phone — because the colour
/// is computed from the id rather than picked at random or by list position.
/// A list that reorders must not repaint everybody.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.userId,
    required this.initials,
    this.radius = 20,
  });

  final String userId;
  final String initials;
  final double radius;

  static const _palette = [
    Color(0xFF5E7CE2),
    Color(0xFF2FA84F),
    Color(0xFFE2725B),
    Color(0xFF8E6BBF),
    Color(0xFF00897B),
    Color(0xFFD4A017),
    Color(0xFFC2185B),
    Color(0xFF3949AB),
  ];

  Color get _colour =>
      _palette[userId.hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colour,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
