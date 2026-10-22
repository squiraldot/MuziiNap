import 'dart:io';
import '../utils/helper.dart';

class LocalProxy {
  static HttpServer? _server;
  static Future<void>? _startFuture;
  static final Map<String, _ProxyTask> _urlMap = {};

  static Future<void> start() {
    if (_server != null) return Future.value();
    final existing = _startFuture;
    if (existing != null) return existing;

    final future = _bindAndServe();
    _startFuture = future;
    return future;
  }

  static Future<void> _bindAndServe() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      printINFO("Local proxy started on port ${_server!.port}");
      _server!.listen((HttpRequest request) async {
        final id = request.uri.pathSegments.isNotEmpty ? request.uri.pathSegments.first : '';
        if (id.endsWith('.mp3')) {
          final realId = id.substring(0, id.length - 4);
          final task = _urlMap[realId];
          if (task == null) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.close();
            return;
          }

          final client = HttpClient();
          try {
            final clientReq = await client.getUrl(Uri.parse(task.url));
            if (task.headers != null) {
              task.headers!.forEach((key, value) {
                clientReq.headers.set(key, value);
              });
            }

            // Allow seeking by passing Range header if present
            if (request.headers.value('range') != null) {
              clientReq.headers.set('range', request.headers.value('range')!);
            }

            final clientRes = await clientReq.close();

            printINFO("LocalProxy: YouTube returned status ${clientRes.statusCode} for ${task.url.substring(0, 50)}...");

            request.response.statusCode = clientRes.statusCode;
            clientRes.headers.forEach((name, values) {
              for (final value in values) {
                request.response.headers.add(name, value);
              }
            });

            await clientRes.pipe(request.response);
          } catch (e) {
            printINFO("LocalProxy Error: $e");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.close();
          } finally {
            client.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });
    } catch (e) {
      printINFO("Failed to start local proxy: $e");
    } finally {
      _startFuture = null;
    }
  }

  static Future<String> addUrlAsync(
    String url, {
    Map<String, String>? headers,
  }) async {
    await start();
    final server = _server;
    if (server == null) {
      throw StateError('Local audio proxy failed to start');
    }

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${_urlMap.length}';
    _urlMap[id] = _ProxyTask(url, headers);

    // Keep the in-memory map bounded; old stream URLs are already expired
    // shortly after use and must not grow for long-running sessions.
    if (_urlMap.length > 20) {
      final keys = _urlMap.keys.toList();
      for (final key in keys.take(_urlMap.length - 20)) {
        _urlMap.remove(key);
      }
    }

    return 'http://127.0.0.1:${server.port}/$id.mp3';
  }
}

class _ProxyTask {
  final String url;
  final Map<String, String>? headers;

  _ProxyTask(this.url, this.headers);
}
