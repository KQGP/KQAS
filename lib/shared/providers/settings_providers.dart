import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory for Phase 1. Persisted through app_settings in Phase 10 (Settings).
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);
