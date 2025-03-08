import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'models/manilla_data.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foqqus Cashless',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ManillaData? _lastData;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _initUniLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initUniLinks() async {
    // Handle incoming links - deep linking
    _sub = uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleIncomingLink(uri);
      }
    }, onError: (err) {
      print('Error handling incoming links: $err');
    });

    // Handle initial URI if the app was launched with one
    try {
      final initialUri = await getInitialUri();
      if (initialUri != null) {
        _handleIncomingLink(initialUri);
      }
    } catch (e) {
      print('Error handling initial uri: $e');
    }
  }

  void _handleIncomingLink(Uri uri) {
    final data = ManillaData.fromUri(uri);
    if (data != null) {
      setState(() {
        _lastData = data;
      });
    }
  }

  Future<void> _volverAWeb() async {
    final baseUrl = 'https://delicate-cendol-2dc565.netlify.app';
    
    // Construir la URL con los parámetros del estado actual
    final Map<String, String> params = _lastData != null ? {
      'accion': _lastData!.accion,
      'timestamp': _lastData!.timestamp.toString(),
      'origen': 'app'
    } : {};
    
    try {
      // Construir la URL final
      final uri = Uri.https('delicate-cendol-2dc565.netlify.app', '', params);
      print('Intentando abrir URL: $uri');

      // Intentar abrir directamente con launchUrl
      final result = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );

      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la URL: $uri'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error al abrir URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir la página web: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foqqus Cashless'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_lastData != null) ...[
              Text(
                'Acción recibida: ${_lastData!.accion}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Text(
                'Timestamp: ${_lastData!.timestamp}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
            ],
            ElevatedButton(
              onPressed: _volverAWeb,
              child: const Text('Volver a la Web'),
            ),
          ],
        ),
      ),
    );
  }
}
