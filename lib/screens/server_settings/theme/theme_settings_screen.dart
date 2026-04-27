import 'package:flutter/material.dart';

class ThemeSettingsScreen extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const ThemeSettingsScreen({
    super.key,
    required this.currentMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appearance',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildThemeTile(
            context,
            mode: ThemeMode.system,
            title: 'System Default',
            subtitle: 'Match device settings',
            icon: Icons.brightness_auto,
          ),
          const SizedBox(height: 12),
          _buildThemeTile(
            context,
            mode: ThemeMode.light,
            title: 'Light Mode',
            subtitle: 'Classic bright appearance',
            icon: Icons.wb_sunny_outlined,
          ),
          const SizedBox(height: 12),
          _buildThemeTile(
            context,
            mode: ThemeMode.dark,
            title: 'Dark Mode',
            subtitle: 'Easy on the eyes in low light',
            icon: Icons.nightlight_round_outlined,
          ),
          const SizedBox(height: 32),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Changes will be applied immediately across all application screens.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeTile(
    BuildContext context, {
    required ThemeMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = currentMode == mode;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onThemeChanged(mode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? theme.colorScheme.primary 
                : theme.colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected 
              ? theme.colorScheme.primary.withOpacity(0.05) 
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected 
                    ? theme.colorScheme.onPrimary 
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
