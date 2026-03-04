import 'package:puppeteer/puppeteer.dart' as pptr;

import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:glue/src/web/browser/browser_config.dart';

/// Launches a local Chrome/Chromium instance via puppeteer.
class LocalProvider implements BrowserEndpointProvider {
  final BrowserConfig config;

  LocalProvider(this.config);

  bool get headed => config.headed;

  @override
  String get name => 'local';

  @override
  bool get isConfigured => true;

  @override
  @Deprecated('Use isConfigured instead.')
  bool get isAvailable => isConfigured;

  @override
  Future<BrowserEndpoint> provision() async {
    final browser = await pptr.puppeteer.launch(
      headless: !config.headed,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
      ],
    );

    return BrowserEndpoint(
      cdpWsUrl: browser.wsEndpoint,
      backendName: name,
      headed: config.headed,
      onClose: () async {
        await browser.close();
      },
    );
  }
}
