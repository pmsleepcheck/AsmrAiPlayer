import 'package:flutter/material.dart';
import 'package:aaplay/core/settings/no_image_mode.dart';
import 'package:aaplay/core/theme/app_radius.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aaplay/widgets/common/skeleton_pulse.dart';
import 'package:aaplay/core/image/cache/image_cache_manager.dart';

class MiniPlayerCover extends StatelessWidget {
  final String? coverUrl;
  final double size;

  const MiniPlayerCover({
    super.key,
    this.coverUrl,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return withNoImageMode((context, noImage) {
      if (coverUrl == null || noImage) {
        return _buildEmptyPlaceholder(context, noImage: noImage);
      }

      final dpr = MediaQuery.of(context).devicePixelRatio;
      int? cacheWidth;
      if (size.isFinite && size > 0) {
        final p = (size * dpr).round();
        cacheWidth = p < 1 ? 1 : p;
      }
      return ClipRRect(
        borderRadius: AppRadius.smAll,
        child: CachedNetworkImage(
          imageUrl: coverUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 150),
          cacheManager: ImageCacheManager.instance,
          placeholder: (context, url) => _buildPlaceholder(context),
          errorWidget: (context, url, error) => _buildErrorWidget(),
        ),
      );
    });
  }

  Widget _buildEmptyPlaceholder(BuildContext context, {bool noImage = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: noImage ? cs.surfaceContainerHighest : Colors.grey[200],
        borderRadius: AppRadius.smAll,
      ),
      child: Icon(
        noImage ? Icons.image_outlined : Icons.music_note,
        color: noImage ? cs.onSurfaceVariant : Colors.grey,
        size: noImage ? size * 0.5 : null,
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return SkeletonPulse(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.smAll,
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: AppRadius.smAll,
      ),
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
