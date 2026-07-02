// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_catalog_follow.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxCatalogFollowStatusHash() =>
    r'2995dce0bceaacf210e6602b832f698e526146f3';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$OxCatalogFollowStatus
    extends BuildlessAutoDisposeAsyncNotifier<bool> {
  late final String catalogId;

  FutureOr<bool> build(
    String catalogId,
  );
}

/// See also [OxCatalogFollowStatus].
@ProviderFor(OxCatalogFollowStatus)
const oxCatalogFollowStatusProvider = OxCatalogFollowStatusFamily();

/// See also [OxCatalogFollowStatus].
class OxCatalogFollowStatusFamily extends Family<AsyncValue<bool>> {
  /// See also [OxCatalogFollowStatus].
  const OxCatalogFollowStatusFamily();

  /// See also [OxCatalogFollowStatus].
  OxCatalogFollowStatusProvider call(
    String catalogId,
  ) {
    return OxCatalogFollowStatusProvider(
      catalogId,
    );
  }

  @override
  OxCatalogFollowStatusProvider getProviderOverride(
    covariant OxCatalogFollowStatusProvider provider,
  ) {
    return call(
      provider.catalogId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'oxCatalogFollowStatusProvider';
}

/// See also [OxCatalogFollowStatus].
class OxCatalogFollowStatusProvider
    extends AutoDisposeAsyncNotifierProviderImpl<OxCatalogFollowStatus, bool> {
  /// See also [OxCatalogFollowStatus].
  OxCatalogFollowStatusProvider(
    String catalogId,
  ) : this._internal(
          () => OxCatalogFollowStatus()..catalogId = catalogId,
          from: oxCatalogFollowStatusProvider,
          name: r'oxCatalogFollowStatusProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxCatalogFollowStatusHash,
          dependencies: OxCatalogFollowStatusFamily._dependencies,
          allTransitiveDependencies:
              OxCatalogFollowStatusFamily._allTransitiveDependencies,
          catalogId: catalogId,
        );

  OxCatalogFollowStatusProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.catalogId,
  }) : super.internal();

  final String catalogId;

  @override
  FutureOr<bool> runNotifierBuild(
    covariant OxCatalogFollowStatus notifier,
  ) {
    return notifier.build(
      catalogId,
    );
  }

  @override
  Override overrideWith(OxCatalogFollowStatus Function() create) {
    return ProviderOverride(
      origin: this,
      override: OxCatalogFollowStatusProvider._internal(
        () => create()..catalogId = catalogId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        catalogId: catalogId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<OxCatalogFollowStatus, bool>
      createElement() {
    return _OxCatalogFollowStatusProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxCatalogFollowStatusProvider &&
        other.catalogId == catalogId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, catalogId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OxCatalogFollowStatusRef on AutoDisposeAsyncNotifierProviderRef<bool> {
  /// The parameter `catalogId` of this provider.
  String get catalogId;
}

class _OxCatalogFollowStatusProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<OxCatalogFollowStatus, bool>
    with OxCatalogFollowStatusRef {
  _OxCatalogFollowStatusProviderElement(super.provider);

  @override
  String get catalogId => (origin as OxCatalogFollowStatusProvider).catalogId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
