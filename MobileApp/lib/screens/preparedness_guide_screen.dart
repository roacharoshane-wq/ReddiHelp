import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/api_service.dart';

class PreparednessGuideScreen extends StatefulWidget {
  final bool victimMode;

  const PreparednessGuideScreen({super.key, this.victimMode = false});

  @override
  State<PreparednessGuideScreen> createState() =>
      _PreparednessGuideScreenState();
}

class _PreparednessGuideScreenState extends State<PreparednessGuideScreen> {
  static const String _hiveSectionsBox = 'preparedness_sections';
  static const String _hiveChecklistBox = 'preparedness_checklists';

  List<Map<String, dynamic>> _sections = [];
  Map<String, List<bool>> _checklists = {};
  bool _loading = true;
  String? _lastUpdated;

  static const _guideTabs = [
    ('Getting Started', <String>[]),
    (
      'During a Disaster',
      <String>['evacuation', 'hurricane', 'earthquake', 'flood']
    ),
    ('SOS & Requests', <String>['shelter', 'supplies']),
    ('Responder Actions', <String>[]),
    ('Contacts & Resources', <String>['contacts']),
  ];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);

    // Load from Hive cache first
    final sectionsBox = await Hive.openBox(_hiveSectionsBox);
    final checklistBox = await Hive.openBox(_hiveChecklistBox);

    final cachedSections = sectionsBox.get('sections');
    if (cachedSections != null) {
      _sections = List<Map<String, dynamic>>.from(
        (cachedSections as List).map((e) => Map<String, dynamic>.from(e)),
      );
      _lastUpdated = sectionsBox.get('lastUpdated');
    }

    // Load checklists from local storage
    for (final key in checklistBox.keys) {
      final stored = checklistBox.get(key);
      if (stored is List) {
        _checklists[key.toString()] = stored.cast<bool>();
      }
    }

    // Try fetching from server
    try {
      final headers = await ApiService.getHeaders();
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/preparedness'),
              headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        _sections = data.cast<Map<String, dynamic>>();
        await sectionsBox.put('sections', _sections);
        await sectionsBox.put('lastUpdated', DateTime.now().toIso8601String());
        _lastUpdated = DateTime.now().toIso8601String();
      }
    } catch (e) {
      print('⚠️ [Preparedness] Server fetch failed, using cache: $e');
    }

    // If no content from server or cache, use built-in defaults
    if (_sections.isEmpty) {
      _sections = _defaultSections;
    }

    // Initialize checklists for sections that have them
    for (final section in _sections) {
      final id = section['id']?.toString() ?? section['title'];
      final items = _extractChecklistItems(section['content'] ?? '');
      if (items.isNotEmpty && !_checklists.containsKey(id)) {
        _checklists[id] = List.filled(items.length, false);
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  List<String> _extractChecklistItems(String content) {
    final lines = content.split('\n');
    return lines
        .where(
            (l) => l.trim().startsWith('- [ ]') || l.trim().startsWith('- [x]'))
        .map((l) => l.replaceAll(RegExp(r'^-\s*\[[ x]\]\s*'), '').trim())
        .toList();
  }

  Future<void> _toggleChecklistItem(
      String sectionId, int index, bool value) async {
    setState(() {
      _checklists[sectionId]![index] = value;
    });
    final box = await Hive.openBox(_hiveChecklistBox);
    await box.put(sectionId, _checklists[sectionId]);
  }

  Future<void> _exportAsPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text('ReddiHelp Disaster Preparedness Guide',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Jamaica Emergency Preparedness',
                style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
          ];

          for (final section in _sections) {
            final category =
                (section['category'] ?? 'general').toString().toUpperCase();
            final title = section['title'] ?? 'Untitled';
            final content = section['content'] ?? '';

            widgets.add(
              pw.Header(
                level: 1,
                child: pw.Text('[$category] $title',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ),
            );

            // Add content lines
            for (final line in content.split('\n')) {
              if (line.trim().isEmpty) continue;
              final cleanLine =
                  line.replaceAll(RegExp(r'^-\s*\[[ x]\]\s*'), '• ');
              widgets.add(pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child:
                    pw.Text(cleanLine, style: const pw.TextStyle(fontSize: 11)),
              ));
            }

            // Add checklist status
            final sectionId = section['id']?.toString() ?? section['title'];
            if (_checklists.containsKey(sectionId)) {
              final items = _extractChecklistItems(content);
              final checks = _checklists[sectionId]!;
              widgets.add(pw.SizedBox(height: 8));
              for (int i = 0; i < items.length && i < checks.length; i++) {
                widgets.add(pw.Text(
                  '${checks[i] ? "✅" : "☐"} ${items[i]}',
                  style: const pw.TextStyle(fontSize: 11),
                ));
              }
            }

            widgets.add(pw.SizedBox(height: 16));
          }

          return widgets;
        },
      ),
    );

    // Save PDF to a temporary file
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/preparedness_guide.pdf');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF saved to ${file.path}')),
    );
  }

  Future<void> _printPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return _sections.map((section) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 1,
                  child: pw.Text(section['title'] ?? '',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text(section['content'] ?? '',
                    style: const pw.TextStyle(fontSize: 11)),
                pw.SizedBox(height: 16),
              ],
            );
          }).toList();
        },
      ),
    );
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/preparedness_guide_print.pdf');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF saved to ${file.path}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.victimMode
        ? _guideTabs.where((tab) => tab.$1 != 'Responder Actions').toList()
        : _guideTabs;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preparedness Guide'),
          bottom: TabBar(
            isScrollable: true,
            tabs: tabs.map((tab) => Tab(text: tab.$1)).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _exportAsPdf,
              tooltip: 'Share as PDF',
            ),
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _printPdf,
              tooltip: 'Print',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadContent,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_lastUpdated != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      color: Colors.green[50],
                      child: Text(
                        'Last updated: ${_formatDate(_lastUpdated!)}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.green[700]),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: tabs.map((tab) {
                        return _buildTabContent(
                          tab.$1,
                          tab.$2,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTabContent(String tabTitle, List<String> categories) {
    final filteredSections = categories.isEmpty
        ? (tabTitle == 'Getting Started'
            ? const <Map<String, dynamic>>[]
            : tabTitle == 'Responder Actions'
                ? const <Map<String, dynamic>>[]
                : _sections)
        : _sections.where((section) {
            final category = (section['category'] ?? 'general').toString();
            return categories.contains(category);
          }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tabTitle == 'Getting Started') _buildIntroCard(),
        if (tabTitle == 'Responder Actions' && !widget.victimMode)
          _buildResponderCard(),
        if (tabTitle == 'Responder Actions' && widget.victimMode)
          const SizedBox.shrink(),
        ...filteredSections.map(_buildSection),
        if (filteredSections.isEmpty && tabTitle != 'Getting Started')
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'No guide content in this section yet.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIntroCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to use ReddiHelp',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
                'Use the tabs to move from setup guidance to disaster actions, request types, and emergency contacts.'),
            SizedBox(height: 8),
            Text(
                'Victims can access SOS and requests guidance here. Volunteers and responders also get responder-specific actions.'),
          ],
        ),
      ),
    );
  }

  Widget _buildResponderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Responder Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
                'Open the incident chat from any incident sheet, confirm location, coordinate with dispatch, and update status as you move from En Route to Resolved.'),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(Map<String, dynamic> section) {
    final category = section['category'] ?? 'general';
    final title = section['title'] ?? 'Untitled';
    final content = section['content'] ?? '';
    final parish = section['parish'];
    final sectionId = section['id']?.toString() ?? title;
    final checklistItems = _extractChecklistItems(content);
    final hasChecklist = checklistItems.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ExpansionTile(
        leading: _categoryIcon(category),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            _categoryBadge(category),
            if (parish != null) ...[
              const SizedBox(width: 8),
              Text(parish,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content text (non-checklist lines)
                ...content
                    .split('\n')
                    .where((l) =>
                        l.trim().isNotEmpty &&
                        !l.trim().startsWith('- [ ]') &&
                        !l.trim().startsWith('- [x]'))
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(line.trim(),
                            style: const TextStyle(fontSize: 14)),
                      ),
                    ),

                // Interactive checklist
                if (hasChecklist) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const Text('Checklist',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  ...List.generate(checklistItems.length, (i) {
                    final checked = _checklists[sectionId] != null &&
                        i < _checklists[sectionId]!.length &&
                        _checklists[sectionId]![i];
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (val) =>
                          _toggleChecklistItem(sectionId, i, val ?? false),
                      title: Text(
                        checklistItems[i],
                        style: TextStyle(
                          fontSize: 14,
                          decoration:
                              checked ? TextDecoration.lineThrough : null,
                          color: checked ? Colors.grey : Colors.black87,
                        ),
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                ],

                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryIcon(String category) {
    switch (category) {
      case 'shelter':
        return const Icon(Icons.night_shelter, color: Colors.blue);
      case 'evacuation':
        return const Icon(Icons.directions_run, color: Colors.red);
      case 'supplies':
        return const Icon(Icons.inventory_2, color: Colors.orange);
      case 'contacts':
        return const Icon(Icons.phone, color: Colors.green);
      case 'hurricane':
        return const Icon(Icons.storm, color: Colors.purple);
      case 'earthquake':
        return const Icon(Icons.landscape, color: Colors.brown);
      case 'flood':
        return const Icon(Icons.water, color: Colors.blue);
      default:
        return const Icon(Icons.info_outline, color: Colors.teal);
    }
  }

  Widget _categoryBadge(String category) {
    final colors = {
      'shelter': Colors.blue,
      'evacuation': Colors.red,
      'supplies': Colors.orange,
      'contacts': Colors.green,
      'hurricane': Colors.purple,
      'earthquake': Colors.brown,
      'flood': Colors.blue,
      'general': Colors.teal,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (colors[category] ?? Colors.teal).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            color: colors[category] ?? Colors.teal,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  static final List<Map<String, dynamic>> _defaultSections = [
    {
      'id': 'shelters',
      'title': 'Emergency Shelters',
      'category': 'shelter',
      'content': '''Approved emergency shelters in Jamaica by parish:

Kingston & St. Andrew:
- National Arena, Arthur Wint Drive
- Excelsior High School, Mountain View Avenue
- Kingston College, North Street

St. Catherine:
- Portmore Community College
- Greater Portmore Civic Centre
- Spanish Town Civic Centre

St. James:
- Montego Bay Civic Centre
- Catherine Hall Primary School
- Montego Bay High School

Contact your local municipal corporation for the nearest shelter.''',
    },
    {
      'id': 'evacuation',
      'title': 'Evacuation Routes',
      'category': 'evacuation',
      'content': '''Major evacuation routes for Jamaica:

Kingston Area:
- Highway 2000 → May Pen direction (inland)
- Washington Boulevard → Mandela Highway (westbound)
- Windward Road → Harbour View → Bull Bay (eastbound)

North Coast:
- A1 Highway — Montego Bay to Lucea
- A3 — Ocho Rios to Port Maria

South Coast:
- A2 — Mandeville to Black River

Rules during evacuation:
- Follow instructions from ODPEM officials
- Do NOT cross flooded roads
- Bring emergency supplies (water, documents, medication)
- Assist elderly and disabled neighbours''',
    },
    {
      'id': 'supply_checklist',
      'title': 'Emergency Supply Checklist',
      'category': 'supplies',
      'content': '''Essential supplies for 72-hour emergency kit:

Water & Food:
- [ ] 1 gallon of water per person per day (3 days)
- [ ] Non-perishable food (canned goods, crackers, dried fruit)
- [ ] Manual can opener
- [ ] Baby food / formula (if needed)

Documents & Cash:
- [ ] ID, passport, birth certificate (copies in waterproof bag)
- [ ] Insurance documents
- [ ] Cash in small denominations
- [ ] Emergency contact list

Medical:
- [ ] Prescription medications (7-day supply)
- [ ] First aid kit
- [ ] Masks, hand sanitizer

Tools & Safety:
- [ ] Flashlight with extra batteries
- [ ] Battery-powered or crank radio
- [ ] Whistle (to signal for help)
- [ ] Multi-tool or Swiss army knife
- [ ] Matches in waterproof container

Personal:
- [ ] Change of clothes and sturdy shoes
- [ ] Blankets or sleeping bags
- [ ] Personal hygiene items
- [ ] Phone charger / power bank''',
    },
    {
      'id': 'contacts',
      'title': 'Emergency Contacts',
      'category': 'contacts',
      'content': '''Important emergency numbers for Jamaica:

Police / Fire / Ambulance: 119
ODPEM (Office of Disaster Preparedness): 876-906-9674
Jamaica Fire Brigade: 110
Coastguard: 876-967-8189
Red Cross Jamaica: 876-984-7860
Jamaica Defence Force: 876-926-8121
NWA (Road Conditions): 888-NWA-HELP

Utilities:
JPS (Jamaica Public Service): 888-225-5577
NWC (Water): 888-225-5692

Mental Health Support:
National Council on Drug Abuse: 876-926-9002''',
    },
    {
      'id': 'hurricane_prep',
      'title': 'Hurricane Preparedness',
      'category': 'hurricane',
      'content': '''Hurricane season: June 1 – November 30

Before Hurricane Season:
- [ ] Know your evacuation zone
- [ ] Identify nearest shelter
- [ ] Trim trees near your home
- [ ] Clear drains and gutters
- [ ] Stock emergency supplies
- [ ] Secure important documents

When a Hurricane Watch is Issued (48 hours):
- [ ] Fill vehicle with fuel
- [ ] Withdraw cash from ATM
- [ ] Charge all devices
- [ ] Fill containers with water
- [ ] Board up windows or install shutters

When a Hurricane Warning is Issued (36 hours):
- [ ] Move to shelter if in flood zone
- [ ] Turn refrigerator to coldest setting
- [ ] Turn off propane tanks
- [ ] Unplug small appliances
- [ ] Stay indoors away from windows

After the Hurricane:
- Avoid downed power lines
- Do not drink tap water until cleared
- Check on neighbours, especially elderly
- Document damage with photos for insurance
- Listen to JIS (Jamaica Information Service) for updates''',
    },
    {
      'id': 'earthquake_prep',
      'title': 'Earthquake Safety',
      'category': 'earthquake',
      'content': '''Jamaica sits on the Enriquillo–Plantain Garden fault zone.

During an Earthquake:
- DROP, COVER, and HOLD ON
- Get under sturdy furniture
- Stay away from windows and heavy objects
- If outdoors, move to open area away from buildings
- If driving, stop safely and stay in vehicle

After an Earthquake:
- [ ] Check yourself and others for injuries
- [ ] Watch for aftershocks
- [ ] Do not enter damaged buildings
- [ ] Check gas, water, and electrical lines for damage
- [ ] Use phone only for emergencies
- [ ] Listen for official instructions

Preparation:
- [ ] Secure heavy furniture to walls
- [ ] Know how to turn off utilities
- [ ] Identify safe spots in each room
- [ ] Practice DROP, COVER, HOLD with family''',
    },
    {
      'id': 'flood_prep',
      'title': 'Flood Safety',
      'category': 'flood',
      'content': '''Flash flooding is common in Jamaica during rainy season.

If Flooding is Expected:
- [ ] Move to higher ground
- [ ] Move valuables to upper floors
- [ ] Fill bathtubs and containers with clean water
- [ ] Charge devices and power banks

During a Flood:
- NEVER walk through flowing water (6 inches can knock you down)
- NEVER drive through flooded roads
- Move to highest point if trapped
- Signal for help with bright cloth or flashlight

After Flooding:
- [ ] Avoid floodwater (may be contaminated)
- [ ] Check home for structural damage before entering
- [ ] Discard food that contacted floodwater
- [ ] Clean and disinfect everything that got wet
- [ ] Watch for mosquitoes and waterborne illness''',
    },
  ];
}
