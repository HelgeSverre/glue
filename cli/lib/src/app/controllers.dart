part of 'package:glue/src/app.dart';

class _AppControllers implements SlashCommandContext {
  _AppControllers(App app)
      : _config = app._configService,
        _session = app._sessionService {
    system = SystemController(
      environment: app._environment,
      requestExit: app.requestExit,
      panels: app._panels,
      commands: () => app._commands.commands,
      render: app._render,
      currentSessionId: () => _session.currentId,
      debugController: app._debugController,
    );
    chat = ChatController(
      terminal: app.terminal,
      layout: app.layout,
      clearConversationState: () {
        app._transcript.blocks.clear();
        app._transcript.scrollOffset = 0;
        app._transcript.streamingText = '';
      },
      render: app._render,
      tools: () => app.agent.tools.values,
      getApprovalMode: () => app._approvalMode,
      setApprovalMode: (mode) => app._approvalMode = mode,
      transcript: app._transcript,
    );
    models = ModelController(
      config: _config,
      getLlmFactory: () => app._llmFactory,
      getSystemPrompt: () => app._systemPrompt,
      agent: app.agent,
      session: _session,
      panels: app._panels,
      confirmations: _AppConfirmations(app),
      transcript: app._transcript,
      render: app._render,
      setModelId: (modelId) => app._modelId = modelId,
    );
    sessions = SessionController(
      session: _session,
      agent: app.agent,
      panels: app._panels,
      transcript: app._transcript,
      render: app._render,
      shortenPath: app._shortenPath,
      cwd: app._cwd,
      modelLabel: () => formatInfoModelLabel(
        app._config?.activeModel,
        app._config?.catalogData,
        app._modelId,
      ),
      approvalLabel: () => app._approvalMode.label,
      autoApprovedTools: () => app._configService.trustedTools.toList(),
    );
    share = ShareController(
      canShare: () => app._mode == AppMode.idle,
      currentStore: () => _session.currentStore,
      cwd: app._cwd,
      transcript: app._transcript,
      render: app._render,
    );
    skills = SkillsController(
      skillRuntime: app._skillRuntime,
      docks: app._docks,
      render: app._render,
      transcript: app._transcript,
      activateSkill: app._activateSkillFromUi,
    );
    providers = ProviderController(
      config: _config,
      panels: app._panels,
      transcript: app._transcript,
      render: app._render,
    );
  }

  final Config _config;
  final Session _session;

  @override
  late final SystemCommandController system;

  @override
  late final ChatCommandController chat;

  @override
  late final ModelCommandController models;

  @override
  late final SessionCommandController sessions;

  @override
  late final ShareCommandController share;

  @override
  late final SkillsCommandController skills;

  @override
  late final ProviderCommandController providers;
}

class _AppConfirmations implements Confirmations {
  const _AppConfirmations(this.app);

  final App app;

  @override
  Future<bool> confirm({
    required String title,
    required List<String> bodyLines,
    List<ModalChoice> choices = const [
      ModalChoice('Yes', 'y'),
      ModalChoice('No', 'n'),
    ],
  }) async {
    app._mode = AppMode.confirming;
    final modal = ConfirmModal(
      title: title,
      bodyLines: bodyLines,
      choices: choices,
    );
    app._activeModal = modal;
    app._render();

    try {
      final choiceIndex = await modal.result;
      return choiceIndex == 0;
    } finally {
      if (identical(app._activeModal, modal)) {
        app._activeModal = null;
      }
      app._mode = AppMode.idle;
      app._render();
    }
  }
}
