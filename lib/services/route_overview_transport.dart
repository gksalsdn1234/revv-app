import 'package:supabase/supabase.dart';

typedef RouteRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

/// Additive rollout: only an absent RPC falls back, never auth/server errors.
class RouteOverviewTransport {
  RouteOverviewTransport(this.rpc);
  final RouteRpc rpc;
  final Set<String> _unavailable = {};
  Future<dynamic> request(
    String overview,
    String legacy,
    Map<String, dynamic> params,
  ) async {
    if (!_unavailable.contains(overview)) {
      try {
        return await rpc(overview, params);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
        _unavailable.add(overview);
      }
    }
    return rpc(legacy, params);
  }
}
