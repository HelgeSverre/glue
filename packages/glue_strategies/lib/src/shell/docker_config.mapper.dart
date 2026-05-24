// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'docker_config.dart';

class MountModeMapper extends EnumMapper<MountMode> {
  MountModeMapper._();

  static MountModeMapper? _instance;
  static MountModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MountModeMapper._());
    }
    return _instance!;
  }

  static MountMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  MountMode decode(dynamic value) {
    switch (value) {
      case r'ro':
        return MountMode.ro;
      case r'rw':
        return MountMode.rw;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(MountMode self) {
    switch (self) {
      case MountMode.ro:
        return r'ro';
      case MountMode.rw:
        return r'rw';
    }
  }
}

extension MountModeMapperExtension on MountMode {
  String toValue() {
    MountModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<MountMode>(this) as String;
  }
}

class MountEntryMapper extends ClassMapperBase<MountEntry> {
  MountEntryMapper._();

  static MountEntryMapper? _instance;
  static MountEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MountEntryMapper._());
      MountModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MountEntry';

  static String _$hostPath(MountEntry v) => v.hostPath;
  static const Field<MountEntry, String> _f$hostPath = Field(
    'hostPath',
    _$hostPath,
    key: r'host_path',
  );
  static MountMode _$mode(MountEntry v) => v.mode;
  static const Field<MountEntry, MountMode> _f$mode = Field(
    'mode',
    _$mode,
    opt: true,
    def: MountMode.rw,
  );
  static String? _$containerPath(MountEntry v) => v.containerPath;
  static const Field<MountEntry, String> _f$containerPath = Field(
    'containerPath',
    _$containerPath,
    key: r'container_path',
    opt: true,
  );
  static DateTime? _$addedAt(MountEntry v) => v.addedAt;
  static const Field<MountEntry, DateTime> _f$addedAt = Field(
    'addedAt',
    _$addedAt,
    key: r'added_at',
    opt: true,
  );

  @override
  final MappableFields<MountEntry> fields = const {
    #hostPath: _f$hostPath,
    #mode: _f$mode,
    #containerPath: _f$containerPath,
    #addedAt: _f$addedAt,
  };

  static MountEntry _instantiate(DecodingData data) {
    return MountEntry(
      hostPath: data.dec(_f$hostPath),
      mode: data.dec(_f$mode),
      containerPath: data.dec(_f$containerPath),
      addedAt: data.dec(_f$addedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MountEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MountEntry>(map);
  }

  static MountEntry fromJson(String json) {
    return ensureInitialized().decodeJson<MountEntry>(json);
  }
}

mixin MountEntryMappable {
  String toJson() {
    return MountEntryMapper.ensureInitialized().encodeJson<MountEntry>(
      this as MountEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return MountEntryMapper.ensureInitialized().encodeMap<MountEntry>(
      this as MountEntry,
    );
  }

  MountEntryCopyWith<MountEntry, MountEntry, MountEntry> get copyWith =>
      _MountEntryCopyWithImpl<MountEntry, MountEntry>(
        this as MountEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MountEntryMapper.ensureInitialized().stringifyValue(
      this as MountEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return MountEntryMapper.ensureInitialized().equalsValue(
      this as MountEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return MountEntryMapper.ensureInitialized().hashValue(this as MountEntry);
  }
}

extension MountEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MountEntry, $Out> {
  MountEntryCopyWith<$R, MountEntry, $Out> get $asMountEntry =>
      $base.as((v, t, t2) => _MountEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MountEntryCopyWith<$R, $In extends MountEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? hostPath,
    MountMode? mode,
    String? containerPath,
    DateTime? addedAt,
  });
  MountEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MountEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MountEntry, $Out>
    implements MountEntryCopyWith<$R, MountEntry, $Out> {
  _MountEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MountEntry> $mapper =
      MountEntryMapper.ensureInitialized();
  @override
  $R call({
    String? hostPath,
    MountMode? mode,
    Object? containerPath = $none,
    Object? addedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (hostPath != null) #hostPath: hostPath,
      if (mode != null) #mode: mode,
      if (containerPath != $none) #containerPath: containerPath,
      if (addedAt != $none) #addedAt: addedAt,
    }),
  );
  @override
  MountEntry $make(CopyWithData data) => MountEntry(
    hostPath: data.get(#hostPath, or: $value.hostPath),
    mode: data.get(#mode, or: $value.mode),
    containerPath: data.get(#containerPath, or: $value.containerPath),
    addedAt: data.get(#addedAt, or: $value.addedAt),
  );

  @override
  MountEntryCopyWith<$R2, MountEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MountEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DockerConfigMapper extends ClassMapperBase<DockerConfig> {
  DockerConfigMapper._();

  static DockerConfigMapper? _instance;
  static DockerConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DockerConfigMapper._());
      MountEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DockerConfig';

  static bool _$enabled(DockerConfig v) => v.enabled;
  static const Field<DockerConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: false,
  );
  static String _$image(DockerConfig v) => v.image;
  static const Field<DockerConfig, String> _f$image = Field(
    'image',
    _$image,
    opt: true,
    def: 'ubuntu:24.04',
  );
  static String _$shell(DockerConfig v) => v.shell;
  static const Field<DockerConfig, String> _f$shell = Field(
    'shell',
    _$shell,
    opt: true,
    def: 'sh',
  );
  static bool _$fallbackToHost(DockerConfig v) => v.fallbackToHost;
  static const Field<DockerConfig, bool> _f$fallbackToHost = Field(
    'fallbackToHost',
    _$fallbackToHost,
    opt: true,
    def: true,
  );
  static List<MountEntry> _$mounts(DockerConfig v) => v.mounts;
  static const Field<DockerConfig, List<MountEntry>> _f$mounts = Field(
    'mounts',
    _$mounts,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<DockerConfig> fields = const {
    #enabled: _f$enabled,
    #image: _f$image,
    #shell: _f$shell,
    #fallbackToHost: _f$fallbackToHost,
    #mounts: _f$mounts,
  };

  static DockerConfig _instantiate(DecodingData data) {
    return DockerConfig(
      enabled: data.dec(_f$enabled),
      image: data.dec(_f$image),
      shell: data.dec(_f$shell),
      fallbackToHost: data.dec(_f$fallbackToHost),
      mounts: data.dec(_f$mounts),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DockerConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DockerConfig>(map);
  }

  static DockerConfig fromJson(String json) {
    return ensureInitialized().decodeJson<DockerConfig>(json);
  }
}

mixin DockerConfigMappable {
  String toJson() {
    return DockerConfigMapper.ensureInitialized().encodeJson<DockerConfig>(
      this as DockerConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return DockerConfigMapper.ensureInitialized().encodeMap<DockerConfig>(
      this as DockerConfig,
    );
  }

  DockerConfigCopyWith<DockerConfig, DockerConfig, DockerConfig> get copyWith =>
      _DockerConfigCopyWithImpl<DockerConfig, DockerConfig>(
        this as DockerConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DockerConfigMapper.ensureInitialized().stringifyValue(
      this as DockerConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return DockerConfigMapper.ensureInitialized().equalsValue(
      this as DockerConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return DockerConfigMapper.ensureInitialized().hashValue(
      this as DockerConfig,
    );
  }
}

extension DockerConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DockerConfig, $Out> {
  DockerConfigCopyWith<$R, DockerConfig, $Out> get $asDockerConfig =>
      $base.as((v, t, t2) => _DockerConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DockerConfigCopyWith<$R, $In extends DockerConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, MountEntry, MountEntryCopyWith<$R, MountEntry, MountEntry>>
  get mounts;
  $R call({
    bool? enabled,
    String? image,
    String? shell,
    bool? fallbackToHost,
    List<MountEntry>? mounts,
  });
  DockerConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DockerConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DockerConfig, $Out>
    implements DockerConfigCopyWith<$R, DockerConfig, $Out> {
  _DockerConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DockerConfig> $mapper =
      DockerConfigMapper.ensureInitialized();
  @override
  ListCopyWith<$R, MountEntry, MountEntryCopyWith<$R, MountEntry, MountEntry>>
  get mounts => ListCopyWith(
    $value.mounts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(mounts: v),
  );
  @override
  $R call({
    bool? enabled,
    String? image,
    String? shell,
    bool? fallbackToHost,
    List<MountEntry>? mounts,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (image != null) #image: image,
      if (shell != null) #shell: shell,
      if (fallbackToHost != null) #fallbackToHost: fallbackToHost,
      if (mounts != null) #mounts: mounts,
    }),
  );
  @override
  DockerConfig $make(CopyWithData data) => DockerConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    image: data.get(#image, or: $value.image),
    shell: data.get(#shell, or: $value.shell),
    fallbackToHost: data.get(#fallbackToHost, or: $value.fallbackToHost),
    mounts: data.get(#mounts, or: $value.mounts),
  );

  @override
  DockerConfigCopyWith<$R2, DockerConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DockerConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

