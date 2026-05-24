// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'config.dart';

class McpSubprocessEnvModeMapper extends EnumMapper<McpSubprocessEnvMode> {
  McpSubprocessEnvModeMapper._();

  static McpSubprocessEnvModeMapper? _instance;
  static McpSubprocessEnvModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpSubprocessEnvModeMapper._());
    }
    return _instance!;
  }

  static McpSubprocessEnvMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  McpSubprocessEnvMode decode(dynamic value) {
    switch (value) {
      case r'allowlist':
        return McpSubprocessEnvMode.allowlist;
      case r'full':
        return McpSubprocessEnvMode.full;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(McpSubprocessEnvMode self) {
    switch (self) {
      case McpSubprocessEnvMode.allowlist:
        return r'allowlist';
      case McpSubprocessEnvMode.full:
        return r'full';
    }
  }
}

extension McpSubprocessEnvModeMapperExtension on McpSubprocessEnvMode {
  String toValue() {
    McpSubprocessEnvModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<McpSubprocessEnvMode>(this)
        as String;
  }
}

class McpServerSpecMapper extends ClassMapperBase<McpServerSpec> {
  McpServerSpecMapper._();

  static McpServerSpecMapper? _instance;
  static McpServerSpecMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpServerSpecMapper._());
      McpStdioServerSpecMapper.ensureInitialized();
      McpUrlServerSpecMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'McpServerSpec';

  static String _$id(McpServerSpec v) => v.id;
  static const Field<McpServerSpec, String> _f$id = Field('id', _$id);
  static bool _$enabled(McpServerSpec v) => v.enabled;
  static const Field<McpServerSpec, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int? _$callTimeoutSeconds(McpServerSpec v) => v.callTimeoutSeconds;
  static const Field<McpServerSpec, int> _f$callTimeoutSeconds = Field(
    'callTimeoutSeconds',
    _$callTimeoutSeconds,
    opt: true,
  );

  @override
  final MappableFields<McpServerSpec> fields = const {
    #id: _f$id,
    #enabled: _f$enabled,
    #callTimeoutSeconds: _f$callTimeoutSeconds,
  };

  static McpServerSpec _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'McpServerSpec',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpServerSpec fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpServerSpec>(map);
  }

  static McpServerSpec fromJson(String json) {
    return ensureInitialized().decodeJson<McpServerSpec>(json);
  }
}

mixin McpServerSpecMappable {
  String toJson();
  Map<String, dynamic> toMap();
  McpServerSpecCopyWith<McpServerSpec, McpServerSpec, McpServerSpec>
  get copyWith;
}

abstract class McpServerSpecCopyWith<$R, $In extends McpServerSpec, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, bool? enabled, int? callTimeoutSeconds});
  McpServerSpecCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class McpStdioServerSpecMapper extends SubClassMapperBase<McpStdioServerSpec> {
  McpStdioServerSpecMapper._();

  static McpStdioServerSpecMapper? _instance;
  static McpStdioServerSpecMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpStdioServerSpecMapper._());
      McpServerSpecMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'McpStdioServerSpec';

  static String _$id(McpStdioServerSpec v) => v.id;
  static const Field<McpStdioServerSpec, String> _f$id = Field('id', _$id);
  static String _$command(McpStdioServerSpec v) => v.command;
  static const Field<McpStdioServerSpec, String> _f$command = Field(
    'command',
    _$command,
  );
  static List<String> _$args(McpStdioServerSpec v) => v.args;
  static const Field<McpStdioServerSpec, List<String>> _f$args = Field(
    'args',
    _$args,
    opt: true,
    def: const [],
  );
  static Map<String, String> _$env(McpStdioServerSpec v) => v.env;
  static const Field<McpStdioServerSpec, Map<String, String>> _f$env = Field(
    'env',
    _$env,
    opt: true,
    def: const {},
  );
  static String? _$workingDirectory(McpStdioServerSpec v) => v.workingDirectory;
  static const Field<McpStdioServerSpec, String> _f$workingDirectory = Field(
    'workingDirectory',
    _$workingDirectory,
    opt: true,
  );
  static bool _$enabled(McpStdioServerSpec v) => v.enabled;
  static const Field<McpStdioServerSpec, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int? _$callTimeoutSeconds(McpStdioServerSpec v) =>
      v.callTimeoutSeconds;
  static const Field<McpStdioServerSpec, int> _f$callTimeoutSeconds = Field(
    'callTimeoutSeconds',
    _$callTimeoutSeconds,
    opt: true,
  );

  @override
  final MappableFields<McpStdioServerSpec> fields = const {
    #id: _f$id,
    #command: _f$command,
    #args: _f$args,
    #env: _f$env,
    #workingDirectory: _f$workingDirectory,
    #enabled: _f$enabled,
    #callTimeoutSeconds: _f$callTimeoutSeconds,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'stdio';
  @override
  late final ClassMapperBase superMapper =
      McpServerSpecMapper.ensureInitialized();

  static McpStdioServerSpec _instantiate(DecodingData data) {
    return McpStdioServerSpec(
      id: data.dec(_f$id),
      command: data.dec(_f$command),
      args: data.dec(_f$args),
      env: data.dec(_f$env),
      workingDirectory: data.dec(_f$workingDirectory),
      enabled: data.dec(_f$enabled),
      callTimeoutSeconds: data.dec(_f$callTimeoutSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpStdioServerSpec fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpStdioServerSpec>(map);
  }

  static McpStdioServerSpec fromJson(String json) {
    return ensureInitialized().decodeJson<McpStdioServerSpec>(json);
  }
}

mixin McpStdioServerSpecMappable {
  String toJson() {
    return McpStdioServerSpecMapper.ensureInitialized()
        .encodeJson<McpStdioServerSpec>(this as McpStdioServerSpec);
  }

  Map<String, dynamic> toMap() {
    return McpStdioServerSpecMapper.ensureInitialized()
        .encodeMap<McpStdioServerSpec>(this as McpStdioServerSpec);
  }

  McpStdioServerSpecCopyWith<
    McpStdioServerSpec,
    McpStdioServerSpec,
    McpStdioServerSpec
  >
  get copyWith =>
      _McpStdioServerSpecCopyWithImpl<McpStdioServerSpec, McpStdioServerSpec>(
        this as McpStdioServerSpec,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpStdioServerSpecMapper.ensureInitialized().stringifyValue(
      this as McpStdioServerSpec,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpStdioServerSpecMapper.ensureInitialized().equalsValue(
      this as McpStdioServerSpec,
      other,
    );
  }

  @override
  int get hashCode {
    return McpStdioServerSpecMapper.ensureInitialized().hashValue(
      this as McpStdioServerSpec,
    );
  }
}

extension McpStdioServerSpecValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpStdioServerSpec, $Out> {
  McpStdioServerSpecCopyWith<$R, McpStdioServerSpec, $Out>
  get $asMcpStdioServerSpec => $base.as(
    (v, t, t2) => _McpStdioServerSpecCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class McpStdioServerSpecCopyWith<
  $R,
  $In extends McpStdioServerSpec,
  $Out
>
    implements McpServerSpecCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get args;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>> get env;
  @override
  $R call({
    String? id,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? workingDirectory,
    bool? enabled,
    int? callTimeoutSeconds,
  });
  McpStdioServerSpecCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _McpStdioServerSpecCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpStdioServerSpec, $Out>
    implements McpStdioServerSpecCopyWith<$R, McpStdioServerSpec, $Out> {
  _McpStdioServerSpecCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpStdioServerSpec> $mapper =
      McpStdioServerSpecMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get args =>
      ListCopyWith(
        $value.args,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(args: v),
      );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>> get env =>
      MapCopyWith(
        $value.env,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(env: v),
      );
  @override
  $R call({
    String? id,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    Object? workingDirectory = $none,
    bool? enabled,
    Object? callTimeoutSeconds = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (command != null) #command: command,
      if (args != null) #args: args,
      if (env != null) #env: env,
      if (workingDirectory != $none) #workingDirectory: workingDirectory,
      if (enabled != null) #enabled: enabled,
      if (callTimeoutSeconds != $none) #callTimeoutSeconds: callTimeoutSeconds,
    }),
  );
  @override
  McpStdioServerSpec $make(CopyWithData data) => McpStdioServerSpec(
    id: data.get(#id, or: $value.id),
    command: data.get(#command, or: $value.command),
    args: data.get(#args, or: $value.args),
    env: data.get(#env, or: $value.env),
    workingDirectory: data.get(#workingDirectory, or: $value.workingDirectory),
    enabled: data.get(#enabled, or: $value.enabled),
    callTimeoutSeconds: data.get(
      #callTimeoutSeconds,
      or: $value.callTimeoutSeconds,
    ),
  );

  @override
  McpStdioServerSpecCopyWith<$R2, McpStdioServerSpec, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpStdioServerSpecCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpUrlServerSpecMapper extends SubClassMapperBase<McpUrlServerSpec> {
  McpUrlServerSpecMapper._();

  static McpUrlServerSpecMapper? _instance;
  static McpUrlServerSpecMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpUrlServerSpecMapper._());
      McpServerSpecMapper.ensureInitialized().addSubMapper(_instance!);
      MapperContainer.globals.useAll([UriMapper()]);
      McpAuthSpecMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'McpUrlServerSpec';

  static String _$id(McpUrlServerSpec v) => v.id;
  static const Field<McpUrlServerSpec, String> _f$id = Field('id', _$id);
  static Uri _$url(McpUrlServerSpec v) => v.url;
  static const Field<McpUrlServerSpec, Uri> _f$url = Field('url', _$url);
  static bool _$isWebSocket(McpUrlServerSpec v) => v.isWebSocket;
  static const Field<McpUrlServerSpec, bool> _f$isWebSocket = Field(
    'isWebSocket',
    _$isWebSocket,
  );
  static McpAuthSpec _$auth(McpUrlServerSpec v) => v.auth;
  static const Field<McpUrlServerSpec, McpAuthSpec> _f$auth = Field(
    'auth',
    _$auth,
    opt: true,
    def: const McpNoAuth(),
  );
  static Uri? _$resourceMetadataUrl(McpUrlServerSpec v) =>
      v.resourceMetadataUrl;
  static const Field<McpUrlServerSpec, Uri> _f$resourceMetadataUrl = Field(
    'resourceMetadataUrl',
    _$resourceMetadataUrl,
    opt: true,
  );
  static Uri? _$authorizationServer(McpUrlServerSpec v) =>
      v.authorizationServer;
  static const Field<McpUrlServerSpec, Uri> _f$authorizationServer = Field(
    'authorizationServer',
    _$authorizationServer,
    opt: true,
  );
  static bool _$enabled(McpUrlServerSpec v) => v.enabled;
  static const Field<McpUrlServerSpec, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int? _$callTimeoutSeconds(McpUrlServerSpec v) => v.callTimeoutSeconds;
  static const Field<McpUrlServerSpec, int> _f$callTimeoutSeconds = Field(
    'callTimeoutSeconds',
    _$callTimeoutSeconds,
    opt: true,
  );

  @override
  final MappableFields<McpUrlServerSpec> fields = const {
    #id: _f$id,
    #url: _f$url,
    #isWebSocket: _f$isWebSocket,
    #auth: _f$auth,
    #resourceMetadataUrl: _f$resourceMetadataUrl,
    #authorizationServer: _f$authorizationServer,
    #enabled: _f$enabled,
    #callTimeoutSeconds: _f$callTimeoutSeconds,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'url';
  @override
  late final ClassMapperBase superMapper =
      McpServerSpecMapper.ensureInitialized();

  static McpUrlServerSpec _instantiate(DecodingData data) {
    return McpUrlServerSpec(
      id: data.dec(_f$id),
      url: data.dec(_f$url),
      isWebSocket: data.dec(_f$isWebSocket),
      auth: data.dec(_f$auth),
      resourceMetadataUrl: data.dec(_f$resourceMetadataUrl),
      authorizationServer: data.dec(_f$authorizationServer),
      enabled: data.dec(_f$enabled),
      callTimeoutSeconds: data.dec(_f$callTimeoutSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpUrlServerSpec fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpUrlServerSpec>(map);
  }

  static McpUrlServerSpec fromJson(String json) {
    return ensureInitialized().decodeJson<McpUrlServerSpec>(json);
  }
}

mixin McpUrlServerSpecMappable {
  String toJson() {
    return McpUrlServerSpecMapper.ensureInitialized()
        .encodeJson<McpUrlServerSpec>(this as McpUrlServerSpec);
  }

  Map<String, dynamic> toMap() {
    return McpUrlServerSpecMapper.ensureInitialized()
        .encodeMap<McpUrlServerSpec>(this as McpUrlServerSpec);
  }

  McpUrlServerSpecCopyWith<McpUrlServerSpec, McpUrlServerSpec, McpUrlServerSpec>
  get copyWith =>
      _McpUrlServerSpecCopyWithImpl<McpUrlServerSpec, McpUrlServerSpec>(
        this as McpUrlServerSpec,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpUrlServerSpecMapper.ensureInitialized().stringifyValue(
      this as McpUrlServerSpec,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpUrlServerSpecMapper.ensureInitialized().equalsValue(
      this as McpUrlServerSpec,
      other,
    );
  }

  @override
  int get hashCode {
    return McpUrlServerSpecMapper.ensureInitialized().hashValue(
      this as McpUrlServerSpec,
    );
  }
}

extension McpUrlServerSpecValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpUrlServerSpec, $Out> {
  McpUrlServerSpecCopyWith<$R, McpUrlServerSpec, $Out>
  get $asMcpUrlServerSpec =>
      $base.as((v, t, t2) => _McpUrlServerSpecCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpUrlServerSpecCopyWith<$R, $In extends McpUrlServerSpec, $Out>
    implements McpServerSpecCopyWith<$R, $In, $Out> {
  McpAuthSpecCopyWith<$R, McpAuthSpec, McpAuthSpec> get auth;
  @override
  $R call({
    String? id,
    Uri? url,
    bool? isWebSocket,
    McpAuthSpec? auth,
    Uri? resourceMetadataUrl,
    Uri? authorizationServer,
    bool? enabled,
    int? callTimeoutSeconds,
  });
  McpUrlServerSpecCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _McpUrlServerSpecCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpUrlServerSpec, $Out>
    implements McpUrlServerSpecCopyWith<$R, McpUrlServerSpec, $Out> {
  _McpUrlServerSpecCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpUrlServerSpec> $mapper =
      McpUrlServerSpecMapper.ensureInitialized();
  @override
  McpAuthSpecCopyWith<$R, McpAuthSpec, McpAuthSpec> get auth =>
      $value.auth.copyWith.$chain((v) => call(auth: v));
  @override
  $R call({
    String? id,
    Uri? url,
    bool? isWebSocket,
    McpAuthSpec? auth,
    Object? resourceMetadataUrl = $none,
    Object? authorizationServer = $none,
    bool? enabled,
    Object? callTimeoutSeconds = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (url != null) #url: url,
      if (isWebSocket != null) #isWebSocket: isWebSocket,
      if (auth != null) #auth: auth,
      if (resourceMetadataUrl != $none)
        #resourceMetadataUrl: resourceMetadataUrl,
      if (authorizationServer != $none)
        #authorizationServer: authorizationServer,
      if (enabled != null) #enabled: enabled,
      if (callTimeoutSeconds != $none) #callTimeoutSeconds: callTimeoutSeconds,
    }),
  );
  @override
  McpUrlServerSpec $make(CopyWithData data) => McpUrlServerSpec(
    id: data.get(#id, or: $value.id),
    url: data.get(#url, or: $value.url),
    isWebSocket: data.get(#isWebSocket, or: $value.isWebSocket),
    auth: data.get(#auth, or: $value.auth),
    resourceMetadataUrl: data.get(
      #resourceMetadataUrl,
      or: $value.resourceMetadataUrl,
    ),
    authorizationServer: data.get(
      #authorizationServer,
      or: $value.authorizationServer,
    ),
    enabled: data.get(#enabled, or: $value.enabled),
    callTimeoutSeconds: data.get(
      #callTimeoutSeconds,
      or: $value.callTimeoutSeconds,
    ),
  );

  @override
  McpUrlServerSpecCopyWith<$R2, McpUrlServerSpec, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpUrlServerSpecCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpAuthSpecMapper extends ClassMapperBase<McpAuthSpec> {
  McpAuthSpecMapper._();

  static McpAuthSpecMapper? _instance;
  static McpAuthSpecMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpAuthSpecMapper._());
      McpNoAuthMapper.ensureInitialized();
      McpBearerAuthMapper.ensureInitialized();
      McpOAuthAuthMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'McpAuthSpec';

  @override
  final MappableFields<McpAuthSpec> fields = const {};

  static McpAuthSpec _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'McpAuthSpec',
      'kind',
      '${data.value['kind']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpAuthSpec fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpAuthSpec>(map);
  }

  static McpAuthSpec fromJson(String json) {
    return ensureInitialized().decodeJson<McpAuthSpec>(json);
  }
}

mixin McpAuthSpecMappable {
  String toJson();
  Map<String, dynamic> toMap();
  McpAuthSpecCopyWith<McpAuthSpec, McpAuthSpec, McpAuthSpec> get copyWith;
}

abstract class McpAuthSpecCopyWith<$R, $In extends McpAuthSpec, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call();
  McpAuthSpecCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class McpNoAuthMapper extends SubClassMapperBase<McpNoAuth> {
  McpNoAuthMapper._();

  static McpNoAuthMapper? _instance;
  static McpNoAuthMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpNoAuthMapper._());
      McpAuthSpecMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'McpNoAuth';

  @override
  final MappableFields<McpNoAuth> fields = const {};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'none';
  @override
  late final ClassMapperBase superMapper =
      McpAuthSpecMapper.ensureInitialized();

  static McpNoAuth _instantiate(DecodingData data) {
    return McpNoAuth();
  }

  @override
  final Function instantiate = _instantiate;

  static McpNoAuth fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpNoAuth>(map);
  }

  static McpNoAuth fromJson(String json) {
    return ensureInitialized().decodeJson<McpNoAuth>(json);
  }
}

mixin McpNoAuthMappable {
  String toJson() {
    return McpNoAuthMapper.ensureInitialized().encodeJson<McpNoAuth>(
      this as McpNoAuth,
    );
  }

  Map<String, dynamic> toMap() {
    return McpNoAuthMapper.ensureInitialized().encodeMap<McpNoAuth>(
      this as McpNoAuth,
    );
  }

  McpNoAuthCopyWith<McpNoAuth, McpNoAuth, McpNoAuth> get copyWith =>
      _McpNoAuthCopyWithImpl<McpNoAuth, McpNoAuth>(
        this as McpNoAuth,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpNoAuthMapper.ensureInitialized().stringifyValue(
      this as McpNoAuth,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpNoAuthMapper.ensureInitialized().equalsValue(
      this as McpNoAuth,
      other,
    );
  }

  @override
  int get hashCode {
    return McpNoAuthMapper.ensureInitialized().hashValue(this as McpNoAuth);
  }
}

extension McpNoAuthValueCopy<$R, $Out> on ObjectCopyWith<$R, McpNoAuth, $Out> {
  McpNoAuthCopyWith<$R, McpNoAuth, $Out> get $asMcpNoAuth =>
      $base.as((v, t, t2) => _McpNoAuthCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpNoAuthCopyWith<$R, $In extends McpNoAuth, $Out>
    implements McpAuthSpecCopyWith<$R, $In, $Out> {
  @override
  $R call();
  McpNoAuthCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _McpNoAuthCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpNoAuth, $Out>
    implements McpNoAuthCopyWith<$R, McpNoAuth, $Out> {
  _McpNoAuthCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpNoAuth> $mapper =
      McpNoAuthMapper.ensureInitialized();
  @override
  $R call() => $apply(FieldCopyWithData({}));
  @override
  McpNoAuth $make(CopyWithData data) => McpNoAuth();

  @override
  McpNoAuthCopyWith<$R2, McpNoAuth, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpNoAuthCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpBearerAuthMapper extends SubClassMapperBase<McpBearerAuth> {
  McpBearerAuthMapper._();

  static McpBearerAuthMapper? _instance;
  static McpBearerAuthMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpBearerAuthMapper._());
      McpAuthSpecMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'McpBearerAuth';

  static String? _$token(McpBearerAuth v) => v.token;
  static const Field<McpBearerAuth, String> _f$token = Field(
    'token',
    _$token,
    opt: true,
  );

  @override
  final MappableFields<McpBearerAuth> fields = const {#token: _f$token};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'bearer';
  @override
  late final ClassMapperBase superMapper =
      McpAuthSpecMapper.ensureInitialized();

  static McpBearerAuth _instantiate(DecodingData data) {
    return McpBearerAuth(token: data.dec(_f$token));
  }

  @override
  final Function instantiate = _instantiate;

  static McpBearerAuth fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpBearerAuth>(map);
  }

  static McpBearerAuth fromJson(String json) {
    return ensureInitialized().decodeJson<McpBearerAuth>(json);
  }
}

mixin McpBearerAuthMappable {
  String toJson() {
    return McpBearerAuthMapper.ensureInitialized().encodeJson<McpBearerAuth>(
      this as McpBearerAuth,
    );
  }

  Map<String, dynamic> toMap() {
    return McpBearerAuthMapper.ensureInitialized().encodeMap<McpBearerAuth>(
      this as McpBearerAuth,
    );
  }

  McpBearerAuthCopyWith<McpBearerAuth, McpBearerAuth, McpBearerAuth>
  get copyWith => _McpBearerAuthCopyWithImpl<McpBearerAuth, McpBearerAuth>(
    this as McpBearerAuth,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return McpBearerAuthMapper.ensureInitialized().stringifyValue(
      this as McpBearerAuth,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpBearerAuthMapper.ensureInitialized().equalsValue(
      this as McpBearerAuth,
      other,
    );
  }

  @override
  int get hashCode {
    return McpBearerAuthMapper.ensureInitialized().hashValue(
      this as McpBearerAuth,
    );
  }
}

extension McpBearerAuthValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpBearerAuth, $Out> {
  McpBearerAuthCopyWith<$R, McpBearerAuth, $Out> get $asMcpBearerAuth =>
      $base.as((v, t, t2) => _McpBearerAuthCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpBearerAuthCopyWith<$R, $In extends McpBearerAuth, $Out>
    implements McpAuthSpecCopyWith<$R, $In, $Out> {
  @override
  $R call({String? token});
  McpBearerAuthCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _McpBearerAuthCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpBearerAuth, $Out>
    implements McpBearerAuthCopyWith<$R, McpBearerAuth, $Out> {
  _McpBearerAuthCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpBearerAuth> $mapper =
      McpBearerAuthMapper.ensureInitialized();
  @override
  $R call({Object? token = $none}) =>
      $apply(FieldCopyWithData({if (token != $none) #token: token}));
  @override
  McpBearerAuth $make(CopyWithData data) =>
      McpBearerAuth(token: data.get(#token, or: $value.token));

  @override
  McpBearerAuthCopyWith<$R2, McpBearerAuth, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpBearerAuthCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpOAuthAuthMapper extends SubClassMapperBase<McpOAuthAuth> {
  McpOAuthAuthMapper._();

  static McpOAuthAuthMapper? _instance;
  static McpOAuthAuthMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpOAuthAuthMapper._());
      McpAuthSpecMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'McpOAuthAuth';

  @override
  final MappableFields<McpOAuthAuth> fields = const {};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'oauth';
  @override
  late final ClassMapperBase superMapper =
      McpAuthSpecMapper.ensureInitialized();

  static McpOAuthAuth _instantiate(DecodingData data) {
    return McpOAuthAuth();
  }

  @override
  final Function instantiate = _instantiate;

  static McpOAuthAuth fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpOAuthAuth>(map);
  }

  static McpOAuthAuth fromJson(String json) {
    return ensureInitialized().decodeJson<McpOAuthAuth>(json);
  }
}

mixin McpOAuthAuthMappable {
  String toJson() {
    return McpOAuthAuthMapper.ensureInitialized().encodeJson<McpOAuthAuth>(
      this as McpOAuthAuth,
    );
  }

  Map<String, dynamic> toMap() {
    return McpOAuthAuthMapper.ensureInitialized().encodeMap<McpOAuthAuth>(
      this as McpOAuthAuth,
    );
  }

  McpOAuthAuthCopyWith<McpOAuthAuth, McpOAuthAuth, McpOAuthAuth> get copyWith =>
      _McpOAuthAuthCopyWithImpl<McpOAuthAuth, McpOAuthAuth>(
        this as McpOAuthAuth,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpOAuthAuthMapper.ensureInitialized().stringifyValue(
      this as McpOAuthAuth,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpOAuthAuthMapper.ensureInitialized().equalsValue(
      this as McpOAuthAuth,
      other,
    );
  }

  @override
  int get hashCode {
    return McpOAuthAuthMapper.ensureInitialized().hashValue(
      this as McpOAuthAuth,
    );
  }
}

extension McpOAuthAuthValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpOAuthAuth, $Out> {
  McpOAuthAuthCopyWith<$R, McpOAuthAuth, $Out> get $asMcpOAuthAuth =>
      $base.as((v, t, t2) => _McpOAuthAuthCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpOAuthAuthCopyWith<$R, $In extends McpOAuthAuth, $Out>
    implements McpAuthSpecCopyWith<$R, $In, $Out> {
  @override
  $R call();
  McpOAuthAuthCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _McpOAuthAuthCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpOAuthAuth, $Out>
    implements McpOAuthAuthCopyWith<$R, McpOAuthAuth, $Out> {
  _McpOAuthAuthCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpOAuthAuth> $mapper =
      McpOAuthAuthMapper.ensureInitialized();
  @override
  $R call() => $apply(FieldCopyWithData({}));
  @override
  McpOAuthAuth $make(CopyWithData data) => McpOAuthAuth();

  @override
  McpOAuthAuthCopyWith<$R2, McpOAuthAuth, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpOAuthAuthCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpToolPolicyMapper extends ClassMapperBase<McpToolPolicy> {
  McpToolPolicyMapper._();

  static McpToolPolicyMapper? _instance;
  static McpToolPolicyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpToolPolicyMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'McpToolPolicy';

  static List<String> _$autoApprove(McpToolPolicy v) => v.autoApprove;
  static const Field<McpToolPolicy, List<String>> _f$autoApprove = Field(
    'autoApprove',
    _$autoApprove,
    opt: true,
    def: const [],
  );
  static List<String> _$deny(McpToolPolicy v) => v.deny;
  static const Field<McpToolPolicy, List<String>> _f$deny = Field(
    'deny',
    _$deny,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<McpToolPolicy> fields = const {
    #autoApprove: _f$autoApprove,
    #deny: _f$deny,
  };

  static McpToolPolicy _instantiate(DecodingData data) {
    return McpToolPolicy(
      autoApprove: data.dec(_f$autoApprove),
      deny: data.dec(_f$deny),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpToolPolicy fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpToolPolicy>(map);
  }

  static McpToolPolicy fromJson(String json) {
    return ensureInitialized().decodeJson<McpToolPolicy>(json);
  }
}

mixin McpToolPolicyMappable {
  String toJson() {
    return McpToolPolicyMapper.ensureInitialized().encodeJson<McpToolPolicy>(
      this as McpToolPolicy,
    );
  }

  Map<String, dynamic> toMap() {
    return McpToolPolicyMapper.ensureInitialized().encodeMap<McpToolPolicy>(
      this as McpToolPolicy,
    );
  }

  McpToolPolicyCopyWith<McpToolPolicy, McpToolPolicy, McpToolPolicy>
  get copyWith => _McpToolPolicyCopyWithImpl<McpToolPolicy, McpToolPolicy>(
    this as McpToolPolicy,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return McpToolPolicyMapper.ensureInitialized().stringifyValue(
      this as McpToolPolicy,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpToolPolicyMapper.ensureInitialized().equalsValue(
      this as McpToolPolicy,
      other,
    );
  }

  @override
  int get hashCode {
    return McpToolPolicyMapper.ensureInitialized().hashValue(
      this as McpToolPolicy,
    );
  }
}

extension McpToolPolicyValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpToolPolicy, $Out> {
  McpToolPolicyCopyWith<$R, McpToolPolicy, $Out> get $asMcpToolPolicy =>
      $base.as((v, t, t2) => _McpToolPolicyCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpToolPolicyCopyWith<$R, $In extends McpToolPolicy, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get autoApprove;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get deny;
  $R call({List<String>? autoApprove, List<String>? deny});
  McpToolPolicyCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _McpToolPolicyCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpToolPolicy, $Out>
    implements McpToolPolicyCopyWith<$R, McpToolPolicy, $Out> {
  _McpToolPolicyCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpToolPolicy> $mapper =
      McpToolPolicyMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get autoApprove => ListCopyWith(
    $value.autoApprove,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(autoApprove: v),
  );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get deny =>
      ListCopyWith(
        $value.deny,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(deny: v),
      );
  @override
  $R call({List<String>? autoApprove, List<String>? deny}) => $apply(
    FieldCopyWithData({
      if (autoApprove != null) #autoApprove: autoApprove,
      if (deny != null) #deny: deny,
    }),
  );
  @override
  McpToolPolicy $make(CopyWithData data) => McpToolPolicy(
    autoApprove: data.get(#autoApprove, or: $value.autoApprove),
    deny: data.get(#deny, or: $value.deny),
  );

  @override
  McpToolPolicyCopyWith<$R2, McpToolPolicy, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpToolPolicyCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpReconnectPolicyMapper extends ClassMapperBase<McpReconnectPolicy> {
  McpReconnectPolicyMapper._();

  static McpReconnectPolicyMapper? _instance;
  static McpReconnectPolicyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpReconnectPolicyMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'McpReconnectPolicy';

  static bool _$enabled(McpReconnectPolicy v) => v.enabled;
  static const Field<McpReconnectPolicy, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int _$initialDelayMs(McpReconnectPolicy v) => v.initialDelayMs;
  static const Field<McpReconnectPolicy, int> _f$initialDelayMs = Field(
    'initialDelayMs',
    _$initialDelayMs,
    opt: true,
    def: 500,
  );
  static int _$maxDelayMs(McpReconnectPolicy v) => v.maxDelayMs;
  static const Field<McpReconnectPolicy, int> _f$maxDelayMs = Field(
    'maxDelayMs',
    _$maxDelayMs,
    opt: true,
    def: 30000,
  );
  static int _$maxAttempts(McpReconnectPolicy v) => v.maxAttempts;
  static const Field<McpReconnectPolicy, int> _f$maxAttempts = Field(
    'maxAttempts',
    _$maxAttempts,
    opt: true,
    def: 10,
  );

  @override
  final MappableFields<McpReconnectPolicy> fields = const {
    #enabled: _f$enabled,
    #initialDelayMs: _f$initialDelayMs,
    #maxDelayMs: _f$maxDelayMs,
    #maxAttempts: _f$maxAttempts,
  };

  static McpReconnectPolicy _instantiate(DecodingData data) {
    return McpReconnectPolicy(
      enabled: data.dec(_f$enabled),
      initialDelayMs: data.dec(_f$initialDelayMs),
      maxDelayMs: data.dec(_f$maxDelayMs),
      maxAttempts: data.dec(_f$maxAttempts),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpReconnectPolicy fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpReconnectPolicy>(map);
  }

  static McpReconnectPolicy fromJson(String json) {
    return ensureInitialized().decodeJson<McpReconnectPolicy>(json);
  }
}

mixin McpReconnectPolicyMappable {
  String toJson() {
    return McpReconnectPolicyMapper.ensureInitialized()
        .encodeJson<McpReconnectPolicy>(this as McpReconnectPolicy);
  }

  Map<String, dynamic> toMap() {
    return McpReconnectPolicyMapper.ensureInitialized()
        .encodeMap<McpReconnectPolicy>(this as McpReconnectPolicy);
  }

  McpReconnectPolicyCopyWith<
    McpReconnectPolicy,
    McpReconnectPolicy,
    McpReconnectPolicy
  >
  get copyWith =>
      _McpReconnectPolicyCopyWithImpl<McpReconnectPolicy, McpReconnectPolicy>(
        this as McpReconnectPolicy,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpReconnectPolicyMapper.ensureInitialized().stringifyValue(
      this as McpReconnectPolicy,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpReconnectPolicyMapper.ensureInitialized().equalsValue(
      this as McpReconnectPolicy,
      other,
    );
  }

  @override
  int get hashCode {
    return McpReconnectPolicyMapper.ensureInitialized().hashValue(
      this as McpReconnectPolicy,
    );
  }
}

extension McpReconnectPolicyValueCopy<$R, $Out>
    on ObjectCopyWith<$R, McpReconnectPolicy, $Out> {
  McpReconnectPolicyCopyWith<$R, McpReconnectPolicy, $Out>
  get $asMcpReconnectPolicy => $base.as(
    (v, t, t2) => _McpReconnectPolicyCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class McpReconnectPolicyCopyWith<
  $R,
  $In extends McpReconnectPolicy,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? enabled,
    int? initialDelayMs,
    int? maxDelayMs,
    int? maxAttempts,
  });
  McpReconnectPolicyCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _McpReconnectPolicyCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpReconnectPolicy, $Out>
    implements McpReconnectPolicyCopyWith<$R, McpReconnectPolicy, $Out> {
  _McpReconnectPolicyCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpReconnectPolicy> $mapper =
      McpReconnectPolicyMapper.ensureInitialized();
  @override
  $R call({
    bool? enabled,
    int? initialDelayMs,
    int? maxDelayMs,
    int? maxAttempts,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (initialDelayMs != null) #initialDelayMs: initialDelayMs,
      if (maxDelayMs != null) #maxDelayMs: maxDelayMs,
      if (maxAttempts != null) #maxAttempts: maxAttempts,
    }),
  );
  @override
  McpReconnectPolicy $make(CopyWithData data) => McpReconnectPolicy(
    enabled: data.get(#enabled, or: $value.enabled),
    initialDelayMs: data.get(#initialDelayMs, or: $value.initialDelayMs),
    maxDelayMs: data.get(#maxDelayMs, or: $value.maxDelayMs),
    maxAttempts: data.get(#maxAttempts, or: $value.maxAttempts),
  );

  @override
  McpReconnectPolicyCopyWith<$R2, McpReconnectPolicy, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpReconnectPolicyCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class McpConfigMapper extends ClassMapperBase<McpConfig> {
  McpConfigMapper._();

  static McpConfigMapper? _instance;
  static McpConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = McpConfigMapper._());
      McpServerSpecMapper.ensureInitialized();
      McpToolPolicyMapper.ensureInitialized();
      McpReconnectPolicyMapper.ensureInitialized();
      McpSubprocessEnvModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'McpConfig';

  static List<McpServerSpec> _$servers(McpConfig v) => v.servers;
  static const Field<McpConfig, List<McpServerSpec>> _f$servers = Field(
    'servers',
    _$servers,
    opt: true,
    def: const [],
  );
  static McpToolPolicy _$toolPolicy(McpConfig v) => v.toolPolicy;
  static const Field<McpConfig, McpToolPolicy> _f$toolPolicy = Field(
    'toolPolicy',
    _$toolPolicy,
    opt: true,
    def: const McpToolPolicy(),
  );
  static McpReconnectPolicy _$reconnect(McpConfig v) => v.reconnect;
  static const Field<McpConfig, McpReconnectPolicy> _f$reconnect = Field(
    'reconnect',
    _$reconnect,
    opt: true,
    def: const McpReconnectPolicy(),
  );
  static int _$callTimeoutSeconds(McpConfig v) => v.callTimeoutSeconds;
  static const Field<McpConfig, int> _f$callTimeoutSeconds = Field(
    'callTimeoutSeconds',
    _$callTimeoutSeconds,
    opt: true,
    def: 30,
  );
  static McpSubprocessEnvMode _$subprocessEnv(McpConfig v) => v.subprocessEnv;
  static const Field<McpConfig, McpSubprocessEnvMode> _f$subprocessEnv = Field(
    'subprocessEnv',
    _$subprocessEnv,
    opt: true,
    def: McpSubprocessEnvMode.allowlist,
  );

  @override
  final MappableFields<McpConfig> fields = const {
    #servers: _f$servers,
    #toolPolicy: _f$toolPolicy,
    #reconnect: _f$reconnect,
    #callTimeoutSeconds: _f$callTimeoutSeconds,
    #subprocessEnv: _f$subprocessEnv,
  };

  static McpConfig _instantiate(DecodingData data) {
    return McpConfig(
      servers: data.dec(_f$servers),
      toolPolicy: data.dec(_f$toolPolicy),
      reconnect: data.dec(_f$reconnect),
      callTimeoutSeconds: data.dec(_f$callTimeoutSeconds),
      subprocessEnv: data.dec(_f$subprocessEnv),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static McpConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<McpConfig>(map);
  }

  static McpConfig fromJson(String json) {
    return ensureInitialized().decodeJson<McpConfig>(json);
  }
}

mixin McpConfigMappable {
  String toJson() {
    return McpConfigMapper.ensureInitialized().encodeJson<McpConfig>(
      this as McpConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return McpConfigMapper.ensureInitialized().encodeMap<McpConfig>(
      this as McpConfig,
    );
  }

  McpConfigCopyWith<McpConfig, McpConfig, McpConfig> get copyWith =>
      _McpConfigCopyWithImpl<McpConfig, McpConfig>(
        this as McpConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return McpConfigMapper.ensureInitialized().stringifyValue(
      this as McpConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return McpConfigMapper.ensureInitialized().equalsValue(
      this as McpConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return McpConfigMapper.ensureInitialized().hashValue(this as McpConfig);
  }
}

extension McpConfigValueCopy<$R, $Out> on ObjectCopyWith<$R, McpConfig, $Out> {
  McpConfigCopyWith<$R, McpConfig, $Out> get $asMcpConfig =>
      $base.as((v, t, t2) => _McpConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class McpConfigCopyWith<$R, $In extends McpConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    McpServerSpec,
    McpServerSpecCopyWith<$R, McpServerSpec, McpServerSpec>
  >
  get servers;
  McpToolPolicyCopyWith<$R, McpToolPolicy, McpToolPolicy> get toolPolicy;
  McpReconnectPolicyCopyWith<$R, McpReconnectPolicy, McpReconnectPolicy>
  get reconnect;
  $R call({
    List<McpServerSpec>? servers,
    McpToolPolicy? toolPolicy,
    McpReconnectPolicy? reconnect,
    int? callTimeoutSeconds,
    McpSubprocessEnvMode? subprocessEnv,
  });
  McpConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _McpConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, McpConfig, $Out>
    implements McpConfigCopyWith<$R, McpConfig, $Out> {
  _McpConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<McpConfig> $mapper =
      McpConfigMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    McpServerSpec,
    McpServerSpecCopyWith<$R, McpServerSpec, McpServerSpec>
  >
  get servers => ListCopyWith(
    $value.servers,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(servers: v),
  );
  @override
  McpToolPolicyCopyWith<$R, McpToolPolicy, McpToolPolicy> get toolPolicy =>
      $value.toolPolicy.copyWith.$chain((v) => call(toolPolicy: v));
  @override
  McpReconnectPolicyCopyWith<$R, McpReconnectPolicy, McpReconnectPolicy>
  get reconnect => $value.reconnect.copyWith.$chain((v) => call(reconnect: v));
  @override
  $R call({
    List<McpServerSpec>? servers,
    McpToolPolicy? toolPolicy,
    McpReconnectPolicy? reconnect,
    int? callTimeoutSeconds,
    McpSubprocessEnvMode? subprocessEnv,
  }) => $apply(
    FieldCopyWithData({
      if (servers != null) #servers: servers,
      if (toolPolicy != null) #toolPolicy: toolPolicy,
      if (reconnect != null) #reconnect: reconnect,
      if (callTimeoutSeconds != null) #callTimeoutSeconds: callTimeoutSeconds,
      if (subprocessEnv != null) #subprocessEnv: subprocessEnv,
    }),
  );
  @override
  McpConfig $make(CopyWithData data) => McpConfig(
    servers: data.get(#servers, or: $value.servers),
    toolPolicy: data.get(#toolPolicy, or: $value.toolPolicy),
    reconnect: data.get(#reconnect, or: $value.reconnect),
    callTimeoutSeconds: data.get(
      #callTimeoutSeconds,
      or: $value.callTimeoutSeconds,
    ),
    subprocessEnv: data.get(#subprocessEnv, or: $value.subprocessEnv),
  );

  @override
  McpConfigCopyWith<$R2, McpConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _McpConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

