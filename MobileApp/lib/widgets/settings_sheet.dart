import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../utils/accessibility_helper.dart';

/// Reusable settings bottom sheet – call `SettingsSheet.show(context)` from anywhere.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: Provider.of<ThemeProvider>(context, listen: false),
        child: const SettingsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final a11y = AccessibilityHelper();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Settings',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // ── Dark Mode ─────────────────────────────────────────────
            _SettingsTile(
              icon: themeProvider.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              title: 'Dark Mode',
              subtitle: themeProvider.isDarkMode ? 'On' : 'Off',
              trailing: Switch.adaptive(
                value: themeProvider.isDarkMode,
                onChanged: (_) => themeProvider.toggleDarkMode(),
              ),
            ),

            const Divider(height: 1),

            // ── Accessibility ─────────────────────────────────────────
            ListenableBuilder(
              listenable: a11y,
              builder: (context, _) => _SettingsTile(
                icon: Icons.accessibility_new_rounded,
                title: 'Accessibility Mode',
                subtitle: a11y.enabled
                    ? 'Large text & high contrast'
                    : 'Standard display',
                trailing: Switch.adaptive(
                  value: a11y.enabled,
                  onChanged: (v) => a11y.setEnabled(v),
                ),
              ),
            ),

            const Divider(height: 1),

            // ── About ─────────────────────────────────────────────────
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              title: 'About ReddiHelp',
              subtitle: 'v1.0.0',
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: 'ReddiHelp',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2025 ReddiHelp Team',
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'A disaster response platform connecting '
                        'communities with first responders.',
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
