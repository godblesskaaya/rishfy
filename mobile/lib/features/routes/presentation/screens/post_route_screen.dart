import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../data/datasources/location_search_remote_datasource.dart';
import '../../data/models/route_models.dart';
import '../providers/route_provider.dart';

class PostRouteScreen extends ConsumerStatefulWidget {
  const PostRouteScreen({super.key});

  @override
  ConsumerState<PostRouteScreen> createState() => _PostRouteScreenState();
}

class _PostRouteScreenState extends ConsumerState<PostRouteScreen> {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destinationCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _manualVehicleIdCtrl = TextEditingController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  DateTime _departureDate = DateTime.now();
  TimeOfDay _departureTime = TimeOfDay.now();
  int _availableSeats = 1;
  int _flexibilityMinutes = 15;
  bool _manualVehicleEntry = false;
  String? _selectedVehicleId;
  String _mapTargetField = 'origin';
  bool _reverseGeocodingMapPoint = false;
  GoogleMapController? _planningMapController;

  LocationSearchResult? _originSelection;
  LocationSearchResult? _destinationSelection;
  List<LocationSearchResult> _waypoints = const <LocationSearchResult>[];

  List<LocationSearchResult> _originSuggestions =
      const <LocationSearchResult>[];
  List<LocationSearchResult> _destinationSuggestions =
      const <LocationSearchResult>[];
  bool _loadingOriginSuggestions = false;
  bool _loadingDestinationSuggestions = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = '5000';
    _departureDate = DateTime.now().add(const Duration(hours: 1));
    _departureTime = TimeOfDay.fromDateTime(_departureDate);
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    _priceCtrl.dispose();
    _manualVehicleIdCtrl.dispose();
    _sheetController.dispose();
    _planningMapController?.dispose();
    super.dispose();
  }

  // ── Map markers & polylines ──────────────────────────────────────────────────

  Set<Marker> get _markers {
    final Set<Marker> markers = <Marker>{};
    if (_originSelection != null) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position:
            LatLng(_originSelection!.latitude, _originSelection!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _originSelection!.label),
        draggable: true,
        onDragEnd: (LatLng p) =>
            unawaited(_selectMapPointForField('origin', p)),
      ));
    }
    if (_destinationSelection != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(
            _destinationSelection!.latitude, _destinationSelection!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: _destinationSelection!.label),
        draggable: true,
        onDragEnd: (LatLng p) =>
            unawaited(_selectMapPointForField('destination', p)),
      ));
    }
    for (int i = 0; i < _waypoints.length; i++) {
      markers.add(Marker(
        markerId: MarkerId('waypoint_$i'),
        position: LatLng(_waypoints[i].latitude, _waypoints[i].longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: _waypoints[i].label),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolylines(RoutePreviewDto? preview) {
    final String encoded = preview?.polyline ?? '';
    if (encoded.isEmpty) return <Polyline>{};
    final List<List<num>> coords = decodePolyline(encoded);
    if (coords.length < 2) return <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('preview'),
        points: coords
            .map((List<num> p) => LatLng(p[0].toDouble(), p[1].toDouble()))
            .toList(),
        color: Colors.blue,
        width: 5,
      ),
    };
  }

  // ── Camera helpers ───────────────────────────────────────────────────────────

  void _fitPlanningBounds() {
    if (_planningMapController == null ||
        _originSelection == null ||
        _destinationSelection == null) {
      return;
    }
    final List<LatLng> points = <LatLng>[
      LatLng(_originSelection!.latitude, _originSelection!.longitude),
      LatLng(_destinationSelection!.latitude, _destinationSelection!.longitude),
      ..._waypoints
          .map((LocationSearchResult p) => LatLng(p.latitude, p.longitude)),
    ];
    final double minLat = points
        .map((LatLng p) => p.latitude)
        .reduce((double a, double b) => a < b ? a : b);
    final double maxLat = points
        .map((LatLng p) => p.latitude)
        .reduce((double a, double b) => a > b ? a : b);
    final double minLng = points
        .map((LatLng p) => p.longitude)
        .reduce((double a, double b) => a < b ? a : b);
    final double maxLng = points
        .map((LatLng p) => p.longitude)
        .reduce((double a, double b) => a > b ? a : b);
    unawaited(_planningMapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.01, minLng - 0.01),
          northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
        ),
        60,
      ),
    ));
  }

  // ── Map tap handlers ─────────────────────────────────────────────────────────

  Future<void> _selectMapPoint(LatLng point) async {
    await _selectMapPointForField(_mapTargetField, point);
  }

  Future<void> _selectMapPointForField(String field, LatLng point) async {
    setState(() => _reverseGeocodingMapPoint = true);
    final LocationSearchResult fallback = LocationSearchResult(
      label:
          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
      latitude: point.latitude,
      longitude: point.longitude,
    );
    try {
      final LocationSearchResult? resolved = await ref
          .read(locationSearchDataSourceProvider)
          .reverseGeocode(point.latitude, point.longitude);
      if (!mounted) return;
      _applySelection(field, resolved ?? fallback);
    } finally {
      if (mounted) setState(() => _reverseGeocodingMapPoint = false);
    }
  }

  // ── Date/time pickers ────────────────────────────────────────────────────────

  Future<void> _pickDepartureDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _departureDate.isBefore(now) ? now : _departureDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
    );
    if (picked == null) return;
    setState(() => _departureDate = picked);
  }

  Future<void> _pickDepartureTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _departureTime,
    );
    if (picked == null) return;
    setState(() => _departureTime = picked);
  }

  DateTime get _departureDateTime => DateTime(
        _departureDate.year,
        _departureDate.month,
        _departureDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );

  // ── Autocomplete ─────────────────────────────────────────────────────────────

  bool _isValidUuid(String value) => _uuidPattern.hasMatch(value.trim());

  Future<void> _fetchSuggestions(String field, String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < 3) {
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
      final List<LocationSearchResult> results =
          await ref.read(locationSearchDataSourceProvider).geocodeAddress(
                trimmed,
                proximity: field == 'destination'
                    ? _originSelection
                    : _destinationSelection,
              );
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

  void _applySelection(String field, LocationSearchResult result) {
    setState(() {
      if (field == 'origin') {
        _originSelection = result;
        _originCtrl.text = result.label;
        _originSuggestions = const <LocationSearchResult>[];
        _mapTargetField =
            _destinationSelection == null ? 'destination' : 'origin';
      } else if (field == 'destination') {
        _destinationSelection = result;
        _destinationCtrl.text = result.label;
        _destinationSuggestions = const <LocationSearchResult>[];
        _mapTargetField = _originSelection == null ? 'origin' : 'destination';
      } else if (_waypoints.length < 5) {
        _waypoints = <LocationSearchResult>[..._waypoints, result];
      }
    });
    _resetPreview();

    final GoogleMapController? ctrl = _planningMapController;
    if (ctrl != null) {
      unawaited(ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(
            LatLng(result.latitude, result.longitude), 14),
      ));
    }

    if (_originSelection != null && _destinationSelection != null) {
      // Snap sheet up to show form controls and trigger preview
      if (_sheetController.isAttached) {
        unawaited(_sheetController.animateTo(
          0.48,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_preview());
      });
    }
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints = <LocationSearchResult>[
        ..._waypoints.take(index),
        ..._waypoints.skip(index + 1),
      ];
    });
    _resetPreview();
  }

  // ── Route preview ────────────────────────────────────────────────────────────

  void _resetPreview() {
    ref.read(previewRouteProvider.notifier).reset();
  }

  List<Map<String, double>> get _waypointPayload => _waypoints
      .map((LocationSearchResult p) =>
          <String, double>{'lat': p.latitude, 'lng': p.longitude})
      .toList();

  Future<void> _preview() async {
    if (_originSelection == null || _destinationSelection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select origin and destination on the map first.')),
      );
      return;
    }
    await ref.read(previewRouteProvider.notifier).preview(
          RoutePreviewRequest(
            originLat: _originSelection!.latitude,
            originLng: _originSelection!.longitude,
            destinationLat: _destinationSelection!.latitude,
            destinationLng: _destinationSelection!.longitude,
            flexibilityMinutes: _flexibilityMinutes,
            waypoints: _waypointPayload,
          ),
        );
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitPlanningBounds();
        if (_sheetController.isAttached) {
          unawaited(_sheetController.animateTo(
            0.60,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ));
        }
      });
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submit(List<DriverVehicleOption> vehicleOptions) async {
    PreviewRouteState previewState = ref.read(previewRouteProvider);
    if (previewState.status != PreviewRouteStatus.success) {
      await _preview();
      if (!mounted) return;
      previewState = ref.read(previewRouteProvider);
    }
    if (previewState.status != PreviewRouteStatus.success) return;

    final bool useManualVehicle = vehicleOptions.isEmpty || _manualVehicleEntry;
    final String vehicleId = useManualVehicle
        ? _manualVehicleIdCtrl.text.trim()
        : (_selectedVehicleId ?? vehicleOptions.first.id);

    if (!_isValidUuid(vehicleId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle ID must be a valid UUID.')),
      );
      return;
    }

    final DateTime departure = _departureDateTime;
    if (!departure.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Departure must be in the future.')),
      );
      return;
    }

    final int? price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid price per seat.')),
      );
      return;
    }

    await ref.read(createRouteProvider.notifier).submit(
          CreateRouteRequest(
            vehicleId: vehicleId,
            originName: _originCtrl.text.trim(),
            originLat: _originSelection!.latitude,
            originLng: _originSelection!.longitude,
            destinationName: _destinationCtrl.text.trim(),
            destinationLat: _destinationSelection!.latitude,
            destinationLng: _destinationSelection!.longitude,
            availableSeats: _availableSeats,
            pricePerSeat: price,
            departureTime: departure,
            flexibilityMinutes: _flexibilityMinutes,
            waypoints: _waypointPayload,
          ),
        );

    final CreateRouteState state = ref.read(createRouteProvider);
    if (state.status != CreateRouteStatus.success ||
        state.createdRoute == null ||
        !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route posted successfully.')),
    );
    context.pushReplacement('/routes/${state.createdRoute!.routeId}');
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DriverVehicleOption>> vehiclesAsync =
        ref.watch(myVehicleOptionsProvider);
    final CreateRouteState createState = ref.watch(createRouteProvider);
    final PreviewRouteState previewState = ref.watch(previewRouteProvider);
    final List<DriverVehicleOption> vehicleOptions =
        vehiclesAsync.valueOrNull ?? const <DriverVehicleOption>[];
    final bool useManualVehicle = vehicleOptions.isEmpty || _manualVehicleEntry;
    final bool isSubmitting = createState.status == CreateRouteStatus.loading;
    final bool isPreviewing = previewState.status == PreviewRouteStatus.loading;
    final bool hasPreview = previewState.status == PreviewRouteStatus.success;

    DriverVehicleOption? selectedVehicle;
    if (vehicleOptions.isNotEmpty) {
      final String svId = _selectedVehicleId ?? vehicleOptions.first.id;
      for (final DriverVehicleOption v in vehicleOptions) {
        if (v.id == svId) {
          selectedVehicle = v;
          break;
        }
      }
    }
    final int maxSeats = selectedVehicle?.capacity == null
        ? 4
        : selectedVehicle!.capacity!.clamp(1, 4).toInt();

    final LatLng initialTarget = _originSelection != null
        ? LatLng(_originSelection!.latitude, _originSelection!.longitude)
        : const LatLng(-6.7924, 39.2083);

    return Form(
      key: _formKey,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            // ── 1. Fullscreen map ───────────────────────────────────────────
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: _originSelection == null ? 11 : 13,
              ),
              onMapCreated: (GoogleMapController c) {
                _planningMapController = c;
                unawaited(Future<void>.delayed(
                  const Duration(milliseconds: 400),
                  _fitPlanningBounds,
                ));
              },
              onTap: _selectMapPoint,
              markers: _markers,
              polylines: _buildPolylines(previewState.preview),
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
            ),

            // ── 2. Floating route header ────────────────────────────────────
            SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _FloatingHeader(
                    originCtrl: _originCtrl,
                    destinationCtrl: _destinationCtrl,
                    originSelected: _originSelection != null,
                    destinationSelected: _destinationSelection != null,
                    mapTargetField: _mapTargetField,
                    loadingOrigin: _loadingOriginSuggestions,
                    loadingDestination: _loadingDestinationSuggestions,
                    onOriginChanged: (String v) {
                      if (_originSelection?.label != v.trim()) {
                        setState(() {
                          _originSelection = null;
                          _mapTargetField = 'origin';
                        });
                        _resetPreview();
                      }
                      unawaited(_fetchSuggestions('origin', v));
                    },
                    onDestinationChanged: (String v) {
                      if (_destinationSelection?.label != v.trim()) {
                        setState(() {
                          _destinationSelection = null;
                          _mapTargetField = 'destination';
                        });
                        _resetPreview();
                      }
                      unawaited(_fetchSuggestions('destination', v));
                    },
                    onTargetChanged: (String field) =>
                        setState(() => _mapTargetField = field),
                    onBack: () => context.pop(),
                  ),
                  if (_originSuggestions.isNotEmpty)
                    _SuggestionOverlay(
                      suggestions: _originSuggestions,
                      onSelect: (LocationSearchResult r) =>
                          _applySelection('origin', r),
                    ),
                  if (_destinationSuggestions.isNotEmpty)
                    _SuggestionOverlay(
                      suggestions: _destinationSuggestions,
                      onSelect: (LocationSearchResult r) =>
                          _applySelection('destination', r),
                    ),
                ],
              ),
            ),

            // ── 3. Reverse geocoding progress ───────────────────────────────
            if (_reverseGeocodingMapPoint)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),

            // ── 4. Form bottom sheet ────────────────────────────────────────
            DraggableScrollableSheet(
              controller: _sheetController,
              minChildSize: 0.08,
              initialChildSize: 0.12,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const <double>[0.12, 0.48, 0.72],
              builder: (BuildContext _, ScrollController scrollCtrl) {
                return Material(
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppConstants.radiusXl)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: <Widget>[
                      // Drag handle
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_sheetController.isAttached) {
                            final double target =
                                _sheetController.size < 0.30 ? 0.48 : 0.12;
                            unawaited(_sheetController.animateTo(
                              target,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            children: <Widget>[
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Route details',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      // Form content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollCtrl,
                          padding: EdgeInsets.fromLTRB(
                            AppConstants.spaceLg,
                            AppConstants.spaceMd,
                            AppConstants.spaceLg,
                            AppConstants.spaceLg +
                                MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              // Waypoints
                              if (_waypoints.isNotEmpty) ...<Widget>[
                                _WaypointList(
                                  waypoints: _waypoints,
                                  onRemove: _removeWaypoint,
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Departure date/time
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickDepartureDate,
                                      icon: const Icon(Icons.calendar_today,
                                          size: 18),
                                      label: Text(DateFormat('EEE, d MMM y')
                                          .format(_departureDate)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickDepartureTime,
                                      icon:
                                          const Icon(Icons.schedule, size: 18),
                                      label:
                                          Text(_departureTime.format(context)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Flexibility
                              Text('Pickup flexibility',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(
                                'Passengers within this time window of your route will match.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: <int>[0, 5, 10, 15, 30]
                                    .map((int m) => ChoiceChip(
                                          label:
                                              Text(m == 0 ? 'Exact' : '$m min'),
                                          selected: _flexibilityMinutes == m,
                                          onSelected: (_) {
                                            setState(
                                                () => _flexibilityMinutes = m);
                                            _resetPreview();
                                          },
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 16),

                              // Seats
                              Row(
                                children: <Widget>[
                                  Text('Available seats',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: _availableSeats > 1
                                        ? () =>
                                            setState(() => _availableSeats--)
                                        : null,
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('$_availableSeats'),
                                  IconButton(
                                    onPressed: _availableSeats < maxSeats
                                        ? () =>
                                            setState(() => _availableSeats++)
                                        : null,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Price
                              TextFormField(
                                controller: _priceCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Price per seat (TZS)',
                                  hintText: '5000',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (String? value) {
                                  final int? parsed =
                                      int.tryParse((value ?? '').trim());
                                  if (parsed == null || parsed <= 0) {
                                    return 'Enter a valid positive amount';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // Vehicle
                              if (vehicleOptions.isNotEmpty) ...<Widget>[
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title:
                                      const Text('Enter vehicle UUID manually'),
                                  value: _manualVehicleEntry,
                                  onChanged: (bool v) =>
                                      setState(() => _manualVehicleEntry = v),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (useManualVehicle)
                                TextFormField(
                                  controller: _manualVehicleIdCtrl,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Vehicle UUID',
                                    hintText:
                                        'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (String? value) {
                                    if (!useManualVehicle) return null;
                                    final String raw = (value ?? '').trim();
                                    if (raw.isEmpty) {
                                      return 'Vehicle UUID is required';
                                    }
                                    if (!_isValidUuid(raw)) {
                                      return 'Enter a valid UUID';
                                    }
                                    return null;
                                  },
                                )
                              else
                                DropdownButtonFormField<String>(
                                  value: _selectedVehicleId,
                                  items: vehicleOptions
                                      .map((DriverVehicleOption v) =>
                                          DropdownMenuItem<String>(
                                            value: v.id,
                                            child: Text(v.isActive
                                                ? '${v.label} (Active)'
                                                : v.label),
                                          ))
                                      .toList(),
                                  decoration: const InputDecoration(
                                    labelText: 'Select vehicle',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (String? value) {
                                    DriverVehicleOption? next;
                                    for (final DriverVehicleOption v
                                        in vehicleOptions) {
                                      if (v.id == value) {
                                        next = v;
                                        break;
                                      }
                                    }
                                    final int nextMax = next?.capacity == null
                                        ? 4
                                        : next!.capacity!.clamp(1, 4).toInt();
                                    setState(() {
                                      _selectedVehicleId = value;
                                      if (_availableSeats > nextMax) {
                                        _availableSeats = nextMax;
                                      }
                                    });
                                  },
                                ),
                              if (vehiclesAsync.isLoading &&
                                  vehicleOptions.isEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  'Loading vehicles…',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (vehicleOptions.isEmpty &&
                                  !vehiclesAsync.isLoading) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  'No vehicles on your profile yet. Enter UUID manually.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (vehiclesAsync.hasError) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  'Vehicle list unavailable. Enter UUID manually.',
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error),
                                ),
                              ],
                              const SizedBox(height: 24),

                              // Preview error
                              if (previewState.error != null) ...<Widget>[
                                _ErrorCard(message: previewState.error!),
                                const SizedBox(height: 12),
                              ],

                              // Preview success card
                              if (hasPreview &&
                                  _originSelection != null &&
                                  _destinationSelection != null) ...<Widget>[
                                _PreviewCard(preview: previewState.preview!),
                                const SizedBox(height: 16),
                              ],

                              // Create error
                              if (createState.error != null) ...<Widget>[
                                _ErrorCard(message: createState.error!),
                                const SizedBox(height: 12),
                              ],

                              // Action buttons
                              if (!hasPreview)
                                PrimaryButton(
                                  label: 'Preview route',
                                  icon: Icons.route,
                                  loading: isPreviewing,
                                  onPressed: isPreviewing ? null : _preview,
                                )
                              else
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    OutlinedButton.icon(
                                      onPressed: _resetPreview,
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Adjust route'),
                                    ),
                                    const SizedBox(height: 12),
                                    PrimaryButton(
                                      label: 'Post route',
                                      icon: Icons.add_road,
                                      loading: isSubmitting,
                                      onPressed: isSubmitting
                                          ? null
                                          : () => _submit(vehicleOptions),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Floating header ────────────────────────────────────────────────────────────

class _FloatingHeader extends StatelessWidget {
  const _FloatingHeader({
    required this.originCtrl,
    required this.destinationCtrl,
    required this.originSelected,
    required this.destinationSelected,
    required this.mapTargetField,
    required this.loadingOrigin,
    required this.loadingDestination,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onTargetChanged,
    required this.onBack,
  });

  final TextEditingController originCtrl;
  final TextEditingController destinationCtrl;
  final bool originSelected;
  final bool destinationSelected;
  final String mapTargetField;
  final bool loadingOrigin;
  final bool loadingDestination;
  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Title row
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    'Post a route',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            // Origin field
            Row(
              children: <Widget>[
                const SizedBox(width: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: originCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'From…',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: loadingOrigin
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (originSelected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 18)
                              : null),
                    ),
                    onChanged: onOriginChanged,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            const Divider(height: 1, indent: 40),
            // Destination field
            Row(
              children: <Widget>[
                const SizedBox(width: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: destinationCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'To…',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: loadingDestination
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (destinationSelected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 18)
                              : null),
                    ),
                    onChanged: onDestinationChanged,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            const Divider(height: 1),
            // Map target chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.touch_app_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  const Text(
                    'Tap map:',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  _TargetChip(
                    label: 'Start',
                    selected: mapTargetField == 'origin',
                    color: Colors.green,
                    onSelected: () => onTargetChanged('origin'),
                  ),
                  const SizedBox(width: 4),
                  _TargetChip(
                    label: 'End',
                    selected: mapTargetField == 'destination',
                    color: Colors.red,
                    onSelected: () => onTargetChanged('destination'),
                  ),
                  const SizedBox(width: 4),
                  _TargetChip(
                    label: 'Stop',
                    selected: mapTargetField == 'waypoint',
                    color: Colors.blue,
                    onSelected: () => onTargetChanged('waypoint'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suggestion overlay ─────────────────────────────────────────────────────────

class _SuggestionOverlay extends StatelessWidget {
  const _SuggestionOverlay({
    required this.suggestions,
    required this.onSelect,
  });

  final List<LocationSearchResult> suggestions;
  final ValueChanged<LocationSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, int i) {
              final LocationSearchResult r = suggestions[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18),
                title:
                    Text(r.label, style: Theme.of(context).textTheme.bodySmall),
                subtitle: Text(r.asLatLng,
                    style: Theme.of(context).textTheme.labelSmall),
                onTap: () => onSelect(r),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Target chip ────────────────────────────────────────────────────────────────

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: color.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Waypoint list ──────────────────────────────────────────────────────────────

class _WaypointList extends StatelessWidget {
  const _WaypointList({required this.waypoints, required this.onRemove});

  final List<LocationSearchResult> waypoints;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Stops', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...waypoints.indexed.map(
          ((int, LocationSearchResult) entry) {
            final int index = entry.$1;
            final LocationSearchResult waypoint = entry.$2;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                    radius: 12,
                    child: Text('${index + 1}',
                        style: const TextStyle(fontSize: 11))),
                title: Text(waypoint.label),
                subtitle: Text(waypoint.asLatLng),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onRemove(index),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Preview card ───────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final RoutePreviewDto preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Route preview',
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${preview.distanceLabel} · ${preview.durationLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error card ─────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

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
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
