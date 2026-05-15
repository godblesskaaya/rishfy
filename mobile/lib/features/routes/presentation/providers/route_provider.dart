import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/location_search_remote_datasource.dart';
import '../../data/datasources/route_remote_datasource.dart';
import '../../data/models/route_models.dart';
import '../../domain/entities/route_entity.dart';

String _errorMessage(Object e, String fallback) {
  if (e is AppException) return e.message;
  // ErrorInterceptor stores the AppException in DioException.error
  if (e is DioException && e.error is AppException) {
    return (e.error! as AppException).message;
  }
  return fallback;
}

final Provider<RouteRemoteDataSource> routeDataSourceProvider =
    Provider<RouteRemoteDataSource>(
  (Ref ref) => RouteRemoteDataSource(ref.read(dioClientProvider)),
);

final Provider<LocationSearchRemoteDataSource> locationSearchDataSourceProvider =
    Provider<LocationSearchRemoteDataSource>(
  (Ref ref) => LocationSearchRemoteDataSource(ref.read(dioClientProvider)),
);

// ---- Search state ----

class RouteSearchState {
  const RouteSearchState({
    this.results = const <SearchResultDto>[],
    this.isLoading = false,
    this.error,
    this.params,
  });

  final List<SearchResultDto> results;
  final bool isLoading;
  final String? error;
  final RouteSearchParams? params;

  RouteSearchState copyWith({
    List<SearchResultDto>? results,
    bool? isLoading,
    String? error,
    RouteSearchParams? params,
  }) =>
      RouteSearchState(
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        params: params ?? this.params,
      );
}

final StateNotifierProvider<RouteSearchNotifier, RouteSearchState>
    routeSearchProvider =
    StateNotifierProvider<RouteSearchNotifier, RouteSearchState>(
  (Ref ref) => RouteSearchNotifier(ref.read(routeDataSourceProvider)),
);

class RouteSearchNotifier extends StateNotifier<RouteSearchState> {
  RouteSearchNotifier(this._ds) : super(const RouteSearchState());

  final RouteRemoteDataSource _ds;

  Future<void> search(RouteSearchParams params) async {
    state = state.copyWith(isLoading: true, error: null, params: params);
    try {
      final List<SearchResultDto> results = await _ds.searchRoutes(params);
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _errorMessage(e, 'Could not search routes. Try again.'),
      );
    }
  }

  void clear() => state = const RouteSearchState();
}

// ---- Preview route ----

enum PreviewRouteStatus { idle, loading, success, failed }

class PreviewRouteState {
  const PreviewRouteState({
    this.status = PreviewRouteStatus.idle,
    this.preview,
    this.error,
  });

  final PreviewRouteStatus status;
  final RoutePreviewDto? preview;
  final String? error;

  PreviewRouteState copyWith({
    PreviewRouteStatus? status,
    RoutePreviewDto? preview,
    String? error,
  }) =>
      PreviewRouteState(
        status: status ?? this.status,
        preview: preview ?? this.preview,
        error: error,
      );
}

final previewRouteProvider =
    StateNotifierProvider.autoDispose<PreviewRouteNotifier, PreviewRouteState>(
  (Ref ref) => PreviewRouteNotifier(ref.read(routeDataSourceProvider)),
);

class PreviewRouteNotifier extends StateNotifier<PreviewRouteState> {
  PreviewRouteNotifier(this._ds) : super(const PreviewRouteState());

  final RouteRemoteDataSource _ds;

  Future<void> preview(RoutePreviewRequest req) async {
    state = const PreviewRouteState(status: PreviewRouteStatus.loading);
    try {
      final RoutePreviewDto dto = await _ds.previewRoute(req);
      state = PreviewRouteState(
        status: PreviewRouteStatus.success,
        preview: dto,
      );
    } catch (e) {
      state = PreviewRouteState(
        status: PreviewRouteStatus.failed,
        error: _errorMessage(e, 'Could not preview the route.'),
      );
    }
  }

  void reset() => state = const PreviewRouteState();
}

// ---- Single route detail ----

final FutureProviderFamily<RouteEntity, String> routeDetailProvider =
    FutureProviderFamily<RouteEntity, String>((Ref ref, String routeId) async {
  final RouteRemoteDataSource ds = ref.read(routeDataSourceProvider);
  final RouteDto dto = await ds.getRoute(routeId);
  return dto.toDomain();
});

// ---- Driver vehicles (for route posting) ----

final myVehicleOptionsProvider =
    FutureProvider.autoDispose<List<DriverVehicleOption>>((Ref ref) async {
  final RouteRemoteDataSource ds = ref.read(routeDataSourceProvider);
  return ds.listMyVehicles();
});

// ---- Driver's own posted routes (driver home) ----

final myRoutesProvider =
    FutureProvider.autoDispose<List<RouteEntity>>((Ref ref) async {
  final RouteRemoteDataSource ds = ref.read(routeDataSourceProvider);
  final List<RouteDto> dtos = await ds.listMyRoutes();
  return dtos.map((RouteDto d) => d.toDomain()).toList();
});

// ---- Create route ----

enum CreateRouteStatus { idle, loading, success, failed }

class CreateRouteState {
  const CreateRouteState({
    this.status = CreateRouteStatus.idle,
    this.createdRoute,
    this.error,
  });

  final CreateRouteStatus status;
  final RouteEntity? createdRoute;
  final String? error;

  CreateRouteState copyWith({
    CreateRouteStatus? status,
    RouteEntity? createdRoute,
    String? error,
  }) =>
      CreateRouteState(
        status: status ?? this.status,
        createdRoute: createdRoute ?? this.createdRoute,
        error: error,
      );
}

final createRouteProvider =
    StateNotifierProvider.autoDispose<CreateRouteNotifier, CreateRouteState>(
  (Ref ref) => CreateRouteNotifier(ref.read(routeDataSourceProvider)),
);

class CreateRouteNotifier extends StateNotifier<CreateRouteState> {
  CreateRouteNotifier(this._ds) : super(const CreateRouteState());

  final RouteRemoteDataSource _ds;

  Future<void> submit(CreateRouteRequest req) async {
    state = const CreateRouteState(status: CreateRouteStatus.loading);
    try {
      final RouteDto dto = await _ds.createRoute(req);
      state = CreateRouteState(
        status: CreateRouteStatus.success,
        createdRoute: dto.toDomain(),
      );
    } catch (e) {
      state = CreateRouteState(
        status: CreateRouteStatus.failed,
        error: _errorMessage(e, 'Could not post the route.'),
      );
    }
  }

  void reset() => state = const CreateRouteState();
}

// ---- Cancel route (driver only) ----

enum CancelRouteStatus { idle, loading, success, failed }

class CancelRouteState {
  const CancelRouteState({
    this.status = CancelRouteStatus.idle,
    this.error,
  });

  final CancelRouteStatus status;
  final String? error;

  CancelRouteState copyWith({CancelRouteStatus? status, String? error}) =>
      CancelRouteState(
        status: status ?? this.status,
        error: error,
      );
}

final cancelRouteProvider =
    StateNotifierProvider.autoDispose<CancelRouteNotifier, CancelRouteState>(
  (Ref ref) => CancelRouteNotifier(ref.read(routeDataSourceProvider), ref),
);

class CancelRouteNotifier extends StateNotifier<CancelRouteState> {
  CancelRouteNotifier(this._ds, this._ref) : super(const CancelRouteState());

  final RouteRemoteDataSource _ds;
  final Ref _ref;

  Future<void> cancel(String routeId) async {
    state = state.copyWith(status: CancelRouteStatus.loading, error: null);
    try {
      await _ds.cancelRoute(routeId);
      _ref.invalidate(myRoutesProvider);
      state = state.copyWith(status: CancelRouteStatus.success);
    } catch (e) {
      state = state.copyWith(
        status: CancelRouteStatus.failed,
        error: _errorMessage(e, 'Could not cancel the route.'),
      );
    }
  }

  void reset() => state = const CancelRouteState();
}
