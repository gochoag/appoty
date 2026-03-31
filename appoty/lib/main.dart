import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'activation_screen.dart';
import 'activation_service.dart';
import 'scanner_screen.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const AppOty());
}

class AppOty extends StatelessWidget {
  const AppOty({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appoty',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.green,
          secondary: Colors.greenAccent,
        ),
      ),
      home: const _ActivationGate(),
    );
  }
}

class _ActivationGate extends StatefulWidget {
  const _ActivationGate();
  @override
  State<_ActivationGate> createState() => _ActivationGateState();
}

class _ActivationGateState extends State<_ActivationGate> {
  bool? _activated;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await ActivationService.isActivated();
    if (mounted) setState(() => _activated = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_activated == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }
    if (!_activated!) {
      return ActivationScreen(
        onActivated: () => setState(() => _activated = true),
      );
    }
    return HomeScreen(cameras: cameras);
  }
}

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.sim_card,
                      color: Colors.greenAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Appoty',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Ingresa tu tarjeta Claro\nautomáticamente',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              _buildStep(number: '1', title: 'Abre la cámara'),
              const SizedBox(height: 20),
              _buildStep(number: '2', title: 'Escanea el código'),
              const SizedBox(height: 20),
              _buildStep(number: '3', title: 'Se ingresa tu tarjeta'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(cameras: cameras),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text(
                    'Escanear tarjeta',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({required String number, required String title}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            border: Border.all(
              color: Colors.greenAccent.withOpacity(0.6),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
