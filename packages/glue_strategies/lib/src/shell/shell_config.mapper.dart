// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'shell_config.dart';

class ShellModeMapper extends EnumMapper<ShellMode> {
  ShellModeMapper._();

  static ShellModeMapper? _instance;
  static ShellModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShellModeMapper._());
    }
    return _instance!;
  }

  static ShellMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ShellMode decode(dynamic value) {
    switch (value) {
      case r'nonInteractive':
        return ShellMode.nonInteractive;
      case r'interactive':
        return ShellMode.interactive;
      case r'login':
        return ShellMode.login;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ShellMode self) {
    switch (self) {
      case ShellMode.nonInteractive:
        return r'nonInteractive';
      case ShellMode.interactive:
        return r'interactive';
      case ShellMode.login:
        return r'login';
    }
  }
}

extension ShellModeMapperExtension on ShellMode {
  String toValue() {
    ShellModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ShellMode>(this) as String;
  }
}

class ShellConfigMapper extends ClassMapperBase<ShellConfig> {
  ShellConfigMapper._();

  static ShellConfigMapper? _instance;
  static ShellConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShellConfigMapper._());
      ShellModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ShellConfig';

  static String _$executable(ShellConfig v) => v.executable;
  static const Field<ShellConfig, String> _f$executable = Field(
    'executable',
    _$executable,
    opt: true,
    def: 'sh',
  );
  static ShellMode _$mode(ShellConfig v) => v.mode;
  static const Field<ShellConfig, ShellMode> _f$mode = Field(
    'mode',
    _$mode,
    opt: true,
    def: ShellMode.nonInteractive,
  );

  @override
  final MappableFields<ShellConfig> fields = const {
    #executable: _f$executable,
    #mode: _f$mode,
  };

  static ShellConfig _instantiate(DecodingData data) {
    return ShellConfig(
      executable: data.dec(_f$executable),
      mode: data.dec(_f$mode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ShellConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShellConfig>(map);
  }

  static ShellConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ShellConfig>(json);
  }
}

mixin ShellConfigMappable {
  String toJson() {
    return ShellConfigMapper.ensureInitialized().encodeJson<ShellConfig>(
      this as ShellConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return ShellConfigMapper.ensureInitialized().encodeMap<ShellConfig>(
      this as ShellConfig,
    );
  }

  ShellConfigCopyWith<ShellConfig, ShellConfig, ShellConfig> get copyWith =>
      _ShellConfigCopyWithImpl<ShellConfig, ShellConfig>(
        this as ShellConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShellConfigMapper.ensureInitialized().stringifyValue(
      this as ShellConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShellConfigMapper.ensureInitialized().equalsValue(
      this as ShellConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ShellConfigMapper.ensureInitialized().hashValue(this as ShellConfig);
  }
}

extension ShellConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ShellConfig, $Out> {
  ShellConfigCopyWith<$R, ShellConfig, $Out> get $asShellConfig =>
      $base.as((v, t, t2) => _ShellConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ShellConfigCopyWith<$R, $In extends ShellConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? executable, ShellMode? mode});
  ShellConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ShellConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShellConfig, $Out>
    implements ShellConfigCopyWith<$R, ShellConfig, $Out> {
  _ShellConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShellConfig> $mapper =
      ShellConfigMapper.ensureInitialized();
  @override
  $R call({String? executable, ShellMode? mode}) => $apply(
    FieldCopyWithData({
      if (executable != null) #executable: executable,
      if (mode != null) #mode: mode,
    }),
  );
  @override
  ShellConfig $make(CopyWithData data) => ShellConfig(
    executable: data.get(#executable, or: $value.executable),
    mode: data.get(#mode, or: $value.mode),
  );

  @override
  ShellConfigCopyWith<$R2, ShellConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShellConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

