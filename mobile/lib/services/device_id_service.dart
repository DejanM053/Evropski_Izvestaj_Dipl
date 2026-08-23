import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists a locally generated `deviceId` (uuid v4) on first launch, so the
/// app can scope its own report history without user accounts (§6 client
/// rules — "store a locally generated deviceId (uuid, persisted) to scope
/// history"). Not wired into any request yet: `GET /api/reports?deviceId=`
/// is a no-op until the backend schema gains the field (see PROGRESS.md
/// "Known issues"); this service just makes sure a stable id exists and is
/// ready for that once it lands.
class DeviceIdService {
  DeviceIdService._();

  static const _prefsKey = 'device_id';
  static String? _cached;

  static Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }
}
