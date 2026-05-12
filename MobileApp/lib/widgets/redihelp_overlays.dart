import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/preparedness_guide_screen.dart';
import 'settings_sheet.dart';

const Color reddiPrimaryBlue = Color(0xFF1A73E8);
const Color reddiTeal = Color(0xFF00BFA5);
const Color reddiDanger = Color(0xFFE53935);
const Color reddiWarning = Color(0xFFFB8C00);
const Color reddiTextSecondary = Color(0xFF6B7280);

Future<void> showPreparednessGuideSheet(
  BuildContext context, {
  bool victimMode = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PreparednessGuideScreen(victimMode: victimMode),
    ),
  );
}

Future<void> showProfileSkillsSheet(
  BuildContext context, {
  required String title,
  required String primaryFieldLabel,
  required String primaryFieldKey,
  required String fallbackInitial,
  required Color accentColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.user ?? <String, dynamic>{};
      final currentSkills = List<String>.from(user['skills'] ?? auth.skills);

      final nameController = TextEditingController(
        text: (user['name'] ?? user['username'] ?? '').toString(),
      );
      final phoneController = TextEditingController(
        text: (user['phone'] ?? user['mobile'] ?? '').toString(),
      );
      final primaryFieldController = TextEditingController(
        text: (user[primaryFieldKey] ?? '').toString(),
      );
      final addSkillController = TextEditingController();

      return StatefulBuilder(
        builder: (context, setSheetState) {
          void addSkill() {
            final value = addSkillController.text.trim();
            if (value.isEmpty || currentSkills.contains(value)) return;
            setSheetState(() {
              currentSkills.add(value);
              addSkillController.clear();
            });
          }

          Future<void> saveProfile() async {
            final updatedProfile = <String, dynamic>{
              'name': nameController.text.trim(),
              'phone': phoneController.text.trim(),
              primaryFieldKey: primaryFieldController.text.trim(),
              'skills': currentSkills,
            };
            await auth.updateUserProfile(updatedProfile);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Saved ✓'),
                backgroundColor: Color(0xFF22C55E),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.55,
            maxChildSize: 0.98,
            expand: false,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: accentColor.withValues(alpha: 0.12),
                          child: Text(
                            fallbackInitial,
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Auto-filled from your profile',
                                style: TextStyle(
                                  color: reddiTextSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Full name',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: accentColor, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: 'Contact number',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: accentColor, width: 1.5),
                        ),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: primaryFieldController,
                      decoration: InputDecoration(
                        labelText: primaryFieldLabel,
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: accentColor, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text(
                          'Skills',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${currentSkills.length} saved',
                          style: const TextStyle(color: reddiTextSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: currentSkills
                          .map(
                            (skill) => InputChip(
                              label: Text(skill),
                              onDeleted: () {
                                setSheetState(
                                    () => currentSkills.remove(skill));
                              },
                              deleteIconColor: accentColor,
                              side: BorderSide(
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                              labelStyle: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: Colors.white,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: addSkillController,
                            decoration: const InputDecoration(
                              labelText: 'Add skill',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => addSkill(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          width: 56,
                          child: FloatingActionButton(
                            heroTag: null,
                            onPressed: addSkill,
                            backgroundColor: accentColor,
                            elevation: 0,
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              SettingsSheet.show(context);
                            },
                            icon: const Icon(Icons.settings_rounded),
                            label: const Text('Settings'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Logout'),
                                  content: const Text(
                                    'Are you sure you want to logout?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        dialogContext,
                                        false,
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        dialogContext,
                                        true,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: reddiDanger,
                                      ),
                                      child: const Text('Logout'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await auth.logout();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: reddiDanger,
                              side: const BorderSide(color: reddiDanger),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
