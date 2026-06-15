import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../domain/favorite_driver.dart';
import '../providers/profile_provider.dart';

class FavoriteDriversScreen extends ConsumerWidget {
  const FavoriteDriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavoriteDriver>> favoritesAsync =
        ref.watch(favoriteDriversProvider);
    final FavoriteDriverActionState actionState =
        ref.watch(favoriteDriverActionProvider);

    ref.listen<FavoriteDriverActionState>(
      favoriteDriverActionProvider,
      (FavoriteDriverActionState? previous, FavoriteDriverActionState next) {
        if (previous?.status == next.status) return;
        if (next.status == FavoriteDriverActionStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Favorite drivers updated.')),
          );
        }
        if (next.status == FavoriteDriverActionStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.error ?? 'Could not update favorite.')),
          );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Favorite drivers')),
      body: favoritesAsync.when(
        loading: () => const LoadingView(message: 'Loading favorite drivers'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(favoriteDriversProvider),
        ),
        data: (List<FavoriteDriver> favorites) {
          if (favorites.isEmpty) {
            return EmptyView(
              icon: Icons.favorite_border,
              title: 'No favorite drivers yet',
              subtitle:
                  'Add trusted drivers after rides so you can find them again faster.',
              actionLabel: 'Find routes',
              onAction: () => context.go('/search'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(favoriteDriversProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                return _FavoriteDriverTile(
                  favorite: favorites[index],
                  busy: actionState.status ==
                      FavoriteDriverActionStatus.loading,
                  onRemove: () => _confirmRemove(context, ref, favorites[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    FavoriteDriver favorite,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove favorite?'),
        content: Text('Remove ${favorite.displayName} from your favorites?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(favoriteDriverActionProvider.notifier)
        .remove(favorite.driverUserId);
  }
}

class _FavoriteDriverTile extends StatelessWidget {
  const _FavoriteDriverTile({
    required this.favorite,
    required this.busy,
    required this.onRemove,
  });

  final FavoriteDriver favorite;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String savedAt =
        DateFormat('d MMM yyyy').format(favorite.createdAt.toLocal());
    final String rating = favorite.ratingCount > 0
        ? '${favorite.ratingAverage.toStringAsFixed(1)} (${favorite.ratingCount})'
        : 'No public rating yet';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/drivers/${favorite.driverUserId}'),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  _initials(favorite.displayName),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      favorite.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: <Widget>[
                        _Meta(icon: Icons.star_border, label: rating),
                        _Meta(
                          icon: Icons.bookmark_border,
                          label: 'Saved $savedAt',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove favorite',
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.favorite),
                color: scheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
