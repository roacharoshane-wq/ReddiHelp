import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance =
      LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _pollingTimer;
  bool _isTracking = false;
  bool _hasActiveTask = false;
  Position? _lastPosition;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;

  // Polls every 30s when task active, every 5min when idle (per spec #3)
  Future<void> startTracking({bool hasActiveTask = false}) async {
    if (_isTracking) return;

    _hasActiveTask = hasActiveTask;
    _isTracking = true;

    // Request 'always on' permission for volunteers/responders per spec
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // Start polling timer
    _startPolling();

    // Also listen to significant location changes for battery optimization
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // only fire when moved 50m+ (battery optimization)
      ),
    ).listen(
      (position) {
        _lastPosition = position;
        _sendLocationUpdate(position);
      },
      onError: (e) {
        print('⚠️ [LocationTracking] Stream error: $e');
      },
    );

    print(
        '📍 [LocationTracking] Started tracking (activeTask=$_hasActiveTask)');
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // 30s when task active, 5min when idle (per spec #3)
    final interval = _hasActiveTask
        ? const Duration(seconds: 30)
        : const Duration(minutes: 5);

    _pollingTimer = Timer.periodic(interval, (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        _lastPosition = pos;
        _sendLocationUpdate(pos);
      } catch (e) {
        print('⚠️ [LocationTracking] Poll failed: $e');
      }
    });
  }

  void setActiveTask(bool hasActiveTask) {
    if (_hasActiveTask == hasActiveTask) return;
    _hasActiveTask = hasActiveTask;
    if (_isTracking) {
      _startPolling(); // restart with new interval
    }
  }

  Future<void> _sendLocationUpdate(Position position) async {
    try {
      print(
          '📍 [LocationTracking] Sending location: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
      await ApiService.updateVolunteerLocation(
        position.latitude,
        position.longitude,
        accuracy: position.accuracy,
      );
    } catch (e) {
      print('⚠️ [LocationTracking] Failed to send location: $e');
    }
  }

  void stopTracking() {
    _pollingTimer?.cancel();
    _positionSubscription?.cancel();
    _isTracking = false;
    _lastPosition = null;
    print('📍 [LocationTracking] Stopped tracking');
  }

  static Future<bool> isGpsAccurate() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return pos.accuracy <= 50;
    } catch (_) {
      return false;
    }
  }
}
