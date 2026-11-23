import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera scanner and returns the scanned code, or null if the user
/// backed out. The scanner page itself also offers "Enter manually", so a
/// denied camera permission or a damaged label never blocks the user.
Future<String?> scanBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeScanPage()),
    );

class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});
  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
      BarcodeFormat.itf,
      BarcodeFormat.dataMatrix,
    ],
  );
  bool _handled = false; // ignore further detections once one is accepted
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _handled = true;
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  Future<void> _manual() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Barcode'),
          onSubmitted: (s) => Navigator.pop(context, s.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Use')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && mounted) {
      _handled = true;
      Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.no_photography, color: Colors.white70, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'The camera is not available. Allow camera access in system settings, '
                  'or enter the barcode manually.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: _manual, icon: const Icon(Icons.keyboard), label: const Text('Enter manually')),
              ]),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: MediaQuery.sizeOf(context).width * 0.75,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Column(children: [
            const Text('Point the camera at the barcode', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
              onPressed: _manual,
              icon: const Icon(Icons.keyboard),
              label: const Text('Enter manually'),
            ),
          ]),
        ),
      ]),
    );
  }
}
