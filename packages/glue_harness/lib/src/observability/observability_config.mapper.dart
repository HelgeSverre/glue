// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'observability_config.dart';

class OtelConfigMapper extends ClassMapperBase<OtelConfig> {
  OtelConfigMapper._();

  static OtelConfigMapper? _instance;
  static OtelConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OtelConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'OtelConfig';

  static bool _$enabled(OtelConfig v) => v.enabled;
  static const Field<OtelConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: false,
  );
  static String? _$endpoint(OtelConfig v) => v.endpoint;
  static const Field<OtelConfig, String> _f$endpoint = Field(
    'endpoint',
    _$endpoint,
    opt: true,
  );
  static Map<String, String> _$headers(OtelConfig v) => v.headers;
  static const Field<OtelConfig, Map<String, String>> _f$headers = Field(
    'headers',
    _$headers,
    opt: true,
    def: const {},
  );
  static String _$serviceName(OtelConfig v) => v.serviceName;
  static const Field<OtelConfig, String> _f$serviceName = Field(
    'serviceName',
    _$serviceName,
    opt: true,
    def: 'glue',
  );
  static Map<String, String> _$resourceAttributes(OtelConfig v) =>
      v.resourceAttributes;
  static const Field<OtelConfig, Map<String, String>> _f$resourceAttributes =
      Field(
        'resourceAttributes',
        _$resourceAttributes,
        opt: true,
        def: const {},
      );
  static int _$timeoutMilliseconds(OtelConfig v) => v.timeoutMilliseconds;
  static const Field<OtelConfig, int> _f$timeoutMilliseconds = Field(
    'timeoutMilliseconds',
    _$timeoutMilliseconds,
    opt: true,
    def: 10000,
  );

  @override
  final MappableFields<OtelConfig> fields = const {
    #enabled: _f$enabled,
    #endpoint: _f$endpoint,
    #headers: _f$headers,
    #serviceName: _f$serviceName,
    #resourceAttributes: _f$resourceAttributes,
    #timeoutMilliseconds: _f$timeoutMilliseconds,
  };

  static OtelConfig _instantiate(DecodingData data) {
    return OtelConfig(
      enabled: data.dec(_f$enabled),
      endpoint: data.dec(_f$endpoint),
      headers: data.dec(_f$headers),
      serviceName: data.dec(_f$serviceName),
      resourceAttributes: data.dec(_f$resourceAttributes),
      timeoutMilliseconds: data.dec(_f$timeoutMilliseconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OtelConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OtelConfig>(map);
  }

  static OtelConfig fromJson(String json) {
    return ensureInitialized().decodeJson<OtelConfig>(json);
  }
}

mixin OtelConfigMappable {
  String toJson() {
    return OtelConfigMapper.ensureInitialized().encodeJson<OtelConfig>(
      this as OtelConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return OtelConfigMapper.ensureInitialized().encodeMap<OtelConfig>(
      this as OtelConfig,
    );
  }

  OtelConfigCopyWith<OtelConfig, OtelConfig, OtelConfig> get copyWith =>
      _OtelConfigCopyWithImpl<OtelConfig, OtelConfig>(
        this as OtelConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return OtelConfigMapper.ensureInitialized().stringifyValue(
      this as OtelConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return OtelConfigMapper.ensureInitialized().equalsValue(
      this as OtelConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return OtelConfigMapper.ensureInitialized().hashValue(this as OtelConfig);
  }
}

extension OtelConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OtelConfig, $Out> {
  OtelConfigCopyWith<$R, OtelConfig, $Out> get $asOtelConfig =>
      $base.as((v, t, t2) => _OtelConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class OtelConfigCopyWith<$R, $In extends OtelConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get headers;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get resourceAttributes;
  $R call({
    bool? enabled,
    String? endpoint,
    Map<String, String>? headers,
    String? serviceName,
    Map<String, String>? resourceAttributes,
    int? timeoutMilliseconds,
  });
  OtelConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _OtelConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OtelConfig, $Out>
    implements OtelConfigCopyWith<$R, OtelConfig, $Out> {
  _OtelConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<OtelConfig> $mapper =
      OtelConfigMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get headers => MapCopyWith(
    $value.headers,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(headers: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get resourceAttributes => MapCopyWith(
    $value.resourceAttributes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(resourceAttributes: v),
  );
  @override
  $R call({
    bool? enabled,
    Object? endpoint = $none,
    Map<String, String>? headers,
    String? serviceName,
    Map<String, String>? resourceAttributes,
    int? timeoutMilliseconds,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (endpoint != $none) #endpoint: endpoint,
      if (headers != null) #headers: headers,
      if (serviceName != null) #serviceName: serviceName,
      if (resourceAttributes != null) #resourceAttributes: resourceAttributes,
      if (timeoutMilliseconds != null)
        #timeoutMilliseconds: timeoutMilliseconds,
    }),
  );
  @override
  OtelConfig $make(CopyWithData data) => OtelConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    endpoint: data.get(#endpoint, or: $value.endpoint),
    headers: data.get(#headers, or: $value.headers),
    serviceName: data.get(#serviceName, or: $value.serviceName),
    resourceAttributes: data.get(
      #resourceAttributes,
      or: $value.resourceAttributes,
    ),
    timeoutMilliseconds: data.get(
      #timeoutMilliseconds,
      or: $value.timeoutMilliseconds,
    ),
  );

  @override
  OtelConfigCopyWith<$R2, OtelConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _OtelConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ObservabilityConfigMapper extends ClassMapperBase<ObservabilityConfig> {
  ObservabilityConfigMapper._();

  static ObservabilityConfigMapper? _instance;
  static ObservabilityConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ObservabilityConfigMapper._());
      OtelConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ObservabilityConfig';

  static bool _$debug(ObservabilityConfig v) => v.debug;
  static const Field<ObservabilityConfig, bool> _f$debug = Field(
    'debug',
    _$debug,
    opt: true,
    def: false,
  );
  static int _$maxBodyBytes(ObservabilityConfig v) => v.maxBodyBytes;
  static const Field<ObservabilityConfig, int> _f$maxBodyBytes = Field(
    'maxBodyBytes',
    _$maxBodyBytes,
    opt: true,
    def: 65536,
  );
  static bool _$redact(ObservabilityConfig v) => v.redact;
  static const Field<ObservabilityConfig, bool> _f$redact = Field(
    'redact',
    _$redact,
    opt: true,
    def: true,
  );
  static OtelConfig _$otel(ObservabilityConfig v) => v.otel;
  static const Field<ObservabilityConfig, OtelConfig> _f$otel = Field(
    'otel',
    _$otel,
    opt: true,
    def: const OtelConfig(),
  );

  @override
  final MappableFields<ObservabilityConfig> fields = const {
    #debug: _f$debug,
    #maxBodyBytes: _f$maxBodyBytes,
    #redact: _f$redact,
    #otel: _f$otel,
  };

  static ObservabilityConfig _instantiate(DecodingData data) {
    return ObservabilityConfig(
      debug: data.dec(_f$debug),
      maxBodyBytes: data.dec(_f$maxBodyBytes),
      redact: data.dec(_f$redact),
      otel: data.dec(_f$otel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ObservabilityConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ObservabilityConfig>(map);
  }

  static ObservabilityConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ObservabilityConfig>(json);
  }
}

mixin ObservabilityConfigMappable {
  String toJson() {
    return ObservabilityConfigMapper.ensureInitialized()
        .encodeJson<ObservabilityConfig>(this as ObservabilityConfig);
  }

  Map<String, dynamic> toMap() {
    return ObservabilityConfigMapper.ensureInitialized()
        .encodeMap<ObservabilityConfig>(this as ObservabilityConfig);
  }

  ObservabilityConfigCopyWith<
    ObservabilityConfig,
    ObservabilityConfig,
    ObservabilityConfig
  >
  get copyWith =>
      _ObservabilityConfigCopyWithImpl<
        ObservabilityConfig,
        ObservabilityConfig
      >(this as ObservabilityConfig, $identity, $identity);
  @override
  String toString() {
    return ObservabilityConfigMapper.ensureInitialized().stringifyValue(
      this as ObservabilityConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ObservabilityConfigMapper.ensureInitialized().equalsValue(
      this as ObservabilityConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ObservabilityConfigMapper.ensureInitialized().hashValue(
      this as ObservabilityConfig,
    );
  }
}

extension ObservabilityConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ObservabilityConfig, $Out> {
  ObservabilityConfigCopyWith<$R, ObservabilityConfig, $Out>
  get $asObservabilityConfig => $base.as(
    (v, t, t2) => _ObservabilityConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ObservabilityConfigCopyWith<
  $R,
  $In extends ObservabilityConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  OtelConfigCopyWith<$R, OtelConfig, OtelConfig> get otel;
  $R call({bool? debug, int? maxBodyBytes, bool? redact, OtelConfig? otel});
  ObservabilityConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ObservabilityConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ObservabilityConfig, $Out>
    implements ObservabilityConfigCopyWith<$R, ObservabilityConfig, $Out> {
  _ObservabilityConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ObservabilityConfig> $mapper =
      ObservabilityConfigMapper.ensureInitialized();
  @override
  OtelConfigCopyWith<$R, OtelConfig, OtelConfig> get otel =>
      $value.otel.copyWith.$chain((v) => call(otel: v));
  @override
  $R call({bool? debug, int? maxBodyBytes, bool? redact, OtelConfig? otel}) =>
      $apply(
        FieldCopyWithData({
          if (debug != null) #debug: debug,
          if (maxBodyBytes != null) #maxBodyBytes: maxBodyBytes,
          if (redact != null) #redact: redact,
          if (otel != null) #otel: otel,
        }),
      );
  @override
  ObservabilityConfig $make(CopyWithData data) => ObservabilityConfig(
    debug: data.get(#debug, or: $value.debug),
    maxBodyBytes: data.get(#maxBodyBytes, or: $value.maxBodyBytes),
    redact: data.get(#redact, or: $value.redact),
    otel: data.get(#otel, or: $value.otel),
  );

  @override
  ObservabilityConfigCopyWith<$R2, ObservabilityConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ObservabilityConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

