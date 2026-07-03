// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_tmdb_interest.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxTmdbInterestHash() => r'8450bc57934366b9909c8a1abea45afbc701b114';

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

abstract class _$OxTmdbInterest
    extends BuildlessAutoDisposeAsyncNotifier<OxTmdbInterestState> {
  late final int tmdbId;
  late final SeerrMediaType mediaType;

  FutureOr<OxTmdbInterestState> build(
    int tmdbId,
    SeerrMediaType mediaType,
  );
}

/// See also [OxTmdbInterest].
@ProviderFor(OxTmdbInterest)
const oxTmdbInterestProvider = OxTmdbInterestFamily();

/// See also [OxTmdbInterest].
class OxTmdbInterestFamily extends Family<AsyncValue<OxTmdbInterestState>> {
  /// See also [OxTmdbInterest].
  const OxTmdbInterestFamily();

  /// See also [OxTmdbInterest].
  OxTmdbInterestProvider call(
    int tmdbId,
    SeerrMediaType mediaType,
  ) {
    return OxTmdbInterestProvider(
      tmdbId,
      mediaType,
    );
  }

  @override
  OxTmdbInterestProvider getProviderOverride(
    covariant OxTmdbInterestProvider provider,
  ) {
    return call(
      provider.tmdbId,
      provider.mediaType,
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
  String? get name => r'oxTmdbInterestProvider';
}

/// See also [OxTmdbInterest].
class OxTmdbInterestProvider extends AutoDisposeAsyncNotifierProviderImpl<
    OxTmdbInterest, OxTmdbInterestState> {
  /// See also [OxTmdbInterest].
  OxTmdbInterestProvider(
    int tmdbId,
    SeerrMediaType mediaType,
  ) : this._internal(
          () => OxTmdbInterest()
            ..tmdbId = tmdbId
            ..mediaType = mediaType,
          from: oxTmdbInterestProvider,
          name: r'oxTmdbInterestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxTmdbInterestHash,
          dependencies: OxTmdbInterestFamily._dependencies,
          allTransitiveDependencies:
              OxTmdbInterestFamily._allTransitiveDependencies,
          tmdbId: tmdbId,
          mediaType: mediaType,
        );

  OxTmdbInterestProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.tmdbId,
    required this.mediaType,
  }) : super.internal();

  final int tmdbId;
  final SeerrMediaType mediaType;

  @override
  FutureOr<OxTmdbInterestState> runNotifierBuild(
    covariant OxTmdbInterest notifier,
  ) {
    return notifier.build(
      tmdbId,
      mediaType,
    );
  }

  @override
  Override overrideWith(OxTmdbInterest Function() create) {
    return ProviderOverride(
      origin: this,
      override: OxTmdbInterestProvider._internal(
        () => create()
          ..tmdbId = tmdbId
          ..mediaType = mediaType,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        tmdbId: tmdbId,
        mediaType: mediaType,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<OxTmdbInterest, OxTmdbInterestState>
      createElement() {
    return _OxTmdbInterestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxTmdbInterestProvider &&
        other.tmdbId == tmdbId &&
        other.mediaType == mediaType;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, tmdbId.hashCode);
    hash = _SystemHash.combine(hash, mediaType.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OxTmdbInterestRef
    on AutoDisposeAsyncNotifierProviderRef<OxTmdbInterestState> {
  /// The parameter `tmdbId` of this provider.
  int get tmdbId;

  /// The parameter `mediaType` of this provider.
  SeerrMediaType get mediaType;
}

class _OxTmdbInterestProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<OxTmdbInterest,
        OxTmdbInterestState> with OxTmdbInterestRef {
  _OxTmdbInterestProviderElement(super.provider);

  @override
  int get tmdbId => (origin as OxTmdbInterestProvider).tmdbId;
  @override
  SeerrMediaType get mediaType => (origin as OxTmdbInterestProvider).mediaType;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
