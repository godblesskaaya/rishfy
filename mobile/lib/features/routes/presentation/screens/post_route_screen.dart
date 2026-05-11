import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  DateTime _departureDate = DateTime.now();
  TimeOfDay _departureTime = TimeOfDay.now();
  int _availableSeats = 1;
  int _flexibilityMinutes = 15;
  bool _manualVehicleEntry = false;
  String? _selectedVehicleId;

  LocationSearchResult? _originSelection;
  LocationSearchResult? _destinationSelection;

  List<LocationSearchResult> _originSuggestions = const <LocationSearchResult>[];
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
    super.dispose();
  }

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
      final List<LocationSearchResult> results = await ref
          .read(locationSearchDataSourceProvider)
          .geocodeAddress(trimmed);
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
      } else {
        _destinationSelection = result;
        _destinationCtrl.text = result.label;
        _destinationSuggestions = const <LocationSearchResult>[];
      }
    });
    // Reset preview when either endpoint changes
    ref.read(previewRouteProvider.notifier).reset();
  }

  Future<void> _preview() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_originSelection == null || _destinationSelection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Select origin and destination from the suggestion list.'),
        ),
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
          ),
        );
  }

  Future<void> _submit(List<DriverVehicleOption> vehicleOptions) async {
    final PreviewRouteState previewState = ref.read(previewRouteProvider);
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
    context.go('/routes/${state.createdRoute!.routeId}');
  }

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

    return Scaffold(
      appBar: AppBar(title: const Text('Post a route')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── Origin ──────────────────────────────────────────────────
              TextFormField(
                controller: _originCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Origin',
                  hintText: 'Search city or area',
                  border: const OutlineInputBorder(),
                  suffixIcon: _originSelection != null
                      ? const Icon(Icons.check_circle_outline,
                          color: Colors.green)
                      : null,
                ),
                onChanged: (String v) {
                  if (_originSelection?.label != v.trim()) {
                    setState(() => _originSelection = null);
                    ref.read(previewRouteProvider.notifier).reset();
                  }
                  _fetchSuggestions('origin', v);
                },
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Origin is required';
                  }
                  return null;
                },
              ),
              if (_loadingOriginSuggestions) ...<Widget>[
                const SizedBox(height: 4),
                const LinearProgressIndicator(),
              ],
              if (_originSuggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                _SuggestionList(
                  suggestions: _originSuggestions,
                  onSelect: (LocationSearchResult r) =>
                      _applySelection('origin', r),
                ),
              ],
              const SizedBox(height: 12),

              // ── Destination ──────────────────────────────────────────────
              TextFormField(
                controller: _destinationCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Destination',
                  hintText: 'Search city or area',
                  border: const OutlineInputBorder(),
                  suffixIcon: _destinationSelection != null
                      ? const Icon(Icons.check_circle_outline,
                          color: Colors.green)
                      : null,
                ),
                onChanged: (String v) {
                  if (_destinationSelection?.label != v.trim()) {
                    setState(() => _destinationSelection = null);
                    ref.read(previewRouteProvider.notifier).reset();
                  }
                  _fetchSuggestions('destination', v);
                },
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Destination is required';
                  }
                  return null;
                },
              ),
              if (_loadingDestinationSuggestions) ...<Widget>[
                const SizedBox(height: 4),
                const LinearProgressIndicator(),
              ],
              if (_destinationSuggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                _SuggestionList(
                  suggestions: _destinationSuggestions,
                  onSelect: (LocationSearchResult r) =>
                      _applySelection('destination', r),
                ),
              ],
              const SizedBox(height: 16),

              // ── Departure date/time ──────────────────────────────────────
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDepartureDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        DateFormat('EEE, d MMM y').format(_departureDate),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDepartureTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(_departureTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Flexibility ──────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Pickup flexibility',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Passengers whose desired pickup time is within this window '
                    'of your route will be matched.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <int>[0, 5, 10, 15, 30].map((int m) {
                      return ChoiceChip(
                        label: Text(m == 0 ? 'Exact' : '$m min'),
                        selected: _flexibilityMinutes == m,
                        onSelected: (_) {
                          setState(() => _flexibilityMinutes = m);
                          ref.read(previewRouteProvider.notifier).reset();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Available seats ──────────────────────────────────────────
              Row(
                children: <Widget>[
                  Text('Available seats',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: _availableSeats > 1
                        ? () => setState(() => _availableSeats--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_availableSeats'),
                  IconButton(
                    onPressed: _availableSeats < 20
                        ? () => setState(() => _availableSeats++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Price ────────────────────────────────────────────────────
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price per seat (TZS)',
                  hintText: '5000',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) {
                  final int? parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Vehicle ──────────────────────────────────────────────────
              if (vehicleOptions.isNotEmpty) ...<Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enter vehicle UUID manually'),
                  value: _manualVehicleEntry,
                  onChanged: (bool value) {
                    setState(() => _manualVehicleEntry = value);
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (useManualVehicle)
                TextFormField(
                  controller: _manualVehicleIdCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle UUID',
                    hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    if (!useManualVehicle) return null;
                    final String raw = (value ?? '').trim();
                    if (raw.isEmpty) return 'Vehicle UUID is required';
                    if (!_isValidUuid(raw)) return 'Enter a valid UUID';
                    return null;
                  },
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedVehicleId,
                  items: vehicleOptions
                      .map((DriverVehicleOption vehicle) =>
                          DropdownMenuItem<String>(
                            value: vehicle.id,
                            child: Text(
                              vehicle.isActive
                                  ? '${vehicle.label} (Active)'
                                  : vehicle.label,
                            ),
                          ))
                      .toList(),
                  decoration: const InputDecoration(
                    labelText: 'Select vehicle',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (String? value) {
                    setState(() => _selectedVehicleId = value);
                  },
                ),
              if (vehiclesAsync.isLoading && vehicleOptions.isEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Loading your vehicles. You can continue with manual UUID entry.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (vehicleOptions.isEmpty && !vehiclesAsync.isLoading) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'No vehicles found on your driver profile yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (vehiclesAsync.hasError) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Vehicle list unavailable. Enter vehicle UUID manually.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),

              // ── Preview result ───────────────────────────────────────────
              if (previewState.error != null) ...<Widget>[
                _ErrorCard(message: previewState.error!),
                const SizedBox(height: 12),
              ],
              if (hasPreview) ...<Widget>[
                _PreviewCard(preview: previewState.preview!),
                const SizedBox(height: 16),
              ],

              // ── Create errors ────────────────────────────────────────────
              if (createState.error != null) ...<Widget>[
                _ErrorCard(message: createState.error!),
                const SizedBox(height: 12),
              ],

              // ── Action buttons ───────────────────────────────────────────
              if (!hasPreview)
                PrimaryButton(
                  label: 'Preview route',
                  icon: Icons.route,
                  loading: isPreviewing,
                  onPressed: isPreviewing ? null : _preview,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () {
                        ref.read(previewRouteProvider.notifier).reset();
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Adjust route'),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Post route',
                      icon: Icons.add_road,
                      loading: isSubmitting,
                      onPressed:
                          isSubmitting ? null : () => _submit(vehicleOptions),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.onSelect,
  });

  final List<LocationSearchResult> suggestions;
  final ValueChanged<LocationSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        children: suggestions
            .take(4)
            .map(
              (LocationSearchResult r) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text(r.label,
                    style: Theme.of(context).textTheme.bodySmall),
                onTap: () => onSelect(r),
              ),
            )
            .toList(),
      ),
    );
  }
}

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
                Text(
                  'Route preview',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
        style:
            TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
