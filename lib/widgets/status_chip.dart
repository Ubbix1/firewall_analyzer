import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final int status;
  final bool small;

  const StatusChip({
    super.key,
    required this.status,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    
    if (status >= 200 && status < 300) {
      color = Colors.green;
    } else if (status >= 300 && status < 400) {
      color = Colors.blue;
    } else if (status >= 400 && status < 500) {
      color = Colors.orange;
    } else if (status >= 500) {
      color = Colors.red;
    } else {
      color = theme.disabledColor;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(small ? 4 : 8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toString(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: small ? 10 : 12,
        ),
      ),
    );
  }
}
