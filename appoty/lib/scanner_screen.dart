import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'sim_service.dart';

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ScannerScreen({super.key, required this.cameras});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  bool _isProcessing = false;
  bool _isCameraReady = false;
  bool _flashOn = false;
  bool _useMethod2 = false;
  String? _detectedCode;
  Timer? _scanTimer;
  List<SimCard> _simCards = [];
  int? _preferredSimId;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadSimInfo();
  }

  Future<void> _loadSimInfo() async {
    final prefId = await SimService.getPreferredSimId();
    if (mounted) {
      setState(() => _preferredSimId = prefId);
    }
  }

  Future<void> _initCamera() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _showMessage('Permiso de cámara denegado');
      return;
    }

    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.off);
    setState(() => _flashOn = false);
    if (!mounted) return;

    setState(() => _isCameraReady = true);

    _scanTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _scanFrame(),
    );
  }

  Future<void> _scanFrame() async {
    if (_isProcessing ||
        _detectedCode != null ||
        _controller == null ||
        !_controller!.value.isInitialized)
      return;
    _isProcessing = true;

    try {
      final file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final recognized = await _textRecognizer.processImage(inputImage);
      final code = _extractCardCode(recognized.text);

      if (code != null && code != _detectedCode && mounted) {
        setState(() => _detectedCode = code);
      }
    } catch (_) {}

    _isProcessing = false;
  }

  String? _extractCardCode(String text) {
    final cleaned = text.replaceAll(RegExp(r'[\s\-]'), '');
    final regex = RegExp(r'\d{12,16}');
    final match = regex.firstMatch(cleaned);
    return match?.group(0);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isCameraReady) return;
    final next = _flashOn ? FlashMode.off : FlashMode.torch;
    await _controller!.setFlashMode(next);
    setState(() => _flashOn = !_flashOn);
  }

  Future<void> _makeCall() async {
    if (_detectedCode == null) return;

    final phoneStatus = await Permission.phone.request();
    if (!phoneStatus.isGranted) {
      _showMessage('Permiso de teléfono denegado');
      return;
    }

    final sims = await SimService.getSimCards();
    if (mounted) setState(() => _simCards = sims);

    final code = _detectedCode!;

    if (sims.length <= 1) {
      await _callUssd(code, sims.isNotEmpty ? sims.first.subscriptionId : -1);
      return;
    }

    if (_preferredSimId != null) {
      await _callUssd(code, _preferredSimId!);
      return;
    }

    await _showSimSelector(code);
  }

  Future<void> _callUssd(String code, int subscriptionId) async {
    if (subscriptionId == -1) {
      _showMessage('No se pudo determinar el chip a usar');
      return;
    }
    final ussd = _useMethod2 ? '*123*2*1*$code%23' : '*100*$code%23';
    await SimService.callWithSim(ussd, subscriptionId);
  }

  Future<void> _showSimSelector(String code) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _buildSimPickerSheet(
        ctx: ctx,
        onSelect: (sim) async {
          Navigator.pop(ctx);
          await SimService.savePreferredSimId(sim.subscriptionId);
          if (mounted) setState(() => _preferredSimId = sim.subscriptionId);
          await _callUssd(code, sim.subscriptionId);
        },
      ),
    );
  }

  Widget _buildSimPickerSheet({
    required BuildContext ctx,
    required Future<void> Function(SimCard) onSelect,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sim_card, color: Colors.greenAccent, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '¿Con qué chip ingresar la tarjeta?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Se guardará tu selección para la próxima vez',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ..._simCards.map((sim) => _buildSimTile(ctx, sim, onSelect)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSimTile(
    BuildContext ctx,
    SimCard sim,
    Future<void> Function(SimCard) onSelect,
  ) {
    final color = _carrierColor(sim.carrierName);
    final carrier = sim.carrierName.isNotEmpty
        ? sim.carrierName
        : 'SIM ${sim.slotIndex + 1}';
    return Semantics(
      label:
          '$carrier${sim.phoneNumber.isNotEmpty ? ", ${sim.phoneNumber}" : ""}. SIM ${sim.slotIndex + 1}.',
      button: true,
      child: GestureDetector(
        onTap: () => onSelect(sim),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.45), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.7), width: 2),
                ),
                child: Center(
                  child: Text(
                    sim.carrierName.isNotEmpty
                        ? sim.carrierName
                              .substring(0, sim.carrierName.length.clamp(0, 2))
                              .toUpperCase()
                        : 'S${sim.slotIndex + 1}',
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      carrier,
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SIM ${sim.slotIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                      ),
                    ),
                    if (sim.phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sim.phoneNumber,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color.withOpacity(0.7),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearCode() => setState(() => _detectedCode = null);

  Color _carrierColor(String carrierName) {
    final n = carrierName.toLowerCase();
    if (n.contains('claro')) return const Color(0xFFDA291C);
    if (n.contains('cnt')) return const Color(0xFF003DA5);
    if (n.contains('movistar')) return const Color(0xFF009A44);
    if (n.contains('tuenti')) return const Color(0xFFF26522);
    return Colors.teal;
  }

  Future<void> _changeSimPreference() async {
    if (_simCards.isEmpty) {
      final status = await Permission.phone.request();
      if (!status.isGranted) return;
      final sims = await SimService.getSimCards();
      if (mounted) setState(() => _simCards = sims);
    }
    if (_simCards.length <= 1 || !mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _buildSimPickerSheet(
        ctx: ctx,
        onSelect: (sim) async {
          Navigator.pop(ctx);
          await SimService.savePreferredSimId(sim.subscriptionId);
          if (mounted) setState(() => _preferredSimId = sim.subscriptionId);
        },
      ),
    );
  }

  Widget _buildSimBadge() {
    final sim = _simCards.firstWhere(
      (s) => s.subscriptionId == _preferredSimId,
      orElse: () => _simCards.first,
    );
    final color = _carrierColor(sim.carrierName);
    return Semantics(
      label: 'Chip seleccionado: ${sim.label}. Toca para cambiar.',
      button: true,
      child: GestureDetector(
        onTap: _changeSimPreference,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.6)),
                ),
                child: Center(
                  child: Text(
                    sim.carrierName.isNotEmpty
                        ? sim.carrierName[0].toUpperCase()
                        : 'S',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sim.carrierName.isNotEmpty
                          ? sim.carrierName
                          : 'Chip ${sim.slotIndex + 1}',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (sim.phoneNumber.isNotEmpty)
                      Text(
                        sim.phoneNumber,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      )
                    else
                      Text(
                        'SIM ${sim.slotIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Cambiar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraReady ? _buildScanner() : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.greenAccent),
          SizedBox(height: 16),
          Text('Iniciando cámara...', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _detectedCode != null ? -95.0 : 0.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      builder: (context, frameOffset, _) {
        return Stack(
          children: [
            SizedBox.expand(child: CameraPreview(_controller!)),
            _buildDimOverlay(frameOffset),
            _buildScanFrame(),
            // Flash button: round, above the scan frame, moves with frame
            Center(
              child: Transform.translate(
                offset: Offset(0, -148 + frameOffset),
                child: Semantics(
                  label: _flashOn ? 'Apagar linterna' : 'Encender linterna',
                  button: true,
                  child: GestureDetector(
                    onTap: _toggleFlash,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _flashOn
                            ? Colors.amber.withOpacity(0.25)
                            : Colors.black54,
                        border: Border.all(
                          color: _flashOn ? Colors.amber : Colors.white38,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _flashOn ? Icons.flashlight_on : Icons.flashlight_off,
                        color: _flashOn ? Colors.amber : Colors.white60,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_detectedCode != null)
              Center(
                child: Transform.translate(
                  offset: Offset(0, frameOffset),
                  child: GestureDetector(
                    onTap: _clearCode,
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.greenAccent,
                      size: 80,
                      semanticLabel: 'Volver a escanear',
                    ),
                  ),
                ),
              ),
            _buildTopBar(),
            _buildBottomPanel(),
          ],
        );
      },
    );
  }

  Widget _buildDimOverlay(double frameOffset) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _DimOverlayPainter(
          detected: _detectedCode != null,
          frameOffset: frameOffset,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Escanear Tarjeta Claro',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanFrame() => const SizedBox.shrink();

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: _detectedCode != null
              ? _buildCodePanel()
              : _buildScanningPanel(),
        ),
      ),
    );
  }

  Widget _buildScanningPanel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: Colors.greenAccent,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Buscando código en la tarjeta...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mantén la tarjeta dentro del recuadro',
            style: TextStyle(color: Colors.white30, fontSize: 12),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMethodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _methodTab('Método 1', '*100*', !_useMethod2),
          _methodTab('Método 2', '*123*', _useMethod2),
        ],
      ),
    );
  }

  Widget _methodTab(String label, String hint, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _useMethod2 = label == 'Método 2'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.green : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                hint,
                style: TextStyle(
                  color: active ? Colors.white70 : Colors.white24,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Código detectado',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.12),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _detectedCode!,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildMethodToggle(),
        const SizedBox(height: 10),
        if (_preferredSimId != null && _simCards.length > 1) _buildSimBadge(),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _makeCall,
            icon: const Icon(Icons.phone, size: 22),
            label: const Text(
              'Ingresar tarjeta',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DimOverlayPainter extends CustomPainter {
  final bool detected;
  final double frameOffset;
  const _DimOverlayPainter({required this.detected, this.frameOffset = 0});

  @override
  void paint(Canvas canvas, Size size) {
    const double frameW = 280;
    const double frameH = 160;
    const double radius = 12;
    final double cx = size.width / 2;
    final double cy = size.height / 2 + frameOffset;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: frameW, height: frameH),
      const Radius.circular(radius),
    );

    // Dim overlay with transparent hole
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rrect),
      ),
      Paint()..color = Colors.black.withOpacity(0.45),
    );

    // Border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = detected ? Colors.greenAccent : Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner accents
    final cp = Paint()
      ..color = detected ? Colors.greenAccent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const double cs = 22;
    final l = cx - frameW / 2;
    final r = cx + frameW / 2;
    final t = cy - frameH / 2;
    final b = cy + frameH / 2;
    // top-left
    canvas.drawLine(Offset(l, t + cs), Offset(l, t), cp);
    canvas.drawLine(Offset(l, t), Offset(l + cs, t), cp);
    // top-right
    canvas.drawLine(Offset(r - cs, t), Offset(r, t), cp);
    canvas.drawLine(Offset(r, t), Offset(r, t + cs), cp);
    // bottom-left
    canvas.drawLine(Offset(l, b - cs), Offset(l, b), cp);
    canvas.drawLine(Offset(l, b), Offset(l + cs, b), cp);
    // bottom-right
    canvas.drawLine(Offset(r - cs, b), Offset(r, b), cp);
    canvas.drawLine(Offset(r, b), Offset(r, b - cs), cp);
  }

  @override
  bool shouldRepaint(_DimOverlayPainter old) =>
      old.detected != detected || old.frameOffset != frameOffset;
}
