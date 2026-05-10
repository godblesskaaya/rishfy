import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routes/data/models/route_models.dart';
import '../../data/datasources/profile_remote_datasource.dart';

final myVehiclesProvider =
    FutureProvider.autoDispose<List<DriverVehicleOption>>((Ref ref) async {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.listMyVehicles();
});
