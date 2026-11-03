import 'composite_data_service.dart';
import 'data_service.dart';
import 'local_data_service.dart';
import 'remote_data_service.dart';
import 'service_result.dart';

/// Opt-in result boundary for pages, without changing DataService implementers.
/// Generic callbacks run on adapters: ONE remote-capable data operation, not
/// auth or a multi-step workflow. Local preferences use the named methods.
class ServiceOperations {
  const ServiceOperations(this.service);
  final DataService service;

  ServiceSource get _preferenceSource =>
      service is CompositeDataService ? ServiceSource.local : _source;

  Future<ServiceResult<String?>> getFavoriteDevice() => _capture(
    service.getFavoriteDevice,
    write: false,
    source: _preferenceSource,
  );

  Future<ServiceResult<void>> setFavoriteDevice(String deviceId) => _capture(
    () => service.setFavoriteDevice(deviceId),
    write: true,
    source: _preferenceSource,
  );

  ServiceSource get _source => service is RemoteDataService
      ? ServiceSource.remote
      : service is LocalDataService
      ? ServiceSource.local
      : ServiceSource.unknown;

  Future<ServiceResult<T>> read<T>(Future<T> Function(DataService) read) {
    final current = service;
    if (current is CompositeDataService) return current.readResult(read);
    return _capture(() => read(current), write: false);
  }

  Future<ServiceResult<void>> write(Future<void> Function(DataService) write) {
    final current = service;
    if (current is CompositeDataService) return current.writeResult(write);
    return _capture(() => write(current), write: true);
  }

  Future<ServiceResult<T>> _capture<T>(
    Future<T> Function() operation, {
    required bool write,
    ServiceSource? source,
  }) async {
    try {
      return ServiceSuccess(await operation(), source: source ?? _source);
    } catch (error, stack) {
      return ServiceFailure(
        serviceProblem(error, stack, source ?? _source, write: write),
      );
    }
  }

  /// [copy] must be a deep copy for mutable drafts. The writer receives another
  /// copy on EACH adapter invocation, so mutation cannot corrupt the retained
  /// draft or the payload subsequently sent to the local cache/fallback.
  /// Copy/validation failures before dispatch leave the caller's draft intact.
  Future<DraftSaveResult<D>> saveDraft<D>({
    required D draft,
    required D Function(D) copy,
    required Future<void> Function(DataService, D) save,
  }) async {
    final retained = copy(draft);
    final result = await write((service) => save(service, copy(retained)));
    return DraftSaveResult(draft: retained, result: result);
  }
}

class DraftSaveResult<D> {
  const DraftSaveResult({required this.draft, required this.result});
  final D draft;
  final ServiceResult<void> result;
}
