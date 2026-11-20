import 'package:geolocator/geolocator.dart';
import 'api.dart';

class PunchOutcome {
  final String message;
  PunchOutcome(this.message);
}

const punchLabels = {'IN': 'Punched in ✔', 'OUT': 'Punched out ✔', 'LUNCH_OUT': 'Lunch break started ✔', 'LUNCH_IN': 'Welcome back from lunch ✔'};
const punchTitles = {'IN': 'Punch in', 'OUT': 'Punch out', 'LUNCH_OUT': 'Start lunch break', 'LUNCH_IN': 'Back from lunch'};

/// A verified location fix, checked on the phone for fast feedback (the server checks everything again).
class Fix {
  final Position pos;
  Fix(this.pos);
}

class PunchService {
  /// Plain GPS reading (used by the owner to set the office location).
  static Future<Position> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw ApiError(0, 'GPS_OFF', 'Turn on location (GPS) first.');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw ApiError(0, 'GPS_DENIED', 'Location permission is required. Enable it in app settings.');
    }
    return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)));
  }

  /// GPS + fake-location + office-radius checks BEFORE asking for a face scan, so people do not scan for nothing.
  static Future<Fix> locate(Map cfg) async {
    if (!await Geolocator.isLocationServiceEnabled()) throw ApiError(0, 'GPS_OFF', 'Turn on location (GPS) to punch.');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw ApiError(0, 'GPS_DENIED', 'Location permission is required. Enable it in app settings.');
    }
    final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)));
    if (pos.isMocked) throw ApiError(0, 'MOCK_LOCATION', 'Fake GPS detected. Turn off mock location apps.');
    if (pos.accuracy > (cfg['maxAccuracyM'] as num)) throw ApiError(0, 'GPS_ACCURACY', 'GPS signal is weak (±${pos.accuracy.round()} m). Move near a window and retry.');
    if (cfg['officeLat'] == null) throw ApiError(0, 'LOCATION_NOT_SET', 'Owner has not set the office location yet.');
    final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, (cfg['officeLat'] as num).toDouble(), (cfg['officeLng'] as num).toDouble());
    if (d > (cfg['radiusM'] as num)) throw ApiError(0, 'OUTSIDE_GEOFENCE', 'You are ${d.round()} m away. Go within ${cfg['radiusM']} m of the office.');
    return Fix(pos);
  }

  /// The server picks random liveness actions for this punch and remembers them (single use).
  static Future<Map> challenge(String type) async => await Api.i.get('/me/punch-challenge?type=$type');

  static Future<PunchOutcome> send({required String type, required Fix fix, required Map challenge, required List<List<double>> frames, required List<String> actions}) async {
    await Api.i.post('/punch', {
      'type': type, 'lat': fix.pos.latitude, 'lng': fix.pos.longitude, 'accuracy': fix.pos.accuracy, 'isMock': fix.pos.isMocked,
      'nonce': challenge['nonce'], 'frames': frames, 'actionsDone': actions,
    });
    return PunchOutcome(punchLabels[type] ?? 'Done ✔');
  }
}
