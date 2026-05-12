import 'package:flutter/material.dart';
import 'package:MobileApp/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class VolunteerProfileScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const VolunteerProfileScreen({super.key, required this.onComplete});

  @override
  State<VolunteerProfileScreen> createState() => _VolunteerProfileScreenState();
}

class _VolunteerProfileScreenState extends State<VolunteerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _orgController = TextEditingController();
  final _phoneController = TextEditingController();

  // Vehicle availability (spec: none/car/truck/boat)
  String _vehicleType = 'none';
  static const _vehicleOptions = [
    {'value': 'none', 'label': 'No Vehicle', 'icon': Icons.directions_walk},
    {'value': 'car', 'label': 'Car', 'icon': Icons.directions_car},
    {'value': 'truck', 'label': 'Truck', 'icon': Icons.local_shipping},
    {'value': 'boat', 'label': 'Boat', 'icon': Icons.directions_boat},
  ];

  // Availability status (spec: Available, Unavailable, On Task)
  String _availability = 'available';

  // Professional verification flag
  bool _hasProfessionalCredentials = false;

  // Skills (spec: predefined multi-select list + free-text 'Other')
  final Map<String, bool> _skills = {
    'First Aid / CPR': false,
    'Search & Rescue': false,
    'Medical Professional': false,
    'Heavy Equipment': false,
    'Multilingual': false,
    'Mental Health': false,
    'Logistics / Supply': false,
    'Firefighting': false,
    'Communication / Radio': false,
    'Counselling': false,
    'Construction / Repairs': false,
    'Other': false,
  };

  // Free-text field for 'Other' skill
  final _otherSkillController = TextEditingController();

  // Languages (spec: language selection for Multilingual skill)
  final Map<String, bool> _languages = {
    'English': true,
    'Spanish': false,
    'French': false,
    'Patois/Creole': false,
    'Mandarin': false,
    'Hindi': false,
    'Arabic': false,
    'Portuguese': false,
  };

  final Map<String, bool> _resources = {
    'Vehicle (car/truck)': false,
    'Boat': false,
    'Generator': false,
    'Medical kit': false,
    'Food / Water supplies': false,
    'Tent / Shelter': false,
    'Communication equipment': false,
    'Tools / Equipment': false,
  };

  // Active Location — preferred parish for volunteer deployment
  String? _activeLocationName;
  static const _jamaicaParishes = [
    {'name': 'Kingston', 'lat': 17.9714, 'lon': -76.7920},
    {'name': 'St. Andrew', 'lat': 18.0179, 'lon': -76.7494},
    {'name': 'St. Thomas', 'lat': 17.9936, 'lon': -76.3497},
    {'name': 'Portland', 'lat': 18.1750, 'lon': -76.4105},
    {'name': 'St. Mary', 'lat': 18.2647, 'lon': -76.7872},
    {'name': 'St. Ann', 'lat': 18.3525, 'lon': -77.2000},
    {'name': 'Trelawny', 'lat': 18.3522, 'lon': -77.6100},
    {'name': 'St. James', 'lat': 18.4762, 'lon': -77.8939},
    {'name': 'Hanover', 'lat': 18.4098, 'lon': -78.1292},
    {'name': 'Westmoreland', 'lat': 18.2380, 'lon': -78.1486},
    {'name': 'St. Elizabeth', 'lat': 18.0757, 'lon': -77.8448},
    {'name': 'Manchester', 'lat': 18.0339, 'lon': -77.5000},
    {'name': 'Clarendon', 'lat': 17.9557, 'lon': -77.2396},
    {'name': 'St. Catherine', 'lat': 18.0269, 'lon': -77.0584},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _orgController.dispose();
    _phoneController.dispose();
    _otherSkillController.dispose();
    super.dispose();
  }

  // void _saveProfile() {
  //   if (_formKey.currentState!.validate()) {
  //     _formKey.currentState!.save();
  //     // In a real app, POST profile data to the backend here.
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('✅ Profile saved!'),
  //         backgroundColor: Colors.green,
  //         behavior: SnackBarBehavior.floating,
  //       ),
  //     );
  //     widget.onComplete();
  //   }
  // }

  // In volunteer_profile_screen.dart, inside _saveProfile:

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // Collect selected skills (keys where value is true)
      final selectedSkills =
          _skills.entries.where((e) => e.value).map((e) => e.key).toList();

      // Replace 'Other' with the actual freetext value
      if (selectedSkills.contains('Other') &&
          _otherSkillController.text.trim().isNotEmpty) {
        selectedSkills.remove('Other');
        selectedSkills.add(_otherSkillController.text.trim());
      }

      // Collect selected resources
      final selectedResources =
          _resources.entries.where((e) => e.value).map((e) => e.key).toList();

      // Collect selected languages
      final selectedLanguages =
          _languages.entries.where((e) => e.value).map((e) => e.key).toList();

      // Update auth provider with full profile data
      final auth = Provider.of<AuthProvider>(context, listen: false);

      // Resolve active location coordinates
      double? activeLocLat;
      double? activeLocLon;
      if (_activeLocationName != null) {
        final parish = _jamaicaParishes.firstWhere(
          (p) => p['name'] == _activeLocationName,
          orElse: () => {},
        );
        if (parish.isNotEmpty) {
          activeLocLat = parish['lat'] as double;
          activeLocLon = parish['lon'] as double;
        }
      }

      auth.updateVolunteerProfile({
        'skills': selectedSkills,
        'resources': selectedResources,
        'name': _nameController.text,
        'phone': _phoneController.text,
        'organisation': _orgController.text,
        'vehicle': _vehicleType,
        'availability': _availability,
        'languages': selectedLanguages,
        'hasProfessionalCredentials': _hasProfessionalCredentials,
        if (_activeLocationName != null)
          'active_location_name': _activeLocationName,
        if (activeLocLat != null) 'active_location_lat': activeLocLat,
        if (activeLocLon != null) 'active_location_lon': activeLocLon,
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
                color: Colors.teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(Icons.volunteer_activism,
                            color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome, Volunteer',
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
                                  color: Colors.white70, fontSize: 13),
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
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Contact Number *',
                  hintText: '+1876...',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Phone is required'
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _orgController,
                decoration: const InputDecoration(
                  labelText: 'Organisation (optional)',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Vehicle availability (spec: none/car/truck/boat)
              _sectionHeader('Vehicle Availability', Icons.directions_car),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _vehicleOptions.map((v) {
                  final selected = _vehicleType == v['value'];
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(v['icon'] as IconData,
                            size: 18,
                            color: selected ? Colors.teal[800] : Colors.grey),
                        const SizedBox(width: 6),
                        Text(v['label'] as String),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _vehicleType = v['value'] as String),
                    selectedColor: Colors.teal.withOpacity(0.25),
                    side: BorderSide(
                      color: selected ? Colors.teal : Colors.grey[300]!,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Availability status (spec: Available, Unavailable, On Task)
              _sectionHeader('Availability Status', Icons.access_time),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'available',
                    label: Text('Available'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  ButtonSegment(
                    value: 'unavailable',
                    label: Text('Unavailable'),
                    icon: Icon(Icons.block),
                  ),
                  ButtonSegment(
                    value: 'on_task',
                    label: Text('On Task'),
                    icon: Icon(Icons.directions_run),
                  ),
                ],
                selected: {_availability},
                onSelectionChanged: (v) =>
                    setState(() => _availability = v.first),
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.teal;
                    }
                    return Colors.grey[700];
                  }),
                ),
              ),
              const SizedBox(height: 24),

              // Active Location (preferred parish for deployment)
              _sectionHeader('Active Location', Icons.location_on),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _activeLocationName,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Select your preferred parish',
                  prefixIcon: Icon(Icons.map),
                ),
                items: _jamaicaParishes
                    .map((p) => DropdownMenuItem<String>(
                          value: p['name'] as String,
                          child: Text(p['name'] as String),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _activeLocationName = val),
              ),
              const SizedBox(height: 24),

              // Skills
              _sectionHeader(
                  'Skills  ($selectedSkillCount selected)', Icons.build),
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
                    selectedColor: Colors.teal.withOpacity(0.25),
                    checkmarkColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: selected ? Colors.teal[800] : Colors.black87,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: selected ? Colors.teal : Colors.grey[300]!,
                    ),
                  );
                }).toList(),
              ),
              // Show freetext if 'Other' is selected
              if (_skills['Other'] == true) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otherSkillController,
                  decoration: const InputDecoration(
                    labelText: 'Describe your other skill',
                    hintText: 'e.g. Drone Piloting, Water Purification',
                    prefixIcon: Icon(Icons.edit),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (_skills['Other'] == true &&
                        (v == null || v.trim().isEmpty)) {
                      return 'Please describe your skill';
                    }
                    return null;
                  },
                ),
              ],
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
                  activeColor: Colors.teal,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setState(() => _resources[e.key] = val ?? false),
                );
              }),
              const SizedBox(height: 24),

              // Language capabilities (spec: language selection for Multilingual)
              _sectionHeader('Languages Spoken', Icons.language),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _languages.entries.map((e) {
                  final selected = e.value;
                  return FilterChip(
                    label: Text(e.key),
                    selected: selected,
                    onSelected: (val) =>
                        setState(() => _languages[e.key] = val),
                    selectedColor: Colors.teal.withOpacity(0.25),
                    checkmarkColor: Colors.teal,
                    labelStyle: TextStyle(
                      color: selected ? Colors.teal[800] : Colors.black87,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: selected ? Colors.teal : Colors.grey[300]!,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Professional credentials verification (spec: verification flag)
              _sectionHeader('Professional Credentials', Icons.verified_user),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('I have professional credentials'),
                subtitle: const Text(
                  'Medical, rescue, or other certifications — will be verified by a coordinator',
                  style: TextStyle(fontSize: 12),
                ),
                value: _hasProfessionalCredentials,
                activeColor: Colors.teal,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) =>
                    setState(() => _hasProfessionalCredentials = val),
              ),
              if (_hasProfessionalCredentials)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A coordinator will verify your credentials after reviewing documentation.',
                          style: TextStyle(fontSize: 12, color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                ),
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
                    backgroundColor: Colors.teal,
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
        Icon(icon, color: Colors.teal, size: 20),
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
