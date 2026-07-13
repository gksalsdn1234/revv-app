import 'exploration_service.dart';
import 'supabase_service.dart';

class SupabaseExplorationCloudClient implements ExplorationCloudClient {
  SupabaseExplorationCloudClient({SupabaseService? service})
    : _service = service ?? SupabaseService();

  final SupabaseService _service;

  @override
  bool get isReady => _service.isReady;

  @override
  String? get uid => _service.uid;

  @override
  Future<bool> deleteExploredCells() => _service.deleteExploredCells();

  @override
  Future<Map<String, DateTime>> fetchExploredCells() =>
      _service.fetchExploredCells();

  @override
  Future<bool> upsertExploredCells(Map<String, DateTime> cells) =>
      _service.upsertExploredCells(cells);
}
