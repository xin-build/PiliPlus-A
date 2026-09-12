import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Information about a detected GPU compute device
class GpuDeviceInfo {
  final String name;
  final String vendor;
  final String driverVersion;
  final int maxComputeUnits;
  final int globalMemSizeInBytes;
  final bool isGpu;

  const GpuDeviceInfo({
    required this.name,
    required this.vendor,
    required this.driverVersion,
    required this.maxComputeUnits,
    required this.globalMemSizeInBytes,
    required this.isGpu,
  });

  double get globalMemSizeInMB => globalMemSizeInBytes / (1024 * 1024);

  @override
  String toString() =>
      'GpuDeviceInfo($name, vendor: $vendor, computeUnits: $maxComputeUnits, vram: ${globalMemSizeInMB.toStringAsFixed(1)}MB)';
}

/// OpenCL FFI typedefs
typedef _clGetPlatformIDsNative = Int32 Function(
  Uint32 numEntries,
  Pointer<Pointer<Void>> platforms,
  Pointer<Uint32> numPlatforms,
);
typedef _clGetPlatformIDsDart = int Function(
  int numEntries,
  Pointer<Pointer<Void>> platforms,
  Pointer<Uint32> numPlatforms,
);

typedef _clGetDeviceIDsNative = Int32 Function(
  Pointer<Void> platform,
  Uint64 deviceType,
  Uint32 numEntries,
  Pointer<Pointer<Void>> devices,
  Pointer<Uint32> numDevices,
);
typedef _clGetDeviceIDsDart = int Function(
  Pointer<Void> platform,
  int deviceType,
  int numEntries,
  Pointer<Pointer<Void>> devices,
  Pointer<Uint32> numDevices,
);

typedef _clGetDeviceInfoNative = Int32 Function(
  Pointer<Void> device,
  Uint32 paramName,
  IntPtr paramValueSize,
  Pointer<Void> paramValue,
  Pointer<IntPtr> paramValueSizeRet,
);
typedef _clGetDeviceInfoDart = int Function(
  Pointer<Void> device,
  int paramName,
  int paramValueSize,
  Pointer<Void> paramValue,
  Pointer<IntPtr> paramValueSizeRet,
);

/// Native GPU Compute service via FFI (OpenCL / WebGPU / Native GPU Compute)
class NativeGpuCompute {
  static const int _CL_DEVICE_TYPE_GPU = 1 << 2;
  static const int _CL_DEVICE_TYPE_ALL = 0xFFFFFFFF;
  static const int _CL_DEVICE_NAME = 0x102B;
  static const int _CL_DEVICE_VENDOR = 0x102C;
  static const int _CL_DRIVER_VERSION = 0x102D;
  static const int _CL_DEVICE_MAX_COMPUTE_UNITS = 0x1002;
  static const int _CL_DEVICE_GLOBAL_MEM_SIZE = 0x101F;
  static const int _CL_SUCCESS = 0;

  static DynamicLibrary? _openClLib;
  static bool _initialized = false;
  static final List<GpuDeviceInfo> _detectedDevices = [];

  /// Check if Native GPU compute (OpenCL) is supported on this system
  static bool get isSupported {
    _ensureInitialized();
    return _detectedDevices.isNotEmpty;
  }

  /// Get list of all detected GPU devices
  static List<GpuDeviceInfo> get detectedDevices {
    _ensureInitialized();
    return List.unmodifiable(_detectedDevices);
  }

  /// Primary GPU device (or first available)
  static GpuDeviceInfo? get primaryGpu {
    _ensureInitialized();
    if (_detectedDevices.isEmpty) return null;
    return _detectedDevices.firstWhere(
      (d) => d.isGpu,
      orElse: () => _detectedDevices.first,
    );
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    try {
      _loadLibrary();
      if (_openClLib != null) {
        _queryDevices();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NativeGpuCompute: OpenCL init failed: $e');
      }
    }
  }

  static void _loadLibrary() {
    try {
      if (Platform.isWindows) {
        _openClLib = DynamicLibrary.open('OpenCL.dll');
      } else if (Platform.isLinux) {
        try {
          _openClLib = DynamicLibrary.open('libOpenCL.so.1');
        } catch (_) {
          _openClLib = DynamicLibrary.open('libOpenCL.so');
        }
      } else if (Platform.isMacOS) {
        _openClLib = DynamicLibrary.open(
          '/System/Library/Frameworks/OpenCL.framework/OpenCL',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NativeGpuCompute: Could not load OpenCL dynamic library: $e');
      }
    }
  }

  static void _queryDevices() {
    final lib = _openClLib;
    if (lib == null) return;

    try {
      final clGetPlatformIDs = lib.lookupFunction<_clGetPlatformIDsNative, _clGetPlatformIDsDart>(
        'clGetPlatformIDs',
      );
      final clGetDeviceIDs = lib.lookupFunction<_clGetDeviceIDsNative, _clGetDeviceIDsDart>(
        'clGetDeviceIDs',
      );
      final clGetDeviceInfo = lib.lookupFunction<_clGetDeviceInfoNative, _clGetDeviceInfoDart>(
        'clGetDeviceInfo',
      );

      using((arena) {
        final numPlatformsPtr = arena<Uint32>();
        var err = clGetPlatformIDs(0, nullptr, numPlatformsPtr);
        if (err != _CL_SUCCESS || numPlatformsPtr.value == 0) return;

        final numPlatforms = numPlatformsPtr.value;
        final platformsPtr = arena<Pointer<Void>>(numPlatforms);
        err = clGetPlatformIDs(numPlatforms, platformsPtr, nullptr);
        if (err != _CL_SUCCESS) return;

        for (int p = 0; p < numPlatforms; p++) {
          final platform = platformsPtr[p];
          final numDevicesPtr = arena<Uint32>();

          err = clGetDeviceIDs(platform, _CL_DEVICE_TYPE_ALL, 0, nullptr, numDevicesPtr);
          if (err != _CL_SUCCESS || numDevicesPtr.value == 0) continue;

          final numDevices = numDevicesPtr.value;
          final devicesPtr = arena<Pointer<Void>>(numDevices);
          err = clGetDeviceIDs(platform, _CL_DEVICE_TYPE_ALL, numDevices, devicesPtr, nullptr);
          if (err != _CL_SUCCESS) continue;

          for (int d = 0; d < numDevices; d++) {
            final device = devicesPtr[d];

            final name = _getStringInfo(clGetDeviceInfo, device, _CL_DEVICE_NAME, arena);
            final vendor = _getStringInfo(clGetDeviceInfo, device, _CL_DEVICE_VENDOR, arena);
            final driver = _getStringInfo(clGetDeviceInfo, device, _CL_DRIVER_VERSION, arena);

            final computeUnitsPtr = arena<Uint32>();
            clGetDeviceInfo(device, _CL_DEVICE_MAX_COMPUTE_UNITS, sizeOf<Uint32>(), computeUnitsPtr.cast(), nullptr);

            final memSizePtr = arena<Uint64>();
            clGetDeviceInfo(device, _CL_DEVICE_GLOBAL_MEM_SIZE, sizeOf<Uint64>(), memSizePtr.cast(), nullptr);

            final devTypePtr = arena<Uint64>();
            clGetDeviceInfo(device, 0x1000 /* CL_DEVICE_TYPE */, sizeOf<Uint64>(), devTypePtr.cast(), nullptr);

            final isGpu = (devTypePtr.value & _CL_DEVICE_TYPE_GPU) != 0;

            _detectedDevices.add(
              GpuDeviceInfo(
                name: name,
                vendor: vendor,
                driverVersion: driver,
                maxComputeUnits: computeUnitsPtr.value,
                globalMemSizeInBytes: memSizePtr.value,
                isGpu: isGpu,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NativeGpuCompute: queryDevices error: $e');
      }
    }
  }

  static String _getStringInfo(
    _clGetDeviceInfoDart clGetDeviceInfo,
    Pointer<Void> device,
    int param,
    Arena arena,
  ) {
    final sizeRet = arena<IntPtr>();
    var err = clGetDeviceInfo(device, param, 0, nullptr, sizeRet);
    if (err != _CL_SUCCESS || sizeRet.value <= 0) return 'Unknown';

    final buf = arena<Uint8>(sizeRet.value);
    err = clGetDeviceInfo(device, param, sizeRet.value, buf.cast(), nullptr);
    if (err != _CL_SUCCESS) return 'Unknown';

    final bytes = buf.asTypedList(sizeRet.value);
    final zeroIdx = bytes.indexOf(0);
    final len = zeroIdx >= 0 ? zeroIdx : bytes.length;
    return String.fromCharCodes(bytes.sublist(0, len)).trim();
  }
}
