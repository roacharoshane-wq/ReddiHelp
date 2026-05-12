import 'package:flutter/material.dart';
import 'package:MobileApp/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class ResponderProfileScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const ResponderProfileScreen({super.key, required this.onComplete});

  @override
  State<ResponderProfileScreen> createState() => _ResponderProfileScreenState();
}

class _ResponderProfileScreenState extends State<ResponderProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _agencyController = TextEditingController();
  final _stationController = TextEditingController();

  final Map<String, bool> _skills = {
    'First Aid / CPR': false,
    'Search & Rescue': false,
    'Firefighting': false,
    'Medical / Nursing': false,
    'Logistics / Transport': false,
    'Food Distribution': false,
    'Communication / Radio': false,
    'Incident Command': false,
    'Hazmat Response': false,
    'Evacuation Planning': false,
  };

  final Map<String, bool> _resources = {
    'Ambulance': false,
    'Fire Truck': false,
    'Police Vehicle': false,
    'Rescue Equipment': false,
    'Medical Supplies': false,
    'Communication Equipment': false,
    'Generators': false,
    'Helicopter / Air Support': false,
  };

  @override
  void dispose() {
    _nameController.dispose();
    _agencyController.dispose();
    _stationController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // Collect selected skills
      final selectedSkills =
          _skills.entries.where((e) => e.value).map((e) => e.key).toList();

      // Collect selected resources
      final selectedResources =
          _resources.entries.where((e) => e.value).map((e) => e.key).toList();

      // Update auth provider
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.updateUserProfile({
        'skills': selectedSkills,
        'resources': selectedResources,
        'name': _nameController.text,
        'agency': _agencyController.text,
        'station': _stationController.text,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profile saved!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSkillCount = _skills.values.where((v) => v).length;
    final selectedResourceCount = _resources.values.where((v) => v).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero card
              Card(
                color: Colors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(Icons.emergency_share,
                            color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome, Responder',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tell us about your skills and available resources',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Profile form
              _sectionHeader('Your Profile', Icons.person),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyController,
                decoration: const InputDecoration(
                  labelText: 'Agency / Department',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _stationController,
                decoration: const InputDecoration(
                  labelText: 'Station / Location',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Skills
              _sectionHeader(
                  'Specialised Skills  ($selectedSkillCount selected)',
                  Icons.build),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _skills.entries.map((e) {
                  final selected = e.value;
                  return FilterChip(
                    label: Text(e.key),
                    selected: selected,
                    onSelected: (val) => setState(() => _skills[e.key] = val),
                    selectedColor: Colors.orange.withOpacity(0.25),
                    checkmarkColor: Colors.orange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.orange[800] : Colors.black87,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: selected ? Colors.orange : Colors.grey[300]!,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Resources
              _sectionHeader(
                  'Available Resources  ($selectedResourceCount selected)',
                  Icons.inventory_2),
              const SizedBox(height: 8),
              ..._resources.entries.map((e) {
                return CheckboxListTile(
                  title: Text(e.key),
                  value: e.value,
                  activeColor: Colors.orange,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setState(() => _resources[e.key] = val ?? false),
                );
              }),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Profile',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
