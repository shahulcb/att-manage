import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final int status;
  final String code, message;
  ApiError(this.status, this.code, this.message);
  @override
  String toString() => message;
}

class NetworkError implements Exception {
  @override
  String toString() => 'Cannot reach the server. Check your internet connection.';
}

class Api {
  Api._();
  static final Api i = Api._();
  // Set at build time:  flutter run --dart-define=API_BASE=https://your-server/api
  static const base0 = String.fromEnvironment('API_BASE', defaultValue: 'http://10.242.104.33:4000/api');

  late SharedPreferences prefs;
  /// false after a network failure, true after any successful response (drives the "no internet" banner)
  final ValueNotifier<bool> online = ValueNotifier(true);
  /// called when the server says the session is no longer valid
  void Function(String message)? onUnauthorized;
  final String base = base0;
  String? token;
  String? role;
  String? name;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    role = prefs.getString('role');
    name = prefs.getString('name');
  }

  Future<void> saveSession(Map r) async {
    token = r['token']; role = r['role']; name = r['name'];
    await prefs.setString('token', token!);
    await prefs.setString('role', role!);
    await prefs.setString('name', name ?? '');
  }

  Future<void> logout() async {
    token = null; role = null;
    await prefs.remove('token');
    await prefs.remove('role');
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$base$path');
    final headers = {'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token'};
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    } on SocketException { online.value = false; throw NetworkError(); }
    on TimeoutException { online.value = false; throw NetworkError(); }
    on http.ClientException { online.value = false; throw NetworkError(); }
    online.value = true;
    final isJson = (r.headers['content-type'] ?? '').contains('json');
    final data = isJson && r.body.isNotEmpty ? jsonDecode(r.body) : r.body;
    if (r.statusCode >= 400) {
      if (r.statusCode == 401 && token != null) { await logout(); onUnauthorized?.call('Your session expired. Please sign in again.'); }
      final m = data is Map ? data : {};
      throw ApiError(r.statusCode, '${m['code'] ?? 'ERROR'}', '${m['message'] ?? 'Request failed (${r.statusCode})'}');
    }
    return data;
  }

  Future<dynamic> get(String p) => _send('GET', p);
  Future<dynamic> post(String p, [Object? b]) => _send('POST', p, b ?? {});
  Future<dynamic> put(String p, Object b) => _send('PUT', p, b);
  Future<String> getText(String p) async => (await _send('GET', p)).toString();
}
