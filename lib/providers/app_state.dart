import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/github_service.dart';

class AppState extends ChangeNotifier {
  String? _githubToken;
  String? _username;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  String? _downloadUrl;
  
  final GitHubService _githubService = GitHubService();

  String? get githubToken => _githubToken;
  String? get username => _username;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  String? get downloadUrl => _downloadUrl;
  bool get isAuthenticated => _githubToken != null && _githubToken!.isNotEmpty;

  AppState() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _githubToken = prefs.getString('github_token');
    _username = prefs.getString('github_username');
    notifyListeners();
  }

  Future<void> saveToken(String token) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Verify token by getting user info
      final user = await _githubService.getUserInfo(token);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('github_token', token);
      await prefs.setString('github_username', user['login']);
      
      _githubToken = token;
      _username = user['login'];
      _successMessage = 'Successfully connected to GitHub as ${user['login']}';
    } catch (e) {
      _errorMessage = 'Failed to authenticate: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_token');
    await prefs.remove('github_username');
    _githubToken = null;
    _username = null;
    _downloadUrl = null;
    notifyListeners();
  }

  Future<void> generateApp(String appDescription) async {
    if (_githubToken == null) {
      _errorMessage = 'Please connect your GitHub account first';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    _downloadUrl = null;
    notifyListeners();

    try {
      // Step 1: Generate app code using AI
      _successMessage = 'Generating app code with AI...';
      notifyListeners();
      
      final appCode = await _githubService.generateAppCode(appDescription);
      
      // Step 2: Create GitHub repository
      _successMessage = 'Creating GitHub repository...';
      notifyListeners();
      
      final repoName = 'ai-generated-app-${DateTime.now().millisecondsSinceEpoch}';
      await _githubService.createRepository(_githubToken!, repoName, appDescription);
      
      // Step 3: Upload app files
      _successMessage = 'Uploading app files...';
      notifyListeners();
      
      await _githubService.uploadAppFiles(_githubToken!, _username!, repoName, appCode);
      
      // Step 4: Create GitHub Actions workflow
      _successMessage = 'Creating build workflow...';
      notifyListeners();
      
      await _githubService.createWorkflow(_githubToken!, _username!, repoName);
      
      // Step 5: Wait for build and get download URL
      _successMessage = 'Building APK... This may take a few minutes...';
      notifyListeners();
      
      final downloadUrl = await _githubService.waitForBuildAndGetDownloadUrl(
        _githubToken!, 
        _username!, 
        repoName
      );
      
      _downloadUrl = downloadUrl;
      _successMessage = 'APK generated successfully! Repository: https://github.com/$_username/$repoName';
    } catch (e) {
      _errorMessage = 'Failed to generate app: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }
}
