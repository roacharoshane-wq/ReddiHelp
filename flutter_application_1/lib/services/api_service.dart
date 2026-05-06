import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/incident.dart';
import '../models/resource.dart';
import '../models/stats.dart';

class ApiService {
  // 🔁 REPLACE 192.168.0.1 WITH YOUR SERVER'S ACTUAL IP ADDRESS
  // Example: if your server runs on 192.168.100.66, use:
  // static const String baseUrl = 'http://192.168.100.66:3000/api';
  static const String baseUrl = 'http://192.168.100.66:3000/api';

  // Incidents
  static Future<List<Incident>> getIncidents() async {
    final response = await http.get(Uri.parse('$baseUrl/incidents'));
    if (response.statusCode == 200) {
      List jsonList = json.decode(response.body);
      return jsonList.map((e) => Incident.fromJson(e)).toList();
    }
    throw Exception('Failed to load incidents');
  }

  static Future<Incident> postIncident(Incident incident) async {
    print('📡 Making API call to: $baseUrl/incidents');
    print('📦 Request body: ${json.encode(incident.toJson())}');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/incidents'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(incident.toJson()),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 201) {
        return Incident.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to post incident: ${response.statusCode}');
    } catch (e) {
      print('❌ Network error: $e');
      rethrow;
    }
  }

  static Future<void> updateIncidentStatus(int id, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/incidents/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update incident');
    }
  }

  static Future<void> deleteIncident(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/incidents/$id'));
    if (response.statusCode != 204) {
      throw Exception('Failed to delete incident');
    }
  }

  // Resources
  static Future<List<Resource>> getResources() async {
    final response = await http.get(Uri.parse('$baseUrl/resources'));
    if (response.statusCode == 200) {
      List jsonList = json.decode(response.body);
      return jsonList.map((e) => Resource.fromJson(e)).toList();
    }
    throw Exception('Failed to load resources');
  }

  // Stats
  static Future<Stats> getStats() async {
    final response = await http.get(Uri.parse('$baseUrl/stats'));
    if (response.statusCode == 200) {
      return Stats.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load stats');
  }

  // Area analysis
  static Future<Map<String, dynamic>> getAreaSeverity(String areaId) async {
    final response = await http.get(Uri.parse('$baseUrl/severity/$areaId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get area severity');
  }

  static Future<Map<String, dynamic>> getAreaResourceEstimate(
    String areaId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/resources/estimate/$areaId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get area resource estimate');
  }
}
