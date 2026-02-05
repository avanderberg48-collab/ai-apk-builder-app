import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class GitHubService {
  static const String githubApiBase = 'https://api.github.com';
  
  Future<Map<String, dynamic>> getUserInfo(String token) async {
    final response = await http.get(
      Uri.parse('$githubApiBase/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get user info: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> generateAppCode(String appDescription) async {
    // Use OpenAI API to generate Flutter app code
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null) {
      throw Exception('OpenAI API key not found');
    }

    final prompt = '''
Generate a complete Flutter Android app based on this description: $appDescription

Requirements:
- Create a simple, functional Flutter app
- Use Material Design 3
- Include proper error handling
- Make it user-friendly
- Keep it simple but functional

Provide the main.dart file content only. Make it a complete, working Flutter application.
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': 'gpt-4.1-mini',
        'messages': [
          {
            'role': 'system',
            'content': 'You are a Flutter expert. Generate clean, working Flutter code.'
          },
          {
            'role': 'user',
            'content': prompt
          }
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final generatedCode = data['choices'][0]['message']['content'];
      
      // Extract code from markdown if present
      String cleanCode = generatedCode;
      if (cleanCode.contains('```dart')) {
        final start = cleanCode.indexOf('```dart') + 7;
        final end = cleanCode.lastIndexOf('```');
        cleanCode = cleanCode.substring(start, end).trim();
      } else if (cleanCode.contains('```')) {
        final start = cleanCode.indexOf('```') + 3;
        final end = cleanCode.lastIndexOf('```');
        cleanCode = cleanCode.substring(start, end).trim();
      }
      
      return {
        'main.dart': cleanCode,
        'pubspec.yaml': _generatePubspec(appDescription),
      };
    } else {
      throw Exception('Failed to generate code: ${response.body}');
    }
  }

  String _generatePubspec(String appDescription) {
    final appName = appDescription
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    
    return '''
name: $appName
description: $appDescription
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true
''';
  }

  Future<void> createRepository(String token, String repoName, String description) async {
    final response = await http.post(
      Uri.parse('$githubApiBase/user/repos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': repoName,
        'description': description,
        'private': false,
        'auto_init': true,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create repository: ${response.body}');
    }
    
    // Wait for repository to be ready
    await Future.delayed(const Duration(seconds: 3));
  }

  Future<void> uploadAppFiles(
    String token,
    String username,
    String repoName,
    Map<String, dynamic> files,
  ) async {
    // Upload main.dart
    await _uploadFile(
      token,
      username,
      repoName,
      'lib/main.dart',
      files['main.dart'],
    );

    // Upload pubspec.yaml
    await _uploadFile(
      token,
      username,
      repoName,
      'pubspec.yaml',
      files['pubspec.yaml'],
    );

    // Upload analysis_options.yaml
    await _uploadFile(
      token,
      username,
      repoName,
      'analysis_options.yaml',
      'include: package:flutter_lints/flutter.yaml\n',
    );
  }

  Future<void> _uploadFile(
    String token,
    String username,
    String repoName,
    String path,
    String content,
  ) async {
    final response = await http.put(
      Uri.parse('$githubApiBase/repos/$username/$repoName/contents/$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'message': 'Add $path',
        'content': base64Encode(utf8.encode(content)),
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to upload $path: ${response.body}');
    }
  }

  Future<void> createWorkflow(String token, String username, String repoName) async {
    final workflowContent = '''
name: Build Android APK

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up JDK 17
      uses: actions/setup-java@v3
      with:
        distribution: 'zulu'
        java-version: '17'
    
    - name: Set up Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.24.0'
        channel: 'stable'
    
    - name: Install dependencies
      run: flutter pub get
    
    - name: Build APK
      run: flutter build apk --release
    
    - name: Create Release
      id: create_release
      uses: actions/create-release@v1
      env:
        GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
      with:
        tag_name: v\${{ github.run_number }}
        release_name: Release v\${{ github.run_number }}
        draft: false
        prerelease: false
    
    - name: Upload APK to Release
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: \${{ steps.create_release.outputs.upload_url }}
        asset_path: build/app/outputs/flutter-apk/app-release.apk
        asset_name: app-release.apk
        asset_content_type: application/vnd.android.package-archive
''';

    await _uploadFile(
      token,
      username,
      repoName,
      '.github/workflows/build.yml',
      workflowContent,
    );
  }

  Future<String> waitForBuildAndGetDownloadUrl(
    String token,
    String username,
    String repoName,
  ) async {
    // Wait for workflow to start
    await Future.delayed(const Duration(seconds: 10));
    
    // Poll for workflow completion (max 10 minutes)
    for (int i = 0; i < 60; i++) {
      try {
        // Check for releases
        final response = await http.get(
          Uri.parse('$githubApiBase/repos/$username/$repoName/releases'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/vnd.github.v3+json',
          },
        );

        if (response.statusCode == 200) {
          final releases = json.decode(response.body) as List;
          if (releases.isNotEmpty) {
            final latestRelease = releases[0];
            final assets = latestRelease['assets'] as List;
            if (assets.isNotEmpty) {
              return assets[0]['browser_download_url'];
            }
          }
        }
      } catch (e) {
        // Continue polling
      }
      
      await Future.delayed(const Duration(seconds: 10));
    }
    
    throw Exception('Build timeout. Please check the repository for the APK: https://github.com/$username/$repoName/releases');
  }
}
