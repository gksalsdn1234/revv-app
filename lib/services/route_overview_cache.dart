import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/revv_route.dart';

typedef RouteOverviewDirectoryProvider = Future<Directory> Function();

class RouteOverviewCacheEntry {
  const RouteOverviewCacheEntry({
    required this.routes,
    required this.completedRegionKeys,
  });

  final List<RevvRoute> routes;
  final Set<String> completedRegionKeys;
}

class RouteOverviewCache {
  RouteOverviewCache({RouteOverviewDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'route_overview_v1.json.gz';
  static const _version = 2;
  static const ttl = Duration(days: 7);

  final RouteOverviewDirectoryProvider _directoryProvider;

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_fileName');
  }

  Future<RouteOverviewCacheEntry?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(
        utf8.decode(gzip.decode(await file.readAsBytes())),
      );
      if (decoded is! Map<String, dynamic> || decoded['version'] != _version) {
        return null;
      }
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt']?.toString() ?? '',
      );
      if (fetchedAt == null || DateTime.now().difference(fetchedAt) > ttl) {
        return null;
      }
      final routes = ((decoded['routes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RevvRoute.fromJson)
          .where((route) => route.nodes.length > 1)
          .toList(growable: false);
      final completedRegionKeys =
          ((decoded['completedRegionKeys'] as List?) ?? const [])
              .whereType<String>()
              .toSet();
      if (completedRegionKeys.isEmpty) return null;
      return RouteOverviewCacheEntry(
        routes: routes,
        completedRegionKeys: completedRegionKeys,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(RouteOverviewCacheEntry entry) async {
    if (entry.completedRegionKeys.isEmpty) return;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final bytes = gzip.encode(
        utf8.encode(
          jsonEncode({
            'version': _version,
            'fetchedAt': DateTime.now().toIso8601String(),
            'completedRegionKeys': entry.completedRegionKeys.toList()..sort(),
            'routes': entry.routes.map((route) => route.toJson()).toList(),
          }),
        ),
      );
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // Cache persistence is best effort; the network result remains usable.
    }
  }
}
