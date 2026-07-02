// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_media_issue_context.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$oxMediaIssueContextHash() =>
    r'6cbd3a2bfee16c2933958f6aaed52e2a46b0957a';

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

/// See also [oxMediaIssueContext].
@ProviderFor(oxMediaIssueContext)
const oxMediaIssueContextProvider = OxMediaIssueContextFamily();

/// See also [oxMediaIssueContext].
class OxMediaIssueContextFamily
    extends Family<AsyncValue<OxMediaIssueContext>> {
  /// See also [oxMediaIssueContext].
  const OxMediaIssueContextFamily();

  /// See also [oxMediaIssueContext].
  OxMediaIssueContextProvider call(
    OxMediaIssueTarget target,
  ) {
    return OxMediaIssueContextProvider(
      target,
    );
  }

  @override
  OxMediaIssueContextProvider getProviderOverride(
    covariant OxMediaIssueContextProvider provider,
  ) {
    return call(
      provider.target,
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
  String? get name => r'oxMediaIssueContextProvider';
}

/// See also [oxMediaIssueContext].
class OxMediaIssueContextProvider
    extends AutoDisposeFutureProvider<OxMediaIssueContext> {
  /// See also [oxMediaIssueContext].
  OxMediaIssueContextProvider(
    OxMediaIssueTarget target,
  ) : this._internal(
          (ref) => oxMediaIssueContext(
            ref as OxMediaIssueContextRef,
            target,
          ),
          from: oxMediaIssueContextProvider,
          name: r'oxMediaIssueContextProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$oxMediaIssueContextHash,
          dependencies: OxMediaIssueContextFamily._dependencies,
          allTransitiveDependencies:
              OxMediaIssueContextFamily._allTransitiveDependencies,
          target: target,
        );

  OxMediaIssueContextProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.target,
  }) : super.internal();

  final OxMediaIssueTarget target;

  @override
  Override overrideWith(
    FutureOr<OxMediaIssueContext> Function(OxMediaIssueContextRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: OxMediaIssueContextProvider._internal(
        (ref) => create(ref as OxMediaIssueContextRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        target: target,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<OxMediaIssueContext> createElement() {
    return _OxMediaIssueContextProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OxMediaIssueContextProvider && other.target == target;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, target.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OxMediaIssueContextRef
    on AutoDisposeFutureProviderRef<OxMediaIssueContext> {
  /// The parameter `target` of this provider.
  OxMediaIssueTarget get target;
}

class _OxMediaIssueContextProviderElement
    extends AutoDisposeFutureProviderElement<OxMediaIssueContext>
    with OxMediaIssueContextRef {
  _OxMediaIssueContextProviderElement(super.provider);

  @override
  OxMediaIssueTarget get target =>
      (origin as OxMediaIssueContextProvider).target;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
