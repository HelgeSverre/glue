// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'config_file.dart';

class ConfigFileMapper extends ClassMapperBase<ConfigFile> {
  ConfigFileMapper._();

  static ConfigFileMapper? _instance;
  static ConfigFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConfigFileMapper._());
      CatalogSectionConfigMapper.ensureInitialized();
      BashSectionConfigMapper.ensureInitialized();
      ShellSectionConfigMapper.ensureInitialized();
      DockerSectionConfigMapper.ensureInitialized();
      WebSectionConfigMapper.ensureInitialized();
      ObservabilitySectionConfigMapper.ensureInitialized();
      SkillsSectionConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ConfigFile';

  static String? _$activeModel(ConfigFile v) => v.activeModel;
  static const Field<ConfigFile, String> _f$activeModel = Field(
    'activeModel',
    _$activeModel,
    key: r'active_model',
    opt: true,
  );
  static String? _$smallModel(ConfigFile v) => v.smallModel;
  static const Field<ConfigFile, String> _f$smallModel = Field(
    'smallModel',
    _$smallModel,
    key: r'small_model',
    opt: true,
  );
  static Map<String, String>? _$profiles(ConfigFile v) => v.profiles;
  static const Field<ConfigFile, Map<String, String>> _f$profiles = Field(
    'profiles',
    _$profiles,
    opt: true,
  );
  static CatalogSectionConfig? _$catalog(ConfigFile v) => v.catalog;
  static const Field<ConfigFile, CatalogSectionConfig> _f$catalog = Field(
    'catalog',
    _$catalog,
    opt: true,
  );
  static BashSectionConfig? _$bash(ConfigFile v) => v.bash;
  static const Field<ConfigFile, BashSectionConfig> _f$bash = Field(
    'bash',
    _$bash,
    opt: true,
  );
  static ShellSectionConfig? _$shell(ConfigFile v) => v.shell;
  static const Field<ConfigFile, ShellSectionConfig> _f$shell = Field(
    'shell',
    _$shell,
    opt: true,
  );
  static DockerSectionConfig? _$docker(ConfigFile v) => v.docker;
  static const Field<ConfigFile, DockerSectionConfig> _f$docker = Field(
    'docker',
    _$docker,
    opt: true,
  );
  static WebSectionConfig? _$web(ConfigFile v) => v.web;
  static const Field<ConfigFile, WebSectionConfig> _f$web = Field(
    'web',
    _$web,
    opt: true,
  );
  static ObservabilitySectionConfig? _$observability(ConfigFile v) =>
      v.observability;
  static const Field<ConfigFile, ObservabilitySectionConfig> _f$observability =
      Field('observability', _$observability, opt: true);
  static Map<String, dynamic>? _$mcp(ConfigFile v) => v.mcp;
  static const Field<ConfigFile, Map<String, dynamic>> _f$mcp = Field(
    'mcp',
    _$mcp,
    opt: true,
  );
  static String? _$runtime(ConfigFile v) => v.runtime;
  static const Field<ConfigFile, String> _f$runtime = Field(
    'runtime',
    _$runtime,
    opt: true,
  );
  static SkillsSectionConfig? _$skills(ConfigFile v) => v.skills;
  static const Field<ConfigFile, SkillsSectionConfig> _f$skills = Field(
    'skills',
    _$skills,
    opt: true,
  );
  static bool? _$titleGenerationEnabled(ConfigFile v) =>
      v.titleGenerationEnabled;
  static const Field<ConfigFile, bool> _f$titleGenerationEnabled = Field(
    'titleGenerationEnabled',
    _$titleGenerationEnabled,
    key: r'title_generation_enabled',
    opt: true,
  );
  static bool? _$anthropicPromptCache(ConfigFile v) => v.anthropicPromptCache;
  static const Field<ConfigFile, bool> _f$anthropicPromptCache = Field(
    'anthropicPromptCache',
    _$anthropicPromptCache,
    key: r'anthropic_prompt_cache',
    opt: true,
  );
  static String? _$approvalMode(ConfigFile v) => v.approvalMode;
  static const Field<ConfigFile, String> _f$approvalMode = Field(
    'approvalMode',
    _$approvalMode,
    key: r'approval_mode',
    opt: true,
  );

  @override
  final MappableFields<ConfigFile> fields = const {
    #activeModel: _f$activeModel,
    #smallModel: _f$smallModel,
    #profiles: _f$profiles,
    #catalog: _f$catalog,
    #bash: _f$bash,
    #shell: _f$shell,
    #docker: _f$docker,
    #web: _f$web,
    #observability: _f$observability,
    #mcp: _f$mcp,
    #runtime: _f$runtime,
    #skills: _f$skills,
    #titleGenerationEnabled: _f$titleGenerationEnabled,
    #anthropicPromptCache: _f$anthropicPromptCache,
    #approvalMode: _f$approvalMode,
  };
  @override
  final bool ignoreNull = true;

  static ConfigFile _instantiate(DecodingData data) {
    return ConfigFile(
      activeModel: data.dec(_f$activeModel),
      smallModel: data.dec(_f$smallModel),
      profiles: data.dec(_f$profiles),
      catalog: data.dec(_f$catalog),
      bash: data.dec(_f$bash),
      shell: data.dec(_f$shell),
      docker: data.dec(_f$docker),
      web: data.dec(_f$web),
      observability: data.dec(_f$observability),
      mcp: data.dec(_f$mcp),
      runtime: data.dec(_f$runtime),
      skills: data.dec(_f$skills),
      titleGenerationEnabled: data.dec(_f$titleGenerationEnabled),
      anthropicPromptCache: data.dec(_f$anthropicPromptCache),
      approvalMode: data.dec(_f$approvalMode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ConfigFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ConfigFile>(map);
  }

  static ConfigFile fromJson(String json) {
    return ensureInitialized().decodeJson<ConfigFile>(json);
  }
}

mixin ConfigFileMappable {
  String toJson() {
    return ConfigFileMapper.ensureInitialized().encodeJson<ConfigFile>(
      this as ConfigFile,
    );
  }

  Map<String, dynamic> toMap() {
    return ConfigFileMapper.ensureInitialized().encodeMap<ConfigFile>(
      this as ConfigFile,
    );
  }

  ConfigFileCopyWith<ConfigFile, ConfigFile, ConfigFile> get copyWith =>
      _ConfigFileCopyWithImpl<ConfigFile, ConfigFile>(
        this as ConfigFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ConfigFileMapper.ensureInitialized().stringifyValue(
      this as ConfigFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return ConfigFileMapper.ensureInitialized().equalsValue(
      this as ConfigFile,
      other,
    );
  }

  @override
  int get hashCode {
    return ConfigFileMapper.ensureInitialized().hashValue(this as ConfigFile);
  }
}

extension ConfigFileValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ConfigFile, $Out> {
  ConfigFileCopyWith<$R, ConfigFile, $Out> get $asConfigFile =>
      $base.as((v, t, t2) => _ConfigFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ConfigFileCopyWith<$R, $In extends ConfigFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get profiles;
  CatalogSectionConfigCopyWith<$R, CatalogSectionConfig, CatalogSectionConfig>?
  get catalog;
  BashSectionConfigCopyWith<$R, BashSectionConfig, BashSectionConfig>? get bash;
  ShellSectionConfigCopyWith<$R, ShellSectionConfig, ShellSectionConfig>?
  get shell;
  DockerSectionConfigCopyWith<$R, DockerSectionConfig, DockerSectionConfig>?
  get docker;
  WebSectionConfigCopyWith<$R, WebSectionConfig, WebSectionConfig>? get web;
  ObservabilitySectionConfigCopyWith<
    $R,
    ObservabilitySectionConfig,
    ObservabilitySectionConfig
  >?
  get observability;
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get mcp;
  SkillsSectionConfigCopyWith<$R, SkillsSectionConfig, SkillsSectionConfig>?
  get skills;
  $R call({
    String? activeModel,
    String? smallModel,
    Map<String, String>? profiles,
    CatalogSectionConfig? catalog,
    BashSectionConfig? bash,
    ShellSectionConfig? shell,
    DockerSectionConfig? docker,
    WebSectionConfig? web,
    ObservabilitySectionConfig? observability,
    Map<String, dynamic>? mcp,
    String? runtime,
    SkillsSectionConfig? skills,
    bool? titleGenerationEnabled,
    bool? anthropicPromptCache,
    String? approvalMode,
  });
  ConfigFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ConfigFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ConfigFile, $Out>
    implements ConfigFileCopyWith<$R, ConfigFile, $Out> {
  _ConfigFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ConfigFile> $mapper =
      ConfigFileMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get profiles => $value.profiles != null
      ? MapCopyWith(
          $value.profiles!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(profiles: v),
        )
      : null;
  @override
  CatalogSectionConfigCopyWith<$R, CatalogSectionConfig, CatalogSectionConfig>?
  get catalog => $value.catalog?.copyWith.$chain((v) => call(catalog: v));
  @override
  BashSectionConfigCopyWith<$R, BashSectionConfig, BashSectionConfig>?
  get bash => $value.bash?.copyWith.$chain((v) => call(bash: v));
  @override
  ShellSectionConfigCopyWith<$R, ShellSectionConfig, ShellSectionConfig>?
  get shell => $value.shell?.copyWith.$chain((v) => call(shell: v));
  @override
  DockerSectionConfigCopyWith<$R, DockerSectionConfig, DockerSectionConfig>?
  get docker => $value.docker?.copyWith.$chain((v) => call(docker: v));
  @override
  WebSectionConfigCopyWith<$R, WebSectionConfig, WebSectionConfig>? get web =>
      $value.web?.copyWith.$chain((v) => call(web: v));
  @override
  ObservabilitySectionConfigCopyWith<
    $R,
    ObservabilitySectionConfig,
    ObservabilitySectionConfig
  >?
  get observability =>
      $value.observability?.copyWith.$chain((v) => call(observability: v));
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get mcp => $value.mcp != null
      ? MapCopyWith(
          $value.mcp!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(mcp: v),
        )
      : null;
  @override
  SkillsSectionConfigCopyWith<$R, SkillsSectionConfig, SkillsSectionConfig>?
  get skills => $value.skills?.copyWith.$chain((v) => call(skills: v));
  @override
  $R call({
    Object? activeModel = $none,
    Object? smallModel = $none,
    Object? profiles = $none,
    Object? catalog = $none,
    Object? bash = $none,
    Object? shell = $none,
    Object? docker = $none,
    Object? web = $none,
    Object? observability = $none,
    Object? mcp = $none,
    Object? runtime = $none,
    Object? skills = $none,
    Object? titleGenerationEnabled = $none,
    Object? anthropicPromptCache = $none,
    Object? approvalMode = $none,
  }) => $apply(
    FieldCopyWithData({
      if (activeModel != $none) #activeModel: activeModel,
      if (smallModel != $none) #smallModel: smallModel,
      if (profiles != $none) #profiles: profiles,
      if (catalog != $none) #catalog: catalog,
      if (bash != $none) #bash: bash,
      if (shell != $none) #shell: shell,
      if (docker != $none) #docker: docker,
      if (web != $none) #web: web,
      if (observability != $none) #observability: observability,
      if (mcp != $none) #mcp: mcp,
      if (runtime != $none) #runtime: runtime,
      if (skills != $none) #skills: skills,
      if (titleGenerationEnabled != $none)
        #titleGenerationEnabled: titleGenerationEnabled,
      if (anthropicPromptCache != $none)
        #anthropicPromptCache: anthropicPromptCache,
      if (approvalMode != $none) #approvalMode: approvalMode,
    }),
  );
  @override
  ConfigFile $make(CopyWithData data) => ConfigFile(
    activeModel: data.get(#activeModel, or: $value.activeModel),
    smallModel: data.get(#smallModel, or: $value.smallModel),
    profiles: data.get(#profiles, or: $value.profiles),
    catalog: data.get(#catalog, or: $value.catalog),
    bash: data.get(#bash, or: $value.bash),
    shell: data.get(#shell, or: $value.shell),
    docker: data.get(#docker, or: $value.docker),
    web: data.get(#web, or: $value.web),
    observability: data.get(#observability, or: $value.observability),
    mcp: data.get(#mcp, or: $value.mcp),
    runtime: data.get(#runtime, or: $value.runtime),
    skills: data.get(#skills, or: $value.skills),
    titleGenerationEnabled: data.get(
      #titleGenerationEnabled,
      or: $value.titleGenerationEnabled,
    ),
    anthropicPromptCache: data.get(
      #anthropicPromptCache,
      or: $value.anthropicPromptCache,
    ),
    approvalMode: data.get(#approvalMode, or: $value.approvalMode),
  );

  @override
  ConfigFileCopyWith<$R2, ConfigFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ConfigFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class CatalogSectionConfigMapper extends ClassMapperBase<CatalogSectionConfig> {
  CatalogSectionConfigMapper._();

  static CatalogSectionConfigMapper? _instance;
  static CatalogSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CatalogSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'CatalogSectionConfig';

  static String? _$refresh(CatalogSectionConfig v) => v.refresh;
  static const Field<CatalogSectionConfig, String> _f$refresh = Field(
    'refresh',
    _$refresh,
    opt: true,
  );
  static String? _$remoteUrl(CatalogSectionConfig v) => v.remoteUrl;
  static const Field<CatalogSectionConfig, String> _f$remoteUrl = Field(
    'remoteUrl',
    _$remoteUrl,
    key: r'remote_url',
    opt: true,
  );

  @override
  final MappableFields<CatalogSectionConfig> fields = const {
    #refresh: _f$refresh,
    #remoteUrl: _f$remoteUrl,
  };

  static CatalogSectionConfig _instantiate(DecodingData data) {
    return CatalogSectionConfig(
      refresh: data.dec(_f$refresh),
      remoteUrl: data.dec(_f$remoteUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static CatalogSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CatalogSectionConfig>(map);
  }

  static CatalogSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<CatalogSectionConfig>(json);
  }
}

mixin CatalogSectionConfigMappable {
  String toJson() {
    return CatalogSectionConfigMapper.ensureInitialized()
        .encodeJson<CatalogSectionConfig>(this as CatalogSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return CatalogSectionConfigMapper.ensureInitialized()
        .encodeMap<CatalogSectionConfig>(this as CatalogSectionConfig);
  }

  CatalogSectionConfigCopyWith<
    CatalogSectionConfig,
    CatalogSectionConfig,
    CatalogSectionConfig
  >
  get copyWith =>
      _CatalogSectionConfigCopyWithImpl<
        CatalogSectionConfig,
        CatalogSectionConfig
      >(this as CatalogSectionConfig, $identity, $identity);
  @override
  String toString() {
    return CatalogSectionConfigMapper.ensureInitialized().stringifyValue(
      this as CatalogSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return CatalogSectionConfigMapper.ensureInitialized().equalsValue(
      this as CatalogSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return CatalogSectionConfigMapper.ensureInitialized().hashValue(
      this as CatalogSectionConfig,
    );
  }
}

extension CatalogSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, CatalogSectionConfig, $Out> {
  CatalogSectionConfigCopyWith<$R, CatalogSectionConfig, $Out>
  get $asCatalogSectionConfig => $base.as(
    (v, t, t2) => _CatalogSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class CatalogSectionConfigCopyWith<
  $R,
  $In extends CatalogSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? refresh, String? remoteUrl});
  CatalogSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _CatalogSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, CatalogSectionConfig, $Out>
    implements CatalogSectionConfigCopyWith<$R, CatalogSectionConfig, $Out> {
  _CatalogSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<CatalogSectionConfig> $mapper =
      CatalogSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? refresh = $none, Object? remoteUrl = $none}) => $apply(
    FieldCopyWithData({
      if (refresh != $none) #refresh: refresh,
      if (remoteUrl != $none) #remoteUrl: remoteUrl,
    }),
  );
  @override
  CatalogSectionConfig $make(CopyWithData data) => CatalogSectionConfig(
    refresh: data.get(#refresh, or: $value.refresh),
    remoteUrl: data.get(#remoteUrl, or: $value.remoteUrl),
  );

  @override
  CatalogSectionConfigCopyWith<$R2, CatalogSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _CatalogSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BashSectionConfigMapper extends ClassMapperBase<BashSectionConfig> {
  BashSectionConfigMapper._();

  static BashSectionConfigMapper? _instance;
  static BashSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BashSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'BashSectionConfig';

  static int? _$maxLines(BashSectionConfig v) => v.maxLines;
  static const Field<BashSectionConfig, int> _f$maxLines = Field(
    'maxLines',
    _$maxLines,
    key: r'max_lines',
    opt: true,
  );

  @override
  final MappableFields<BashSectionConfig> fields = const {
    #maxLines: _f$maxLines,
  };

  static BashSectionConfig _instantiate(DecodingData data) {
    return BashSectionConfig(maxLines: data.dec(_f$maxLines));
  }

  @override
  final Function instantiate = _instantiate;

  static BashSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BashSectionConfig>(map);
  }

  static BashSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<BashSectionConfig>(json);
  }
}

mixin BashSectionConfigMappable {
  String toJson() {
    return BashSectionConfigMapper.ensureInitialized()
        .encodeJson<BashSectionConfig>(this as BashSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return BashSectionConfigMapper.ensureInitialized()
        .encodeMap<BashSectionConfig>(this as BashSectionConfig);
  }

  BashSectionConfigCopyWith<
    BashSectionConfig,
    BashSectionConfig,
    BashSectionConfig
  >
  get copyWith =>
      _BashSectionConfigCopyWithImpl<BashSectionConfig, BashSectionConfig>(
        this as BashSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BashSectionConfigMapper.ensureInitialized().stringifyValue(
      this as BashSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return BashSectionConfigMapper.ensureInitialized().equalsValue(
      this as BashSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return BashSectionConfigMapper.ensureInitialized().hashValue(
      this as BashSectionConfig,
    );
  }
}

extension BashSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BashSectionConfig, $Out> {
  BashSectionConfigCopyWith<$R, BashSectionConfig, $Out>
  get $asBashSectionConfig => $base.as(
    (v, t, t2) => _BashSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BashSectionConfigCopyWith<
  $R,
  $In extends BashSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? maxLines});
  BashSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BashSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BashSectionConfig, $Out>
    implements BashSectionConfigCopyWith<$R, BashSectionConfig, $Out> {
  _BashSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BashSectionConfig> $mapper =
      BashSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? maxLines = $none}) =>
      $apply(FieldCopyWithData({if (maxLines != $none) #maxLines: maxLines}));
  @override
  BashSectionConfig $make(CopyWithData data) =>
      BashSectionConfig(maxLines: data.get(#maxLines, or: $value.maxLines));

  @override
  BashSectionConfigCopyWith<$R2, BashSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BashSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ShellSectionConfigMapper extends ClassMapperBase<ShellSectionConfig> {
  ShellSectionConfigMapper._();

  static ShellSectionConfigMapper? _instance;
  static ShellSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShellSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ShellSectionConfig';

  static String? _$executable(ShellSectionConfig v) => v.executable;
  static const Field<ShellSectionConfig, String> _f$executable = Field(
    'executable',
    _$executable,
    opt: true,
  );
  static String? _$mode(ShellSectionConfig v) => v.mode;
  static const Field<ShellSectionConfig, String> _f$mode = Field(
    'mode',
    _$mode,
    opt: true,
  );

  @override
  final MappableFields<ShellSectionConfig> fields = const {
    #executable: _f$executable,
    #mode: _f$mode,
  };

  static ShellSectionConfig _instantiate(DecodingData data) {
    return ShellSectionConfig(
      executable: data.dec(_f$executable),
      mode: data.dec(_f$mode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ShellSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShellSectionConfig>(map);
  }

  static ShellSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ShellSectionConfig>(json);
  }
}

mixin ShellSectionConfigMappable {
  String toJson() {
    return ShellSectionConfigMapper.ensureInitialized()
        .encodeJson<ShellSectionConfig>(this as ShellSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return ShellSectionConfigMapper.ensureInitialized()
        .encodeMap<ShellSectionConfig>(this as ShellSectionConfig);
  }

  ShellSectionConfigCopyWith<
    ShellSectionConfig,
    ShellSectionConfig,
    ShellSectionConfig
  >
  get copyWith =>
      _ShellSectionConfigCopyWithImpl<ShellSectionConfig, ShellSectionConfig>(
        this as ShellSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShellSectionConfigMapper.ensureInitialized().stringifyValue(
      this as ShellSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShellSectionConfigMapper.ensureInitialized().equalsValue(
      this as ShellSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ShellSectionConfigMapper.ensureInitialized().hashValue(
      this as ShellSectionConfig,
    );
  }
}

extension ShellSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ShellSectionConfig, $Out> {
  ShellSectionConfigCopyWith<$R, ShellSectionConfig, $Out>
  get $asShellSectionConfig => $base.as(
    (v, t, t2) => _ShellSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ShellSectionConfigCopyWith<
  $R,
  $In extends ShellSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? executable, String? mode});
  ShellSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ShellSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShellSectionConfig, $Out>
    implements ShellSectionConfigCopyWith<$R, ShellSectionConfig, $Out> {
  _ShellSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShellSectionConfig> $mapper =
      ShellSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? executable = $none, Object? mode = $none}) => $apply(
    FieldCopyWithData({
      if (executable != $none) #executable: executable,
      if (mode != $none) #mode: mode,
    }),
  );
  @override
  ShellSectionConfig $make(CopyWithData data) => ShellSectionConfig(
    executable: data.get(#executable, or: $value.executable),
    mode: data.get(#mode, or: $value.mode),
  );

  @override
  ShellSectionConfigCopyWith<$R2, ShellSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShellSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DockerSectionConfigMapper extends ClassMapperBase<DockerSectionConfig> {
  DockerSectionConfigMapper._();

  static DockerSectionConfigMapper? _instance;
  static DockerSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DockerSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'DockerSectionConfig';

  static bool? _$enabled(DockerSectionConfig v) => v.enabled;
  static const Field<DockerSectionConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
  );
  static String? _$image(DockerSectionConfig v) => v.image;
  static const Field<DockerSectionConfig, String> _f$image = Field(
    'image',
    _$image,
    opt: true,
  );
  static String? _$shell(DockerSectionConfig v) => v.shell;
  static const Field<DockerSectionConfig, String> _f$shell = Field(
    'shell',
    _$shell,
    opt: true,
  );
  static bool? _$fallbackToHost(DockerSectionConfig v) => v.fallbackToHost;
  static const Field<DockerSectionConfig, bool> _f$fallbackToHost = Field(
    'fallbackToHost',
    _$fallbackToHost,
    key: r'fallback_to_host',
    opt: true,
  );
  static List<String>? _$mounts(DockerSectionConfig v) => v.mounts;
  static const Field<DockerSectionConfig, List<String>> _f$mounts = Field(
    'mounts',
    _$mounts,
    opt: true,
  );

  @override
  final MappableFields<DockerSectionConfig> fields = const {
    #enabled: _f$enabled,
    #image: _f$image,
    #shell: _f$shell,
    #fallbackToHost: _f$fallbackToHost,
    #mounts: _f$mounts,
  };

  static DockerSectionConfig _instantiate(DecodingData data) {
    return DockerSectionConfig(
      enabled: data.dec(_f$enabled),
      image: data.dec(_f$image),
      shell: data.dec(_f$shell),
      fallbackToHost: data.dec(_f$fallbackToHost),
      mounts: data.dec(_f$mounts),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DockerSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DockerSectionConfig>(map);
  }

  static DockerSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<DockerSectionConfig>(json);
  }
}

mixin DockerSectionConfigMappable {
  String toJson() {
    return DockerSectionConfigMapper.ensureInitialized()
        .encodeJson<DockerSectionConfig>(this as DockerSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return DockerSectionConfigMapper.ensureInitialized()
        .encodeMap<DockerSectionConfig>(this as DockerSectionConfig);
  }

  DockerSectionConfigCopyWith<
    DockerSectionConfig,
    DockerSectionConfig,
    DockerSectionConfig
  >
  get copyWith =>
      _DockerSectionConfigCopyWithImpl<
        DockerSectionConfig,
        DockerSectionConfig
      >(this as DockerSectionConfig, $identity, $identity);
  @override
  String toString() {
    return DockerSectionConfigMapper.ensureInitialized().stringifyValue(
      this as DockerSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return DockerSectionConfigMapper.ensureInitialized().equalsValue(
      this as DockerSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return DockerSectionConfigMapper.ensureInitialized().hashValue(
      this as DockerSectionConfig,
    );
  }
}

extension DockerSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DockerSectionConfig, $Out> {
  DockerSectionConfigCopyWith<$R, DockerSectionConfig, $Out>
  get $asDockerSectionConfig => $base.as(
    (v, t, t2) => _DockerSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class DockerSectionConfigCopyWith<
  $R,
  $In extends DockerSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get mounts;
  $R call({
    bool? enabled,
    String? image,
    String? shell,
    bool? fallbackToHost,
    List<String>? mounts,
  });
  DockerSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DockerSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DockerSectionConfig, $Out>
    implements DockerSectionConfigCopyWith<$R, DockerSectionConfig, $Out> {
  _DockerSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DockerSectionConfig> $mapper =
      DockerSectionConfigMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get mounts =>
      $value.mounts != null
      ? ListCopyWith(
          $value.mounts!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(mounts: v),
        )
      : null;
  @override
  $R call({
    Object? enabled = $none,
    Object? image = $none,
    Object? shell = $none,
    Object? fallbackToHost = $none,
    Object? mounts = $none,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != $none) #enabled: enabled,
      if (image != $none) #image: image,
      if (shell != $none) #shell: shell,
      if (fallbackToHost != $none) #fallbackToHost: fallbackToHost,
      if (mounts != $none) #mounts: mounts,
    }),
  );
  @override
  DockerSectionConfig $make(CopyWithData data) => DockerSectionConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    image: data.get(#image, or: $value.image),
    shell: data.get(#shell, or: $value.shell),
    fallbackToHost: data.get(#fallbackToHost, or: $value.fallbackToHost),
    mounts: data.get(#mounts, or: $value.mounts),
  );

  @override
  DockerSectionConfigCopyWith<$R2, DockerSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _DockerSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WebSectionConfigMapper extends ClassMapperBase<WebSectionConfig> {
  WebSectionConfigMapper._();

  static WebSectionConfigMapper? _instance;
  static WebSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WebSectionConfigMapper._());
      FetchSectionConfigMapper.ensureInitialized();
      SearchSectionConfigMapper.ensureInitialized();
      PdfSectionConfigMapper.ensureInitialized();
      BrowserSectionConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WebSectionConfig';

  static FetchSectionConfig? _$fetch(WebSectionConfig v) => v.fetch;
  static const Field<WebSectionConfig, FetchSectionConfig> _f$fetch = Field(
    'fetch',
    _$fetch,
    opt: true,
  );
  static SearchSectionConfig? _$search(WebSectionConfig v) => v.search;
  static const Field<WebSectionConfig, SearchSectionConfig> _f$search = Field(
    'search',
    _$search,
    opt: true,
  );
  static PdfSectionConfig? _$pdf(WebSectionConfig v) => v.pdf;
  static const Field<WebSectionConfig, PdfSectionConfig> _f$pdf = Field(
    'pdf',
    _$pdf,
    opt: true,
  );
  static BrowserSectionConfig? _$browser(WebSectionConfig v) => v.browser;
  static const Field<WebSectionConfig, BrowserSectionConfig> _f$browser = Field(
    'browser',
    _$browser,
    opt: true,
  );

  @override
  final MappableFields<WebSectionConfig> fields = const {
    #fetch: _f$fetch,
    #search: _f$search,
    #pdf: _f$pdf,
    #browser: _f$browser,
  };

  static WebSectionConfig _instantiate(DecodingData data) {
    return WebSectionConfig(
      fetch: data.dec(_f$fetch),
      search: data.dec(_f$search),
      pdf: data.dec(_f$pdf),
      browser: data.dec(_f$browser),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WebSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WebSectionConfig>(map);
  }

  static WebSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WebSectionConfig>(json);
  }
}

mixin WebSectionConfigMappable {
  String toJson() {
    return WebSectionConfigMapper.ensureInitialized()
        .encodeJson<WebSectionConfig>(this as WebSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return WebSectionConfigMapper.ensureInitialized()
        .encodeMap<WebSectionConfig>(this as WebSectionConfig);
  }

  WebSectionConfigCopyWith<WebSectionConfig, WebSectionConfig, WebSectionConfig>
  get copyWith =>
      _WebSectionConfigCopyWithImpl<WebSectionConfig, WebSectionConfig>(
        this as WebSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WebSectionConfigMapper.ensureInitialized().stringifyValue(
      this as WebSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WebSectionConfigMapper.ensureInitialized().equalsValue(
      this as WebSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WebSectionConfigMapper.ensureInitialized().hashValue(
      this as WebSectionConfig,
    );
  }
}

extension WebSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WebSectionConfig, $Out> {
  WebSectionConfigCopyWith<$R, WebSectionConfig, $Out>
  get $asWebSectionConfig =>
      $base.as((v, t, t2) => _WebSectionConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WebSectionConfigCopyWith<$R, $In extends WebSectionConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  FetchSectionConfigCopyWith<$R, FetchSectionConfig, FetchSectionConfig>?
  get fetch;
  SearchSectionConfigCopyWith<$R, SearchSectionConfig, SearchSectionConfig>?
  get search;
  PdfSectionConfigCopyWith<$R, PdfSectionConfig, PdfSectionConfig>? get pdf;
  BrowserSectionConfigCopyWith<$R, BrowserSectionConfig, BrowserSectionConfig>?
  get browser;
  $R call({
    FetchSectionConfig? fetch,
    SearchSectionConfig? search,
    PdfSectionConfig? pdf,
    BrowserSectionConfig? browser,
  });
  WebSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WebSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WebSectionConfig, $Out>
    implements WebSectionConfigCopyWith<$R, WebSectionConfig, $Out> {
  _WebSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WebSectionConfig> $mapper =
      WebSectionConfigMapper.ensureInitialized();
  @override
  FetchSectionConfigCopyWith<$R, FetchSectionConfig, FetchSectionConfig>?
  get fetch => $value.fetch?.copyWith.$chain((v) => call(fetch: v));
  @override
  SearchSectionConfigCopyWith<$R, SearchSectionConfig, SearchSectionConfig>?
  get search => $value.search?.copyWith.$chain((v) => call(search: v));
  @override
  PdfSectionConfigCopyWith<$R, PdfSectionConfig, PdfSectionConfig>? get pdf =>
      $value.pdf?.copyWith.$chain((v) => call(pdf: v));
  @override
  BrowserSectionConfigCopyWith<$R, BrowserSectionConfig, BrowserSectionConfig>?
  get browser => $value.browser?.copyWith.$chain((v) => call(browser: v));
  @override
  $R call({
    Object? fetch = $none,
    Object? search = $none,
    Object? pdf = $none,
    Object? browser = $none,
  }) => $apply(
    FieldCopyWithData({
      if (fetch != $none) #fetch: fetch,
      if (search != $none) #search: search,
      if (pdf != $none) #pdf: pdf,
      if (browser != $none) #browser: browser,
    }),
  );
  @override
  WebSectionConfig $make(CopyWithData data) => WebSectionConfig(
    fetch: data.get(#fetch, or: $value.fetch),
    search: data.get(#search, or: $value.search),
    pdf: data.get(#pdf, or: $value.pdf),
    browser: data.get(#browser, or: $value.browser),
  );

  @override
  WebSectionConfigCopyWith<$R2, WebSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WebSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FetchSectionConfigMapper extends ClassMapperBase<FetchSectionConfig> {
  FetchSectionConfigMapper._();

  static FetchSectionConfigMapper? _instance;
  static FetchSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FetchSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FetchSectionConfig';

  static String? _$jinaApiKey(FetchSectionConfig v) => v.jinaApiKey;
  static const Field<FetchSectionConfig, String> _f$jinaApiKey = Field(
    'jinaApiKey',
    _$jinaApiKey,
    key: r'jina_api_key',
    opt: true,
  );
  static bool? _$allowJinaFallback(FetchSectionConfig v) => v.allowJinaFallback;
  static const Field<FetchSectionConfig, bool> _f$allowJinaFallback = Field(
    'allowJinaFallback',
    _$allowJinaFallback,
    key: r'allow_jina_fallback',
    opt: true,
  );
  static int? _$timeoutSeconds(FetchSectionConfig v) => v.timeoutSeconds;
  static const Field<FetchSectionConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    key: r'timeout_seconds',
    opt: true,
  );
  static int? _$maxBytes(FetchSectionConfig v) => v.maxBytes;
  static const Field<FetchSectionConfig, int> _f$maxBytes = Field(
    'maxBytes',
    _$maxBytes,
    key: r'max_bytes',
    opt: true,
  );
  static int? _$maxTokens(FetchSectionConfig v) => v.maxTokens;
  static const Field<FetchSectionConfig, int> _f$maxTokens = Field(
    'maxTokens',
    _$maxTokens,
    key: r'max_tokens',
    opt: true,
  );

  @override
  final MappableFields<FetchSectionConfig> fields = const {
    #jinaApiKey: _f$jinaApiKey,
    #allowJinaFallback: _f$allowJinaFallback,
    #timeoutSeconds: _f$timeoutSeconds,
    #maxBytes: _f$maxBytes,
    #maxTokens: _f$maxTokens,
  };

  static FetchSectionConfig _instantiate(DecodingData data) {
    return FetchSectionConfig(
      jinaApiKey: data.dec(_f$jinaApiKey),
      allowJinaFallback: data.dec(_f$allowJinaFallback),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      maxBytes: data.dec(_f$maxBytes),
      maxTokens: data.dec(_f$maxTokens),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FetchSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FetchSectionConfig>(map);
  }

  static FetchSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<FetchSectionConfig>(json);
  }
}

mixin FetchSectionConfigMappable {
  String toJson() {
    return FetchSectionConfigMapper.ensureInitialized()
        .encodeJson<FetchSectionConfig>(this as FetchSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return FetchSectionConfigMapper.ensureInitialized()
        .encodeMap<FetchSectionConfig>(this as FetchSectionConfig);
  }

  FetchSectionConfigCopyWith<
    FetchSectionConfig,
    FetchSectionConfig,
    FetchSectionConfig
  >
  get copyWith =>
      _FetchSectionConfigCopyWithImpl<FetchSectionConfig, FetchSectionConfig>(
        this as FetchSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FetchSectionConfigMapper.ensureInitialized().stringifyValue(
      this as FetchSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return FetchSectionConfigMapper.ensureInitialized().equalsValue(
      this as FetchSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return FetchSectionConfigMapper.ensureInitialized().hashValue(
      this as FetchSectionConfig,
    );
  }
}

extension FetchSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FetchSectionConfig, $Out> {
  FetchSectionConfigCopyWith<$R, FetchSectionConfig, $Out>
  get $asFetchSectionConfig => $base.as(
    (v, t, t2) => _FetchSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class FetchSectionConfigCopyWith<
  $R,
  $In extends FetchSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? jinaApiKey,
    bool? allowJinaFallback,
    int? timeoutSeconds,
    int? maxBytes,
    int? maxTokens,
  });
  FetchSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FetchSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FetchSectionConfig, $Out>
    implements FetchSectionConfigCopyWith<$R, FetchSectionConfig, $Out> {
  _FetchSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FetchSectionConfig> $mapper =
      FetchSectionConfigMapper.ensureInitialized();
  @override
  $R call({
    Object? jinaApiKey = $none,
    Object? allowJinaFallback = $none,
    Object? timeoutSeconds = $none,
    Object? maxBytes = $none,
    Object? maxTokens = $none,
  }) => $apply(
    FieldCopyWithData({
      if (jinaApiKey != $none) #jinaApiKey: jinaApiKey,
      if (allowJinaFallback != $none) #allowJinaFallback: allowJinaFallback,
      if (timeoutSeconds != $none) #timeoutSeconds: timeoutSeconds,
      if (maxBytes != $none) #maxBytes: maxBytes,
      if (maxTokens != $none) #maxTokens: maxTokens,
    }),
  );
  @override
  FetchSectionConfig $make(CopyWithData data) => FetchSectionConfig(
    jinaApiKey: data.get(#jinaApiKey, or: $value.jinaApiKey),
    allowJinaFallback: data.get(
      #allowJinaFallback,
      or: $value.allowJinaFallback,
    ),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    maxBytes: data.get(#maxBytes, or: $value.maxBytes),
    maxTokens: data.get(#maxTokens, or: $value.maxTokens),
  );

  @override
  FetchSectionConfigCopyWith<$R2, FetchSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FetchSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchSectionConfigMapper extends ClassMapperBase<SearchSectionConfig> {
  SearchSectionConfigMapper._();

  static SearchSectionConfigMapper? _instance;
  static SearchSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SearchSectionConfig';

  static String? _$provider(SearchSectionConfig v) => v.provider;
  static const Field<SearchSectionConfig, String> _f$provider = Field(
    'provider',
    _$provider,
    opt: true,
  );
  static String? _$braveApiKey(SearchSectionConfig v) => v.braveApiKey;
  static const Field<SearchSectionConfig, String> _f$braveApiKey = Field(
    'braveApiKey',
    _$braveApiKey,
    key: r'brave_api_key',
    opt: true,
  );
  static String? _$tavilyApiKey(SearchSectionConfig v) => v.tavilyApiKey;
  static const Field<SearchSectionConfig, String> _f$tavilyApiKey = Field(
    'tavilyApiKey',
    _$tavilyApiKey,
    key: r'tavily_api_key',
    opt: true,
  );
  static String? _$firecrawlApiKey(SearchSectionConfig v) => v.firecrawlApiKey;
  static const Field<SearchSectionConfig, String> _f$firecrawlApiKey = Field(
    'firecrawlApiKey',
    _$firecrawlApiKey,
    key: r'firecrawl_api_key',
    opt: true,
  );
  static String? _$firecrawlBaseUrl(SearchSectionConfig v) =>
      v.firecrawlBaseUrl;
  static const Field<SearchSectionConfig, String> _f$firecrawlBaseUrl = Field(
    'firecrawlBaseUrl',
    _$firecrawlBaseUrl,
    key: r'firecrawl_base_url',
    opt: true,
  );
  static int? _$timeoutSeconds(SearchSectionConfig v) => v.timeoutSeconds;
  static const Field<SearchSectionConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    key: r'timeout_seconds',
    opt: true,
  );
  static int? _$maxResults(SearchSectionConfig v) => v.maxResults;
  static const Field<SearchSectionConfig, int> _f$maxResults = Field(
    'maxResults',
    _$maxResults,
    key: r'max_results',
    opt: true,
  );

  @override
  final MappableFields<SearchSectionConfig> fields = const {
    #provider: _f$provider,
    #braveApiKey: _f$braveApiKey,
    #tavilyApiKey: _f$tavilyApiKey,
    #firecrawlApiKey: _f$firecrawlApiKey,
    #firecrawlBaseUrl: _f$firecrawlBaseUrl,
    #timeoutSeconds: _f$timeoutSeconds,
    #maxResults: _f$maxResults,
  };

  static SearchSectionConfig _instantiate(DecodingData data) {
    return SearchSectionConfig(
      provider: data.dec(_f$provider),
      braveApiKey: data.dec(_f$braveApiKey),
      tavilyApiKey: data.dec(_f$tavilyApiKey),
      firecrawlApiKey: data.dec(_f$firecrawlApiKey),
      firecrawlBaseUrl: data.dec(_f$firecrawlBaseUrl),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      maxResults: data.dec(_f$maxResults),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchSectionConfig>(map);
  }

  static SearchSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<SearchSectionConfig>(json);
  }
}

mixin SearchSectionConfigMappable {
  String toJson() {
    return SearchSectionConfigMapper.ensureInitialized()
        .encodeJson<SearchSectionConfig>(this as SearchSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return SearchSectionConfigMapper.ensureInitialized()
        .encodeMap<SearchSectionConfig>(this as SearchSectionConfig);
  }

  SearchSectionConfigCopyWith<
    SearchSectionConfig,
    SearchSectionConfig,
    SearchSectionConfig
  >
  get copyWith =>
      _SearchSectionConfigCopyWithImpl<
        SearchSectionConfig,
        SearchSectionConfig
      >(this as SearchSectionConfig, $identity, $identity);
  @override
  String toString() {
    return SearchSectionConfigMapper.ensureInitialized().stringifyValue(
      this as SearchSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchSectionConfigMapper.ensureInitialized().equalsValue(
      this as SearchSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchSectionConfigMapper.ensureInitialized().hashValue(
      this as SearchSectionConfig,
    );
  }
}

extension SearchSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchSectionConfig, $Out> {
  SearchSectionConfigCopyWith<$R, SearchSectionConfig, $Out>
  get $asSearchSectionConfig => $base.as(
    (v, t, t2) => _SearchSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchSectionConfigCopyWith<
  $R,
  $In extends SearchSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? provider,
    String? braveApiKey,
    String? tavilyApiKey,
    String? firecrawlApiKey,
    String? firecrawlBaseUrl,
    int? timeoutSeconds,
    int? maxResults,
  });
  SearchSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchSectionConfig, $Out>
    implements SearchSectionConfigCopyWith<$R, SearchSectionConfig, $Out> {
  _SearchSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchSectionConfig> $mapper =
      SearchSectionConfigMapper.ensureInitialized();
  @override
  $R call({
    Object? provider = $none,
    Object? braveApiKey = $none,
    Object? tavilyApiKey = $none,
    Object? firecrawlApiKey = $none,
    Object? firecrawlBaseUrl = $none,
    Object? timeoutSeconds = $none,
    Object? maxResults = $none,
  }) => $apply(
    FieldCopyWithData({
      if (provider != $none) #provider: provider,
      if (braveApiKey != $none) #braveApiKey: braveApiKey,
      if (tavilyApiKey != $none) #tavilyApiKey: tavilyApiKey,
      if (firecrawlApiKey != $none) #firecrawlApiKey: firecrawlApiKey,
      if (firecrawlBaseUrl != $none) #firecrawlBaseUrl: firecrawlBaseUrl,
      if (timeoutSeconds != $none) #timeoutSeconds: timeoutSeconds,
      if (maxResults != $none) #maxResults: maxResults,
    }),
  );
  @override
  SearchSectionConfig $make(CopyWithData data) => SearchSectionConfig(
    provider: data.get(#provider, or: $value.provider),
    braveApiKey: data.get(#braveApiKey, or: $value.braveApiKey),
    tavilyApiKey: data.get(#tavilyApiKey, or: $value.tavilyApiKey),
    firecrawlApiKey: data.get(#firecrawlApiKey, or: $value.firecrawlApiKey),
    firecrawlBaseUrl: data.get(#firecrawlBaseUrl, or: $value.firecrawlBaseUrl),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    maxResults: data.get(#maxResults, or: $value.maxResults),
  );

  @override
  SearchSectionConfigCopyWith<$R2, SearchSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SearchSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PdfSectionConfigMapper extends ClassMapperBase<PdfSectionConfig> {
  PdfSectionConfigMapper._();

  static PdfSectionConfigMapper? _instance;
  static PdfSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PdfSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PdfSectionConfig';

  static String? _$mistralApiKey(PdfSectionConfig v) => v.mistralApiKey;
  static const Field<PdfSectionConfig, String> _f$mistralApiKey = Field(
    'mistralApiKey',
    _$mistralApiKey,
    key: r'mistral_api_key',
    opt: true,
  );
  static String? _$openaiApiKey(PdfSectionConfig v) => v.openaiApiKey;
  static const Field<PdfSectionConfig, String> _f$openaiApiKey = Field(
    'openaiApiKey',
    _$openaiApiKey,
    key: r'openai_api_key',
    opt: true,
  );
  static String? _$ocrProvider(PdfSectionConfig v) => v.ocrProvider;
  static const Field<PdfSectionConfig, String> _f$ocrProvider = Field(
    'ocrProvider',
    _$ocrProvider,
    key: r'ocr_provider',
    opt: true,
  );
  static int? _$maxBytes(PdfSectionConfig v) => v.maxBytes;
  static const Field<PdfSectionConfig, int> _f$maxBytes = Field(
    'maxBytes',
    _$maxBytes,
    key: r'max_bytes',
    opt: true,
  );
  static int? _$timeoutSeconds(PdfSectionConfig v) => v.timeoutSeconds;
  static const Field<PdfSectionConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    key: r'timeout_seconds',
    opt: true,
  );
  static bool? _$enableOcrFallback(PdfSectionConfig v) => v.enableOcrFallback;
  static const Field<PdfSectionConfig, bool> _f$enableOcrFallback = Field(
    'enableOcrFallback',
    _$enableOcrFallback,
    key: r'enable_ocr_fallback',
    opt: true,
  );

  @override
  final MappableFields<PdfSectionConfig> fields = const {
    #mistralApiKey: _f$mistralApiKey,
    #openaiApiKey: _f$openaiApiKey,
    #ocrProvider: _f$ocrProvider,
    #maxBytes: _f$maxBytes,
    #timeoutSeconds: _f$timeoutSeconds,
    #enableOcrFallback: _f$enableOcrFallback,
  };

  static PdfSectionConfig _instantiate(DecodingData data) {
    return PdfSectionConfig(
      mistralApiKey: data.dec(_f$mistralApiKey),
      openaiApiKey: data.dec(_f$openaiApiKey),
      ocrProvider: data.dec(_f$ocrProvider),
      maxBytes: data.dec(_f$maxBytes),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      enableOcrFallback: data.dec(_f$enableOcrFallback),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PdfSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PdfSectionConfig>(map);
  }

  static PdfSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<PdfSectionConfig>(json);
  }
}

mixin PdfSectionConfigMappable {
  String toJson() {
    return PdfSectionConfigMapper.ensureInitialized()
        .encodeJson<PdfSectionConfig>(this as PdfSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return PdfSectionConfigMapper.ensureInitialized()
        .encodeMap<PdfSectionConfig>(this as PdfSectionConfig);
  }

  PdfSectionConfigCopyWith<PdfSectionConfig, PdfSectionConfig, PdfSectionConfig>
  get copyWith =>
      _PdfSectionConfigCopyWithImpl<PdfSectionConfig, PdfSectionConfig>(
        this as PdfSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PdfSectionConfigMapper.ensureInitialized().stringifyValue(
      this as PdfSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return PdfSectionConfigMapper.ensureInitialized().equalsValue(
      this as PdfSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return PdfSectionConfigMapper.ensureInitialized().hashValue(
      this as PdfSectionConfig,
    );
  }
}

extension PdfSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PdfSectionConfig, $Out> {
  PdfSectionConfigCopyWith<$R, PdfSectionConfig, $Out>
  get $asPdfSectionConfig =>
      $base.as((v, t, t2) => _PdfSectionConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PdfSectionConfigCopyWith<$R, $In extends PdfSectionConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? mistralApiKey,
    String? openaiApiKey,
    String? ocrProvider,
    int? maxBytes,
    int? timeoutSeconds,
    bool? enableOcrFallback,
  });
  PdfSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PdfSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PdfSectionConfig, $Out>
    implements PdfSectionConfigCopyWith<$R, PdfSectionConfig, $Out> {
  _PdfSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PdfSectionConfig> $mapper =
      PdfSectionConfigMapper.ensureInitialized();
  @override
  $R call({
    Object? mistralApiKey = $none,
    Object? openaiApiKey = $none,
    Object? ocrProvider = $none,
    Object? maxBytes = $none,
    Object? timeoutSeconds = $none,
    Object? enableOcrFallback = $none,
  }) => $apply(
    FieldCopyWithData({
      if (mistralApiKey != $none) #mistralApiKey: mistralApiKey,
      if (openaiApiKey != $none) #openaiApiKey: openaiApiKey,
      if (ocrProvider != $none) #ocrProvider: ocrProvider,
      if (maxBytes != $none) #maxBytes: maxBytes,
      if (timeoutSeconds != $none) #timeoutSeconds: timeoutSeconds,
      if (enableOcrFallback != $none) #enableOcrFallback: enableOcrFallback,
    }),
  );
  @override
  PdfSectionConfig $make(CopyWithData data) => PdfSectionConfig(
    mistralApiKey: data.get(#mistralApiKey, or: $value.mistralApiKey),
    openaiApiKey: data.get(#openaiApiKey, or: $value.openaiApiKey),
    ocrProvider: data.get(#ocrProvider, or: $value.ocrProvider),
    maxBytes: data.get(#maxBytes, or: $value.maxBytes),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    enableOcrFallback: data.get(
      #enableOcrFallback,
      or: $value.enableOcrFallback,
    ),
  );

  @override
  PdfSectionConfigCopyWith<$R2, PdfSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PdfSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BrowserSectionConfigMapper extends ClassMapperBase<BrowserSectionConfig> {
  BrowserSectionConfigMapper._();

  static BrowserSectionConfigMapper? _instance;
  static BrowserSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BrowserSectionConfigMapper._());
      DockerBrowserSectionConfigMapper.ensureInitialized();
      CredentialSectionConfigMapper.ensureInitialized();
      BrowserbaseSectionConfigMapper.ensureInitialized();
      BrowserlessSectionConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BrowserSectionConfig';

  static String? _$backend(BrowserSectionConfig v) => v.backend;
  static const Field<BrowserSectionConfig, String> _f$backend = Field(
    'backend',
    _$backend,
    opt: true,
  );
  static bool? _$headed(BrowserSectionConfig v) => v.headed;
  static const Field<BrowserSectionConfig, bool> _f$headed = Field(
    'headed',
    _$headed,
    opt: true,
  );
  static DockerBrowserSectionConfig? _$docker(BrowserSectionConfig v) =>
      v.docker;
  static const Field<BrowserSectionConfig, DockerBrowserSectionConfig>
  _f$docker = Field('docker', _$docker, opt: true);
  static CredentialSectionConfig? _$steel(BrowserSectionConfig v) => v.steel;
  static const Field<BrowserSectionConfig, CredentialSectionConfig> _f$steel =
      Field('steel', _$steel, opt: true);
  static BrowserbaseSectionConfig? _$browserbase(BrowserSectionConfig v) =>
      v.browserbase;
  static const Field<BrowserSectionConfig, BrowserbaseSectionConfig>
  _f$browserbase = Field('browserbase', _$browserbase, opt: true);
  static BrowserlessSectionConfig? _$browserless(BrowserSectionConfig v) =>
      v.browserless;
  static const Field<BrowserSectionConfig, BrowserlessSectionConfig>
  _f$browserless = Field('browserless', _$browserless, opt: true);
  static CredentialSectionConfig? _$anchor(BrowserSectionConfig v) => v.anchor;
  static const Field<BrowserSectionConfig, CredentialSectionConfig> _f$anchor =
      Field('anchor', _$anchor, opt: true);
  static CredentialSectionConfig? _$hyperbrowser(BrowserSectionConfig v) =>
      v.hyperbrowser;
  static const Field<BrowserSectionConfig, CredentialSectionConfig>
  _f$hyperbrowser = Field('hyperbrowser', _$hyperbrowser, opt: true);

  @override
  final MappableFields<BrowserSectionConfig> fields = const {
    #backend: _f$backend,
    #headed: _f$headed,
    #docker: _f$docker,
    #steel: _f$steel,
    #browserbase: _f$browserbase,
    #browserless: _f$browserless,
    #anchor: _f$anchor,
    #hyperbrowser: _f$hyperbrowser,
  };

  static BrowserSectionConfig _instantiate(DecodingData data) {
    return BrowserSectionConfig(
      backend: data.dec(_f$backend),
      headed: data.dec(_f$headed),
      docker: data.dec(_f$docker),
      steel: data.dec(_f$steel),
      browserbase: data.dec(_f$browserbase),
      browserless: data.dec(_f$browserless),
      anchor: data.dec(_f$anchor),
      hyperbrowser: data.dec(_f$hyperbrowser),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BrowserSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BrowserSectionConfig>(map);
  }

  static BrowserSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<BrowserSectionConfig>(json);
  }
}

mixin BrowserSectionConfigMappable {
  String toJson() {
    return BrowserSectionConfigMapper.ensureInitialized()
        .encodeJson<BrowserSectionConfig>(this as BrowserSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return BrowserSectionConfigMapper.ensureInitialized()
        .encodeMap<BrowserSectionConfig>(this as BrowserSectionConfig);
  }

  BrowserSectionConfigCopyWith<
    BrowserSectionConfig,
    BrowserSectionConfig,
    BrowserSectionConfig
  >
  get copyWith =>
      _BrowserSectionConfigCopyWithImpl<
        BrowserSectionConfig,
        BrowserSectionConfig
      >(this as BrowserSectionConfig, $identity, $identity);
  @override
  String toString() {
    return BrowserSectionConfigMapper.ensureInitialized().stringifyValue(
      this as BrowserSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return BrowserSectionConfigMapper.ensureInitialized().equalsValue(
      this as BrowserSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return BrowserSectionConfigMapper.ensureInitialized().hashValue(
      this as BrowserSectionConfig,
    );
  }
}

extension BrowserSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BrowserSectionConfig, $Out> {
  BrowserSectionConfigCopyWith<$R, BrowserSectionConfig, $Out>
  get $asBrowserSectionConfig => $base.as(
    (v, t, t2) => _BrowserSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BrowserSectionConfigCopyWith<
  $R,
  $In extends BrowserSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  DockerBrowserSectionConfigCopyWith<
    $R,
    DockerBrowserSectionConfig,
    DockerBrowserSectionConfig
  >?
  get docker;
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get steel;
  BrowserbaseSectionConfigCopyWith<
    $R,
    BrowserbaseSectionConfig,
    BrowserbaseSectionConfig
  >?
  get browserbase;
  BrowserlessSectionConfigCopyWith<
    $R,
    BrowserlessSectionConfig,
    BrowserlessSectionConfig
  >?
  get browserless;
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get anchor;
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get hyperbrowser;
  $R call({
    String? backend,
    bool? headed,
    DockerBrowserSectionConfig? docker,
    CredentialSectionConfig? steel,
    BrowserbaseSectionConfig? browserbase,
    BrowserlessSectionConfig? browserless,
    CredentialSectionConfig? anchor,
    CredentialSectionConfig? hyperbrowser,
  });
  BrowserSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BrowserSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BrowserSectionConfig, $Out>
    implements BrowserSectionConfigCopyWith<$R, BrowserSectionConfig, $Out> {
  _BrowserSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BrowserSectionConfig> $mapper =
      BrowserSectionConfigMapper.ensureInitialized();
  @override
  DockerBrowserSectionConfigCopyWith<
    $R,
    DockerBrowserSectionConfig,
    DockerBrowserSectionConfig
  >?
  get docker => $value.docker?.copyWith.$chain((v) => call(docker: v));
  @override
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get steel => $value.steel?.copyWith.$chain((v) => call(steel: v));
  @override
  BrowserbaseSectionConfigCopyWith<
    $R,
    BrowserbaseSectionConfig,
    BrowserbaseSectionConfig
  >?
  get browserbase =>
      $value.browserbase?.copyWith.$chain((v) => call(browserbase: v));
  @override
  BrowserlessSectionConfigCopyWith<
    $R,
    BrowserlessSectionConfig,
    BrowserlessSectionConfig
  >?
  get browserless =>
      $value.browserless?.copyWith.$chain((v) => call(browserless: v));
  @override
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get anchor => $value.anchor?.copyWith.$chain((v) => call(anchor: v));
  @override
  CredentialSectionConfigCopyWith<
    $R,
    CredentialSectionConfig,
    CredentialSectionConfig
  >?
  get hyperbrowser =>
      $value.hyperbrowser?.copyWith.$chain((v) => call(hyperbrowser: v));
  @override
  $R call({
    Object? backend = $none,
    Object? headed = $none,
    Object? docker = $none,
    Object? steel = $none,
    Object? browserbase = $none,
    Object? browserless = $none,
    Object? anchor = $none,
    Object? hyperbrowser = $none,
  }) => $apply(
    FieldCopyWithData({
      if (backend != $none) #backend: backend,
      if (headed != $none) #headed: headed,
      if (docker != $none) #docker: docker,
      if (steel != $none) #steel: steel,
      if (browserbase != $none) #browserbase: browserbase,
      if (browserless != $none) #browserless: browserless,
      if (anchor != $none) #anchor: anchor,
      if (hyperbrowser != $none) #hyperbrowser: hyperbrowser,
    }),
  );
  @override
  BrowserSectionConfig $make(CopyWithData data) => BrowserSectionConfig(
    backend: data.get(#backend, or: $value.backend),
    headed: data.get(#headed, or: $value.headed),
    docker: data.get(#docker, or: $value.docker),
    steel: data.get(#steel, or: $value.steel),
    browserbase: data.get(#browserbase, or: $value.browserbase),
    browserless: data.get(#browserless, or: $value.browserless),
    anchor: data.get(#anchor, or: $value.anchor),
    hyperbrowser: data.get(#hyperbrowser, or: $value.hyperbrowser),
  );

  @override
  BrowserSectionConfigCopyWith<$R2, BrowserSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _BrowserSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DockerBrowserSectionConfigMapper
    extends ClassMapperBase<DockerBrowserSectionConfig> {
  DockerBrowserSectionConfigMapper._();

  static DockerBrowserSectionConfigMapper? _instance;
  static DockerBrowserSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = DockerBrowserSectionConfigMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'DockerBrowserSectionConfig';

  static String? _$image(DockerBrowserSectionConfig v) => v.image;
  static const Field<DockerBrowserSectionConfig, String> _f$image = Field(
    'image',
    _$image,
    opt: true,
  );
  static int? _$port(DockerBrowserSectionConfig v) => v.port;
  static const Field<DockerBrowserSectionConfig, int> _f$port = Field(
    'port',
    _$port,
    opt: true,
  );

  @override
  final MappableFields<DockerBrowserSectionConfig> fields = const {
    #image: _f$image,
    #port: _f$port,
  };

  static DockerBrowserSectionConfig _instantiate(DecodingData data) {
    return DockerBrowserSectionConfig(
      image: data.dec(_f$image),
      port: data.dec(_f$port),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DockerBrowserSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DockerBrowserSectionConfig>(map);
  }

  static DockerBrowserSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<DockerBrowserSectionConfig>(json);
  }
}

mixin DockerBrowserSectionConfigMappable {
  String toJson() {
    return DockerBrowserSectionConfigMapper.ensureInitialized()
        .encodeJson<DockerBrowserSectionConfig>(
          this as DockerBrowserSectionConfig,
        );
  }

  Map<String, dynamic> toMap() {
    return DockerBrowserSectionConfigMapper.ensureInitialized()
        .encodeMap<DockerBrowserSectionConfig>(
          this as DockerBrowserSectionConfig,
        );
  }

  DockerBrowserSectionConfigCopyWith<
    DockerBrowserSectionConfig,
    DockerBrowserSectionConfig,
    DockerBrowserSectionConfig
  >
  get copyWith =>
      _DockerBrowserSectionConfigCopyWithImpl<
        DockerBrowserSectionConfig,
        DockerBrowserSectionConfig
      >(this as DockerBrowserSectionConfig, $identity, $identity);
  @override
  String toString() {
    return DockerBrowserSectionConfigMapper.ensureInitialized().stringifyValue(
      this as DockerBrowserSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return DockerBrowserSectionConfigMapper.ensureInitialized().equalsValue(
      this as DockerBrowserSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return DockerBrowserSectionConfigMapper.ensureInitialized().hashValue(
      this as DockerBrowserSectionConfig,
    );
  }
}

extension DockerBrowserSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DockerBrowserSectionConfig, $Out> {
  DockerBrowserSectionConfigCopyWith<$R, DockerBrowserSectionConfig, $Out>
  get $asDockerBrowserSectionConfig => $base.as(
    (v, t, t2) => _DockerBrowserSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class DockerBrowserSectionConfigCopyWith<
  $R,
  $In extends DockerBrowserSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? image, int? port});
  DockerBrowserSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DockerBrowserSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DockerBrowserSectionConfig, $Out>
    implements
        DockerBrowserSectionConfigCopyWith<
          $R,
          DockerBrowserSectionConfig,
          $Out
        > {
  _DockerBrowserSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DockerBrowserSectionConfig> $mapper =
      DockerBrowserSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? image = $none, Object? port = $none}) => $apply(
    FieldCopyWithData({
      if (image != $none) #image: image,
      if (port != $none) #port: port,
    }),
  );
  @override
  DockerBrowserSectionConfig $make(CopyWithData data) =>
      DockerBrowserSectionConfig(
        image: data.get(#image, or: $value.image),
        port: data.get(#port, or: $value.port),
      );

  @override
  DockerBrowserSectionConfigCopyWith<$R2, DockerBrowserSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _DockerBrowserSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class CredentialSectionConfigMapper
    extends ClassMapperBase<CredentialSectionConfig> {
  CredentialSectionConfigMapper._();

  static CredentialSectionConfigMapper? _instance;
  static CredentialSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = CredentialSectionConfigMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'CredentialSectionConfig';

  static String? _$apiKey(CredentialSectionConfig v) => v.apiKey;
  static const Field<CredentialSectionConfig, String> _f$apiKey = Field(
    'apiKey',
    _$apiKey,
    key: r'api_key',
    opt: true,
  );

  @override
  final MappableFields<CredentialSectionConfig> fields = const {
    #apiKey: _f$apiKey,
  };

  static CredentialSectionConfig _instantiate(DecodingData data) {
    return CredentialSectionConfig(apiKey: data.dec(_f$apiKey));
  }

  @override
  final Function instantiate = _instantiate;

  static CredentialSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CredentialSectionConfig>(map);
  }

  static CredentialSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<CredentialSectionConfig>(json);
  }
}

mixin CredentialSectionConfigMappable {
  String toJson() {
    return CredentialSectionConfigMapper.ensureInitialized()
        .encodeJson<CredentialSectionConfig>(this as CredentialSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return CredentialSectionConfigMapper.ensureInitialized()
        .encodeMap<CredentialSectionConfig>(this as CredentialSectionConfig);
  }

  CredentialSectionConfigCopyWith<
    CredentialSectionConfig,
    CredentialSectionConfig,
    CredentialSectionConfig
  >
  get copyWith =>
      _CredentialSectionConfigCopyWithImpl<
        CredentialSectionConfig,
        CredentialSectionConfig
      >(this as CredentialSectionConfig, $identity, $identity);
  @override
  String toString() {
    return CredentialSectionConfigMapper.ensureInitialized().stringifyValue(
      this as CredentialSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return CredentialSectionConfigMapper.ensureInitialized().equalsValue(
      this as CredentialSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return CredentialSectionConfigMapper.ensureInitialized().hashValue(
      this as CredentialSectionConfig,
    );
  }
}

extension CredentialSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, CredentialSectionConfig, $Out> {
  CredentialSectionConfigCopyWith<$R, CredentialSectionConfig, $Out>
  get $asCredentialSectionConfig => $base.as(
    (v, t, t2) => _CredentialSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class CredentialSectionConfigCopyWith<
  $R,
  $In extends CredentialSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? apiKey});
  CredentialSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _CredentialSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, CredentialSectionConfig, $Out>
    implements
        CredentialSectionConfigCopyWith<$R, CredentialSectionConfig, $Out> {
  _CredentialSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<CredentialSectionConfig> $mapper =
      CredentialSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? apiKey = $none}) =>
      $apply(FieldCopyWithData({if (apiKey != $none) #apiKey: apiKey}));
  @override
  CredentialSectionConfig $make(CopyWithData data) =>
      CredentialSectionConfig(apiKey: data.get(#apiKey, or: $value.apiKey));

  @override
  CredentialSectionConfigCopyWith<$R2, CredentialSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _CredentialSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BrowserbaseSectionConfigMapper
    extends ClassMapperBase<BrowserbaseSectionConfig> {
  BrowserbaseSectionConfigMapper._();

  static BrowserbaseSectionConfigMapper? _instance;
  static BrowserbaseSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = BrowserbaseSectionConfigMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'BrowserbaseSectionConfig';

  static String? _$apiKey(BrowserbaseSectionConfig v) => v.apiKey;
  static const Field<BrowserbaseSectionConfig, String> _f$apiKey = Field(
    'apiKey',
    _$apiKey,
    key: r'api_key',
    opt: true,
  );
  static String? _$projectId(BrowserbaseSectionConfig v) => v.projectId;
  static const Field<BrowserbaseSectionConfig, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    key: r'project_id',
    opt: true,
  );

  @override
  final MappableFields<BrowserbaseSectionConfig> fields = const {
    #apiKey: _f$apiKey,
    #projectId: _f$projectId,
  };

  static BrowserbaseSectionConfig _instantiate(DecodingData data) {
    return BrowserbaseSectionConfig(
      apiKey: data.dec(_f$apiKey),
      projectId: data.dec(_f$projectId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BrowserbaseSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BrowserbaseSectionConfig>(map);
  }

  static BrowserbaseSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<BrowserbaseSectionConfig>(json);
  }
}

mixin BrowserbaseSectionConfigMappable {
  String toJson() {
    return BrowserbaseSectionConfigMapper.ensureInitialized()
        .encodeJson<BrowserbaseSectionConfig>(this as BrowserbaseSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return BrowserbaseSectionConfigMapper.ensureInitialized()
        .encodeMap<BrowserbaseSectionConfig>(this as BrowserbaseSectionConfig);
  }

  BrowserbaseSectionConfigCopyWith<
    BrowserbaseSectionConfig,
    BrowserbaseSectionConfig,
    BrowserbaseSectionConfig
  >
  get copyWith =>
      _BrowserbaseSectionConfigCopyWithImpl<
        BrowserbaseSectionConfig,
        BrowserbaseSectionConfig
      >(this as BrowserbaseSectionConfig, $identity, $identity);
  @override
  String toString() {
    return BrowserbaseSectionConfigMapper.ensureInitialized().stringifyValue(
      this as BrowserbaseSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return BrowserbaseSectionConfigMapper.ensureInitialized().equalsValue(
      this as BrowserbaseSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return BrowserbaseSectionConfigMapper.ensureInitialized().hashValue(
      this as BrowserbaseSectionConfig,
    );
  }
}

extension BrowserbaseSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BrowserbaseSectionConfig, $Out> {
  BrowserbaseSectionConfigCopyWith<$R, BrowserbaseSectionConfig, $Out>
  get $asBrowserbaseSectionConfig => $base.as(
    (v, t, t2) => _BrowserbaseSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BrowserbaseSectionConfigCopyWith<
  $R,
  $In extends BrowserbaseSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? apiKey, String? projectId});
  BrowserbaseSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BrowserbaseSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BrowserbaseSectionConfig, $Out>
    implements
        BrowserbaseSectionConfigCopyWith<$R, BrowserbaseSectionConfig, $Out> {
  _BrowserbaseSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BrowserbaseSectionConfig> $mapper =
      BrowserbaseSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? apiKey = $none, Object? projectId = $none}) => $apply(
    FieldCopyWithData({
      if (apiKey != $none) #apiKey: apiKey,
      if (projectId != $none) #projectId: projectId,
    }),
  );
  @override
  BrowserbaseSectionConfig $make(CopyWithData data) => BrowserbaseSectionConfig(
    apiKey: data.get(#apiKey, or: $value.apiKey),
    projectId: data.get(#projectId, or: $value.projectId),
  );

  @override
  BrowserbaseSectionConfigCopyWith<$R2, BrowserbaseSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _BrowserbaseSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BrowserlessSectionConfigMapper
    extends ClassMapperBase<BrowserlessSectionConfig> {
  BrowserlessSectionConfigMapper._();

  static BrowserlessSectionConfigMapper? _instance;
  static BrowserlessSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = BrowserlessSectionConfigMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'BrowserlessSectionConfig';

  static String? _$baseUrl(BrowserlessSectionConfig v) => v.baseUrl;
  static const Field<BrowserlessSectionConfig, String> _f$baseUrl = Field(
    'baseUrl',
    _$baseUrl,
    key: r'base_url',
    opt: true,
  );
  static String? _$apiKey(BrowserlessSectionConfig v) => v.apiKey;
  static const Field<BrowserlessSectionConfig, String> _f$apiKey = Field(
    'apiKey',
    _$apiKey,
    key: r'api_key',
    opt: true,
  );

  @override
  final MappableFields<BrowserlessSectionConfig> fields = const {
    #baseUrl: _f$baseUrl,
    #apiKey: _f$apiKey,
  };

  static BrowserlessSectionConfig _instantiate(DecodingData data) {
    return BrowserlessSectionConfig(
      baseUrl: data.dec(_f$baseUrl),
      apiKey: data.dec(_f$apiKey),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BrowserlessSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BrowserlessSectionConfig>(map);
  }

  static BrowserlessSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<BrowserlessSectionConfig>(json);
  }
}

mixin BrowserlessSectionConfigMappable {
  String toJson() {
    return BrowserlessSectionConfigMapper.ensureInitialized()
        .encodeJson<BrowserlessSectionConfig>(this as BrowserlessSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return BrowserlessSectionConfigMapper.ensureInitialized()
        .encodeMap<BrowserlessSectionConfig>(this as BrowserlessSectionConfig);
  }

  BrowserlessSectionConfigCopyWith<
    BrowserlessSectionConfig,
    BrowserlessSectionConfig,
    BrowserlessSectionConfig
  >
  get copyWith =>
      _BrowserlessSectionConfigCopyWithImpl<
        BrowserlessSectionConfig,
        BrowserlessSectionConfig
      >(this as BrowserlessSectionConfig, $identity, $identity);
  @override
  String toString() {
    return BrowserlessSectionConfigMapper.ensureInitialized().stringifyValue(
      this as BrowserlessSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return BrowserlessSectionConfigMapper.ensureInitialized().equalsValue(
      this as BrowserlessSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return BrowserlessSectionConfigMapper.ensureInitialized().hashValue(
      this as BrowserlessSectionConfig,
    );
  }
}

extension BrowserlessSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BrowserlessSectionConfig, $Out> {
  BrowserlessSectionConfigCopyWith<$R, BrowserlessSectionConfig, $Out>
  get $asBrowserlessSectionConfig => $base.as(
    (v, t, t2) => _BrowserlessSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BrowserlessSectionConfigCopyWith<
  $R,
  $In extends BrowserlessSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? baseUrl, String? apiKey});
  BrowserlessSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BrowserlessSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BrowserlessSectionConfig, $Out>
    implements
        BrowserlessSectionConfigCopyWith<$R, BrowserlessSectionConfig, $Out> {
  _BrowserlessSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BrowserlessSectionConfig> $mapper =
      BrowserlessSectionConfigMapper.ensureInitialized();
  @override
  $R call({Object? baseUrl = $none, Object? apiKey = $none}) => $apply(
    FieldCopyWithData({
      if (baseUrl != $none) #baseUrl: baseUrl,
      if (apiKey != $none) #apiKey: apiKey,
    }),
  );
  @override
  BrowserlessSectionConfig $make(CopyWithData data) => BrowserlessSectionConfig(
    baseUrl: data.get(#baseUrl, or: $value.baseUrl),
    apiKey: data.get(#apiKey, or: $value.apiKey),
  );

  @override
  BrowserlessSectionConfigCopyWith<$R2, BrowserlessSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _BrowserlessSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ObservabilitySectionConfigMapper
    extends ClassMapperBase<ObservabilitySectionConfig> {
  ObservabilitySectionConfigMapper._();

  static ObservabilitySectionConfigMapper? _instance;
  static ObservabilitySectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ObservabilitySectionConfigMapper._(),
      );
      OtelSectionConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ObservabilitySectionConfig';

  static bool? _$debug(ObservabilitySectionConfig v) => v.debug;
  static const Field<ObservabilitySectionConfig, bool> _f$debug = Field(
    'debug',
    _$debug,
    opt: true,
  );
  static int? _$maxBodyBytes(ObservabilitySectionConfig v) => v.maxBodyBytes;
  static const Field<ObservabilitySectionConfig, int> _f$maxBodyBytes = Field(
    'maxBodyBytes',
    _$maxBodyBytes,
    key: r'max_body_bytes',
    opt: true,
  );
  static bool? _$redact(ObservabilitySectionConfig v) => v.redact;
  static const Field<ObservabilitySectionConfig, bool> _f$redact = Field(
    'redact',
    _$redact,
    opt: true,
  );
  static OtelSectionConfig? _$otel(ObservabilitySectionConfig v) => v.otel;
  static const Field<ObservabilitySectionConfig, OtelSectionConfig> _f$otel =
      Field('otel', _$otel, opt: true);

  @override
  final MappableFields<ObservabilitySectionConfig> fields = const {
    #debug: _f$debug,
    #maxBodyBytes: _f$maxBodyBytes,
    #redact: _f$redact,
    #otel: _f$otel,
  };

  static ObservabilitySectionConfig _instantiate(DecodingData data) {
    return ObservabilitySectionConfig(
      debug: data.dec(_f$debug),
      maxBodyBytes: data.dec(_f$maxBodyBytes),
      redact: data.dec(_f$redact),
      otel: data.dec(_f$otel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ObservabilitySectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ObservabilitySectionConfig>(map);
  }

  static ObservabilitySectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ObservabilitySectionConfig>(json);
  }
}

mixin ObservabilitySectionConfigMappable {
  String toJson() {
    return ObservabilitySectionConfigMapper.ensureInitialized()
        .encodeJson<ObservabilitySectionConfig>(
          this as ObservabilitySectionConfig,
        );
  }

  Map<String, dynamic> toMap() {
    return ObservabilitySectionConfigMapper.ensureInitialized()
        .encodeMap<ObservabilitySectionConfig>(
          this as ObservabilitySectionConfig,
        );
  }

  ObservabilitySectionConfigCopyWith<
    ObservabilitySectionConfig,
    ObservabilitySectionConfig,
    ObservabilitySectionConfig
  >
  get copyWith =>
      _ObservabilitySectionConfigCopyWithImpl<
        ObservabilitySectionConfig,
        ObservabilitySectionConfig
      >(this as ObservabilitySectionConfig, $identity, $identity);
  @override
  String toString() {
    return ObservabilitySectionConfigMapper.ensureInitialized().stringifyValue(
      this as ObservabilitySectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ObservabilitySectionConfigMapper.ensureInitialized().equalsValue(
      this as ObservabilitySectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ObservabilitySectionConfigMapper.ensureInitialized().hashValue(
      this as ObservabilitySectionConfig,
    );
  }
}

extension ObservabilitySectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ObservabilitySectionConfig, $Out> {
  ObservabilitySectionConfigCopyWith<$R, ObservabilitySectionConfig, $Out>
  get $asObservabilitySectionConfig => $base.as(
    (v, t, t2) => _ObservabilitySectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ObservabilitySectionConfigCopyWith<
  $R,
  $In extends ObservabilitySectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  OtelSectionConfigCopyWith<$R, OtelSectionConfig, OtelSectionConfig>? get otel;
  $R call({
    bool? debug,
    int? maxBodyBytes,
    bool? redact,
    OtelSectionConfig? otel,
  });
  ObservabilitySectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ObservabilitySectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ObservabilitySectionConfig, $Out>
    implements
        ObservabilitySectionConfigCopyWith<
          $R,
          ObservabilitySectionConfig,
          $Out
        > {
  _ObservabilitySectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ObservabilitySectionConfig> $mapper =
      ObservabilitySectionConfigMapper.ensureInitialized();
  @override
  OtelSectionConfigCopyWith<$R, OtelSectionConfig, OtelSectionConfig>?
  get otel => $value.otel?.copyWith.$chain((v) => call(otel: v));
  @override
  $R call({
    Object? debug = $none,
    Object? maxBodyBytes = $none,
    Object? redact = $none,
    Object? otel = $none,
  }) => $apply(
    FieldCopyWithData({
      if (debug != $none) #debug: debug,
      if (maxBodyBytes != $none) #maxBodyBytes: maxBodyBytes,
      if (redact != $none) #redact: redact,
      if (otel != $none) #otel: otel,
    }),
  );
  @override
  ObservabilitySectionConfig $make(CopyWithData data) =>
      ObservabilitySectionConfig(
        debug: data.get(#debug, or: $value.debug),
        maxBodyBytes: data.get(#maxBodyBytes, or: $value.maxBodyBytes),
        redact: data.get(#redact, or: $value.redact),
        otel: data.get(#otel, or: $value.otel),
      );

  @override
  ObservabilitySectionConfigCopyWith<$R2, ObservabilitySectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ObservabilitySectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class OtelSectionConfigMapper extends ClassMapperBase<OtelSectionConfig> {
  OtelSectionConfigMapper._();

  static OtelSectionConfigMapper? _instance;
  static OtelSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OtelSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'OtelSectionConfig';

  static bool? _$enabled(OtelSectionConfig v) => v.enabled;
  static const Field<OtelSectionConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
  );
  static String? _$endpoint(OtelSectionConfig v) => v.endpoint;
  static const Field<OtelSectionConfig, String> _f$endpoint = Field(
    'endpoint',
    _$endpoint,
    opt: true,
  );
  static Map<String, String>? _$headers(OtelSectionConfig v) => v.headers;
  static const Field<OtelSectionConfig, Map<String, String>> _f$headers = Field(
    'headers',
    _$headers,
    opt: true,
  );
  static String? _$serviceName(OtelSectionConfig v) => v.serviceName;
  static const Field<OtelSectionConfig, String> _f$serviceName = Field(
    'serviceName',
    _$serviceName,
    key: r'service_name',
    opt: true,
  );
  static Map<String, String>? _$resourceAttributes(OtelSectionConfig v) =>
      v.resourceAttributes;
  static const Field<OtelSectionConfig, Map<String, String>>
  _f$resourceAttributes = Field(
    'resourceAttributes',
    _$resourceAttributes,
    key: r'resource_attributes',
    opt: true,
  );
  static int? _$timeoutMilliseconds(OtelSectionConfig v) =>
      v.timeoutMilliseconds;
  static const Field<OtelSectionConfig, int> _f$timeoutMilliseconds = Field(
    'timeoutMilliseconds',
    _$timeoutMilliseconds,
    key: r'timeout_milliseconds',
    opt: true,
  );

  @override
  final MappableFields<OtelSectionConfig> fields = const {
    #enabled: _f$enabled,
    #endpoint: _f$endpoint,
    #headers: _f$headers,
    #serviceName: _f$serviceName,
    #resourceAttributes: _f$resourceAttributes,
    #timeoutMilliseconds: _f$timeoutMilliseconds,
  };

  static OtelSectionConfig _instantiate(DecodingData data) {
    return OtelSectionConfig(
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

  static OtelSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OtelSectionConfig>(map);
  }

  static OtelSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<OtelSectionConfig>(json);
  }
}

mixin OtelSectionConfigMappable {
  String toJson() {
    return OtelSectionConfigMapper.ensureInitialized()
        .encodeJson<OtelSectionConfig>(this as OtelSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return OtelSectionConfigMapper.ensureInitialized()
        .encodeMap<OtelSectionConfig>(this as OtelSectionConfig);
  }

  OtelSectionConfigCopyWith<
    OtelSectionConfig,
    OtelSectionConfig,
    OtelSectionConfig
  >
  get copyWith =>
      _OtelSectionConfigCopyWithImpl<OtelSectionConfig, OtelSectionConfig>(
        this as OtelSectionConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return OtelSectionConfigMapper.ensureInitialized().stringifyValue(
      this as OtelSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return OtelSectionConfigMapper.ensureInitialized().equalsValue(
      this as OtelSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return OtelSectionConfigMapper.ensureInitialized().hashValue(
      this as OtelSectionConfig,
    );
  }
}

extension OtelSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OtelSectionConfig, $Out> {
  OtelSectionConfigCopyWith<$R, OtelSectionConfig, $Out>
  get $asOtelSectionConfig => $base.as(
    (v, t, t2) => _OtelSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class OtelSectionConfigCopyWith<
  $R,
  $In extends OtelSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get headers;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get resourceAttributes;
  $R call({
    bool? enabled,
    String? endpoint,
    Map<String, String>? headers,
    String? serviceName,
    Map<String, String>? resourceAttributes,
    int? timeoutMilliseconds,
  });
  OtelSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _OtelSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OtelSectionConfig, $Out>
    implements OtelSectionConfigCopyWith<$R, OtelSectionConfig, $Out> {
  _OtelSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<OtelSectionConfig> $mapper =
      OtelSectionConfigMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get headers => $value.headers != null
      ? MapCopyWith(
          $value.headers!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(headers: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get resourceAttributes => $value.resourceAttributes != null
      ? MapCopyWith(
          $value.resourceAttributes!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(resourceAttributes: v),
        )
      : null;
  @override
  $R call({
    Object? enabled = $none,
    Object? endpoint = $none,
    Object? headers = $none,
    Object? serviceName = $none,
    Object? resourceAttributes = $none,
    Object? timeoutMilliseconds = $none,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != $none) #enabled: enabled,
      if (endpoint != $none) #endpoint: endpoint,
      if (headers != $none) #headers: headers,
      if (serviceName != $none) #serviceName: serviceName,
      if (resourceAttributes != $none) #resourceAttributes: resourceAttributes,
      if (timeoutMilliseconds != $none)
        #timeoutMilliseconds: timeoutMilliseconds,
    }),
  );
  @override
  OtelSectionConfig $make(CopyWithData data) => OtelSectionConfig(
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
  OtelSectionConfigCopyWith<$R2, OtelSectionConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _OtelSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SkillsSectionConfigMapper extends ClassMapperBase<SkillsSectionConfig> {
  SkillsSectionConfigMapper._();

  static SkillsSectionConfigMapper? _instance;
  static SkillsSectionConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SkillsSectionConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SkillsSectionConfig';

  static List<String>? _$paths(SkillsSectionConfig v) => v.paths;
  static const Field<SkillsSectionConfig, List<String>> _f$paths = Field(
    'paths',
    _$paths,
    opt: true,
  );

  @override
  final MappableFields<SkillsSectionConfig> fields = const {#paths: _f$paths};

  static SkillsSectionConfig _instantiate(DecodingData data) {
    return SkillsSectionConfig(paths: data.dec(_f$paths));
  }

  @override
  final Function instantiate = _instantiate;

  static SkillsSectionConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SkillsSectionConfig>(map);
  }

  static SkillsSectionConfig fromJson(String json) {
    return ensureInitialized().decodeJson<SkillsSectionConfig>(json);
  }
}

mixin SkillsSectionConfigMappable {
  String toJson() {
    return SkillsSectionConfigMapper.ensureInitialized()
        .encodeJson<SkillsSectionConfig>(this as SkillsSectionConfig);
  }

  Map<String, dynamic> toMap() {
    return SkillsSectionConfigMapper.ensureInitialized()
        .encodeMap<SkillsSectionConfig>(this as SkillsSectionConfig);
  }

  SkillsSectionConfigCopyWith<
    SkillsSectionConfig,
    SkillsSectionConfig,
    SkillsSectionConfig
  >
  get copyWith =>
      _SkillsSectionConfigCopyWithImpl<
        SkillsSectionConfig,
        SkillsSectionConfig
      >(this as SkillsSectionConfig, $identity, $identity);
  @override
  String toString() {
    return SkillsSectionConfigMapper.ensureInitialized().stringifyValue(
      this as SkillsSectionConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return SkillsSectionConfigMapper.ensureInitialized().equalsValue(
      this as SkillsSectionConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return SkillsSectionConfigMapper.ensureInitialized().hashValue(
      this as SkillsSectionConfig,
    );
  }
}

extension SkillsSectionConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SkillsSectionConfig, $Out> {
  SkillsSectionConfigCopyWith<$R, SkillsSectionConfig, $Out>
  get $asSkillsSectionConfig => $base.as(
    (v, t, t2) => _SkillsSectionConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SkillsSectionConfigCopyWith<
  $R,
  $In extends SkillsSectionConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get paths;
  $R call({List<String>? paths});
  SkillsSectionConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SkillsSectionConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SkillsSectionConfig, $Out>
    implements SkillsSectionConfigCopyWith<$R, SkillsSectionConfig, $Out> {
  _SkillsSectionConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SkillsSectionConfig> $mapper =
      SkillsSectionConfigMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get paths =>
      $value.paths != null
      ? ListCopyWith(
          $value.paths!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(paths: v),
        )
      : null;
  @override
  $R call({Object? paths = $none}) =>
      $apply(FieldCopyWithData({if (paths != $none) #paths: paths}));
  @override
  SkillsSectionConfig $make(CopyWithData data) =>
      SkillsSectionConfig(paths: data.get(#paths, or: $value.paths));

  @override
  SkillsSectionConfigCopyWith<$R2, SkillsSectionConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SkillsSectionConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

