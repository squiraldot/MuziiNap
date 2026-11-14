import 'constant.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'credential_vault.dart';

/// Normalizes a Piped instance URL before credentials or API requests are sent.
/// Only HTTPS origins are trusted; embedded credentials and URL parameters are
/// rejected so usernames/passwords cannot be forwarded through crafted URLs.
String normalizePipedInstanceUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(
      value,
      'instanceUrl',
      'Expected an HTTPS Piped instance URL without credentials, query, or fragment',
    );
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(path: path).toString();
}

class PipedServices extends GetxService {
  final Map<String, dynamic> _headers = {};
  final _dio = Dio();
  String _insApiUrl = "";
  bool _isLoggedIn = false;

  PipedServices() {
    if (Hive.isBoxOpen('AppPrefs')) {
      final appPrefsBox = Hive.box(appPrefsBoxName);
      final piped = appPrefsBox.get('piped') ??
          {"isLoggedIn": false, "token": "", "instApiUrl": ""};
      final token = CredentialVault.instance.pipedToken;
      _isLoggedIn = piped["isLoggedIn"] == true && token != null;
      if (isLoggedIn) {
        _headers["Authorization"] = token;
        try {
          _insApiUrl = normalizePipedInstanceUrl(
            piped["instApiUrl"].toString(),
          );
        } on ArgumentError {
          _headers.clear();
          _isLoggedIn = false;
        }
      }
    }
  }

  bool get isLoggedIn => _isLoggedIn;
  String get apiUrl => _insApiUrl.isEmpty ? "https://pipedapi.kavin.rocks" : _insApiUrl;

  Future<Res> login(String insApiUrl, String userName, String password) async {
    late final String normalizedInstanceUrl;
    try {
      normalizedInstanceUrl = normalizePipedInstanceUrl(insApiUrl);
    } on ArgumentError {
      return Res(
        0,
        errorMessage: 'A valid HTTPS Piped instance URL is required.',
      );
    }
    final url = Uri.parse('$normalizedInstanceUrl/login');
    try {
      final response = await _dio.postUri(
        url,
        data: {"username": userName, "password": password},
      );
      final data = response.data;
      if (data is Map && data['error'] is String) {
        return Res(0, errorMessage: data['error'] as String);
      }
      if (data is! Map ||
          data['token'] is! String ||
          (data['token'] as String).isEmpty) {
        return Res(
          0,
          errorMessage: 'The Piped instance returned an invalid login response.',
        );
      }
      await CredentialVault.instance.savePipedToken(data['token'] as String);
      final appPrefsBox = Hive.box(appPrefsBoxName);
      await appPrefsBox.put("piped", {
        "isLoggedIn": true,
        "instApiUrl": normalizedInstanceUrl
      });
      _headers["Authorization"] = data['token'];
      _isLoggedIn = true;
      _insApiUrl = normalizedInstanceUrl;

      // Never log the returned bearer token or other authentication material.
      printINFO("Piped login successful.");
      return Res(1, response: response.data);
    } on DioException catch (e) {
      // Dio messages can include request URLs; keep credentials and URL query
      // parameters out of diagnostic logs and user-visible error details.
      printERROR(
        'Piped login request failed (${e.response?.statusCode ?? 'network error'}).',
      );
      return Res(
        0,
        errorMessage: 'Piped login request failed. Please check the instance and try again.',
      );
    }
  }

  Future<void> logout() async {
    await CredentialVault.instance.clearPipedToken();
    final appPrefsBox = Hive.box(appPrefsBoxName);
    await appPrefsBox.put(
      "piped",
      {"isLoggedIn": false, "instApiUrl": ""},
    );
    _headers.remove("Authorization");
    _isLoggedIn = false;
    _insApiUrl = "";
  }

  Future<Res> _sendRequest(String endpoint,
      {dynamic data,
      String reqType = "post",
      bool isInstanceListReq = false,
      bool isSongListReq = false}) async {
    final url = isInstanceListReq
        ? "https://piped-instances.kavin.rocks/"
        : "$apiUrl$endpoint";
    try {
      final response = reqType == "post"
          ? await _dio.post(
              url,
              data: data,
              options: Options(
                headers: _headers,
              ),
            )
          : await _dio.get(
              url,
              options: (isInstanceListReq || isSongListReq)
                  ? null
                  : Options(
                      headers: _headers,
                    ),
            );

      printINFO("Successful=> $endpoint");

      if (isInstanceListReq) {
        return Res(1,
            response: response.data
                .map((data) =>
                    PipedInstance(name: data['name'], apiUrl: data['api_url']))
                .toList());
      } else {
        if (response.data.runtimeType.toString() == "_Map<String, dynamic>" &&
            response.data.containsKey("error")) {
          return Res(0, errorMessage: response.data['error']);
        }
        return Res(1, response: response.data);
      }
    } on DioException catch (e) {
      printERROR("Error ! => ${e.response?.statusMessage ?? e.message}");
      return Res(0, errorMessage: e.response?.statusMessage ?? e.message);
    }
  }

  Future<Res> getAllInstanceList() async {
    return await _sendRequest("", isInstanceListReq: true, reqType: "get");
  }

  Future<Res> createPlaylist(String playlistName) async {
    return await _sendRequest("/user/playlists/create",
        data: {"name": playlistName});
  }

  Future<Res> getAllPlaylists() async {
    return await _sendRequest("/user/playlists", reqType: "get");
  }

  Future<Res> renamePlaylist(String plalistId, String newName) async {
    return await _sendRequest("/user/playlists/rename",
        data: {"playlistId": plalistId, "newName": newName});
  }

  Future<Res> deletePlaylist(String plalistId) async {
    return await _sendRequest("/user/playlists/delete",
        data: {"playlistId": plalistId});
  }

  Future<Res> addToPlaylist(String plalistId, List<String> videosId) async {
    return await _sendRequest("/user/playlists/add",
        data: {"playlistId": plalistId, "videoIds": videosId});
  }

  Future<Res> removeFromPlaylist(String plalistId, int index) async {
    return await _sendRequest("/user/playlists/remove",
        data: {"playlistId": plalistId, "index": index});
  }

  Future<Res> getStream(String videoId) async {
    return await _sendRequest("/streams/$videoId", reqType: "get");
  }

  Future<List<MediaItem>> getPlaylistSongs(String playlistid) async {
    final res = await _sendRequest("/playlists/$playlistid",
        reqType: "get", isSongListReq: true);
    if (res.code == 1) {
      return (res.response['relatedStreams'])
          .map((item) {
            return MediaItem(
                id: (item['url']).split("?v=")[1],
                title: item['title'],
                artist: item['uploaderName'],
                duration: Duration(seconds: item['duration']),
                artUri: Uri.tryParse(
                  item['thumbnail'],
                ),
                extras: {
                  'artists': [
                    {"name": item['uploaderName']}
                  ],
                });
          })
          .whereType<MediaItem>()
          .toList();
    }
    return [];
  }
}

class Res {
  final int code;
  final String? errorMessage;
  final dynamic response;
  Res(this.code, {this.errorMessage, this.response});
}

class PipedInstance {
  final String name;
  final String apiUrl;
  PipedInstance({required this.name, required this.apiUrl});
}
