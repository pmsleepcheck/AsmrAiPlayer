import 'package:flutter/material.dart';
import 'package:aaplay/core/theme/app_radius.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aaplay/core/image/cache/image_cache_manager.dart';
import 'package:aaplay/core/settings/no_image_mode.dart';

class WorkCover extends StatelessWidget {
  final String imageUrl;
  final int workId;
  final String sourceId;
  final String? releaseDate;
  final String? heroTag;

  const WorkCover({
    super.key,
    required this.imageUrl,
    required this.workId,
    required this.sourceId,
    this.releaseDate,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = withNoImageMode((context, noImage) {
      return Stack(
        children: [
          AspectRatio(
            aspectRatio: 195 / 146,
            child: noImage
                ? Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final dpr = MediaQuery.of(context).devicePixelRatio;
                      final w = constraints.maxWidth;
                      int? cacheWidth;
                      if (w.isFinite && w > 0) {
                        final p = (w * dpr).round();
                        cacheWidth = p < 1 ? 1 : p;
                      }
                      return CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: cacheWidth,
                        fadeInDuration: const Duration(milliseconds: 150),
                        cacheManager: ImageCacheManager.instance,
                      );
                    },
                  ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                sourceId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                    ),
              ),
            ),
          ),
          if (releaseDate != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  releaseDate!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                ),
              ),
            ),
        ],
      );
    });

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: content,
      );
    }

    return content;
  }
}
