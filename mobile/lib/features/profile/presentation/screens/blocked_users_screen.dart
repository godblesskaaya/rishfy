import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../domain/blocked_user.dart';
import '../providers/profile_provider.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BlockedUser>> blocksAsync =
        ref.watch(blockedUsersProvider);
    final BlockedUserActionState actionState =
        ref.watch(blockedUserActionProvider);

    ref.listen<BlockedUserActionState>(
      blockedUserActionProvider,
      (BlockedUserActionState? previous, BlockedUserActionState next) {
        if (previous?.status == next.status) return;
        if (next.status == BlockedUserActionStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Blocked users updated.')),
          );
        }
        if (next.status == BlockedUserActionStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.error ?? 'Could not update blocks.')),
          );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: blocksAsync.when(
        loading: () => const LoadingView(message: 'Loading blocked users'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        data: (List<BlockedUser> blocks) {
          if (blocks.isEmpty) {
            return EmptyView(
              icon: Icons.block,
              title: 'No blocked users',
              subtitle:
                  'People you block from trip screens will appear here.',
              actionLabel: 'Get support',
              onAction: () => context.push('/help'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(blockedUsersProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              itemCount: blocks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                return _BlockedUserTile(
                  block: blocks[index],
                  busy: actionState.status == BlockedUserActionStatus.loading,
                  onUnblock: () => _confirmUnblock(context, ref, blocks[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmUnblock(
    BuildContext context,
    WidgetRef ref,
    BlockedUser block,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Unblock user?'),
        content: Text('${block.displayName} may be matched with you again.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(blockedUserActionProvider.notifier)
        .unblock(block.blockedUserId);
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.block,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUser block;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final String blockedAt =
        DateFormat('d MMM yyyy').format(block.createdAt.toLocal());

    return Card(
      elevation: 0,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.block)),
        title: Text(block.displayName),
        subtitle: Text(
          block.reason == null
              ? 'Blocked $blockedAt'
              : 'Blocked $blockedAt · ${block.reason}',
        ),
        trailing: TextButton(
          onPressed: busy ? null : onUnblock,
          child: const Text('Unblock'),
        ),
      ),
    );
  }
}
