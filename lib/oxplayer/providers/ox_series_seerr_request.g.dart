// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_series_seerr_request.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxSeriesSeerrRequestHash() =>
    r'4b6f716eac0e3ceef8f0ca42b26b77d393a2cb91';

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

/// See also [oxSeriesSeerrRequest].
@ProviderFor(oxSeriesSeerrRequest)
const oxSeriesSeerrRequestProvider = OxSeriesSeerrRequestFamily();

/// See also [oxSeriesSeerrRequest].
class OxSeriesSeerrRequestFamily
    extends Family<AsyncValue<OxSeriesSeerrRequestState?>> {
  /// See also [oxSeriesSeerrRequest].
  const OxSeriesSeerrRequestFamily();

  /// See also [oxSeriesSeerrRequest].
  OxSeriesSeerrRequestProvider call(
    int tmdbId,
  ) {
    return OxSeriesSeerrRequestProvider(
      tmdbId,
    );
  }

  @override
  OxSeriesSeerrRequestProvider getProviderOverride(
    covariant OxSeriesSeerrRequestProvider provider,
  ) {
    return call(
      provider.tmdbId,
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
  String? get name => r'oxSeriesSeerrRequestProvider';
}

/// See also [oxSeriesSeerrRequest].
class OxSeriesSeerrRequestProvider
    extends AutoDisposeFutureProvider<OxSeriesSeerrRequestState?> {
  /// See also [oxSeriesSeerrRequest].
  OxSeriesSeerrRequestProvider(
    int tmdbId,
  ) : this._internal(
          (ref) => oxSeriesSeerrRequest(
            ref as OxSeriesSeerrRequestRef,
            tmdbId,
          ),
          from: oxSeriesSeerrRequestProvider,
          name: r'oxSeriesSeerrRequestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxSeriesSeerrRequestHash,
          dependencies: OxSeriesSeerrRequestFamily._dependencies,
          allTransitiveDependencies:
              OxSeriesSeerrRequestFamily._allTransitiveDependencies,
          tmdbId: tmdbId,
        );

  OxSeriesSeerrRequestProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.tmdbId,
  }) : super.internal();

  final int tmdbId;

  @override
  Override overrideWith(
    FutureOr<OxSeriesSeerrRequestState?> Function(
            OxSeriesSeerrRequestRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: OxSeriesSeerrRequestProvider._internal(
        (ref) => create(ref as OxSeriesSeerrRequestRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        tmdbId: tmdbId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<OxSeriesSeerrRequestState?> createElement() {
    return _OxSeriesSeerrRequestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxSeriesSeerrRequestProvider && other.tmdbId == tmdbId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, tmdbId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OxSeriesSeerrRequestRef
    on AutoDisposeFutureProviderRef<OxSeriesSeerrRequestState?> {
  /// The parameter `tmdbId` of this provider.
  int get tmdbId;
}

class _OxSeriesSeerrRequestProviderElement
    extends AutoDisposeFutureProviderElement<OxSeriesSeerrRequestState?>
    with OxSeriesSeerrRequestRef {
  _OxSeriesSeerrRequestProviderElement(super.provider);

  @override
  int get tmdbId => (origin as OxSeriesSeerrRequestProvider).tmdbId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
