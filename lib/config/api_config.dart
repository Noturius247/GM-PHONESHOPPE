class ApiConfig {
  // Base URL for the API
  static const String baseUrl = 'http://localhost:3000';

  // API endpoints
  static const String apiVersion = '/api/v1';

  // Full API URL
  static String get apiUrl => '$baseUrl$apiVersion';

  // Specific endpoints
  static String get customersEndpoint => '$apiUrl/customers';
  static String get cignalEndpoint => '$apiUrl/cignal';
  static String get satliteEndpoint => '$apiUrl/satlite';
  static String get gsatEndpoint => '$apiUrl/gsat';
  static String get skyEndpoint => '$apiUrl/sky';
  static String get reportsEndpoint => '$apiUrl/reports';

  // Timeout duration
  static const Duration timeoutDuration = Duration(seconds: 30);
}
