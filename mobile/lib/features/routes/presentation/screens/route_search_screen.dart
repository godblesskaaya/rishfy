import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

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
  List<LocationSearchResult> _originSuggestions =
      const <LocationSearchResult>[];
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
    _sheetController.dispose();
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
    FocusScope.of(context).unfocus();
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

    if (!mounted) return;
    final RouteSearchState state = ref.read(routeSearchProvider);
    if (state.results.isNotEmpty && _sheetController.isAttached) {
      unawaited(_sheetController.animateTo(
        0.60,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ));
    }
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
    if (_originFocusNode.hasFocus) return _originSuggestions;
    if (_destFocusNode.hasFocus) return _destinationSuggestions;
    return const <LocationSearchResult>[];
  }

  bool get _activeSuggestionsLoading {
    if (_originFocusNode.hasFocus) return _loadingOriginSuggestions;
    if (_destFocusNode.hasFocus) return _loadingDestinationSuggestions;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final RouteSearchState searchState = ref.watch(routeSearchProvider);
    final List<SearchResultDto> results = searchState.results;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // ── Fullscreen map ─────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null
                  ? LatLng(
                      _currentLocation!.latitude,
                      _currentLocation!.longitude,
                    )
                  : _tanzaniaCenter,
              zoom: _currentLocation != null ? 12 : 5.5,
            ),
            markers: _buildMarkers(),
            myLocationEnabled: _currentLocation != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            onTap: (LatLng point) {
              FocusScope.of(context).unfocus();
              unawaited(_applyMapSelection(point));
            },
          ),

          // ── Floating input card + suggestions ──────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _FloatingInputCard(
                    originCtrl: _originCtrl,
                    destCtrl: _destCtrl,
                    originFocusNode: _originFocusNode,
                    destFocusNode: _destFocusNode,
                    originSelection: _originSelection,
                    destinationSelection: _destinationSelection,
                    mapTargetField: _mapTargetField,
                    loadingCurrentLocation: _loadingCurrentLocation,
                    onOriginChanged: _onOriginChanged,
                    onDestinationChanged: _onDestinationChanged,
                    onOriginTap: () =>
                        setState(() => _mapTargetField = 'origin'),
                    onDestinationTap: () =>
                        setState(() => _mapTargetField = 'destination'),
                    onUseCurrentLocation: _useCurrentLocation,
                    onSelectField: (String field) =>
                        setState(() => _mapTargetField = field),
                    onSearch: _search,
                  ),
                ),
                if (_locationHint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _InfoBanner(message: _locationHint!),
                  ),
                if (_activeSuggestionsLoading || _activeSuggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 230),
                      child: _SuggestionPanel(
                        loading: _activeSuggestionsLoading,
                        suggestions: _activeSuggestions,
                        onSelect: (LocationSearchResult result) {
                          _applySelection(
                            _originFocusNode.hasFocus
                                ? 'origin'
                                : 'destination',
                            result,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Draggable bottom sheet ─────────────────────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.32,
            minChildSize: 0.10,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const <double>[0.10, 0.32, 0.60, 0.92],
            builder: (BuildContext ctx, ScrollController scrollController) {
              return Material(
                elevation: 8,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusXl),
                ),
                child: Column(
                  children: <Widget>[
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.spaceLg,
                          0,
                          AppConstants.spaceLg,
                          AppConstants.spaceLg,
                        ),
                        children: <Widget>[
                          // ── Date + time row ──────────────────────────
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusLg),
                                  onTap: () async {
                                    final DateTime? picked =
                                        await showDatePicker(
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            DateFormat('d MMM')
                                                .format(_departureDate),
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
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusLg),
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
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

                          // ── Seats row ─────────────────────────────────
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
                                onPressed:
                                    _seatCount < AppConstants.maxSeatsPerBooking
                                        ? () => setState(() => _seatCount++)
                                        : null,
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),

                          // ── Advanced options ──────────────────────────
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
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Icon(
                                    _showAdvanced
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
                              'Preferred walking distance',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children:
                                  <int>[500, 1000, 1500, 2000].map((int m) {
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

                          // ── Results ───────────────────────────────────
                          if (results.isNotEmpty)
                            ...results.map(
                              (SearchResultDto r) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppConstants.spaceSm,
                                ),
                                child: _SearchResultCard(
                                  result: r,
                                  originSelection: _originSelection,
                                  destinationSelection: _destinationSelection,
                                ),
                              ),
                            )
                          else if (!searchState.isLoading &&
                              searchState.params != null &&
                              results.isEmpty)
                            Container(
                              padding:
                                  const EdgeInsets.all(AppConstants.spaceLg),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLg),
                              ),
                              child: const Text(
                                'No routes found. Try a wider time window, '
                                'more seats, or a longer walking preference.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Floating input card ──────────────────────────────────────────────────────

class _FloatingInputCard extends StatelessWidget {
  const _FloatingInputCard({
    required this.originCtrl,
    required this.destCtrl,
    required this.originFocusNode,
    required this.destFocusNode,
    required this.originSelection,
    required this.destinationSelection,
    required this.mapTargetField,
    required this.loadingCurrentLocation,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onOriginTap,
    required this.onDestinationTap,
    required this.onUseCurrentLocation,
    required this.onSelectField,
    required this.onSearch,
  });

  final TextEditingController originCtrl;
  final TextEditingController destCtrl;
  final FocusNode originFocusNode;
  final FocusNode destFocusNode;
  final LocationSearchResult? originSelection;
  final LocationSearchResult? destinationSelection;
  final String mapTargetField;
  final bool loadingCurrentLocation;
  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestinationChanged;
  final VoidCallback onOriginTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<String> onSelectField;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Header row with back button
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Text(
                  'Search routes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // From field
            TextField(
              controller: originCtrl,
              focusNode: originFocusNode,
              textInputAction: TextInputAction.next,
              onTap: onOriginTap,
              onChanged: onOriginChanged,
              decoration: InputDecoration(
                labelText: 'From',
                hintText: 'Search or tap map',
                prefixIcon: Icon(
                  Icons.trip_origin,
                  color: mapTargetField == 'origin' ? Colors.green : null,
                  size: 20,
                ),
                suffixIcon: originSelection != null
                    ? const Icon(Icons.check_circle_outline,
                        color: Colors.green, size: 20)
                    : null,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            const Divider(height: 1),
            // To field
            TextField(
              controller: destCtrl,
              focusNode: destFocusNode,
              textInputAction: TextInputAction.done,
              onTap: onDestinationTap,
              onChanged: onDestinationChanged,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Search or tap map',
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: mapTargetField == 'destination' ? Colors.red : null,
                  size: 20,
                ),
                suffixIcon: destinationSelection != null
                    ? const Icon(Icons.check_circle_outline,
                        color: Colors.green, size: 20)
                    : null,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            const Divider(height: 1),
            // Map target chips + current location button
            Row(
              children: <Widget>[
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('Origin'),
                        selected: mapTargetField == 'origin',
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                        onSelected: (_) => onSelectField('origin'),
                      ),
                      ChoiceChip(
                        label: const Text('Dest.'),
                        selected: mapTargetField == 'destination',
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                        onSelected: (_) => onSelectField('destination'),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      loadingCurrentLocation ? null : onUseCurrentLocation,
                  icon: loadingCurrentLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 16),
                  label: const Text(
                    'My location',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Suggestion panel ─────────────────────────────────────────────────────────

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
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      color: Theme.of(context).colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
              ),
      ),
    );
  }
}

// ─── Info / error banners ─────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
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

// ─── Search result card ───────────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.originSelection,
    required this.destinationSelection,
  });

  final SearchResultDto result;
  final LocationSearchResult? originSelection;
  final LocationSearchResult? destinationSelection;

  @override
  Widget build(BuildContext context) {
    final String price =
        'TZS ${NumberFormat('#,###').format(result.pricePerSeat)}';
    final String pickupTime =
        DateFormat('HH:mm').format(result.estimatedPickupTime.toLocal());
    final String departureTime =
        DateFormat('HH:mm').format(result.driverDepartureTime.toLocal());
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color tradeoffColor = result.walkingExceedsPreference
        ? scheme.tertiary
        : scheme.primary;
    final Color timeTradeoffColor = result.timeExceedsPreference
        ? scheme.tertiary
        : scheme.primary;
    final List<String> reasons = result.matchReasons.take(2).toList();
    final bool hasTradeoff =
        result.walkingExceedsPreference || result.timeExceedsPreference;
    final String routeFitCopy = hasTradeoff
        ? 'Flexible option. Review walking and pickup time before booking.'
        : 'Fits your walking preference with route pickup guidance.';

    return Card(
      elevation: 0,
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
            'suggestedDropoffName': result.suggestedDropoffName,
            'suggestedDropoffLat': result.suggestedDropoffLat,
            'suggestedDropoffLng': result.suggestedDropoffLng,
            'passengerPickupName': originSelection?.label,
            'passengerPickupLat': originSelection?.latitude,
            'passengerPickupLng': originSelection?.longitude,
            'passengerDropoffName': destinationSelection?.label,
            'passengerDropoffLat': destinationSelection?.latitude,
            'passengerDropoffLng': destinationSelection?.longitude,
            'estimatedPickupTime': result.estimatedPickupTime.toIso8601String(),
            'walkingDistanceToPickup': result.walkingDistanceToPickup,
            'walkingTimeToPickup': result.walkingTimeToPickup,
            'walkingDistanceFromDropoff': result.walkingDistanceFromDropoff,
            'walkingTimeFromDropoff': result.walkingTimeFromDropoff,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              result.driverName ?? 'Driver',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(width: 8),
                            if (result.driverRating != null)
                              _SearchStatChip(
                                icon: Icons.star,
                                iconColor: Colors.amber,
                                label: result.driverRating!.toStringAsFixed(1),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (result.vehicleLabel.isNotEmpty)
                          Text(
                            result.vehicleLabel,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      price,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _SearchStatChip(
                    icon: result.matchQuality == 'best'
                        ? Icons.verified_outlined
                        : Icons.tune,
                    iconColor: tradeoffColor,
                    label: result.matchQualityLabel,
                  ),
                  _SearchStatChip(
                    icon: Icons.directions_walk,
                    iconColor: tradeoffColor,
                    label: result.walkingDistanceLabel,
                  ),
                  _SearchStatChip(
                    icon: Icons.flag_outlined,
                    label: result.finalWalkLabel,
                  ),
                  if (result.walkingExceedsPreference)
                    _SearchStatChip(
                      icon: Icons.info_outline,
                      iconColor: tradeoffColor,
                      label: result.walkingTradeoffLabel,
                    ),
                  _SearchStatChip(
                    icon: Icons.event_seat,
                    label: '${result.availableSeats} seats',
                  ),
                  _SearchStatChip(
                    icon: Icons.login,
                    label: 'Departs $departureTime',
                  ),
                  _SearchStatChip(
                    icon: Icons.schedule,
                    iconColor: timeTradeoffColor,
                    label: 'Pickup ~$pickupTime',
                  ),
                  if (result.timeExceedsPreference)
                    _SearchStatChip(
                      icon: Icons.more_time,
                      iconColor: timeTradeoffColor,
                      label: result.timeTradeoffLabel,
                    ),
                ],
              ),
              if (reasons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map(
                        (String reason) => _SearchReasonPill(
                          text: reason,
                          emphasized: result.walkingExceedsPreference &&
                              reason.toLowerCase().contains('walking'),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (result.suggestedPickupName != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.pin_drop_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Suggested pickup',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              result.suggestedPickupName!,
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      routeFitCopy,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'View ride',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchReasonPill extends StatelessWidget {
  const _SearchReasonPill({
    required this.text,
    this.emphasized = false,
  });

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = emphasized ? scheme.tertiary : scheme.secondary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            emphasized ? Icons.info_outline : Icons.check_circle_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchStatChip extends StatelessWidget {
  const _SearchStatChip({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: iconColor ?? scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
