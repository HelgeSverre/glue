// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model_catalog.dart';

class AuthKindMapper extends EnumMapper<AuthKind> {
  AuthKindMapper._();

  static AuthKindMapper? _instance;
  static AuthKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AuthKindMapper._());
    }
    return _instance!;
  }

  static AuthKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AuthKind decode(dynamic value) {
    switch (value) {
      case r'api_key':
        return AuthKind.apiKey;
      case r'oauth':
        return AuthKind.oauth;
      case r'none':
        return AuthKind.none;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AuthKind self) {
    switch (self) {
      case AuthKind.apiKey:
        return r'api_key';
      case AuthKind.oauth:
        return r'oauth';
      case AuthKind.none:
        return r'none';
    }
  }
}

extension AuthKindMapperExtension on AuthKind {
  String toValue() {
    AuthKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AuthKind>(this) as String;
  }
}

class ModelCatalogMapper extends ClassMapperBase<ModelCatalog> {
  ModelCatalogMapper._();

  static ModelCatalogMapper? _instance;
  static ModelCatalogMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModelCatalogMapper._());
      DefaultsConfigMapper.ensureInitialized();
      ProviderDefMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModelCatalog';

  static int _$version(ModelCatalog v) => v.version;
  static const Field<ModelCatalog, int> _f$version = Field(
    'version',
    _$version,
  );
  static String _$updatedAt(ModelCatalog v) => v.updatedAt;
  static const Field<ModelCatalog, String> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    key: r'updated_at',
  );
  static DefaultsConfig _$defaults(ModelCatalog v) => v.defaults;
  static const Field<ModelCatalog, DefaultsConfig> _f$defaults = Field(
    'defaults',
    _$defaults,
  );
  static Map<String, String> _$capabilities(ModelCatalog v) => v.capabilities;
  static const Field<ModelCatalog, Map<String, String>> _f$capabilities = Field(
    'capabilities',
    _$capabilities,
  );
  static Map<String, ProviderDef> _$providers(ModelCatalog v) => v.providers;
  static const Field<ModelCatalog, Map<String, ProviderDef>> _f$providers =
      Field('providers', _$providers);

  @override
  final MappableFields<ModelCatalog> fields = const {
    #version: _f$version,
    #updatedAt: _f$updatedAt,
    #defaults: _f$defaults,
    #capabilities: _f$capabilities,
    #providers: _f$providers,
  };

  static ModelCatalog _instantiate(DecodingData data) {
    return ModelCatalog(
      version: data.dec(_f$version),
      updatedAt: data.dec(_f$updatedAt),
      defaults: data.dec(_f$defaults),
      capabilities: data.dec(_f$capabilities),
      providers: data.dec(_f$providers),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModelCatalog fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModelCatalog>(map);
  }

  static ModelCatalog fromJson(String json) {
    return ensureInitialized().decodeJson<ModelCatalog>(json);
  }
}

mixin ModelCatalogMappable {
  String toJson() {
    return ModelCatalogMapper.ensureInitialized().encodeJson<ModelCatalog>(
      this as ModelCatalog,
    );
  }

  Map<String, dynamic> toMap() {
    return ModelCatalogMapper.ensureInitialized().encodeMap<ModelCatalog>(
      this as ModelCatalog,
    );
  }

  ModelCatalogCopyWith<ModelCatalog, ModelCatalog, ModelCatalog> get copyWith =>
      _ModelCatalogCopyWithImpl<ModelCatalog, ModelCatalog>(
        this as ModelCatalog,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModelCatalogMapper.ensureInitialized().stringifyValue(
      this as ModelCatalog,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModelCatalogMapper.ensureInitialized().equalsValue(
      this as ModelCatalog,
      other,
    );
  }

  @override
  int get hashCode {
    return ModelCatalogMapper.ensureInitialized().hashValue(
      this as ModelCatalog,
    );
  }
}

extension ModelCatalogValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModelCatalog, $Out> {
  ModelCatalogCopyWith<$R, ModelCatalog, $Out> get $asModelCatalog =>
      $base.as((v, t, t2) => _ModelCatalogCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModelCatalogCopyWith<$R, $In extends ModelCatalog, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  DefaultsConfigCopyWith<$R, DefaultsConfig, DefaultsConfig> get defaults;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get capabilities;
  MapCopyWith<
    $R,
    String,
    ProviderDef,
    ProviderDefCopyWith<$R, ProviderDef, ProviderDef>
  >
  get providers;
  $R call({
    int? version,
    String? updatedAt,
    DefaultsConfig? defaults,
    Map<String, String>? capabilities,
    Map<String, ProviderDef>? providers,
  });
  ModelCatalogCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModelCatalogCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModelCatalog, $Out>
    implements ModelCatalogCopyWith<$R, ModelCatalog, $Out> {
  _ModelCatalogCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModelCatalog> $mapper =
      ModelCatalogMapper.ensureInitialized();
  @override
  DefaultsConfigCopyWith<$R, DefaultsConfig, DefaultsConfig> get defaults =>
      $value.defaults.copyWith.$chain((v) => call(defaults: v));
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get capabilities => MapCopyWith(
    $value.capabilities,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(capabilities: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    ProviderDef,
    ProviderDefCopyWith<$R, ProviderDef, ProviderDef>
  >
  get providers => MapCopyWith(
    $value.providers,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(providers: v),
  );
  @override
  $R call({
    int? version,
    String? updatedAt,
    DefaultsConfig? defaults,
    Map<String, String>? capabilities,
    Map<String, ProviderDef>? providers,
  }) => $apply(
    FieldCopyWithData({
      if (version != null) #version: version,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (defaults != null) #defaults: defaults,
      if (capabilities != null) #capabilities: capabilities,
      if (providers != null) #providers: providers,
    }),
  );
  @override
  ModelCatalog $make(CopyWithData data) => ModelCatalog(
    version: data.get(#version, or: $value.version),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    defaults: data.get(#defaults, or: $value.defaults),
    capabilities: data.get(#capabilities, or: $value.capabilities),
    providers: data.get(#providers, or: $value.providers),
  );

  @override
  ModelCatalogCopyWith<$R2, ModelCatalog, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModelCatalogCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DefaultsConfigMapper extends ClassMapperBase<DefaultsConfig> {
  DefaultsConfigMapper._();

  static DefaultsConfigMapper? _instance;
  static DefaultsConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DefaultsConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'DefaultsConfig';

  static String _$model(DefaultsConfig v) => v.model;
  static const Field<DefaultsConfig, String> _f$model = Field('model', _$model);
  static String? _$smallModel(DefaultsConfig v) => v.smallModel;
  static const Field<DefaultsConfig, String> _f$smallModel = Field(
    'smallModel',
    _$smallModel,
    key: r'small_model',
    opt: true,
  );
  static String? _$localModel(DefaultsConfig v) => v.localModel;
  static const Field<DefaultsConfig, String> _f$localModel = Field(
    'localModel',
    _$localModel,
    key: r'local_model',
    opt: true,
  );

  @override
  final MappableFields<DefaultsConfig> fields = const {
    #model: _f$model,
    #smallModel: _f$smallModel,
    #localModel: _f$localModel,
  };

  static DefaultsConfig _instantiate(DecodingData data) {
    return DefaultsConfig(
      model: data.dec(_f$model),
      smallModel: data.dec(_f$smallModel),
      localModel: data.dec(_f$localModel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DefaultsConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DefaultsConfig>(map);
  }

  static DefaultsConfig fromJson(String json) {
    return ensureInitialized().decodeJson<DefaultsConfig>(json);
  }
}

mixin DefaultsConfigMappable {
  String toJson() {
    return DefaultsConfigMapper.ensureInitialized().encodeJson<DefaultsConfig>(
      this as DefaultsConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return DefaultsConfigMapper.ensureInitialized().encodeMap<DefaultsConfig>(
      this as DefaultsConfig,
    );
  }

  DefaultsConfigCopyWith<DefaultsConfig, DefaultsConfig, DefaultsConfig>
  get copyWith => _DefaultsConfigCopyWithImpl<DefaultsConfig, DefaultsConfig>(
    this as DefaultsConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return DefaultsConfigMapper.ensureInitialized().stringifyValue(
      this as DefaultsConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return DefaultsConfigMapper.ensureInitialized().equalsValue(
      this as DefaultsConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return DefaultsConfigMapper.ensureInitialized().hashValue(
      this as DefaultsConfig,
    );
  }
}

extension DefaultsConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DefaultsConfig, $Out> {
  DefaultsConfigCopyWith<$R, DefaultsConfig, $Out> get $asDefaultsConfig =>
      $base.as((v, t, t2) => _DefaultsConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DefaultsConfigCopyWith<$R, $In extends DefaultsConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? model, String? smallModel, String? localModel});
  DefaultsConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DefaultsConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DefaultsConfig, $Out>
    implements DefaultsConfigCopyWith<$R, DefaultsConfig, $Out> {
  _DefaultsConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DefaultsConfig> $mapper =
      DefaultsConfigMapper.ensureInitialized();
  @override
  $R call({
    String? model,
    Object? smallModel = $none,
    Object? localModel = $none,
  }) => $apply(
    FieldCopyWithData({
      if (model != null) #model: model,
      if (smallModel != $none) #smallModel: smallModel,
      if (localModel != $none) #localModel: localModel,
    }),
  );
  @override
  DefaultsConfig $make(CopyWithData data) => DefaultsConfig(
    model: data.get(#model, or: $value.model),
    smallModel: data.get(#smallModel, or: $value.smallModel),
    localModel: data.get(#localModel, or: $value.localModel),
  );

  @override
  DefaultsConfigCopyWith<$R2, DefaultsConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DefaultsConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ProviderDefMapper extends ClassMapperBase<ProviderDef> {
  ProviderDefMapper._();

  static ProviderDefMapper? _instance;
  static ProviderDefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderDefMapper._());
      AuthSpecMapper.ensureInitialized();
      ModelDefMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderDef';

  static String _$id(ProviderDef v) => v.id;
  static const Field<ProviderDef, String> _f$id = Field('id', _$id);
  static String _$name(ProviderDef v) => v.name;
  static const Field<ProviderDef, String> _f$name = Field('name', _$name);
  static String _$adapter(ProviderDef v) => v.adapter;
  static const Field<ProviderDef, String> _f$adapter = Field(
    'adapter',
    _$adapter,
  );
  static AuthSpec _$auth(ProviderDef v) => v.auth;
  static const Field<ProviderDef, AuthSpec> _f$auth = Field('auth', _$auth);
  static Map<String, ModelDef> _$models(ProviderDef v) => v.models;
  static const Field<ProviderDef, Map<String, ModelDef>> _f$models = Field(
    'models',
    _$models,
  );
  static String? _$compatibility(ProviderDef v) => v.compatibility;
  static const Field<ProviderDef, String> _f$compatibility = Field(
    'compatibility',
    _$compatibility,
    opt: true,
  );
  static bool _$enabled(ProviderDef v) => v.enabled;
  static const Field<ProviderDef, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static String? _$baseUrl(ProviderDef v) => v.baseUrl;
  static const Field<ProviderDef, String> _f$baseUrl = Field(
    'baseUrl',
    _$baseUrl,
    key: r'base_url',
    opt: true,
  );
  static String? _$docsUrl(ProviderDef v) => v.docsUrl;
  static const Field<ProviderDef, String> _f$docsUrl = Field(
    'docsUrl',
    _$docsUrl,
    key: r'docs_url',
    opt: true,
  );
  static Map<String, String> _$requestHeaders(ProviderDef v) =>
      v.requestHeaders;
  static const Field<ProviderDef, Map<String, String>> _f$requestHeaders =
      Field(
        'requestHeaders',
        _$requestHeaders,
        key: r'request_headers',
        opt: true,
        def: const {},
      );

  @override
  final MappableFields<ProviderDef> fields = const {
    #id: _f$id,
    #name: _f$name,
    #adapter: _f$adapter,
    #auth: _f$auth,
    #models: _f$models,
    #compatibility: _f$compatibility,
    #enabled: _f$enabled,
    #baseUrl: _f$baseUrl,
    #docsUrl: _f$docsUrl,
    #requestHeaders: _f$requestHeaders,
  };

  static ProviderDef _instantiate(DecodingData data) {
    return ProviderDef(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      adapter: data.dec(_f$adapter),
      auth: data.dec(_f$auth),
      models: data.dec(_f$models),
      compatibility: data.dec(_f$compatibility),
      enabled: data.dec(_f$enabled),
      baseUrl: data.dec(_f$baseUrl),
      docsUrl: data.dec(_f$docsUrl),
      requestHeaders: data.dec(_f$requestHeaders),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderDef fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderDef>(map);
  }

  static ProviderDef fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderDef>(json);
  }
}

mixin ProviderDefMappable {
  String toJson() {
    return ProviderDefMapper.ensureInitialized().encodeJson<ProviderDef>(
      this as ProviderDef,
    );
  }

  Map<String, dynamic> toMap() {
    return ProviderDefMapper.ensureInitialized().encodeMap<ProviderDef>(
      this as ProviderDef,
    );
  }

  ProviderDefCopyWith<ProviderDef, ProviderDef, ProviderDef> get copyWith =>
      _ProviderDefCopyWithImpl<ProviderDef, ProviderDef>(
        this as ProviderDef,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProviderDefMapper.ensureInitialized().stringifyValue(
      this as ProviderDef,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProviderDefMapper.ensureInitialized().equalsValue(
      this as ProviderDef,
      other,
    );
  }

  @override
  int get hashCode {
    return ProviderDefMapper.ensureInitialized().hashValue(this as ProviderDef);
  }
}

extension ProviderDefValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProviderDef, $Out> {
  ProviderDefCopyWith<$R, ProviderDef, $Out> get $asProviderDef =>
      $base.as((v, t, t2) => _ProviderDefCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProviderDefCopyWith<$R, $In extends ProviderDef, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  AuthSpecCopyWith<$R, AuthSpec, AuthSpec> get auth;
  MapCopyWith<$R, String, ModelDef, ModelDefCopyWith<$R, ModelDef, ModelDef>>
  get models;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get requestHeaders;
  $R call({
    String? id,
    String? name,
    String? adapter,
    AuthSpec? auth,
    Map<String, ModelDef>? models,
    String? compatibility,
    bool? enabled,
    String? baseUrl,
    String? docsUrl,
    Map<String, String>? requestHeaders,
  });
  ProviderDefCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ProviderDefCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProviderDef, $Out>
    implements ProviderDefCopyWith<$R, ProviderDef, $Out> {
  _ProviderDefCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProviderDef> $mapper =
      ProviderDefMapper.ensureInitialized();
  @override
  AuthSpecCopyWith<$R, AuthSpec, AuthSpec> get auth =>
      $value.auth.copyWith.$chain((v) => call(auth: v));
  @override
  MapCopyWith<$R, String, ModelDef, ModelDefCopyWith<$R, ModelDef, ModelDef>>
  get models => MapCopyWith(
    $value.models,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(models: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get requestHeaders => MapCopyWith(
    $value.requestHeaders,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(requestHeaders: v),
  );
  @override
  $R call({
    String? id,
    String? name,
    String? adapter,
    AuthSpec? auth,
    Map<String, ModelDef>? models,
    Object? compatibility = $none,
    bool? enabled,
    Object? baseUrl = $none,
    Object? docsUrl = $none,
    Map<String, String>? requestHeaders,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (adapter != null) #adapter: adapter,
      if (auth != null) #auth: auth,
      if (models != null) #models: models,
      if (compatibility != $none) #compatibility: compatibility,
      if (enabled != null) #enabled: enabled,
      if (baseUrl != $none) #baseUrl: baseUrl,
      if (docsUrl != $none) #docsUrl: docsUrl,
      if (requestHeaders != null) #requestHeaders: requestHeaders,
    }),
  );
  @override
  ProviderDef $make(CopyWithData data) => ProviderDef(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    adapter: data.get(#adapter, or: $value.adapter),
    auth: data.get(#auth, or: $value.auth),
    models: data.get(#models, or: $value.models),
    compatibility: data.get(#compatibility, or: $value.compatibility),
    enabled: data.get(#enabled, or: $value.enabled),
    baseUrl: data.get(#baseUrl, or: $value.baseUrl),
    docsUrl: data.get(#docsUrl, or: $value.docsUrl),
    requestHeaders: data.get(#requestHeaders, or: $value.requestHeaders),
  );

  @override
  ProviderDefCopyWith<$R2, ProviderDef, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProviderDefCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AuthSpecMapper extends ClassMapperBase<AuthSpec> {
  AuthSpecMapper._();

  static AuthSpecMapper? _instance;
  static AuthSpecMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AuthSpecMapper._());
      AuthKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AuthSpec';

  static AuthKind _$kind(AuthSpec v) => v.kind;
  static const Field<AuthSpec, AuthKind> _f$kind = Field('kind', _$kind);
  static String? _$envVar(AuthSpec v) => v.envVar;
  static const Field<AuthSpec, String> _f$envVar = Field(
    'envVar',
    _$envVar,
    key: r'env_var',
    opt: true,
  );
  static String? _$helpUrl(AuthSpec v) => v.helpUrl;
  static const Field<AuthSpec, String> _f$helpUrl = Field(
    'helpUrl',
    _$helpUrl,
    key: r'help_url',
    opt: true,
  );

  @override
  final MappableFields<AuthSpec> fields = const {
    #kind: _f$kind,
    #envVar: _f$envVar,
    #helpUrl: _f$helpUrl,
  };

  static AuthSpec _instantiate(DecodingData data) {
    return AuthSpec(
      kind: data.dec(_f$kind),
      envVar: data.dec(_f$envVar),
      helpUrl: data.dec(_f$helpUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AuthSpec fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AuthSpec>(map);
  }

  static AuthSpec fromJson(String json) {
    return ensureInitialized().decodeJson<AuthSpec>(json);
  }
}

mixin AuthSpecMappable {
  String toJson() {
    return AuthSpecMapper.ensureInitialized().encodeJson<AuthSpec>(
      this as AuthSpec,
    );
  }

  Map<String, dynamic> toMap() {
    return AuthSpecMapper.ensureInitialized().encodeMap<AuthSpec>(
      this as AuthSpec,
    );
  }

  AuthSpecCopyWith<AuthSpec, AuthSpec, AuthSpec> get copyWith =>
      _AuthSpecCopyWithImpl<AuthSpec, AuthSpec>(
        this as AuthSpec,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AuthSpecMapper.ensureInitialized().stringifyValue(this as AuthSpec);
  }

  @override
  bool operator ==(Object other) {
    return AuthSpecMapper.ensureInitialized().equalsValue(
      this as AuthSpec,
      other,
    );
  }

  @override
  int get hashCode {
    return AuthSpecMapper.ensureInitialized().hashValue(this as AuthSpec);
  }
}

extension AuthSpecValueCopy<$R, $Out> on ObjectCopyWith<$R, AuthSpec, $Out> {
  AuthSpecCopyWith<$R, AuthSpec, $Out> get $asAuthSpec =>
      $base.as((v, t, t2) => _AuthSpecCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AuthSpecCopyWith<$R, $In extends AuthSpec, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({AuthKind? kind, String? envVar, String? helpUrl});
  AuthSpecCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AuthSpecCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AuthSpec, $Out>
    implements AuthSpecCopyWith<$R, AuthSpec, $Out> {
  _AuthSpecCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AuthSpec> $mapper =
      AuthSpecMapper.ensureInitialized();
  @override
  $R call({AuthKind? kind, Object? envVar = $none, Object? helpUrl = $none}) =>
      $apply(
        FieldCopyWithData({
          if (kind != null) #kind: kind,
          if (envVar != $none) #envVar: envVar,
          if (helpUrl != $none) #helpUrl: helpUrl,
        }),
      );
  @override
  AuthSpec $make(CopyWithData data) => AuthSpec(
    kind: data.get(#kind, or: $value.kind),
    envVar: data.get(#envVar, or: $value.envVar),
    helpUrl: data.get(#helpUrl, or: $value.helpUrl),
  );

  @override
  AuthSpecCopyWith<$R2, AuthSpec, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AuthSpecCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModelDefMapper extends ClassMapperBase<ModelDef> {
  ModelDefMapper._();

  static ModelDefMapper? _instance;
  static ModelDefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModelDefMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ModelDef';

  static String _$id(ModelDef v) => v.id;
  static const Field<ModelDef, String> _f$id = Field('id', _$id);
  static String _$name(ModelDef v) => v.name;
  static const Field<ModelDef, String> _f$name = Field('name', _$name);
  static String _$apiId(ModelDef v) => v.apiId;
  static const Field<ModelDef, String> _f$apiId = Field(
    'apiId',
    _$apiId,
    key: r'api_id',
    opt: true,
  );
  static bool _$recommended(ModelDef v) => v.recommended;
  static const Field<ModelDef, bool> _f$recommended = Field(
    'recommended',
    _$recommended,
    opt: true,
    def: false,
  );
  static bool _$isDefault(ModelDef v) => v.isDefault;
  static const Field<ModelDef, bool> _f$isDefault = Field(
    'isDefault',
    _$isDefault,
    key: r'default',
    opt: true,
    def: false,
  );
  static bool _$enabled(ModelDef v) => v.enabled;
  static const Field<ModelDef, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static Set<String> _$capabilities(ModelDef v) => v.capabilities;
  static const Field<ModelDef, Set<String>> _f$capabilities = Field(
    'capabilities',
    _$capabilities,
    opt: true,
    def: const {},
  );
  static int? _$contextWindow(ModelDef v) => v.contextWindow;
  static const Field<ModelDef, int> _f$contextWindow = Field(
    'contextWindow',
    _$contextWindow,
    key: r'context_window',
    opt: true,
  );
  static int? _$maxOutputTokens(ModelDef v) => v.maxOutputTokens;
  static const Field<ModelDef, int> _f$maxOutputTokens = Field(
    'maxOutputTokens',
    _$maxOutputTokens,
    key: r'max_output_tokens',
    opt: true,
  );
  static String? _$speed(ModelDef v) => v.speed;
  static const Field<ModelDef, String> _f$speed = Field(
    'speed',
    _$speed,
    opt: true,
  );
  static String? _$cost(ModelDef v) => v.cost;
  static const Field<ModelDef, String> _f$cost = Field(
    'cost',
    _$cost,
    opt: true,
  );
  static String? _$notes(ModelDef v) => v.notes;
  static const Field<ModelDef, String> _f$notes = Field(
    'notes',
    _$notes,
    opt: true,
  );

  @override
  final MappableFields<ModelDef> fields = const {
    #id: _f$id,
    #name: _f$name,
    #apiId: _f$apiId,
    #recommended: _f$recommended,
    #isDefault: _f$isDefault,
    #enabled: _f$enabled,
    #capabilities: _f$capabilities,
    #contextWindow: _f$contextWindow,
    #maxOutputTokens: _f$maxOutputTokens,
    #speed: _f$speed,
    #cost: _f$cost,
    #notes: _f$notes,
  };

  static ModelDef _instantiate(DecodingData data) {
    return ModelDef(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      apiId: data.dec(_f$apiId),
      recommended: data.dec(_f$recommended),
      isDefault: data.dec(_f$isDefault),
      enabled: data.dec(_f$enabled),
      capabilities: data.dec(_f$capabilities),
      contextWindow: data.dec(_f$contextWindow),
      maxOutputTokens: data.dec(_f$maxOutputTokens),
      speed: data.dec(_f$speed),
      cost: data.dec(_f$cost),
      notes: data.dec(_f$notes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModelDef fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModelDef>(map);
  }

  static ModelDef fromJson(String json) {
    return ensureInitialized().decodeJson<ModelDef>(json);
  }
}

mixin ModelDefMappable {
  String toJson() {
    return ModelDefMapper.ensureInitialized().encodeJson<ModelDef>(
      this as ModelDef,
    );
  }

  Map<String, dynamic> toMap() {
    return ModelDefMapper.ensureInitialized().encodeMap<ModelDef>(
      this as ModelDef,
    );
  }

  ModelDefCopyWith<ModelDef, ModelDef, ModelDef> get copyWith =>
      _ModelDefCopyWithImpl<ModelDef, ModelDef>(
        this as ModelDef,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModelDefMapper.ensureInitialized().stringifyValue(this as ModelDef);
  }

  @override
  bool operator ==(Object other) {
    return ModelDefMapper.ensureInitialized().equalsValue(
      this as ModelDef,
      other,
    );
  }

  @override
  int get hashCode {
    return ModelDefMapper.ensureInitialized().hashValue(this as ModelDef);
  }
}

extension ModelDefValueCopy<$R, $Out> on ObjectCopyWith<$R, ModelDef, $Out> {
  ModelDefCopyWith<$R, ModelDef, $Out> get $asModelDef =>
      $base.as((v, t, t2) => _ModelDefCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModelDefCopyWith<$R, $In extends ModelDef, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? name,
    String? apiId,
    bool? recommended,
    bool? isDefault,
    bool? enabled,
    Set<String>? capabilities,
    int? contextWindow,
    int? maxOutputTokens,
    String? speed,
    String? cost,
    String? notes,
  });
  ModelDefCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModelDefCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModelDef, $Out>
    implements ModelDefCopyWith<$R, ModelDef, $Out> {
  _ModelDefCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModelDef> $mapper =
      ModelDefMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? name,
    Object? apiId = $none,
    bool? recommended,
    bool? isDefault,
    bool? enabled,
    Set<String>? capabilities,
    Object? contextWindow = $none,
    Object? maxOutputTokens = $none,
    Object? speed = $none,
    Object? cost = $none,
    Object? notes = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (apiId != $none) #apiId: apiId,
      if (recommended != null) #recommended: recommended,
      if (isDefault != null) #isDefault: isDefault,
      if (enabled != null) #enabled: enabled,
      if (capabilities != null) #capabilities: capabilities,
      if (contextWindow != $none) #contextWindow: contextWindow,
      if (maxOutputTokens != $none) #maxOutputTokens: maxOutputTokens,
      if (speed != $none) #speed: speed,
      if (cost != $none) #cost: cost,
      if (notes != $none) #notes: notes,
    }),
  );
  @override
  ModelDef $make(CopyWithData data) => ModelDef(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    apiId: data.get(#apiId, or: $value.apiId),
    recommended: data.get(#recommended, or: $value.recommended),
    isDefault: data.get(#isDefault, or: $value.isDefault),
    enabled: data.get(#enabled, or: $value.enabled),
    capabilities: data.get(#capabilities, or: $value.capabilities),
    contextWindow: data.get(#contextWindow, or: $value.contextWindow),
    maxOutputTokens: data.get(#maxOutputTokens, or: $value.maxOutputTokens),
    speed: data.get(#speed, or: $value.speed),
    cost: data.get(#cost, or: $value.cost),
    notes: data.get(#notes, or: $value.notes),
  );

  @override
  ModelDefCopyWith<$R2, ModelDef, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModelDefCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

