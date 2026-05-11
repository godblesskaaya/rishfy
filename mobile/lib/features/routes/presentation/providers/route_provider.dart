import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/location_search_remote_datasource.dart';
import '../../data/datasources/route_remote_datasource.dart';
import '../../data/models/route_models.dart';
import '../../domain/entities/route_entity.dart';

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
      state = state.copyWith(isLoading: false, error: e.toString());
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

final StateNotifierProvider<PreviewRouteNotifier, PreviewRouteState>
    previewRouteProvider = StateNotifierProvider.autoDispose<PreviewRouteNotifier,
        PreviewRouteState>(
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
        error: e.toString(),
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
        error: e.toString(),
      );
    }
  }

  void reset() => state = const CreateRouteState();
}
