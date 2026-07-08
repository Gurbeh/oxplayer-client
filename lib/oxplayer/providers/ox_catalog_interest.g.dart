// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_catalog_interest.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxCatalogInterestHash() => r'09947559c13ebe29c8fa9c47fcee91d894ad530b';

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

abstract class _$OxCatalogInterest
    extends BuildlessAutoDisposeAsyncNotifier<OxCatalogInterestState> {
  late final String catalogId;

  FutureOr<OxCatalogInterestState> build(
    String catalogId,
  );
}

/// See also [OxCatalogInterest].
@ProviderFor(OxCatalogInterest)
const oxCatalogInterestProvider = OxCatalogInterestFamily();

/// See also [OxCatalogInterest].
class OxCatalogInterestFamily
    extends Family<AsyncValue<OxCatalogInterestState>> {
  /// See also [OxCatalogInterest].
  const OxCatalogInterestFamily();

  /// See also [OxCatalogInterest].
  OxCatalogInterestProvider call(
    String catalogId,
  ) {
    return OxCatalogInterestProvider(
      catalogId,
    );
  }

  @override
  OxCatalogInterestProvider getProviderOverride(
    covariant OxCatalogInterestProvider provider,
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
  String? get name => r'oxCatalogInterestProvider';
}

/// See also [OxCatalogInterest].
class OxCatalogInterestProvider extends AutoDisposeAsyncNotifierProviderImpl<
    OxCatalogInterest, OxCatalogInterestState> {
  /// See also [OxCatalogInterest].
  OxCatalogInterestProvider(
    String catalogId,
  ) : this._internal(
          () => OxCatalogInterest()..catalogId = catalogId,
          from: oxCatalogInterestProvider,
          name: r'oxCatalogInterestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxCatalogInterestHash,
          dependencies: OxCatalogInterestFamily._dependencies,
          allTransitiveDependencies:
              OxCatalogInterestFamily._allTransitiveDependencies,
          catalogId: catalogId,
        );

  OxCatalogInterestProvider._internal(
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
  FutureOr<OxCatalogInterestState> runNotifierBuild(
    covariant OxCatalogInterest notifier,
  ) {
    return notifier.build(
      catalogId,
    );
  }

  @override
  Override overrideWith(OxCatalogInterest Function() create) {
    return ProviderOverride(
      origin: this,
      override: OxCatalogInterestProvider._internal(
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
  AutoDisposeAsyncNotifierProviderElement<OxCatalogInterest,
      OxCatalogInterestState> createElement() {
    return _OxCatalogInterestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxCatalogInterestProvider && other.catalogId == catalogId;
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
mixin OxCatalogInterestRef
    on AutoDisposeAsyncNotifierProviderRef<OxCatalogInterestState> {
  /// The parameter `catalogId` of this provider.
  String get catalogId;
}

class _OxCatalogInterestProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<OxCatalogInterest,
        OxCatalogInterestState> with OxCatalogInterestRef {
  _OxCatalogInterestProviderElement(super.provider);

  @override
  String get catalogId => (origin as OxCatalogInterestProvider).catalogId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
