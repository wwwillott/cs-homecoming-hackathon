/// Base URL of the Spruce API. Override with
/// `--dart-define=ORBIT_API_URL=http://127.0.0.1:8000` to use a local backend.
const String apiBaseUrl = String.fromEnvironment(
  'ORBIT_API_URL',
  defaultValue: 'https://api.spruce.my',
);
