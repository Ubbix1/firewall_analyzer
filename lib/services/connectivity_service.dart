import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:flutter/foundation.dart';

enum AppConnectivityStatus {
  online,
  offline,
  noInternet,
}

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  final InternetConnection _internetConnection = InternetConnection();
  
  AppConnectivityStatus _status = AppConnectivityStatus.online;
  AppConnectivityStatus get status => _status;
  
  bool get isOnline => _status == AppConnectivityStatus.online;
  bool get hasInternet => _status != AppConnectivityStatus.noInternet;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<InternetStatus>? _internetSubscription;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Initial check
    final results = await _connectivity.checkConnectivity();
    await _updateStatus(results);

    // Listen to changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
    
    _internetSubscription = _internetConnection.onStatusChange.listen((status) {
      _handleInternetStatus(status);
    });
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.none)) {
      _status = AppConnectivityStatus.noInternet;
    } else {
      final hasInternet = await _internetConnection.hasInternetAccess;
      _status = hasInternet ? AppConnectivityStatus.online : AppConnectivityStatus.noInternet;
    }
    notifyListeners();
  }

  void _handleInternetStatus(InternetStatus status) {
    if (status == InternetStatus.connected) {
      _status = AppConnectivityStatus.online;
    } else {
      _status = AppConnectivityStatus.noInternet;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _internetSubscription?.cancel();
    super.dispose();
  }
}
