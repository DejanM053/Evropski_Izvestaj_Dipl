import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dev_gallery.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android target, portrait only (docs/master_plan.md §2).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AccidentReportApp());
}

class AccidentReportApp extends StatelessWidget {
  const AccidentReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evropski izveštaj',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Phase 5 only: no real screens exist yet, so the design-system
      // gallery is the temporary home route (see dev_gallery.dart).
      home: const DevGalleryScreen(),
    );
  }
}
