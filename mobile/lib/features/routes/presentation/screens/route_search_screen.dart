import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/env.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../data/datasources/location_search_remote_datasource.dart';
import '../../data/models/route_models.dart';
import '../providers/route_provider.dart';

class RouteSearchScreen extends ConsumerStatefulWidget {
  const RouteSearchScreen({super.key});

  @override
  ConsumerState<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends ConsumerState<RouteSearchScreen> {
  static const LatLng _tanzaniaCenter = LatLng(-6.3690, 34.8888);

  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _destFocusNode = FocusNode();

  GoogleMapController? _mapController;
  Timer? _originDebounce;
  Timer? _destDebounce;

  DateTime _departureDate = DateTime.now();
  TimeOfDay _departureTime = TimeOfDay.now();
  int _seatCount = 1;
  int _timeFlexibilityMinutes = 30;
  int _maxWalkingDistanceMeters = 1000;
  String _mapTargetField = 'origin';
  bool _loadingCurrentLocation = false;
  String? _locationHint;
  bool _showAdvanced = false;

  LocationSearchResult? _originSelection;
  LocationSearchResult? _destinationSelection;
  LocationSearchResult? _currentLocation;

  bool _loadingOriginSuggestions = false;
  bool _loadingDestinationSuggestions = false;
  List<LocationSearchResult> _originSuggestions = const <LocationSearchResult>[];
  List<LocationSearchResult> _destinationSuggestions =
      const <LocationSearchResult>[];

  @override
  void initState() {
    super.initState();
    _departureDate = DateTime.now();
    _departureTime = TimeOfDay.now();
    _originFocusNode.addListener(_handleFocusChange);
    _destFocusNode.addListener(_handleFocusChange);
    unawaited(_loadCurrentLocation());
  }

  @override
  void dispose() {
    _originDebounce?.cancel();
    _destDebounce?.cancel();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _originFocusNode.dispose();
    _destFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_originFocusNode.hasFocus && _mapTargetField != 'origin') {
      setState(() => _mapTargetField = 'origin');
    } else if (_destFocusNode.hasFocus && _mapTargetField != 'destination') {
      setState(() => _mapTargetField = 'destination');
    }
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loadingCurrentLocation = true;
      _locationHint = null;
    });

    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      LocationPermission resolvedPermission = permission;
      if (permission == LocationPermission.denied) {
        resolvedPermission = await Geolocator.requestPermission();
      }
      if (resolvedPermission == LocationPermission.denied ||
          resolvedPermission == LocationPermission.deniedForever) {
        throw const LocationPermissionException(
          message: 'Location permission is required to use current position.',
        );
      }

      final Position position = await Geolocator.getCurrentPosition();
      final LocationSearchResult fallback = LocationSearchResult(
        label:
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final LocationSearchResult? resolved = await ref
          .read(locationSearchDataSourceProvider)
          .reverseGeocode(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _currentLocation = resolved ?? fallback;
        _loadingCurrentLocation = false;
      });
      await _animateTo(
        LatLng(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCurrentLocation = false;
        _locationHint = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCurrentLocation = false;
        _locationHint = 'Unable to read current location right now.';
      });
    }
  }

  Future<void> _animateTo(
    LatLng target, {
    double zoom = 13,
  }) async {
    final GoogleMapController? controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  Future<void> _applyMapSelection(LatLng point) async {
    setState(() => _locationHint = 'Resolving tapped map location...');
    try {
      final LocationSearchResult? resolved = await ref
          .read(locationSearchDataSourceProvider)
          .reverseGeocode(point.latitude, point.longitude);
      if (!mounted) return;
      final LocationSearchResult selection = resolved ??
          LocationSearchResult(
            label: '${point.latitude.toStringAsFixed(6)}, '
                '${point.longitude.toStringAsFixed(6)}',
            latitude: point.latitude,
            longitude: point.longitude,
          );
      _applySelection(_mapTargetField, selection);
      setState(() => _locationHint = null);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _locationHint =
            'Could not reverse geocode that point. You can still search manually.',
      );
    }
  }

  void _applySelection(String field, LocationSearchResult selection) {
    setState(() {
      if (field == 'origin') {
        _originSelection = selection;
        _originCtrl.text = selection.label;
        _originSuggestions = const <LocationSearchResult>[];
      } else {
        _destinationSelection = selection;
        _destCtrl.text = selection.label;
        _destinationSuggestions = const <LocationSearchResult>[];
      }
    });
    unawaited(_animateTo(LatLng(selection.latitude, selection.longitude)));
  }

  void _onOriginChanged(String value) {
    if (_originSelection?.label != value.trim()) {
      setState(() => _originSelection = null);
    }
    _originDebounce?.cancel();
    _originDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchSuggestions('origin', value),
    );
  }

  void _onDestinationChanged(String value) {
    if (_destinationSelection?.label != value.trim()) {
      setState(() => _destinationSelection = null);
    }
    _destDebounce?.cancel();
    _destDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchSuggestions('destination', value),
    );
  }

  Future<void> _fetchSuggestions(String field, String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < 3) {
      if (!mounted) return;
      setState(() {
        if (field == 'origin') {
          _originSuggestions = const <LocationSearchResult>[];
          _loadingOriginSuggestions = false;
        } else {
          _destinationSuggestions = const <LocationSearchResult>[];
          _loadingDestinationSuggestions = false;
        }
      });
      return;
    }

    setState(() {
      if (field == 'origin') {
        _loadingOriginSuggestions = true;
      } else {
        _loadingDestinationSuggestions = true;
      }
    });

    try {
      final List<LocationSearchResult> results = await ref
          .read(locationSearchDataSourceProvider)
          .geocodeAddress(trimmed, proximity: _currentLocation);
      if (!mounted) return;
      setState(() {
        if (field == 'origin') {
          _originSuggestions = results;
          _loadingOriginSuggestions = false;
        } else {
          _destinationSuggestions = results;
          _loadingDestinationSuggestions = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (field == 'origin') {
          _originSuggestions = const <LocationSearchResult>[];
          _loadingOriginSuggestions = false;
        } else {
          _destinationSuggestions = const <LocationSearchResult>[];
          _loadingDestinationSuggestions = false;
        }
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_currentLocation == null) {
      await _loadCurrentLocation();
    }
    if (_currentLocation == null) return;
    _applySelection(_mapTargetField, _currentLocation!);
  }

  DateTime get _desiredDepartureDateTime => DateTime(
        _departureDate.year,
        _departureDate.month,
        _departureDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );

  Future<void> _pickDepartureTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _departureTime,
    );
    if (picked != null) setState(() => _departureTime = picked);
  }

  Future<void> _search() async {
    if (_originSelection == null || _destinationSelection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select pickup and dropoff from the suggestions'),
        ),
      );
      return;
    }

    await ref.read(routeSearchProvider.notifier).search(
          RouteSearchParams(
            pickupLat: _originSelection!.latitude,
            pickupLng: _originSelection!.longitude,
            dropoffLat: _destinationSelection!.latitude,
            dropoffLng: _destinationSelection!.longitude,
            desiredDepartureTime: _desiredDepartureDateTime,
            timeFlexibilityMinutes: _timeFlexibilityMinutes,
            maxWalkingDistanceMeters: _maxWalkingDistanceMeters,
            seatsNeeded: _seatCount,
            pickupLabel: _originSelection!.label,
            dropoffLabel: _destinationSelection!.label,
          ),
        );
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = <Marker>{};

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: LatLng(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
          ),
          infoWindow: const InfoWindow(title: 'Current location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (_originSelection != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(
            _originSelection!.latitude,
            _originSelection!.longitude,
          ),
          infoWindow: InfoWindow(title: _originSelection!.label),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    if (_destinationSelection != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(
            _destinationSelection!.latitude,
            _destinationSelection!.longitude,
          ),
          infoWindow: InfoWindow(title: _destinationSelection!.label),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    return markers;
  }

  List<LocationSearchResult> get _activeSuggestions {
    if (_originFocusNode.hasFocus) {
      return _originSuggestions;
    }
    if (_destFocusNode.hasFocus) {
      return _destinationSuggestions;
    }
    return const <LocationSearchResult>[];
  }

  bool get _activeSuggestionsLoading {
    if (_originFocusNode.hasFocus) {
      return _loadingOriginSuggestions;
    }
    if (_destFocusNode.hasFocus) {
      return _loadingDestinationSuggestions;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final RouteSearchState searchState = ref.watch(routeSearchProvider);
    final bool mapsConfigured = Env.googleMapsApiKey.trim().isNotEmpty;
    final List<SearchResultDto> results = searchState.results;

    return Scaffold(
      appBar: AppBar(title: const Text('Search routes')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _MapSelectionCard(
                      markers: _buildMarkers(),
                      currentLocation: _currentLocation,
                      mapsConfigured: mapsConfigured,
                      loadingCurrentLocation: _loadingCurrentLocation,
                      mapTargetField: _mapTargetField,
                      onMapCreated: (GoogleMapController controller) {
                        _mapController = controller;
                      },
                      onTapMap: _applyMapSelection,
                      onSelectField: (String field) {
                        setState(() => _mapTargetField = field);
                      },
                      onUseCurrentLocation: _useCurrentLocation,
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                    if (_locationHint != null) ...<Widget>[
                      _InfoBanner(message: _locationHint!),
                      const SizedBox(height: AppConstants.spaceMd),
                    ],
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spaceMd),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLg),
                      ),
                      child: Column(
                        children: <Widget>[
                          TextField(
                            controller: _originCtrl,
                            focusNode: _originFocusNode,
                            textInputAction: TextInputAction.next,
                            onTap: () => setState(() => _mapTargetField = 'origin'),
                            onChanged: _onOriginChanged,
                            decoration: InputDecoration(
                              labelText: 'From',
                              hintText: 'Pick on map or search address',
                              prefixIcon: const Icon(Icons.trip_origin),
                              suffixIcon: _originSelection != null
                                  ? const Icon(Icons.check_circle_outline)
                                  : null,
                              border: InputBorder.none,
                            ),
                          ),
                          const Divider(height: 1),
                          TextField(
                            controller: _destCtrl,
                            focusNode: _destFocusNode,
                            textInputAction: TextInputAction.done,
                            onTap:
                                () => setState(() => _mapTargetField = 'destination'),
                            onChanged: _onDestinationChanged,
                            onSubmitted: (_) => _search(),
                            decoration: InputDecoration(
                              labelText: 'To',
                              hintText: 'Pick on map or search address',
                              prefixIcon: const Icon(Icons.location_on_outlined),
                              suffixIcon: _destinationSelection != null
                                  ? const Icon(Icons.check_circle_outline)
                                  : null,
                              border: InputBorder.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_activeSuggestionsLoading ||
                        _activeSuggestions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppConstants.spaceSm),
                      _SuggestionPanel(
                        loading: _activeSuggestionsLoading,
                        suggestions: _activeSuggestions,
                        onSelect: (LocationSearchResult result) {
                          _applySelection(
                            _originFocusNode.hasFocus ? 'origin' : 'destination',
                            result,
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: AppConstants.spaceMd),
                    // ── Date + time row ──────────────────────────────────
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusLg),
                            onTap: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: _departureDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 60)),
                              );
                              if (picked != null) {
                                setState(() => _departureDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.spaceMd,
                                vertical: AppConstants.spaceSm + 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLg),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.calendar_today,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      DateFormat('d MMM').format(_departureDate),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusLg),
                            onTap: _pickDepartureTime,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.spaceMd,
                                vertical: AppConstants.spaceSm + 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLg),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.schedule,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_departureTime.format(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                    // ── Seats row ────────────────────────────────────────
                    Row(
                      children: <Widget>[
                        const Text('Seats'),
                        const Spacer(),
                        IconButton(
                          onPressed: _seatCount > 1
                              ? () => setState(() => _seatCount--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$_seatCount',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          onPressed: _seatCount < AppConstants.maxSeatsPerBooking
                              ? () => setState(() => _seatCount++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    // ── Advanced options ─────────────────────────────────
                    InkWell(
                      onTap: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.spaceSm),
                        child: Row(
                          children: <Widget>[
                            Text(
                              'Advanced options',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 13,
                              ),
                            ),
                            Icon(
                              _showAdvanced
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showAdvanced) ...<Widget>[
                      Text(
                        'Time flexibility',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: <int>[15, 30, 60].map((int m) {
                          return ChoiceChip(
                            label: Text('±$m min'),
                            selected: _timeFlexibilityMinutes == m,
                            onSelected: (_) => setState(
                                () => _timeFlexibilityMinutes = m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Max walking distance to pickup',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: <int>[500, 1000, 1500, 2000].map((int m) {
                          return ChoiceChip(
                            label: Text(
                              m < 1000 ? '${m}m' : '${m ~/ 1000} km',
                            ),
                            selected: _maxWalkingDistanceMeters == m,
                            onSelected: (_) => setState(
                                () => _maxWalkingDistanceMeters = m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: AppConstants.spaceMd),
                    PrimaryButton(
                      label: 'Search',
                      icon: Icons.search,
                      loading: searchState.isLoading,
                      onPressed: searchState.isLoading ? null : _search,
                    ),
                    if (searchState.error != null) ...<Widget>[
                      const SizedBox(height: AppConstants.spaceMd),
                      _ErrorBanner(message: searchState.error!),
                    ],
                    const SizedBox(height: AppConstants.spaceLg),
                    if (results.isNotEmpty)
                      ...results.map(
                        (SearchResultDto r) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppConstants.spaceSm,
                          ),
                          child: _SearchResultCard(result: r),
                        ),
                      )
                    else if (!searchState.isLoading &&
                        searchState.params != null &&
                        results.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(AppConstants.spaceLg),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusLg),
                        ),
                        child: const Text(
                          'No routes found. Try adjusting the time, '
                          'walking distance, or flexibility window.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MapSelectionCard extends StatelessWidget {
  const _MapSelectionCard({
    required this.markers,
    required this.currentLocation,
    required this.mapsConfigured,
    required this.loadingCurrentLocation,
    required this.mapTargetField,
    required this.onMapCreated,
    required this.onTapMap,
    required this.onSelectField,
    required this.onUseCurrentLocation,
  });

  final Set<Marker> markers;
  final LocationSearchResult? currentLocation;
  final bool mapsConfigured;
  final bool loadingCurrentLocation;
  final String mapTargetField;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng> onTapMap;
  final ValueChanged<String> onSelectField;
  final VoidCallback onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final LatLng center = currentLocation != null
        ? LatLng(currentLocation!.latitude, currentLocation!.longitude)
        : _RouteSearchScreenState._tanzaniaCenter;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusLg),
              ),
              child: mapsConfigured
                  ? GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: center,
                        zoom: currentLocation != null ? 12 : 5.5,
                      ),
                      markers: markers,
                      myLocationEnabled: currentLocation != null,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      onMapCreated: onMapCreated,
                      onTap: onTapMap,
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      padding: const EdgeInsets.all(AppConstants.spaceLg),
                      child: const Center(
                        child: Text(
                          'Google Maps is not configured for this build yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Wrap(
              spacing: AppConstants.spaceSm,
              runSpacing: AppConstants.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Pick origin'),
                  selected: mapTargetField == 'origin',
                  onSelected: (_) => onSelectField('origin'),
                ),
                ChoiceChip(
                  label: const Text('Pick destination'),
                  selected: mapTargetField == 'destination',
                  onSelected: (_) => onSelectField('destination'),
                ),
                TextButton.icon(
                  onPressed: loadingCurrentLocation ? null : onUseCurrentLocation,
                  icon: loadingCurrentLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('Use current location'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.loading,
    required this.suggestions,
    required this.onSelect,
  });

  final bool loading;
  final List<LocationSearchResult> suggestions;
  final ValueChanged<LocationSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(AppConstants.spaceMd),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppConstants.spaceSm),
                  Text('Finding matching places...'),
                ],
              ),
            )
          : Column(
              children: suggestions
                  .map(
                    (LocationSearchResult result) => ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(result.label),
                      subtitle: Text(result.asLatLng),
                      onTap: () => onSelect(result),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result});

  final SearchResultDto result;

  @override
  Widget build(BuildContext context) {
    final String price =
        'TZS ${NumberFormat('#,###').format(result.pricePerSeat)}';
    final String pickupTime =
        DateFormat('HH:mm').format(result.estimatedPickupTime.toLocal());
    final String departureTime =
        DateFormat('HH:mm').format(result.driverDepartureTime.toLocal());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: () => GoRouter.of(context).push(
          '/bookings/create',
          extra: <String, dynamic>{
            'routeId': result.routeId,
            'driverId': result.driverId,
            'pricePerSeat': result.pricePerSeat,
            'suggestedPickupName': result.suggestedPickupName,
            'suggestedPickupLat': result.suggestedPickupLat,
            'suggestedPickupLng': result.suggestedPickupLng,
            'estimatedPickupTime': result.estimatedPickupTime.toIso8601String(),
            'walkingDistanceToPickup': result.walkingDistanceToPickup,
            'walkingTimeToPickup': result.walkingTimeToPickup,
            'walkingDistanceFromDropoff': result.walkingDistanceFromDropoff,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      result.driverName ?? 'Driver',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    price,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Walking distance
              Row(
                children: <Widget>[
                  const Icon(Icons.directions_walk, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    result.walkingDistanceLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.event_seat, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${result.availableSeats} seats',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (result.driverRating != null) ...<Widget>[
                    const SizedBox(width: 16),
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      result.driverRating!.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // Pickup time info
              Row(
                children: <Widget>[
                  const Icon(Icons.access_time, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Departs $departureTime · pickup ~$pickupTime',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (result.suggestedPickupName != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    const Icon(Icons.place_outlined, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        result.suggestedPickupName!,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (result.vehicleLabel.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  result.vehicleLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
