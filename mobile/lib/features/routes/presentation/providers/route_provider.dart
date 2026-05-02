import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/route_remote_datasource.dart';
import '../../data/models/route_models.dart';
import '../../domain/entities/route_entity.dart';

final Provider<RouteRemoteDataSource> routeDataSourceProvider =
    Provider<RouteRemoteDataSource>(
  (Ref ref) => RouteRemoteDataSource(ref.read(dioClientProvider)),
);

// ---- Search state ----

class RouteSearchState {
  const RouteSearchState({
    this.results = const <RouteEntity>[],
    this.isLoading = false,
    this.error,
    this.params,
  });

  final List<RouteEntity> results;
  final bool isLoading;
  final String? error;
  final RouteSearchParams? params;

  RouteSearchState copyWith({
    List<RouteEntity>? results,
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
      final List<RouteDto> dtos = await _ds.searchRoutes(params);
      state = state.copyWith(
        isLoading: false,
        results: dtos.map((RouteDto d) => d.toDomain()).toList(),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() => state = const RouteSearchState();
}

// ---- Single route detail ----

final FutureProviderFamily<RouteEntity, String> routeDetailProvider =
    FutureProviderFamily<RouteEntity, String>((Ref ref, String routeId) async {
  final RouteRemoteDataSource ds = ref.read(routeDataSourceProvider);
  final RouteDto dto = await ds.getRoute(routeId);
  return dto.toDomain();
});
