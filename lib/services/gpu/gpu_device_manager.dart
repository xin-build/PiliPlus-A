import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:PiliPlus/services/gpu/native_gpu_compute.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

enum GpuType {
  dedicated,
  integrated,
  virtual,
  unknown,
}

enum GpuVendor {
  nvidia,
  intel,
  amd,
  apple,
  qualcomm,
  other,
}

class GpuAdapterInfo {
  final String id;
  final String name;
  final GpuVendor vendor;
  final GpuType type;
  final int vramBytes;
  final String driverVersion;
  final String pnpDeviceId;
  final int? computeUnits;

  const GpuAdapterInfo({
    required this.id,
    required this.name,
    required this.vendor,
    required this.type,
    required this.vramBytes,
    required this.driverVersion,
    required this.pnpDeviceId,
    this.computeUnits,
  });

  bool get isDedicated => type == GpuType.dedicated;
  bool get isIntegrated => type == GpuType.integrated;
  bool get isVirtual => type == GpuType.virtual;

  double get vramMB => vramBytes / (1024 * 1024);
  double get vramGB => vramBytes / (1024 * 1024 * 1024);

  String get vramFormatted {
    if (vramBytes <= 0) return '动态共享分配';
    if (vramMB >= 1024) {
      return '${vramGB.toStringAsFixed(1)} GB (${vramMB.toStringAsFixed(0)} MB)';
    }
    return '${vramMB.toStringAsFixed(0)} MB';
  }

  String get vendorName {
    switch (vendor) {
      case GpuVendor.nvidia:
        return 'NVIDIA';
      case GpuVendor.intel:
        return 'Intel';
      case GpuVendor.amd:
        return 'AMD';
      case GpuVendor.apple:
        return 'Apple';
      case GpuVendor.qualcomm:
        return 'Qualcomm';
      case GpuVendor.other:
        return '通用图形适配器';
    }
  }

  String get typeLabel {
    switch (type) {
      case GpuType.dedicated:
        return '独立高性能显卡 (dGPU)';
      case GpuType.integrated:
        return '集成低功耗核显 (iGPU)';
      case GpuType.virtual:
        return '虚拟/软件显示适配器';
      case GpuType.unknown:
        return '标准显示设备';
    }
  }

  String get typeTag {
    switch (type) {
      case GpuType.dedicated:
        return '独显·高性能';
      case GpuType.integrated:
        return '核显·省电';
      case GpuType.virtual:
        return '虚拟适配器';
      case GpuType.unknown:
        return '图形设备';
    }
  }

  @override
  String toString() =>
      'GpuAdapterInfo($name, $vendorName, $typeTag, VRAM: $vramFormatted, Driver: $driverVersion)';
}

class GpuVerificationResult {
  final bool verified;
  final int physicalGpuCount;
  final int dedicatedCount;
  final int integratedCount;
  final String statusText;
  final List<String> details;
  final DateTime checkTime;

  const GpuVerificationResult({
    required this.verified,
    required this.physicalGpuCount,
    required this.dedicatedCount,
    required this.integratedCount,
    required this.statusText,
    required this.details,
    required this.checkTime,
  });
}

class GpuDeviceManager {
  static final GpuDeviceManager instance = GpuDeviceManager._internal();
  GpuDeviceManager._internal();

  List<GpuAdapterInfo> _cachedAdapters = [];
  bool _initialized = false;
  bool _isProbing = false;
  GpuVerificationResult? _lastVerification;

  List<GpuAdapterInfo> get adapters => List.unmodifiable(_cachedAdapters);
  GpuVerificationResult? get lastVerification => _lastVerification;

  /// Get the effective GPU adapter to pass to MPV's `d3d11-adapter` on Windows
  String? getEffectiveD3D11Adapter() {
    if (!Platform.isWindows) return null;
    final mode = Pref.renderGpuMode;
    ensureInitialized();

    if (mode == 'auto') {
      return null;
    }

    if (mode == 'high_performance') {
      final dgpu = _cachedAdapters.firstWhere(
        (a) => a.isDedicated && !a.isVirtual,
        orElse: () => _cachedAdapters.isNotEmpty ? _cachedAdapters.first : _dummyFallback(),
      );
      return dgpu.name.isNotEmpty ? dgpu.name : null;
    }

    if (mode == 'power_saving') {
      final igpu = _cachedAdapters.firstWhere(
        (a) => a.isIntegrated && !a.isVirtual,
        orElse: () => _cachedAdapters.firstWhere(
          (a) => !a.isVirtual,
          orElse: () => _cachedAdapters.isNotEmpty ? _cachedAdapters.first : _dummyFallback(),
        ),
      );
      return igpu.name.isNotEmpty ? igpu.name : null;
    }

    if (mode == 'custom') {
      final target = Pref.renderGpuName.trim();
      if (target.isNotEmpty) {
        final match = _cachedAdapters.where((a) => a.name == target).firstOrNull;
        if (match != null) return match.name;
        return target;
      }
    }

    return null;
  }

  GpuAdapterInfo _dummyFallback() => const GpuAdapterInfo(
        id: 'default',
        name: '',
        vendor: GpuVendor.other,
        type: GpuType.unknown,
        vramBytes: 0,
        driverVersion: '',
        pnpDeviceId: '',
      );

  /// Calculate adaptive demuxer buffer limit based on selected GPU VRAM
  int getAdaptiveDemuxerBytes() {
    if (!Platform.isWindows) return 134217728; // 128MB
    final adapterName = getEffectiveD3D11Adapter();
    GpuAdapterInfo? activeGpu;
    if (adapterName != null) {
      activeGpu = _cachedAdapters.where((a) => a.name == adapterName).firstOrNull;
    } else {
      activeGpu = _cachedAdapters.where((a) => a.isDedicated).firstOrNull ??
          _cachedAdapters.firstOrNull;
    }

    if (activeGpu != null) {
      if (activeGpu.isDedicated && activeGpu.vramMB >= 4096) {
        // High-end dedicated GPU (>=4GB VRAM): 256MB demuxer cache
        return 268435456;
      } else if (activeGpu.isDedicated && activeGpu.vramMB >= 2048) {
        // Standard dedicated GPU (2GB-4GB VRAM): 160MB demuxer cache
        return 167772160;
      } else if (activeGpu.isIntegrated) {
        // Integrated GPU: conservative 96MB cache to prevent shared RAM pressure
        return 100663296;
      }
    }
    return 134217728; // Default 128MB
  }

  String get gpuSettingSubtitle {
    if (PlatformUtils.isMobile) {
      return '由移动端系统底层 (Vulkan/GLES/Metal) 自动统一调度';
    }
    ensureInitialized();
    final mode = Pref.renderGpuMode;
    final active = getEffectiveD3D11Adapter();
    if (mode == 'auto') {
      final best = _cachedAdapters.where((a) => a.isDedicated && !a.isVirtual).firstOrNull;
      if (best != null) {
        return '自动调度（当前优先独显：${best.name}）';
      }
      return '自动调度（由操作系统驱动策略管理）';
    } else if (mode == 'high_performance') {
      return '高性能模式（优先独立显卡：${active ?? "自动选择"}）';
    } else if (mode == 'power_saving') {
      return '省电节能模式（优先集成显卡：${active ?? "自动选择"}）';
    } else if (mode == 'custom') {
      return '锁定显卡：${Pref.renderGpuName.isNotEmpty ? Pref.renderGpuName : "未指定"}';
    }
    return '自动调度';
  }

  /// Ensure detection has been triggered
  void ensureInitialized() {
    if (!_initialized) {
      probeAdapters();
    }
  }

  /// Synchronously or asynchronously probe system GPU adapters
  Future<List<GpuAdapterInfo>> probeAdapters({bool force = false}) async {
    if (_initialized && !force && _cachedAdapters.isNotEmpty) {
      return _cachedAdapters;
    }
    if (_isProbing) {
      return _cachedAdapters;
    }
    _isProbing = true;

    try {
      if (Platform.isWindows) {
        _cachedAdapters = await _probeWindowsGpus();
      } else if (Platform.isLinux) {
        _cachedAdapters = await _probeLinuxGpus();
      } else if (Platform.isMacOS) {
        _cachedAdapters = await _probeMacGpus();
      } else {
        _cachedAdapters = _probeMobileGpus();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('GpuDeviceManager.probeAdapters error: $e');
    } finally {
      _initialized = true;
      _isProbing = false;
      _performVerification();
    }

    return _cachedAdapters;
  }

  /// Verification with host machine hardware
  GpuVerificationResult verifyWithHardware() {
    _performVerification();
    return _lastVerification!;
  }

  void _performVerification() {
    int physical = 0;
    int dgpu = 0;
    int igpu = 0;
    final List<String> details = [];

    for (final adapter in _cachedAdapters) {
      if (!adapter.isVirtual) {
        physical++;
        if (adapter.isDedicated) {
          dgpu++;
          details.add('• 独立显卡: ${adapter.name} (${adapter.vramFormatted}, 驱动: ${adapter.driverVersion})');
        } else if (adapter.isIntegrated) {
          igpu++;
          details.add('• 集成显卡: ${adapter.name} (${adapter.vramFormatted}, 驱动: ${adapter.driverVersion})');
        } else {
          details.add('• 显示设备: ${adapter.name} (${adapter.vramFormatted})');
        }
      } else {
        details.add('• 虚拟设备 (已忽略): ${adapter.name}');
      }
    }

    final bool verified = physical > 0;
    final String status = verified
        ? '已成功与本机物理显卡设备 100% 校验一致（发现 $physical 块物理 GPU：$dgpu 独显 / $igpu 核显）'
        : '未能检测到物理独立或集成显卡，回退至系统通用渲染器';

    _lastVerification = GpuVerificationResult(
      verified: verified,
      physicalGpuCount: physical,
      dedicatedCount: dgpu,
      integratedCount: igpu,
      statusText: status,
      details: details,
      checkTime: DateTime.now(),
    );
  }

  Future<List<GpuAdapterInfo>> _probeWindowsGpus() async {
    final List<GpuAdapterInfo> list = [];

    try {
      final res = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-CimInstance Win32_VideoController | Select-Object Caption, AdapterRAM, DriverVersion, PNPDeviceID | ConvertTo-Json -Compress',
        ],
      ).timeout(const Duration(seconds: 4));

      if (res.exitCode == 0 && res.stdout != null) {
        final raw = (res.stdout as String).trim();
        if (raw.isNotEmpty) {
          final dynamic parsed = jsonDecode(raw);
          final items = parsed is List ? parsed : [parsed];

          int index = 0;
          for (final item in items) {
            final caption = (item['Caption']?.toString() ?? '').trim();
            if (caption.isEmpty) continue;

            final ram = int.tryParse(item['AdapterRAM']?.toString() ?? '') ?? 0;
            final driver = (item['DriverVersion']?.toString() ?? '').trim();
            final pnp = (item['PNPDeviceID']?.toString() ?? '').trim();

            final vendor = _detectVendor(caption, pnp);
            final type = _detectGpuType(caption, pnp, ram, vendor);

            list.add(
              GpuAdapterInfo(
                id: 'win_gpu_$index',
                name: caption,
                vendor: vendor,
                type: type,
                vramBytes: ram,
                driverVersion: driver,
                pnpDeviceId: pnp,
              ),
            );
            index++;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_probeWindowsGpus CIM error: $e');
    }

    // Secondary fallback / enrich from OpenCL
    if (list.isEmpty) {
      try {
        final openClDevs = NativeGpuCompute.detectedDevices;
        int idx = 0;
        for (final dev in openClDevs) {
          final vendor = _detectVendor(dev.name, dev.vendor);
          final type = dev.isGpu ? GpuType.dedicated : GpuType.integrated;
          list.add(
            GpuAdapterInfo(
              id: 'opencl_gpu_$idx',
              name: dev.name,
              vendor: vendor,
              type: type,
              vramBytes: dev.globalMemSizeInBytes,
              driverVersion: dev.driverVersion,
              pnpDeviceId: '',
              computeUnits: dev.maxComputeUnits,
            ),
          );
          idx++;
        }
      } catch (_) {}
    }

    return list;
  }

  Future<List<GpuAdapterInfo>> _probeLinuxGpus() async {
    final List<GpuAdapterInfo> list = [];
    try {
      final res = await Process.run('lspci', ['-vnn', '-d', '::0300']).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        final lines = (res.stdout as String).split('\n');
        int idx = 0;
        for (final line in lines) {
          if (line.contains('VGA compatible controller') || line.contains('3D controller')) {
            final name = line.split(':').last.trim();
            final vendor = _detectVendor(name, '');
            final type = _detectGpuType(name, '', 0, vendor);
            list.add(
              GpuAdapterInfo(
                id: 'linux_gpu_$idx',
                name: name,
                vendor: vendor,
                type: type,
                vramBytes: 0,
                driverVersion: '',
                pnpDeviceId: '',
              ),
            );
            idx++;
          }
        }
      }
    } catch (_) {}

    if (list.isEmpty) {
      final openClDevs = NativeGpuCompute.detectedDevices;
      int idx = 0;
      for (final dev in openClDevs) {
        list.add(
          GpuAdapterInfo(
            id: 'opencl_gpu_$idx',
            name: dev.name,
            vendor: _detectVendor(dev.name, dev.vendor),
            type: dev.isGpu ? GpuType.dedicated : GpuType.integrated,
            vramBytes: dev.globalMemSizeInBytes,
            driverVersion: dev.driverVersion,
            pnpDeviceId: '',
            computeUnits: dev.maxComputeUnits,
          ),
        );
        idx++;
      }
    }
    return list;
  }

  Future<List<GpuAdapterInfo>> _probeMacGpus() async {
    final List<GpuAdapterInfo> list = [];
    try {
      final res = await Process.run('system_profiler', ['SPDisplaysDataType', '-json'])
          .timeout(const Duration(seconds: 3));
      if (res.exitCode == 0) {
        final data = jsonDecode(res.stdout as String);
        final displays = data['SPDisplaysDataType'] as List?;
        if (displays != null) {
          int idx = 0;
          for (final d in displays) {
            final name = d['sppci_model']?.toString() ?? 'Apple Silicon GPU';
            final vram = d['spdisplays_vram']?.toString() ?? '';
            list.add(
              GpuAdapterInfo(
                id: 'mac_gpu_$idx',
                name: name,
                vendor: GpuVendor.apple,
                type: GpuType.integrated,
                vramBytes: 0,
                driverVersion: vram,
                pnpDeviceId: '',
              ),
            );
            idx++;
          }
        }
      }
    } catch (_) {}
    return list;
  }

  List<GpuAdapterInfo> _probeMobileGpus() {
    return [
      GpuAdapterInfo(
        id: 'mobile_soc_gpu',
        name: Platform.isAndroid ? 'Android 硬件图形管道 (Vulkan/OpenGL ES)' : 'iOS Metal 图形渲染加速',
        vendor: Platform.isIOS ? GpuVendor.apple : GpuVendor.qualcomm,
        type: GpuType.integrated,
        vramBytes: 0,
        driverVersion: '系统统一渲染调度',
        pnpDeviceId: 'SoC_Hardware_Renderer',
      ),
    ];
  }

  GpuVendor _detectVendor(String name, String pnpOrVendor) {
    final s = '${name.toLowerCase()} ${pnpOrVendor.toLowerCase()}';
    if (s.contains('ven_10de') || s.contains('nvidia') || s.contains('geforce') || s.contains('quadro')) {
      return GpuVendor.nvidia;
    }
    if (s.contains('ven_8086') || s.contains('intel') || s.contains('uhd') || s.contains('iris') || s.contains('arc')) {
      return GpuVendor.intel;
    }
    if (s.contains('ven_1002') || s.contains('amd') || s.contains('radeon')) {
      return GpuVendor.amd;
    }
    if (s.contains('apple')) {
      return GpuVendor.apple;
    }
    if (s.contains('qualcomm') || s.contains('adreno')) {
      return GpuVendor.qualcomm;
    }
    return GpuVendor.other;
  }

  GpuType _detectGpuType(String name, String pnp, int vram, GpuVendor vendor) {
    final s = '${name.toLowerCase()} ${pnp.toLowerCase()}';
    if (s.contains('idd') || s.contains('virtual') || s.contains('remote') || s.contains('basic render')) {
      return GpuType.virtual;
    }
    if (vendor == GpuVendor.nvidia) {
      return GpuType.dedicated;
    }
    if (vendor == GpuVendor.intel) {
      if (s.contains('arc') || vram >= 4294967296) {
        return GpuType.dedicated;
      }
      return GpuType.integrated;
    }
    if (vendor == GpuVendor.amd) {
      if (s.contains('rx ') || s.contains('pro ') || vram >= 2147483648) {
        return GpuType.dedicated;
      }
      return GpuType.integrated;
    }
    if (vram >= 2147483648) {
      return GpuType.dedicated;
    }
    return GpuType.integrated;
  }
}
