import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/storage/file_store.dart';
import 'src/core/storage/local_store.dart';
import 'src/state/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localStore = await LocalStore.create();
  final fileStore = await FileStore.create();

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(localStore),
        fileStoreProvider.overrideWithValue(fileStore),
      ],
      child: const PhantomEyeApp(),
    ),
  );
}
