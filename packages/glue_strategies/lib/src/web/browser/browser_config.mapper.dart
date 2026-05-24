// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'browser_config.dart';

class BrowserBackendMapper extends EnumMapper<BrowserBackend> {
  BrowserBackendMapper._();

  static BrowserBackendMapper? _instance;
  static BrowserBackendMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BrowserBackendMapper._());
    }
    return _instance!;
  }

  static BrowserBackend fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  BrowserBackend decode(dynamic value) {
    switch (value) {
      case r'local':
        return BrowserBackend.local;
      case r'docker':
        return BrowserBackend.docker;
      case r'steel':
        return BrowserBackend.steel;
      case r'browserbase':
        return BrowserBackend.browserbase;
      case r'browserless':
        return BrowserBackend.browserless;
      case r'anchor':
        return BrowserBackend.anchor;
      case r'hyperbrowser':
        return BrowserBackend.hyperbrowser;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(BrowserBackend self) {
    switch (self) {
      case BrowserBackend.local:
        return r'local';
      case BrowserBackend.docker:
        return r'docker';
      case BrowserBackend.steel:
        return r'steel';
      case BrowserBackend.browserbase:
        return r'browserbase';
      case BrowserBackend.browserless:
        return r'browserless';
      case BrowserBackend.anchor:
        return r'anchor';
      case BrowserBackend.hyperbrowser:
        return r'hyperbrowser';
    }
  }
}

extension BrowserBackendMapperExtension on BrowserBackend {
  String toValue() {
    BrowserBackendMapper.ensureInitialized();
    return MapperContainer.globals.toValue<BrowserBackend>(this) as String;
  }
}

class BrowserConfigMapper extends ClassMapperBase<BrowserConfig> {
  BrowserConfigMapper._();

  static BrowserConfigMapper? _instance;
  static BrowserConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BrowserConfigMapper._());
      BrowserBackendMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BrowserConfig';

  static BrowserBackend _$backend(BrowserConfig v) => v.backend;
  static const Field<BrowserConfig, BrowserBackend> _f$backend = Field(
    'backend',
    _$backend,
    opt: true,
    def: BrowserBackend.local,
  );
  static bool _$headed(BrowserConfig v) => v.headed;
  static const Field<BrowserConfig, bool> _f$headed = Field(
    'headed',
    _$headed,
    opt: true,
    def: false,
  );
  static int _$navigationTimeoutSeconds(BrowserConfig v) =>
      v.navigationTimeoutSeconds;
  static const Field<BrowserConfig, int> _f$navigationTimeoutSeconds = Field(
    'navigationTimeoutSeconds',
    _$navigationTimeoutSeconds,
    opt: true,
    def: AppConstants.browserNavigationTimeoutSeconds,
  );
  static int _$actionTimeoutSeconds(BrowserConfig v) => v.actionTimeoutSeconds;
  static const Field<BrowserConfig, int> _f$actionTimeoutSeconds = Field(
    'actionTimeoutSeconds',
    _$actionTimeoutSeconds,
    opt: true,
    def: AppConstants.browserActionTimeoutSeconds,
  );
  static String _$dockerImage(BrowserConfig v) => v.dockerImage;
  static const Field<BrowserConfig, String> _f$dockerImage = Field(
    'dockerImage',
    _$dockerImage,
    opt: true,
    def: AppConstants.browserDockerImage,
  );
  static int _$dockerPort(BrowserConfig v) => v.dockerPort;
  static const Field<BrowserConfig, int> _f$dockerPort = Field(
    'dockerPort',
    _$dockerPort,
    opt: true,
    def: AppConstants.browserDockerPort,
  );
  static String? _$steelApiKey(BrowserConfig v) => v.steelApiKey;
  static const Field<BrowserConfig, String> _f$steelApiKey = Field(
    'steelApiKey',
    _$steelApiKey,
    opt: true,
  );
  static String? _$browserbaseApiKey(BrowserConfig v) => v.browserbaseApiKey;
  static const Field<BrowserConfig, String> _f$browserbaseApiKey = Field(
    'browserbaseApiKey',
    _$browserbaseApiKey,
    opt: true,
  );
  static String? _$browserbaseProjectId(BrowserConfig v) =>
      v.browserbaseProjectId;
  static const Field<BrowserConfig, String> _f$browserbaseProjectId = Field(
    'browserbaseProjectId',
    _$browserbaseProjectId,
    opt: true,
  );
  static String? _$browserlessBaseUrl(BrowserConfig v) => v.browserlessBaseUrl;
  static const Field<BrowserConfig, String> _f$browserlessBaseUrl = Field(
    'browserlessBaseUrl',
    _$browserlessBaseUrl,
    opt: true,
  );
  static String? _$browserlessApiKey(BrowserConfig v) => v.browserlessApiKey;
  static const Field<BrowserConfig, String> _f$browserlessApiKey = Field(
    'browserlessApiKey',
    _$browserlessApiKey,
    opt: true,
  );
  static String? _$anchorApiKey(BrowserConfig v) => v.anchorApiKey;
  static const Field<BrowserConfig, String> _f$anchorApiKey = Field(
    'anchorApiKey',
    _$anchorApiKey,
    opt: true,
  );
  static String? _$hyperbrowserApiKey(BrowserConfig v) => v.hyperbrowserApiKey;
  static const Field<BrowserConfig, String> _f$hyperbrowserApiKey = Field(
    'hyperbrowserApiKey',
    _$hyperbrowserApiKey,
    opt: true,
  );

  @override
  final MappableFields<BrowserConfig> fields = const {
    #backend: _f$backend,
    #headed: _f$headed,
    #navigationTimeoutSeconds: _f$navigationTimeoutSeconds,
    #actionTimeoutSeconds: _f$actionTimeoutSeconds,
    #dockerImage: _f$dockerImage,
    #dockerPort: _f$dockerPort,
    #steelApiKey: _f$steelApiKey,
    #browserbaseApiKey: _f$browserbaseApiKey,
    #browserbaseProjectId: _f$browserbaseProjectId,
    #browserlessBaseUrl: _f$browserlessBaseUrl,
    #browserlessApiKey: _f$browserlessApiKey,
    #anchorApiKey: _f$anchorApiKey,
    #hyperbrowserApiKey: _f$hyperbrowserApiKey,
  };

  static BrowserConfig _instantiate(DecodingData data) {
    return BrowserConfig(
      backend: data.dec(_f$backend),
      headed: data.dec(_f$headed),
      navigationTimeoutSeconds: data.dec(_f$navigationTimeoutSeconds),
      actionTimeoutSeconds: data.dec(_f$actionTimeoutSeconds),
      dockerImage: data.dec(_f$dockerImage),
      dockerPort: data.dec(_f$dockerPort),
      steelApiKey: data.dec(_f$steelApiKey),
      browserbaseApiKey: data.dec(_f$browserbaseApiKey),
      browserbaseProjectId: data.dec(_f$browserbaseProjectId),
      browserlessBaseUrl: data.dec(_f$browserlessBaseUrl),
      browserlessApiKey: data.dec(_f$browserlessApiKey),
      anchorApiKey: data.dec(_f$anchorApiKey),
      hyperbrowserApiKey: data.dec(_f$hyperbrowserApiKey),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BrowserConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BrowserConfig>(map);
  }

  static BrowserConfig fromJson(String json) {
    return ensureInitialized().decodeJson<BrowserConfig>(json);
  }
}

mixin BrowserConfigMappable {
  String toJson() {
    return BrowserConfigMapper.ensureInitialized().encodeJson<BrowserConfig>(
      this as BrowserConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return BrowserConfigMapper.ensureInitialized().encodeMap<BrowserConfig>(
      this as BrowserConfig,
    );
  }

  BrowserConfigCopyWith<BrowserConfig, BrowserConfig, BrowserConfig>
  get copyWith => _BrowserConfigCopyWithImpl<BrowserConfig, BrowserConfig>(
    this as BrowserConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return BrowserConfigMapper.ensureInitialized().stringifyValue(
      this as BrowserConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return BrowserConfigMapper.ensureInitialized().equalsValue(
      this as BrowserConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return BrowserConfigMapper.ensureInitialized().hashValue(
      this as BrowserConfig,
    );
  }
}

extension BrowserConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BrowserConfig, $Out> {
  BrowserConfigCopyWith<$R, BrowserConfig, $Out> get $asBrowserConfig =>
      $base.as((v, t, t2) => _BrowserConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BrowserConfigCopyWith<$R, $In extends BrowserConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    BrowserBackend? backend,
    bool? headed,
    int? navigationTimeoutSeconds,
    int? actionTimeoutSeconds,
    String? dockerImage,
    int? dockerPort,
    String? steelApiKey,
    String? browserbaseApiKey,
    String? browserbaseProjectId,
    String? browserlessBaseUrl,
    String? browserlessApiKey,
    String? anchorApiKey,
    String? hyperbrowserApiKey,
  });
  BrowserConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BrowserConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BrowserConfig, $Out>
    implements BrowserConfigCopyWith<$R, BrowserConfig, $Out> {
  _BrowserConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BrowserConfig> $mapper =
      BrowserConfigMapper.ensureInitialized();
  @override
  $R call({
    BrowserBackend? backend,
    bool? headed,
    int? navigationTimeoutSeconds,
    int? actionTimeoutSeconds,
    String? dockerImage,
    int? dockerPort,
    Object? steelApiKey = $none,
    Object? browserbaseApiKey = $none,
    Object? browserbaseProjectId = $none,
    Object? browserlessBaseUrl = $none,
    Object? browserlessApiKey = $none,
    Object? anchorApiKey = $none,
    Object? hyperbrowserApiKey = $none,
  }) => $apply(
    FieldCopyWithData({
      if (backend != null) #backend: backend,
      if (headed != null) #headed: headed,
      if (navigationTimeoutSeconds != null)
        #navigationTimeoutSeconds: navigationTimeoutSeconds,
      if (actionTimeoutSeconds != null)
        #actionTimeoutSeconds: actionTimeoutSeconds,
      if (dockerImage != null) #dockerImage: dockerImage,
      if (dockerPort != null) #dockerPort: dockerPort,
      if (steelApiKey != $none) #steelApiKey: steelApiKey,
      if (browserbaseApiKey != $none) #browserbaseApiKey: browserbaseApiKey,
      if (browserbaseProjectId != $none)
        #browserbaseProjectId: browserbaseProjectId,
      if (browserlessBaseUrl != $none) #browserlessBaseUrl: browserlessBaseUrl,
      if (browserlessApiKey != $none) #browserlessApiKey: browserlessApiKey,
      if (anchorApiKey != $none) #anchorApiKey: anchorApiKey,
      if (hyperbrowserApiKey != $none) #hyperbrowserApiKey: hyperbrowserApiKey,
    }),
  );
  @override
  BrowserConfig $make(CopyWithData data) => BrowserConfig(
    backend: data.get(#backend, or: $value.backend),
    headed: data.get(#headed, or: $value.headed),
    navigationTimeoutSeconds: data.get(
      #navigationTimeoutSeconds,
      or: $value.navigationTimeoutSeconds,
    ),
    actionTimeoutSeconds: data.get(
      #actionTimeoutSeconds,
      or: $value.actionTimeoutSeconds,
    ),
    dockerImage: data.get(#dockerImage, or: $value.dockerImage),
    dockerPort: data.get(#dockerPort, or: $value.dockerPort),
    steelApiKey: data.get(#steelApiKey, or: $value.steelApiKey),
    browserbaseApiKey: data.get(
      #browserbaseApiKey,
      or: $value.browserbaseApiKey,
    ),
    browserbaseProjectId: data.get(
      #browserbaseProjectId,
      or: $value.browserbaseProjectId,
    ),
    browserlessBaseUrl: data.get(
      #browserlessBaseUrl,
      or: $value.browserlessBaseUrl,
    ),
    browserlessApiKey: data.get(
      #browserlessApiKey,
      or: $value.browserlessApiKey,
    ),
    anchorApiKey: data.get(#anchorApiKey, or: $value.anchorApiKey),
    hyperbrowserApiKey: data.get(
      #hyperbrowserApiKey,
      or: $value.hyperbrowserApiKey,
    ),
  );

  @override
  BrowserConfigCopyWith<$R2, BrowserConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BrowserConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

