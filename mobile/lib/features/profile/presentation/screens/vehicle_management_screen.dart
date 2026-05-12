import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../routes/data/models/route_models.dart';
import '../../data/datasources/profile_remote_datasource.dart';
import '../providers/profile_provider.dart';

class VehicleManagementScreen extends ConsumerStatefulWidget {
  const VehicleManagementScreen({super.key});

  @override
  ConsumerState<VehicleManagementScreen> createState() =>
      _VehicleManagementScreenState();
}

class _VehicleManagementScreenState
    extends ConsumerState<VehicleManagementScreen> {
  bool _upgradingToDriver = false;
  bool _mutatingVehicle = false;

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _refreshProfile() async {
    await ref.read(authControllerProvider.notifier).syncCurrentUser();
  }

  Future<void> _becomeDriver() async {
    final BecomeDriverRequest? request =
        await showModalBottomSheet<BecomeDriverRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BecomeDriverSheet(),
    );
    if (request == null) return;

    setState(() => _upgradingToDriver = true);
    try {
      await ref.read(profileRemoteDataSourceProvider).becomeDriver(request);
      await _refreshProfile();
      ref.invalidate(myVehiclesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver profile created successfully.')),
      );
    } catch (error) {
      await _showError(error);
    } finally {
      if (mounted) {
        setState(() => _upgradingToDriver = false);
      }
    }
  }

  Future<void> _addVehicle() async {
    final CreateVehicleRequest? request =
        await showModalBottomSheet<CreateVehicleRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddVehicleSheet(),
    );
    if (request == null) return;

    setState(() => _mutatingVehicle = true);
    try {
      await ref.read(profileRemoteDataSourceProvider).addVehicle(request);
      ref.invalidate(myVehiclesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle added successfully.')),
      );
    } catch (error) {
      await _showError(error);
    } finally {
      if (mounted) {
        setState(() => _mutatingVehicle = false);
      }
    }
  }

  Future<void> _setActiveVehicle(String vehicleId) async {
    setState(() => _mutatingVehicle = true);
    try {
      await ref
          .read(profileRemoteDataSourceProvider)
          .setActiveVehicle(vehicleId);
      ref.invalidate(myVehiclesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active vehicle updated.')),
      );
    } catch (error) {
      await _showError(error);
    } finally {
      if (mounted) {
        setState(() => _mutatingVehicle = false);
      }
    }
  }

  Future<void> _deleteVehicle(String vehicleId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete vehicle'),
          content: const Text(
            'Remove this vehicle from your driver profile?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _mutatingVehicle = true);
    try {
      await ref.read(profileRemoteDataSourceProvider).deleteVehicle(vehicleId);
      ref.invalidate(myVehiclesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle deleted.')),
      );
    } catch (error) {
      await _showError(error);
    } finally {
      if (mounted) {
        setState(() => _mutatingVehicle = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final bool isDriver = user?.role == UserRole.driver;
    final AsyncValue<List<DriverVehicleOption>> vehiclesAsync =
        ref.watch(myVehiclesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isDriver ? 'My vehicles' : 'Driver setup'),
      ),
      floatingActionButton: isDriver
          ? FloatingActionButton.extended(
              onPressed: _mutatingVehicle ? null : _addVehicle,
              icon: const Icon(Icons.add),
              label: const Text('Add vehicle'),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: isDriver
              ? vehiclesAsync.when(
                  data: (List<DriverVehicleOption> vehicles) {
                    if (vehicles.isEmpty) {
                      return _EmptyVehiclesState(
                        busy: _mutatingVehicle,
                        onAddVehicle: _addVehicle,
                      );
                    }
                    return ListView.separated(
                      itemCount: vehicles.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppConstants.spaceMd),
                      itemBuilder: (BuildContext context, int index) {
                        final DriverVehicleOption vehicle = vehicles[index];
                        return _VehicleCard(
                          vehicle: vehicle,
                          busy: _mutatingVehicle,
                          onDelete: () => _deleteVehicle(vehicle.id),
                          onSetActive: vehicle.isActive
                              ? null
                              : () => _setActiveVehicle(vehicle.id),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object error, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Failed to load vehicles.\n$error'),
                        const SizedBox(height: AppConstants.spaceMd),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(myVehiclesProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _BecomeDriverState(
                  busy: _upgradingToDriver,
                  onBecomeDriver: _becomeDriver,
                ),
        ),
      ),
    );
  }
}

class _BecomeDriverState extends StatelessWidget {
  const _BecomeDriverState({
    required this.busy,
    required this.onBecomeDriver,
  });

  final bool busy;
  final VoidCallback onBecomeDriver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Become a driver',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                'Create your driver profile first, then add a vehicle before posting routes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.spaceLg),
              FilledButton.icon(
                onPressed: busy ? null : onBecomeDriver,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.badge_outlined),
                label: const Text('Create driver profile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceLg),
        Text(
          'Backend-supported now',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppConstants.spaceSm),
        const Text('1. Submit driver licence details'),
        const Text('2. Add one or more vehicles'),
        const Text('3. Set an active vehicle for route posting'),
      ],
    );
  }
}

class _EmptyVehiclesState extends StatelessWidget {
  const _EmptyVehiclesState({
    required this.busy,
    required this.onAddVehicle,
  });

  final bool busy;
  final VoidCallback onAddVehicle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.directions_car_outlined, size: 56),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            'No vehicles added yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            'Add a vehicle to unlock route posting.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spaceLg),
          FilledButton.icon(
            onPressed: busy ? null : onAddVehicle,
            icon: const Icon(Icons.add),
            label: const Text('Add vehicle'),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.busy,
    required this.onDelete,
    this.onSetActive,
  });

  final DriverVehicleOption vehicle;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback? onSetActive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  vehicle.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (vehicle.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceSm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    'Active',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            'Vehicle ID: ${vehicle.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Row(
            children: <Widget>[
              if (onSetActive != null) ...<Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: busy ? null : onSetActive,
                    child: const Text('Set active'),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDelete,
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BecomeDriverSheet extends StatefulWidget {
  const _BecomeDriverSheet();

  @override
  State<_BecomeDriverSheet> createState() => _BecomeDriverSheetState();
}

class _BecomeDriverSheetState extends State<_BecomeDriverSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _latraCtrl = TextEditingController();
  DateTime _licenseExpiry = DateTime.now().add(const Duration(days: 365));

  @override
  void dispose() {
    _licenseCtrl.dispose();
    _latraCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _licenseExpiry,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _licenseExpiry = picked);
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      BecomeDriverRequest(
        licenseNumber: _licenseCtrl.text.trim(),
        licenseExpiry: _licenseExpiry,
        latraPermitNumber: _latraCtrl.text.trim().isEmpty
            ? null
            : _latraCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg + insets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Driver profile details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppConstants.spaceLg),
            TextFormField(
              controller: _licenseCtrl,
              decoration: const InputDecoration(
                labelText: 'Licence number',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.trim().length < 3) {
                  return 'Enter a valid licence number';
                }
                return null;
              },
            ),
            const SizedBox(height: AppConstants.spaceMd),
            OutlinedButton.icon(
              onPressed: _pickExpiry,
              icon: const Icon(Icons.event),
              label: Text(
                'Licence expiry: ${_licenseExpiry.year.toString().padLeft(4, '0')}-'
                '${_licenseExpiry.month.toString().padLeft(2, '0')}-'
                '${_licenseExpiry.day.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            TextFormField(
              controller: _latraCtrl,
              decoration: const InputDecoration(
                labelText: 'LATRA permit number (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            FilledButton(
              onPressed: _submit,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet();

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _makeCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _plateCtrl = TextEditingController();
  final TextEditingController _capacityCtrl = TextEditingController(text: '4');

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      CreateVehicleRequest(
        make: _makeCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        year: int.parse(_yearCtrl.text.trim()),
        color: _colorCtrl.text.trim(),
        plateNumber: _plateCtrl.text.trim(),
        capacity: int.parse(_capacityCtrl.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg + insets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Add vehicle',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppConstants.spaceLg),
              TextFormField(
                controller: _makeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Make',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TextFormField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TextFormField(
                controller: _yearCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) {
                  final int? year = int.tryParse((value ?? '').trim());
                  if (year == null ||
                      year < 1990 ||
                      year > DateTime.now().year + 1) {
                    return 'Enter a valid year';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TextFormField(
                controller: _colorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Color',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TextFormField(
                controller: _plateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Plate number',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TextFormField(
                controller: _capacityCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seat capacity',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) {
                  final int? capacity = int.tryParse((value ?? '').trim());
                  if (capacity == null || capacity < 1 || capacity > 20) {
                    return 'Enter a valid seat capacity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppConstants.spaceLg),
              FilledButton(
                onPressed: _submit,
                child: const Text('Save vehicle'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }
}
