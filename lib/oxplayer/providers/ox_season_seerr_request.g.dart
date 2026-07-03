// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_season_seerr_request.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxSeasonSeerrRequestHash() =>
    r'f594b03487724583d7eaeab5700014551ca5beee';

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

/// See also [oxSeasonSeerrRequest].
@ProviderFor(oxSeasonSeerrRequest)
const oxSeasonSeerrRequestProvider = OxSeasonSeerrRequestFamily();

/// See also [oxSeasonSeerrRequest].
class OxSeasonSeerrRequestFamily
    extends Family<AsyncValue<OxSeasonSeerrRequestState?>> {
  /// See also [oxSeasonSeerrRequest].
  const OxSeasonSeerrRequestFamily();

  /// See also [oxSeasonSeerrRequest].
  OxSeasonSeerrRequestProvider call(
    ({int seasonNumber, String seriesId}) args,
  ) {
    return OxSeasonSeerrRequestProvider(
      args,
    );
  }

  @override
  OxSeasonSeerrRequestProvider getProviderOverride(
    covariant OxSeasonSeerrRequestProvider provider,
  ) {
    return call(
      provider.args,
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
  String? get name => r'oxSeasonSeerrRequestProvider';
}

/// See also [oxSeasonSeerrRequest].
class OxSeasonSeerrRequestProvider
    extends AutoDisposeFutureProvider<OxSeasonSeerrRequestState?> {
  /// See also [oxSeasonSeerrRequest].
  OxSeasonSeerrRequestProvider(
    ({int seasonNumber, String seriesId}) args,
  ) : this._internal(
          (ref) => oxSeasonSeerrRequest(
            ref as OxSeasonSeerrRequestRef,
            args,
          ),
          from: oxSeasonSeerrRequestProvider,
          name: r'oxSeasonSeerrRequestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxSeasonSeerrRequestHash,
          dependencies: OxSeasonSeerrRequestFamily._dependencies,
          allTransitiveDependencies:
              OxSeasonSeerrRequestFamily._allTransitiveDependencies,
          args: args,
        );

  OxSeasonSeerrRequestProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.args,
  }) : super.internal();

  final ({int seasonNumber, String seriesId}) args;

  @override
  Override overrideWith(
    FutureOr<OxSeasonSeerrRequestState?> Function(
            OxSeasonSeerrRequestRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: OxSeasonSeerrRequestProvider._internal(
        (ref) => create(ref as OxSeasonSeerrRequestRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        args: args,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<OxSeasonSeerrRequestState?> createElement() {
    return _OxSeasonSeerrRequestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxSeasonSeerrRequestProvider && other.args == args;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, args.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OxSeasonSeerrRequestRef
    on AutoDisposeFutureProviderRef<OxSeasonSeerrRequestState?> {
  /// The parameter `args` of this provider.
  ({int seasonNumber, String seriesId}) get args;
}

class _OxSeasonSeerrRequestProviderElement
    extends AutoDisposeFutureProviderElement<OxSeasonSeerrRequestState?>
    with OxSeasonSeerrRequestRef {
  _OxSeasonSeerrRequestProviderElement(super.provider);

  @override
  ({int seasonNumber, String seriesId}) get args =>
      (origin as OxSeasonSeerrRequestProvider).args;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
