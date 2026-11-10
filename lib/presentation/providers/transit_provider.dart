import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/transit_service.dart';

final transitServiceProvider = Provider<TransitService>((ref) {
  final service = TransitService();
  ref.onDispose(service.close);
  return service;
});
