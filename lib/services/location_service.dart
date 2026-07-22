import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationDataModel {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String address;
  final String country;
  final DateTime timestamp;

  LocationDataModel({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    required this.country,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'address': address,
      'country': country,
    };
  }
}

class LocationService {
  static StreamSubscription<Position>? _positionStreamSubscription;
  static LocationDataModel? _lastLocation;

  static LocationDataModel? get lastLocation => _lastLocation;

  static Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  static Future<LocationDataModel?> getCurrentLocation() async {
    try {
      bool hasPermission = await checkPermission();
      if (!hasPermission) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      String fullAddress = 'Unknown Address';
      String country = 'Unknown Country';

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          List<String> addressParts = [];
          if (place.street != null && place.street!.isNotEmpty) addressParts.add(place.street!);
          if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) addressParts.add(place.administrativeArea!);
          if (place.postalCode != null && place.postalCode!.isNotEmpty) addressParts.add(place.postalCode!);
          
          fullAddress = addressParts.isNotEmpty ? addressParts.join(', ') : (place.name ?? 'Unknown Address');
          country = place.country ?? 'Unknown Country';
        }
      } catch (e) {
        fullAddress = 'Lat: ${position.latitude.toStringAsFixed(4)}, Long: ${position.longitude.toStringAsFixed(4)}';
      }

      _lastLocation = LocationDataModel(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: fullAddress,
        country: country,
        timestamp: DateTime.now(),
      );

      return _lastLocation;
    } catch (e) {
      return null;
    }
  }

  static void startLiveLocationStream(Function(LocationDataModel) onLocationUpdate) {
    stopBackgroundLocationUpdates();
    
    // High-frequency in-memory stream for live UI monitoring (no disk storage)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0, // Updates on any small position change
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
      String fullAddress = 'Unknown Address';
      String country = 'Unknown Country';

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          fullAddress = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}'.replaceAll(RegExp(r'^,\s*'), '');
          country = place.country ?? 'Unknown Country';
        }
      } catch (_) {
        fullAddress = 'Lat: ${position.latitude.toStringAsFixed(5)}, Long: ${position.longitude.toStringAsFixed(5)}';
      }

      _lastLocation = LocationDataModel(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: fullAddress,
        country: country,
        timestamp: DateTime.now(),
      );

      onLocationUpdate(_lastLocation!);
    });
  }

  static void stopBackgroundLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }
}
