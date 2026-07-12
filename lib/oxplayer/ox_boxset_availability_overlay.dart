import 'package:flutter/material.dart';

import 'package:fladder/models/boxset_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

const _tagCollectionComplete = 'ox-collection-complete';
const _tagCollectionPartial = 'ox-collection-partial';
const _tagCollectionMissing = 'ox-collection-missing';
const _tagCatalogAvailable = 'ox-catalog-available';
const _tagCatalogMissing = 'ox-catalog-missing';

/// Seerr-style top-right badge for box set shelf cards and collection movie tiles.
Widget? oxCatalogAvailabilityOverlay(ItemBaseModel poster) {
  if (!OxplayerConfig.isEnabled) return null;
  final tags = poster.overview.tags;
  if (tags.isEmpty) return null;

  final bool? available = switch (true) {
    true when tags.contains(_tagCollectionComplete) || tags.contains(_tagCatalogAvailable) => true,
    true when tags.contains(_tagCollectionPartial) => null,
    true when tags.contains(_tagCollectionMissing) || tags.contains(_tagCatalogMissing) => false,
    _ => null,
  };
  if (available == null && !tags.contains(_tagCollectionPartial)) {
    return null;
  }

  final Color color;
  final IconData icon;
  if (available == true) {
    color = Colors.green.shade700;
    icon = IconsaxPlusLinear.import_3;
  } else if (available == false) {
    color = Colors.red.shade700;
    icon = Icons.remove_rounded;
  } else {
    color = Colors.orange.shade800;
    icon = IconsaxPlusLinear.box;
  }

  return Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    ),
  );
}

bool oxIsBoxSetShelfItem(ItemBaseModel item) => item is BoxSetModel;
