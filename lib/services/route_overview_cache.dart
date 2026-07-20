import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/revv_route.dart';

typedef RouteOverviewDirectoryProvider = Future<Directory> Function();

class RouteOverviewCacheEntry {
  const RouteOverviewCacheEntry({
    required this.routes,
    required this.completedRegionKeys,
    this.regionHadRoutes = const {},
    this.catalogEpoch,
  });

  final List<RevvRoute> routes;
  final Set<String> completedRegionKeys;
  final Map<String, bool> regionHadRoutes;
  final int? catalogEpoch;
}

class RouteOverviewCache {
  RouteOverviewCache({RouteOverviewDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'route_overview_v1.json.gz';
  static const _version = 6;
  static const maxRoutes = 650;
  static const maxCompressedBytes = 2 * 1024 * 1024;
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
      final rawPresence = decoded['regionHadRoutes'];
      if (rawPresence is! Map) return null;
      final regionHadRoutes = <String, bool>{};
      for (final entry in rawPresence.entries) {
        if (entry.key is String && entry.value is bool) {
          regionHadRoutes[entry.key as String] = entry.value as bool;
        }
      }
      if (!completedRegionKeys.every(regionHadRoutes.containsKey)) return null;
      return RouteOverviewCacheEntry(
        routes: routes,
        completedRegionKeys: completedRegionKeys,
        regionHadRoutes: regionHadRoutes,
        catalogEpoch: (decoded['catalogEpoch'] as num?)?.toInt(),
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
      final boundedRoutes = entry.routes
          .take(maxRoutes)
          .toList(growable: false);
      List<int> encode(int routeCount) => gzip.encode(
        utf8.encode(
          jsonEncode({
            'version': _version,
            'fetchedAt': DateTime.now().toIso8601String(),
            if (entry.catalogEpoch != null) 'catalogEpoch': entry.catalogEpoch,
            'completedRegionKeys': entry.completedRegionKeys.toList()..sort(),
            'regionHadRoutes': {
              for (final key in entry.completedRegionKeys.toList()..sort())
                key: entry.regionHadRoutes[key] ?? false,
            },
            'routes': boundedRoutes
                .take(routeCount)
                .map((route) => route.toJson())
                .toList(),
          }),
        ),
      );
      var low = 0;
      var high = boundedRoutes.length;
      var bytes = encode(high);
      if (bytes.length > maxCompressedBytes) {
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          final candidate = encode(mid);
          if (candidate.length <= maxCompressedBytes) {
            low = mid;
            bytes = candidate;
          } else {
            high = mid - 1;
          }
        }
        if (low == 0) return;
        bytes = encode(low);
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // Cache persistence is best effort; the network result remains usable.
    }
  }
}
