// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'web_config.dart';

class WebSearchProviderTypeMapper extends EnumMapper<WebSearchProviderType> {
  WebSearchProviderTypeMapper._();

  static WebSearchProviderTypeMapper? _instance;
  static WebSearchProviderTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WebSearchProviderTypeMapper._());
    }
    return _instance!;
  }

  static WebSearchProviderType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WebSearchProviderType decode(dynamic value) {
    switch (value) {
      case r'brave':
        return WebSearchProviderType.brave;
      case r'tavily':
        return WebSearchProviderType.tavily;
      case r'firecrawl':
        return WebSearchProviderType.firecrawl;
      case r'duckduckgo':
        return WebSearchProviderType.duckduckgo;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WebSearchProviderType self) {
    switch (self) {
      case WebSearchProviderType.brave:
        return r'brave';
      case WebSearchProviderType.tavily:
        return r'tavily';
      case WebSearchProviderType.firecrawl:
        return r'firecrawl';
      case WebSearchProviderType.duckduckgo:
        return r'duckduckgo';
    }
  }
}

extension WebSearchProviderTypeMapperExtension on WebSearchProviderType {
  String toValue() {
    WebSearchProviderTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WebSearchProviderType>(this)
        as String;
  }
}

class OcrProviderTypeMapper extends EnumMapper<OcrProviderType> {
  OcrProviderTypeMapper._();

  static OcrProviderTypeMapper? _instance;
  static OcrProviderTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OcrProviderTypeMapper._());
    }
    return _instance!;
  }

  static OcrProviderType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  OcrProviderType decode(dynamic value) {
    switch (value) {
      case r'mistral':
        return OcrProviderType.mistral;
      case r'openai':
        return OcrProviderType.openai;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(OcrProviderType self) {
    switch (self) {
      case OcrProviderType.mistral:
        return r'mistral';
      case OcrProviderType.openai:
        return r'openai';
    }
  }
}

extension OcrProviderTypeMapperExtension on OcrProviderType {
  String toValue() {
    OcrProviderTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<OcrProviderType>(this) as String;
  }
}

class WebFetchConfigMapper extends ClassMapperBase<WebFetchConfig> {
  WebFetchConfigMapper._();

  static WebFetchConfigMapper? _instance;
  static WebFetchConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WebFetchConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WebFetchConfig';

  static int _$timeoutSeconds(WebFetchConfig v) => v.timeoutSeconds;
  static const Field<WebFetchConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: AppConstants.webFetchTimeoutSeconds,
  );
  static int _$maxBytes(WebFetchConfig v) => v.maxBytes;
  static const Field<WebFetchConfig, int> _f$maxBytes = Field(
    'maxBytes',
    _$maxBytes,
    opt: true,
    def: AppConstants.webFetchMaxBytes,
  );
  static int _$defaultMaxTokens(WebFetchConfig v) => v.defaultMaxTokens;
  static const Field<WebFetchConfig, int> _f$defaultMaxTokens = Field(
    'defaultMaxTokens',
    _$defaultMaxTokens,
    opt: true,
    def: AppConstants.webFetchDefaultMaxTokens,
  );
  static String? _$jinaApiKey(WebFetchConfig v) => v.jinaApiKey;
  static const Field<WebFetchConfig, String> _f$jinaApiKey = Field(
    'jinaApiKey',
    _$jinaApiKey,
    opt: true,
  );
  static String _$jinaBaseUrl(WebFetchConfig v) => v.jinaBaseUrl;
  static const Field<WebFetchConfig, String> _f$jinaBaseUrl = Field(
    'jinaBaseUrl',
    _$jinaBaseUrl,
    opt: true,
    def: 'https://r.jina.ai',
  );
  static bool _$allowJinaFallback(WebFetchConfig v) => v.allowJinaFallback;
  static const Field<WebFetchConfig, bool> _f$allowJinaFallback = Field(
    'allowJinaFallback',
    _$allowJinaFallback,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<WebFetchConfig> fields = const {
    #timeoutSeconds: _f$timeoutSeconds,
    #maxBytes: _f$maxBytes,
    #defaultMaxTokens: _f$defaultMaxTokens,
    #jinaApiKey: _f$jinaApiKey,
    #jinaBaseUrl: _f$jinaBaseUrl,
    #allowJinaFallback: _f$allowJinaFallback,
  };

  static WebFetchConfig _instantiate(DecodingData data) {
    return WebFetchConfig(
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      maxBytes: data.dec(_f$maxBytes),
      defaultMaxTokens: data.dec(_f$defaultMaxTokens),
      jinaApiKey: data.dec(_f$jinaApiKey),
      jinaBaseUrl: data.dec(_f$jinaBaseUrl),
      allowJinaFallback: data.dec(_f$allowJinaFallback),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WebFetchConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WebFetchConfig>(map);
  }

  static WebFetchConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WebFetchConfig>(json);
  }
}

mixin WebFetchConfigMappable {
  String toJson() {
    return WebFetchConfigMapper.ensureInitialized().encodeJson<WebFetchConfig>(
      this as WebFetchConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return WebFetchConfigMapper.ensureInitialized().encodeMap<WebFetchConfig>(
      this as WebFetchConfig,
    );
  }

  WebFetchConfigCopyWith<WebFetchConfig, WebFetchConfig, WebFetchConfig>
  get copyWith => _WebFetchConfigCopyWithImpl<WebFetchConfig, WebFetchConfig>(
    this as WebFetchConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return WebFetchConfigMapper.ensureInitialized().stringifyValue(
      this as WebFetchConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WebFetchConfigMapper.ensureInitialized().equalsValue(
      this as WebFetchConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WebFetchConfigMapper.ensureInitialized().hashValue(
      this as WebFetchConfig,
    );
  }
}

extension WebFetchConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WebFetchConfig, $Out> {
  WebFetchConfigCopyWith<$R, WebFetchConfig, $Out> get $asWebFetchConfig =>
      $base.as((v, t, t2) => _WebFetchConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WebFetchConfigCopyWith<$R, $In extends WebFetchConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? timeoutSeconds,
    int? maxBytes,
    int? defaultMaxTokens,
    String? jinaApiKey,
    String? jinaBaseUrl,
    bool? allowJinaFallback,
  });
  WebFetchConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WebFetchConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WebFetchConfig, $Out>
    implements WebFetchConfigCopyWith<$R, WebFetchConfig, $Out> {
  _WebFetchConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WebFetchConfig> $mapper =
      WebFetchConfigMapper.ensureInitialized();
  @override
  $R call({
    int? timeoutSeconds,
    int? maxBytes,
    int? defaultMaxTokens,
    Object? jinaApiKey = $none,
    String? jinaBaseUrl,
    bool? allowJinaFallback,
  }) => $apply(
    FieldCopyWithData({
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
      if (maxBytes != null) #maxBytes: maxBytes,
      if (defaultMaxTokens != null) #defaultMaxTokens: defaultMaxTokens,
      if (jinaApiKey != $none) #jinaApiKey: jinaApiKey,
      if (jinaBaseUrl != null) #jinaBaseUrl: jinaBaseUrl,
      if (allowJinaFallback != null) #allowJinaFallback: allowJinaFallback,
    }),
  );
  @override
  WebFetchConfig $make(CopyWithData data) => WebFetchConfig(
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    maxBytes: data.get(#maxBytes, or: $value.maxBytes),
    defaultMaxTokens: data.get(#defaultMaxTokens, or: $value.defaultMaxTokens),
    jinaApiKey: data.get(#jinaApiKey, or: $value.jinaApiKey),
    jinaBaseUrl: data.get(#jinaBaseUrl, or: $value.jinaBaseUrl),
    allowJinaFallback: data.get(
      #allowJinaFallback,
      or: $value.allowJinaFallback,
    ),
  );

  @override
  WebFetchConfigCopyWith<$R2, WebFetchConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WebFetchConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WebSearchConfigMapper extends ClassMapperBase<WebSearchConfig> {
  WebSearchConfigMapper._();

  static WebSearchConfigMapper? _instance;
  static WebSearchConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WebSearchConfigMapper._());
      WebSearchProviderTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WebSearchConfig';

  static WebSearchProviderType? _$provider(WebSearchConfig v) => v.provider;
  static const Field<WebSearchConfig, WebSearchProviderType> _f$provider =
      Field('provider', _$provider, opt: true);
  static int _$timeoutSeconds(WebSearchConfig v) => v.timeoutSeconds;
  static const Field<WebSearchConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: AppConstants.webSearchTimeoutSeconds,
  );
  static int _$defaultMaxResults(WebSearchConfig v) => v.defaultMaxResults;
  static const Field<WebSearchConfig, int> _f$defaultMaxResults = Field(
    'defaultMaxResults',
    _$defaultMaxResults,
    opt: true,
    def: AppConstants.webSearchDefaultMaxResults,
  );
  static String? _$braveApiKey(WebSearchConfig v) => v.braveApiKey;
  static const Field<WebSearchConfig, String> _f$braveApiKey = Field(
    'braveApiKey',
    _$braveApiKey,
    opt: true,
  );
  static String? _$tavilyApiKey(WebSearchConfig v) => v.tavilyApiKey;
  static const Field<WebSearchConfig, String> _f$tavilyApiKey = Field(
    'tavilyApiKey',
    _$tavilyApiKey,
    opt: true,
  );
  static String? _$firecrawlApiKey(WebSearchConfig v) => v.firecrawlApiKey;
  static const Field<WebSearchConfig, String> _f$firecrawlApiKey = Field(
    'firecrawlApiKey',
    _$firecrawlApiKey,
    opt: true,
  );
  static String? _$firecrawlBaseUrl(WebSearchConfig v) => v.firecrawlBaseUrl;
  static const Field<WebSearchConfig, String> _f$firecrawlBaseUrl = Field(
    'firecrawlBaseUrl',
    _$firecrawlBaseUrl,
    opt: true,
  );

  @override
  final MappableFields<WebSearchConfig> fields = const {
    #provider: _f$provider,
    #timeoutSeconds: _f$timeoutSeconds,
    #defaultMaxResults: _f$defaultMaxResults,
    #braveApiKey: _f$braveApiKey,
    #tavilyApiKey: _f$tavilyApiKey,
    #firecrawlApiKey: _f$firecrawlApiKey,
    #firecrawlBaseUrl: _f$firecrawlBaseUrl,
  };

  static WebSearchConfig _instantiate(DecodingData data) {
    return WebSearchConfig(
      provider: data.dec(_f$provider),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      defaultMaxResults: data.dec(_f$defaultMaxResults),
      braveApiKey: data.dec(_f$braveApiKey),
      tavilyApiKey: data.dec(_f$tavilyApiKey),
      firecrawlApiKey: data.dec(_f$firecrawlApiKey),
      firecrawlBaseUrl: data.dec(_f$firecrawlBaseUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WebSearchConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WebSearchConfig>(map);
  }

  static WebSearchConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WebSearchConfig>(json);
  }
}

mixin WebSearchConfigMappable {
  String toJson() {
    return WebSearchConfigMapper.ensureInitialized()
        .encodeJson<WebSearchConfig>(this as WebSearchConfig);
  }

  Map<String, dynamic> toMap() {
    return WebSearchConfigMapper.ensureInitialized().encodeMap<WebSearchConfig>(
      this as WebSearchConfig,
    );
  }

  WebSearchConfigCopyWith<WebSearchConfig, WebSearchConfig, WebSearchConfig>
  get copyWith =>
      _WebSearchConfigCopyWithImpl<WebSearchConfig, WebSearchConfig>(
        this as WebSearchConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WebSearchConfigMapper.ensureInitialized().stringifyValue(
      this as WebSearchConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WebSearchConfigMapper.ensureInitialized().equalsValue(
      this as WebSearchConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WebSearchConfigMapper.ensureInitialized().hashValue(
      this as WebSearchConfig,
    );
  }
}

extension WebSearchConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WebSearchConfig, $Out> {
  WebSearchConfigCopyWith<$R, WebSearchConfig, $Out> get $asWebSearchConfig =>
      $base.as((v, t, t2) => _WebSearchConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WebSearchConfigCopyWith<$R, $In extends WebSearchConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    WebSearchProviderType? provider,
    int? timeoutSeconds,
    int? defaultMaxResults,
    String? braveApiKey,
    String? tavilyApiKey,
    String? firecrawlApiKey,
    String? firecrawlBaseUrl,
  });
  WebSearchConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WebSearchConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WebSearchConfig, $Out>
    implements WebSearchConfigCopyWith<$R, WebSearchConfig, $Out> {
  _WebSearchConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WebSearchConfig> $mapper =
      WebSearchConfigMapper.ensureInitialized();
  @override
  $R call({
    Object? provider = $none,
    int? timeoutSeconds,
    int? defaultMaxResults,
    Object? braveApiKey = $none,
    Object? tavilyApiKey = $none,
    Object? firecrawlApiKey = $none,
    Object? firecrawlBaseUrl = $none,
  }) => $apply(
    FieldCopyWithData({
      if (provider != $none) #provider: provider,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
      if (defaultMaxResults != null) #defaultMaxResults: defaultMaxResults,
      if (braveApiKey != $none) #braveApiKey: braveApiKey,
      if (tavilyApiKey != $none) #tavilyApiKey: tavilyApiKey,
      if (firecrawlApiKey != $none) #firecrawlApiKey: firecrawlApiKey,
      if (firecrawlBaseUrl != $none) #firecrawlBaseUrl: firecrawlBaseUrl,
    }),
  );
  @override
  WebSearchConfig $make(CopyWithData data) => WebSearchConfig(
    provider: data.get(#provider, or: $value.provider),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    defaultMaxResults: data.get(
      #defaultMaxResults,
      or: $value.defaultMaxResults,
    ),
    braveApiKey: data.get(#braveApiKey, or: $value.braveApiKey),
    tavilyApiKey: data.get(#tavilyApiKey, or: $value.tavilyApiKey),
    firecrawlApiKey: data.get(#firecrawlApiKey, or: $value.firecrawlApiKey),
    firecrawlBaseUrl: data.get(#firecrawlBaseUrl, or: $value.firecrawlBaseUrl),
  );

  @override
  WebSearchConfigCopyWith<$R2, WebSearchConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WebSearchConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PdfConfigMapper extends ClassMapperBase<PdfConfig> {
  PdfConfigMapper._();

  static PdfConfigMapper? _instance;
  static PdfConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PdfConfigMapper._());
      OcrProviderTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PdfConfig';

  static int _$maxBytes(PdfConfig v) => v.maxBytes;
  static const Field<PdfConfig, int> _f$maxBytes = Field(
    'maxBytes',
    _$maxBytes,
    opt: true,
    def: AppConstants.pdfMaxBytes,
  );
  static int _$timeoutSeconds(PdfConfig v) => v.timeoutSeconds;
  static const Field<PdfConfig, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: AppConstants.pdfTimeoutSeconds,
  );
  static bool _$enableOcrFallback(PdfConfig v) => v.enableOcrFallback;
  static const Field<PdfConfig, bool> _f$enableOcrFallback = Field(
    'enableOcrFallback',
    _$enableOcrFallback,
    opt: true,
    def: true,
  );
  static OcrProviderType _$ocrProvider(PdfConfig v) => v.ocrProvider;
  static const Field<PdfConfig, OcrProviderType> _f$ocrProvider = Field(
    'ocrProvider',
    _$ocrProvider,
    opt: true,
    def: OcrProviderType.mistral,
  );
  static String? _$mistralApiKey(PdfConfig v) => v.mistralApiKey;
  static const Field<PdfConfig, String> _f$mistralApiKey = Field(
    'mistralApiKey',
    _$mistralApiKey,
    opt: true,
  );
  static String _$mistralModel(PdfConfig v) => v.mistralModel;
  static const Field<PdfConfig, String> _f$mistralModel = Field(
    'mistralModel',
    _$mistralModel,
    opt: true,
    def: 'mistral-ocr-small',
  );
  static String? _$openaiApiKey(PdfConfig v) => v.openaiApiKey;
  static const Field<PdfConfig, String> _f$openaiApiKey = Field(
    'openaiApiKey',
    _$openaiApiKey,
    opt: true,
  );
  static String _$openaiModel(PdfConfig v) => v.openaiModel;
  static const Field<PdfConfig, String> _f$openaiModel = Field(
    'openaiModel',
    _$openaiModel,
    opt: true,
    def: 'gpt-4.1-mini',
  );

  @override
  final MappableFields<PdfConfig> fields = const {
    #maxBytes: _f$maxBytes,
    #timeoutSeconds: _f$timeoutSeconds,
    #enableOcrFallback: _f$enableOcrFallback,
    #ocrProvider: _f$ocrProvider,
    #mistralApiKey: _f$mistralApiKey,
    #mistralModel: _f$mistralModel,
    #openaiApiKey: _f$openaiApiKey,
    #openaiModel: _f$openaiModel,
  };

  static PdfConfig _instantiate(DecodingData data) {
    return PdfConfig(
      maxBytes: data.dec(_f$maxBytes),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      enableOcrFallback: data.dec(_f$enableOcrFallback),
      ocrProvider: data.dec(_f$ocrProvider),
      mistralApiKey: data.dec(_f$mistralApiKey),
      mistralModel: data.dec(_f$mistralModel),
      openaiApiKey: data.dec(_f$openaiApiKey),
      openaiModel: data.dec(_f$openaiModel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PdfConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PdfConfig>(map);
  }

  static PdfConfig fromJson(String json) {
    return ensureInitialized().decodeJson<PdfConfig>(json);
  }
}

mixin PdfConfigMappable {
  String toJson() {
    return PdfConfigMapper.ensureInitialized().encodeJson<PdfConfig>(
      this as PdfConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return PdfConfigMapper.ensureInitialized().encodeMap<PdfConfig>(
      this as PdfConfig,
    );
  }

  PdfConfigCopyWith<PdfConfig, PdfConfig, PdfConfig> get copyWith =>
      _PdfConfigCopyWithImpl<PdfConfig, PdfConfig>(
        this as PdfConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PdfConfigMapper.ensureInitialized().stringifyValue(
      this as PdfConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return PdfConfigMapper.ensureInitialized().equalsValue(
      this as PdfConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return PdfConfigMapper.ensureInitialized().hashValue(this as PdfConfig);
  }
}

extension PdfConfigValueCopy<$R, $Out> on ObjectCopyWith<$R, PdfConfig, $Out> {
  PdfConfigCopyWith<$R, PdfConfig, $Out> get $asPdfConfig =>
      $base.as((v, t, t2) => _PdfConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PdfConfigCopyWith<$R, $In extends PdfConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? maxBytes,
    int? timeoutSeconds,
    bool? enableOcrFallback,
    OcrProviderType? ocrProvider,
    String? mistralApiKey,
    String? mistralModel,
    String? openaiApiKey,
    String? openaiModel,
  });
  PdfConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PdfConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PdfConfig, $Out>
    implements PdfConfigCopyWith<$R, PdfConfig, $Out> {
  _PdfConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PdfConfig> $mapper =
      PdfConfigMapper.ensureInitialized();
  @override
  $R call({
    int? maxBytes,
    int? timeoutSeconds,
    bool? enableOcrFallback,
    OcrProviderType? ocrProvider,
    Object? mistralApiKey = $none,
    String? mistralModel,
    Object? openaiApiKey = $none,
    String? openaiModel,
  }) => $apply(
    FieldCopyWithData({
      if (maxBytes != null) #maxBytes: maxBytes,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
      if (enableOcrFallback != null) #enableOcrFallback: enableOcrFallback,
      if (ocrProvider != null) #ocrProvider: ocrProvider,
      if (mistralApiKey != $none) #mistralApiKey: mistralApiKey,
      if (mistralModel != null) #mistralModel: mistralModel,
      if (openaiApiKey != $none) #openaiApiKey: openaiApiKey,
      if (openaiModel != null) #openaiModel: openaiModel,
    }),
  );
  @override
  PdfConfig $make(CopyWithData data) => PdfConfig(
    maxBytes: data.get(#maxBytes, or: $value.maxBytes),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    enableOcrFallback: data.get(
      #enableOcrFallback,
      or: $value.enableOcrFallback,
    ),
    ocrProvider: data.get(#ocrProvider, or: $value.ocrProvider),
    mistralApiKey: data.get(#mistralApiKey, or: $value.mistralApiKey),
    mistralModel: data.get(#mistralModel, or: $value.mistralModel),
    openaiApiKey: data.get(#openaiApiKey, or: $value.openaiApiKey),
    openaiModel: data.get(#openaiModel, or: $value.openaiModel),
  );

  @override
  PdfConfigCopyWith<$R2, PdfConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PdfConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WebConfigMapper extends ClassMapperBase<WebConfig> {
  WebConfigMapper._();

  static WebConfigMapper? _instance;
  static WebConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WebConfigMapper._());
      WebFetchConfigMapper.ensureInitialized();
      WebSearchConfigMapper.ensureInitialized();
      PdfConfigMapper.ensureInitialized();
      BrowserConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WebConfig';

  static WebFetchConfig _$fetch(WebConfig v) => v.fetch;
  static const Field<WebConfig, WebFetchConfig> _f$fetch = Field(
    'fetch',
    _$fetch,
    opt: true,
    def: const WebFetchConfig(),
  );
  static WebSearchConfig _$search(WebConfig v) => v.search;
  static const Field<WebConfig, WebSearchConfig> _f$search = Field(
    'search',
    _$search,
    opt: true,
    def: const WebSearchConfig(),
  );
  static PdfConfig _$pdf(WebConfig v) => v.pdf;
  static const Field<WebConfig, PdfConfig> _f$pdf = Field(
    'pdf',
    _$pdf,
    opt: true,
    def: const PdfConfig(),
  );
  static BrowserConfig _$browser(WebConfig v) => v.browser;
  static const Field<WebConfig, BrowserConfig> _f$browser = Field(
    'browser',
    _$browser,
    opt: true,
    def: const BrowserConfig(),
  );

  @override
  final MappableFields<WebConfig> fields = const {
    #fetch: _f$fetch,
    #search: _f$search,
    #pdf: _f$pdf,
    #browser: _f$browser,
  };

  static WebConfig _instantiate(DecodingData data) {
    return WebConfig(
      fetch: data.dec(_f$fetch),
      search: data.dec(_f$search),
      pdf: data.dec(_f$pdf),
      browser: data.dec(_f$browser),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WebConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WebConfig>(map);
  }

  static WebConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WebConfig>(json);
  }
}

mixin WebConfigMappable {
  String toJson() {
    return WebConfigMapper.ensureInitialized().encodeJson<WebConfig>(
      this as WebConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return WebConfigMapper.ensureInitialized().encodeMap<WebConfig>(
      this as WebConfig,
    );
  }

  WebConfigCopyWith<WebConfig, WebConfig, WebConfig> get copyWith =>
      _WebConfigCopyWithImpl<WebConfig, WebConfig>(
        this as WebConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WebConfigMapper.ensureInitialized().stringifyValue(
      this as WebConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WebConfigMapper.ensureInitialized().equalsValue(
      this as WebConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WebConfigMapper.ensureInitialized().hashValue(this as WebConfig);
  }
}

extension WebConfigValueCopy<$R, $Out> on ObjectCopyWith<$R, WebConfig, $Out> {
  WebConfigCopyWith<$R, WebConfig, $Out> get $asWebConfig =>
      $base.as((v, t, t2) => _WebConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WebConfigCopyWith<$R, $In extends WebConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  WebFetchConfigCopyWith<$R, WebFetchConfig, WebFetchConfig> get fetch;
  WebSearchConfigCopyWith<$R, WebSearchConfig, WebSearchConfig> get search;
  PdfConfigCopyWith<$R, PdfConfig, PdfConfig> get pdf;
  BrowserConfigCopyWith<$R, BrowserConfig, BrowserConfig> get browser;
  $R call({
    WebFetchConfig? fetch,
    WebSearchConfig? search,
    PdfConfig? pdf,
    BrowserConfig? browser,
  });
  WebConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _WebConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WebConfig, $Out>
    implements WebConfigCopyWith<$R, WebConfig, $Out> {
  _WebConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WebConfig> $mapper =
      WebConfigMapper.ensureInitialized();
  @override
  WebFetchConfigCopyWith<$R, WebFetchConfig, WebFetchConfig> get fetch =>
      $value.fetch.copyWith.$chain((v) => call(fetch: v));
  @override
  WebSearchConfigCopyWith<$R, WebSearchConfig, WebSearchConfig> get search =>
      $value.search.copyWith.$chain((v) => call(search: v));
  @override
  PdfConfigCopyWith<$R, PdfConfig, PdfConfig> get pdf =>
      $value.pdf.copyWith.$chain((v) => call(pdf: v));
  @override
  BrowserConfigCopyWith<$R, BrowserConfig, BrowserConfig> get browser =>
      $value.browser.copyWith.$chain((v) => call(browser: v));
  @override
  $R call({
    WebFetchConfig? fetch,
    WebSearchConfig? search,
    PdfConfig? pdf,
    BrowserConfig? browser,
  }) => $apply(
    FieldCopyWithData({
      if (fetch != null) #fetch: fetch,
      if (search != null) #search: search,
      if (pdf != null) #pdf: pdf,
      if (browser != null) #browser: browser,
    }),
  );
  @override
  WebConfig $make(CopyWithData data) => WebConfig(
    fetch: data.get(#fetch, or: $value.fetch),
    search: data.get(#search, or: $value.search),
    pdf: data.get(#pdf, or: $value.pdf),
    browser: data.get(#browser, or: $value.browser),
  );

  @override
  WebConfigCopyWith<$R2, WebConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WebConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

