import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/dependencies.dart';
import 'ui/screens/groups_screen.dart';
import 'ui/screens/sign_in_screen.dart';

void main() {
  runApp(Dependencies(child: const SplitterApp()));
}

class SplitterApp extends StatelessWidget {
  const SplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Splitter',
      debugShowCheckedModeBanner: false,

      // Forced, not negotiated with the device. The app ships one language,
      // so honouring a phone set to English would only produce Material
      // widgets in English next to our own text in Spanish.
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D64)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D64),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _Entrance(),
    );
  }
}

/// Decides between the sign-in screen and the app, and nothing else.
///
/// It listens to the session rather than navigating on login. That means
/// there is exactly one answer to "am I signed in", and no way to end up on a
/// group screen after the token was thrown away — logging out anywhere in the
/// app rebuilds straight back to sign-in.
class _Entrance extends StatefulWidget {
  const _Entrance();

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  late final Future<void> _restored;

  @override
  void initState() {
    super.initState();
    // Reading the keystore is async, and until it comes back we genuinely do
    // not know which screen is correct. Showing the sign-in form in the
    // meantime would flash it at somebody who is already signed in.
    _restored = Dependencies.of(context).session.restore();
  }

  @override
  Widget build(BuildContext context) {
    final session = Dependencies.of(context).session;

    return FutureBuilder<void>(
      future: _restored,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return ListenableBuilder(
          listenable: session,
          builder: (context, _) =>
              session.isLoggedIn ? const GroupsScreen() : const SignInScreen(),
        );
      },
    );
  }
}
