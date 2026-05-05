import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';
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
  bool _manualVehicleEntry = false;
  String? _selectedVehicleId;

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

  Future<void> _submit(List<DriverVehicleOption> vehicleOptions) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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
            destinationName: _destinationCtrl.text.trim(),
            availableSeats: _availableSeats,
            pricePerSeat: price,
            departureTime: departure,
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
    final List<DriverVehicleOption> vehicleOptions =
        vehiclesAsync.valueOrNull ?? const <DriverVehicleOption>[];
    final bool useManualVehicle = vehicleOptions.isEmpty || _manualVehicleEntry;
    final bool isSubmitting = createState.status == CreateRouteStatus.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Post a route')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _originCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Origin',
                  hintText: 'City name or lat,lng',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Origin is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _destinationCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  hintText: 'City name or lat,lng',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Destination is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Use a common city name in Tanzania (example: Dar es Salaam) or a lat,lng pair.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
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
              if (vehiclesAsync.hasError) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Vehicle list unavailable. Enter vehicle UUID manually.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              if (createState.error != null) ...<Widget>[
                Text(
                  createState.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: 'Post route',
                icon: Icons.add_road,
                loading: isSubmitting,
                onPressed: isSubmitting ? null : () => _submit(vehicleOptions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
