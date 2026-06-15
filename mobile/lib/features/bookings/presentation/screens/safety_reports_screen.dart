import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../data/models/safety_report_models.dart';
import '../providers/booking_provider.dart';

class SafetyReportsScreen extends ConsumerWidget {
  const SafetyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SafetyReportDto>> reportsAsync =
        ref.watch(safetyReportsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Safety reports')),
      body: reportsAsync.when(
        loading: () => const LoadingView(message: 'Loading safety reports'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(safetyReportsProvider),
        ),
        data: (List<SafetyReportDto> reports) {
          if (reports.isEmpty) {
            return const EmptyView(
              icon: Icons.verified_user_outlined,
              title: 'No safety reports',
              subtitle: 'Reports submitted from trip screens will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(safetyReportsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              itemBuilder: (BuildContext context, int index) {
                final SafetyReportDto report = reports[index];
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(
                      report.status == 'under_review'
                          ? Icons.manage_search
                          : Icons.report_problem_outlined,
                    ),
                    title: Text(report.reason ?? 'Safety report'),
                    subtitle: Text(
                      <String>[
                        report.status.replaceAll('_', ' '),
                        DateFormat('d MMM yyyy, HH:mm').format(report.createdAt),
                        if ((report.pickupName ?? '').isNotEmpty)
                          report.pickupName!,
                        if ((report.dropoffName ?? '').isNotEmpty)
                          report.dropoffName!,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/bookings/${report.bookingId}'),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: reports.length,
            ),
          );
        },
      ),
    );
  }
}
