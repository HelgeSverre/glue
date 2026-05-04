/// Sealed reference to a credential source.
///
/// Separates *where* a secret comes from from *what the secret is*. Adapters
/// receive a resolved string (via [CredentialStore.resolve]) and never read
/// the environment or credentials file themselves.
library;

sealed class CredentialRef {
  const CredentialRef();
}

/// The credential is read from an environment variable.
final class EnvCredential extends CredentialRef {
  const EnvCredential(this.name);
  final String name;

  @override
  bool operator ==(Object other) =>
      other is EnvCredential && other.name == name;

  @override
  int get hashCode => Object.hash('Env', name);
}

/// The credential is stored under a provider id in `~/.glue/credentials.json`.
final class StoredCredential extends CredentialRef {
  const StoredCredential(this.key);
  final String key;

  @override
  bool operator ==(Object other) =>
      other is StoredCredential && other.key == key;

  @override
  int get hashCode => Object.hash('Stored', key);
}

/// An inline secret parsed from a user-owned file (not recommended).
final class InlineCredential extends CredentialRef {
  const InlineCredential(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is InlineCredential && other.value == value;

  @override
  int get hashCode => Object.hash('Inline', value);
}

/// The provider needs no credential (e.g. Ollama with `auth: api_key: none`).
final class NoCredential extends CredentialRef {
  const NoCredential();

  @override
  bool operator ==(Object other) => other is NoCredential;

  @override
  int get hashCode => 0;
}
