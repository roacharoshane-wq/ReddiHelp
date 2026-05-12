import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../utils/accessibility_helper.dart';
import '../services/api_service.dart';
import '../models/incident.dart';
import 'package:geolocator/geolocator.dart';

class AccessibilityScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const AccessibilityScreen({super.key, required this.onContinue});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  bool _accessibilityEnabled = false;
  bool _voiceSosEnabled = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  String _voiceStatus = '';

  @override
  void initState() {
    super.initState();
    _accessibilityEnabled = AccessibilityHelper().enabled;
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) =>
          setState(() => _voiceStatus = 'Speech error: ${error.errorMsg}'),
    );
    setState(() {});
  }

  void _toggleAccessibility(bool value) {
    setState(() => _accessibilityEnabled = value);
    AccessibilityHelper().setEnabled(value);
  }

  void _toggleVoiceSos(bool value) {
    setState(() => _voiceSosEnabled = value);
    if (value && _speechAvailable) {
      _startListening();
    } else {
      _stopListening();
    }
  }

  void _startListening() {
    if (!_speechAvailable) return;
    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.contains('emergency') ||
            text.contains('help') ||
            text.contains('sos')) {
          _stopListening();
          _triggerVoiceSos();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
    );
    setState(() {
      _listening = true;
      _voiceStatus = 'Listening for "Emergency" or "Help"...';
    });
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _listening = false;
      _voiceStatus = '';
    });
  }

  Future<void> _triggerVoiceSos() async {
    setState(() => _voiceStatus = 'Voice SOS triggered! Sending emergency...');

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final incident = Incident(
        id: 0,
        type: 'medical',
        lat: pos.latitude,
        lon: pos.longitude,
        severity: 5,
        description: 'Voice-activated SOS emergency. Immediate help needed.',
        disasterType: 'other',
        areaId: 'unknown',
        status: 'active',
        timestamp: DateTime.now(),
        lastUpdated: DateTime.now(),
        peopleAffected: 1,
      );

      await ApiService.postIncident(incident);

      if (mounted) {
        setState(() => _voiceStatus = 'Emergency SOS sent!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice SOS sent! Help is on the way.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      setState(() => _voiceStatus = 'Failed to send SOS: $e');
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAccessible = _accessibilityEnabled;
    final fontSize = isAccessible ? 20.0 : 16.0;
    final headerSize = isAccessible ? 28.0 : 22.0;
    final btnHeight = isAccessible ? 64.0 : 48.0;

    return Scaffold(
      backgroundColor: isAccessible ? Colors.white : Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Logo
              Semantics(
                label: 'ReddiHelp logo',
                child: Icon(
                  Icons.health_and_safety,
                  size: isAccessible ? 80 : 60,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 16),

              Semantics(
                header: true,
                child: Text(
                  'ReddiHelp',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: headerSize + 4,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                child: Text(
                  'Jamaica Disaster Response Platform',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: fontSize, color: Colors.grey[700]),
                ),
              ),

              const SizedBox(height: 40),

              // Accessibility toggle
              Semantics(
                label:
                    'Enable accessibility mode for larger text and high contrast',
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isAccessible ? Colors.yellow[50] : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isAccessible ? Colors.orange : Colors.grey[300]!,
                      width: isAccessible ? 3 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.accessibility_new,
                          size: isAccessible ? 40 : 32,
                          color: Colors.blue[700]),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Accessibility Mode',
                              style: TextStyle(
                                fontSize: fontSize + 2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Large text, high contrast, voice SOS',
                              style: TextStyle(
                                  fontSize: fontSize - 2,
                                  color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _accessibilityEnabled,
                        onChanged: _toggleAccessibility,
                        activeColor: Colors.blue[700],
                      ),
                    ],
                  ),
                ),
              ),

              if (_accessibilityEnabled) ...[
                const SizedBox(height: 16),

                // Voice SOS toggle
                Semantics(
                  label:
                      'Enable voice-activated SOS. Say Emergency or Help to send an alert.',
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!, width: 2),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.mic, size: 40, color: Colors.red[700]),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Voice SOS',
                                    style: TextStyle(
                                        fontSize: fontSize + 2,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _speechAvailable
                                        ? 'Say "Emergency" or "Help" to trigger SOS'
                                        : 'Speech recognition not available',
                                    style: TextStyle(
                                        fontSize: fontSize - 2,
                                        color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _voiceSosEnabled,
                              onChanged:
                                  _speechAvailable ? _toggleVoiceSos : null,
                              activeColor: Colors.red[700],
                            ),
                          ],
                        ),
                        if (_voiceStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (_listening)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _voiceStatus,
                                  style: TextStyle(
                                      fontSize: fontSize - 2,
                                      color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Continue button
              Semantics(
                button: true,
                label: 'Continue to login',
                child: SizedBox(
                  height: btnHeight,
                  child: ElevatedButton(
                    onPressed: widget.onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                          fontSize: fontSize, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Continue to Login'),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
