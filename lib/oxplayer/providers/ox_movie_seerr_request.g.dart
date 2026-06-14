// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_movie_seerr_request.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxMovieSeerrRequestHash() =>
    r'0d48594b890494675b2c80ac06d88e518fde4e39';

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

/// See also [oxMovieSeerrRequest].
@ProviderFor(oxMovieSeerrRequest)
const oxMovieSeerrRequestProvider = OxMovieSeerrRequestFamily();

/// See also [oxMovieSeerrRequest].
class OxMovieSeerrRequestFamily
    extends Family<AsyncValue<OxMovieSeerrRequestState?>> {
  /// See also [oxMovieSeerrRequest].
  const OxMovieSeerrRequestFamily();

  /// See also [oxMovieSeerrRequest].
  OxMovieSeerrRequestProvider call(
    int tmdbId,
  ) {
    return OxMovieSeerrRequestProvider(
      tmdbId,
    );
  }

  @override
  OxMovieSeerrRequestProvider getProviderOverride(
    covariant OxMovieSeerrRequestProvider provider,
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
  String? get name => r'oxMovieSeerrRequestProvider';
}

/// See also [oxMovieSeerrRequest].
class OxMovieSeerrRequestProvider
    extends AutoDisposeFutureProvider<OxMovieSeerrRequestState?> {
  /// See also [oxMovieSeerrRequest].
  OxMovieSeerrRequestProvider(
    int tmdbId,
  ) : this._internal(
          (ref) => oxMovieSeerrRequest(
            ref as OxMovieSeerrRequestRef,
            tmdbId,
          ),
          from: oxMovieSeerrRequestProvider,
          name: r'oxMovieSeerrRequestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxMovieSeerrRequestHash,
          dependencies: OxMovieSeerrRequestFamily._dependencies,
          allTransitiveDependencies:
              OxMovieSeerrRequestFamily._allTransitiveDependencies,
          tmdbId: tmdbId,
        );

  OxMovieSeerrRequestProvider._internal(
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
    FutureOr<OxMovieSeerrRequestState?> Function(
            OxMovieSeerrRequestRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: OxMovieSeerrRequestProvider._internal(
        (ref) => create(ref as OxMovieSeerrRequestRef),
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
  AutoDisposeFutureProviderElement<OxMovieSeerrRequestState?> createElement() {
    return _OxMovieSeerrRequestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxMovieSeerrRequestProvider && other.tmdbId == tmdbId;
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
mixin OxMovieSeerrRequestRef
    on AutoDisposeFutureProviderRef<OxMovieSeerrRequestState?> {
  /// The parameter `tmdbId` of this provider.
  int get tmdbId;
}

class _OxMovieSeerrRequestProviderElement
    extends AutoDisposeFutureProviderElement<OxMovieSeerrRequestState?>
    with OxMovieSeerrRequestRef {
  _OxMovieSeerrRequestProviderElement(super.provider);

  @override
  int get tmdbId => (origin as OxMovieSeerrRequestProvider).tmdbId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
