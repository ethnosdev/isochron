import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:macos_ui/macos_ui.dart';

class ModelPanel extends StatefulWidget {
  final VoidCallback? onModelReady;

  const ModelPanel({super.key, this.onModelReady});

  static Future<void> show(BuildContext context, {VoidCallback? onModelReady}) {
    return showMacosSheet(
      context: context,
      barrierDismissible: true,
      builder: (_) => MacosSheet(
        child: SizedBox(
          width: 520,
          height: 420,
          child: ModelPanel(onModelReady: onModelReady),
        ),
      ),
    );
  }

  @override
  State<ModelPanel> createState() => _ModelPanelState();
}

class _ModelPanelState extends State<ModelPanel> {
  final ModelManager _manager = ModelManager();
  ModelVariant _selectedVariant = ModelVariant.int8;
  ModelStatus _status = ModelStatus.notDownloaded;
  bool _isLoading = true;
  double _downloadProgress = 0.0;
  String _downloadDetails = '';
  bool _isDownloading = false;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus({bool verifySha = false}) async {
    setState(() => _isLoading = true);
    final status = await _manager.checkStatus(_selectedVariant, verifySha: verifySha);
    if (!mounted) return;
    setState(() {
      _status = status;
      _isLoading = false;
    });
    if (status == ModelStatus.ready) {
      widget.onModelReady?.call();
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _cancelRequested = false;
      _downloadDetails = 'Starting download...';
    });

    try {
      await _manager.download(
        _selectedVariant,
        onProgress: (pct, rec, total) {
          if (!mounted) return;
          final mbRec = (rec / 1024 / 1024).toStringAsFixed(1);
          final mbTot = (total / 1024 / 1024).toStringAsFixed(1);
          setState(() {
            _downloadProgress = pct;
            _downloadDetails = '$mbRec / $mbTot MB (${(pct * 100).toStringAsFixed(0)}%)';
          });
        },
        isCancelled: () => _cancelRequested,
      );

      if (!mounted) return;
      await _checkStatus(verifySha: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadDetails = 'Download failed: $e';
      });
      await _checkStatus();
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _cancelDownload() {
    setState(() {
      _cancelRequested = true;
      _downloadDetails = 'Cancelling...';
    });
  }

  Future<void> _deleteModel() async {
    await _manager.delete(_selectedVariant);
    await _checkStatus();
  }

  void _revealInFinder() {
    final file = _manager.getFile(_selectedVariant);
    if (file.existsSync()) {
      Process.run('open', ['-R', file.path]);
    } else {
      Process.run('open', [_manager.modelsDir.path]);
    }
  }

  String get _statusLabel {
    if (_isDownloading) return 'Downloading...';
    switch (_status) {
      case ModelStatus.ready:
        return 'Ready';
      case ModelStatus.corrupt:
        return 'Corrupt (Checksum mismatch)';
      case ModelStatus.notDownloaded:
        return 'Not Downloaded';
      case ModelStatus.downloading:
        return 'Downloading...';
      case ModelStatus.verifying:
        return 'Verifying checksum...';
    }
  }

  Color get _statusColor {
    if (_isDownloading) return CupertinoColors.activeBlue;
    switch (_status) {
      case ModelStatus.ready:
        return CupertinoColors.systemGreen;
      case ModelStatus.corrupt:
        return CupertinoColors.systemRed;
      case ModelStatus.notDownloaded:
        return CupertinoColors.systemGrey;
      case ModelStatus.downloading:
      case ModelStatus.verifying:
        return CupertinoColors.activeBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _manager.getFile(_selectedVariant);
    final sizeMb = (_selectedVariant.sizeBytes / 1024 / 1024).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MMS Acoustic Model',
                style: MacosTheme.of(context).typography.headline,
              ),
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.xmark_circle),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Meta MMS-300M neural acoustic model required for multilingual forced alignment.',
            style: MacosTheme.of(context).typography.subheadline,
          ),
          const SizedBox(height: 20),

          // Variant Picker
          Row(
            children: [
              const Text('Model Variant:  ', style: TextStyle(fontWeight: FontWeight.w600)),
              MacosPopupButton<ModelVariant>(
                value: _selectedVariant,
                onChanged: _isDownloading
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() => _selectedVariant = val);
                          _checkStatus();
                        }
                      },
                items: const [
                  MacosPopupMenuItem(
                    value: ModelVariant.int8,
                    child: Text('Quantized INT8 (Recommended - 302 MB)'),
                  ),
                  MacosPopupMenuItem(
                    value: ModelVariant.fp16,
                    child: Text('FP16 (605 MB)'),
                  ),
                  MacosPopupMenuItem(
                    value: ModelVariant.fp32,
                    child: Text('FP32 Full Precision (1.2 GB)'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Status Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MacosColors.controlBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MacosColors.separatorColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    if (_isLoading)
                      const ProgressCircle(radius: 8)
                    else
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          color: _statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'File: ${_selectedVariant.filename} (~$sizeMb MB)',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Path: ${file.path}',
                  style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Download Progress Bar
          if (_isDownloading) ...[
            ProgressBar(value: _downloadProgress * 100),
            const SizedBox(height: 6),
            Text(
              _downloadDetails,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],

          const Spacer(),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: _revealInFinder,
                child: const Text('Reveal in Finder'),
              ),
              const SizedBox(width: 8),
              if (_status == ModelStatus.ready && !_isDownloading)
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _deleteModel,
                  child: const Text('Delete Model'),
                ),
              if (_isDownloading)
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _cancelDownload,
                  child: const Text('Cancel'),
                ),
              if (_status != ModelStatus.ready && !_isDownloading)
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: _startDownload,
                  child: const Text('Download Model'),
                ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
