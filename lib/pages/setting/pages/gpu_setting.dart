import 'dart:io';
import 'package:flutter/material.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/services/gpu/gpu_device_manager.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class GpuSettingPage extends StatefulWidget {
  const GpuSettingPage({super.key});

  @override
  State<GpuSettingPage> createState() => _GpuSettingPageState();
}

class _GpuSettingPageState extends State<GpuSettingPage> {
  final GpuDeviceManager _manager = GpuDeviceManager.instance;
  bool _isLoading = false;
  late String _currentMode;
  late String _selectedGpuName;
  late bool _d3d11FlipModel;
  late bool _adaptiveGpuVram;

  @override
  void initState() {
    super.initState();
    _currentMode = Pref.renderGpuMode;
    _selectedGpuName = Pref.renderGpuName;
    _d3d11FlipModel = Pref.d3d11FlipModel;
    _adaptiveGpuVram = Pref.adaptiveGpuVram;
    _loadGpus(force: false);
  }

  Future<void> _loadGpus({bool force = false}) async {
    setState(() => _isLoading = true);
    await _manager.probeAdapters(force: force);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMode(String mode) async {
    setState(() {
      _currentMode = mode;
    });
    await GStorage.setting.put(SettingBoxKey.renderGpuMode, mode);
  }

  Future<void> _selectGpu(GpuAdapterInfo adapter) async {
    setState(() {
      _currentMode = 'custom';
      _selectedGpuName = adapter.name;
    });
    await GStorage.setting.put(SettingBoxKey.renderGpuMode, 'custom');
    await GStorage.setting.put(SettingBoxKey.renderGpuName, adapter.name);
    SmartDialog.showToast('已锁定渲染显卡：${adapter.name}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = PlatformUtils.isDesktop;
    final isWindows = Platform.isWindows;

    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('渲染 GPU 与硬件性能配置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新探测与硬件校验',
            onPressed: () => _loadGpus(force: true),
          ),
        ],
      ),
      body: _isLoading && _manager.adapters.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (!isDesktop) ...[
                  _buildMobilePlatformCard(theme, colorScheme),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildModeSelector(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildGpuList(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildVerificationCard(theme, colorScheme),
                  const SizedBox(height: 16),
                  if (isWindows) ...[
                    _buildPerformanceOptimizationCard(theme, colorScheme),
                    const SizedBox(height: 16),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _buildMobilePlatformCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '移动端统一硬件调度已启用',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '当前运行在 ${Platform.operatingSystem} 平台。移动端由芯片底层的硬件图形子系统 (Vulkan / OpenGL ES / Metal) 配合 MediaCodec / VideoToolbox 自动完成零拷贝硬件解码与画面呈现，已全局处于最佳低功耗与高性能状态，无需手动指定物理显卡。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(ThemeData theme, ColorScheme colorScheme) {
    final modes = [
      {'key': 'auto', 'label': '自动调度', 'desc': '由操作系统与显卡驱动策略调度'},
      {'key': 'high_performance', 'label': '独显高性能', 'desc': '优先使用独立显卡 (NVIDIA/AMD dGPU)'},
      {'key': 'power_saving', 'label': '核显节能', 'desc': '优先使用集成显卡 (延长续航/低发热)'},
      {'key': 'custom', 'label': '手动指定', 'desc': '锁定指定显卡'},
    ];

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'GPU 渲染调度策略',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: modes.map((m) {
                final isSelected = _currentMode == m['key'];
                return ChoiceChip(
                  label: Text(m['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _changeMode(m['key']!);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Text(
              _getModeDescription(_currentMode),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeDescription(String mode) {
    switch (mode) {
      case 'auto':
        return '自动模式：由系统默认策略自动分配显卡渲染。适用于台式单显卡或标准环境。';
      case 'high_performance':
        return '高性能模式：强制绑定独立显卡，发挥最大算力与高码率硬解性能，推荐插电或台式游戏场景。';
      case 'power_saving':
        return '省电节能模式：强制绑定集成核显，显著降低整机功耗、温度与风扇噪音，推荐笔记本电池模式。';
      case 'custom':
        return '手动指定模式：在下方列表中点击任意显卡卡片直接锁定该显卡。';
      default:
        return '';
    }
  }

  Widget _buildGpuList(ThemeData theme, ColorScheme colorScheme) {
    final adapters = _manager.adapters;
    final effectiveD3d11 = _manager.getEffectiveD3D11Adapter();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已拥有的 GPU 适配器 (${adapters.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (effectiveD3d11 != null)
              Text(
                '当前生效: $effectiveD3d11',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (adapters.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂未探测到物理显卡，请点击右上角刷新重试。',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          )
        else
          ...adapters.map((adapter) {
            final isCurrentTarget = (_currentMode == 'custom' && _selectedGpuName == adapter.name) ||
                (_currentMode != 'custom' && effectiveD3d11 == adapter.name);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _selectGpu(adapter),
                borderRadius: BorderRadius.circular(16),
                child: Card(
                  elevation: isCurrentTarget ? 2 : 0,
                  color: isCurrentTarget
                      ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isCurrentTarget
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: isCurrentTarget ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildVendorIcon(adapter.vendor, colorScheme),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                adapter.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildTypeBadge(adapter, colorScheme),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '显存: ${adapter.vramFormatted}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (adapter.driverVersion.isNotEmpty)
                              Text(
                                '驱动: ${adapter.driverVersion}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                        if (adapter.pnpDeviceId.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '硬件 ID: ${adapter.pnpDeviceId}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isCurrentTarget)
                              Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    '当前渲染活跃设备',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                '点击切换为此显卡渲染',
                                style: TextStyle(
                                  color: colorScheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildVendorIcon(GpuVendor vendor, ColorScheme colorScheme) {
    IconData icon;
    Color color;
    switch (vendor) {
      case GpuVendor.nvidia:
        icon = Icons.speed;
        color = const Color(0xFF76B900); // NVIDIA Green
      case GpuVendor.intel:
        icon = Icons.memory;
        color = const Color(0xFF0071C5); // Intel Blue
      case GpuVendor.amd:
        icon = Icons.developer_board;
        color = const Color(0xFFED1C24); // AMD Red
      case GpuVendor.apple:
        icon = Icons.apple;
        color = Colors.grey;
      case GpuVendor.qualcomm:
      case GpuVendor.other:
        icon = Icons.memory;
        color = colorScheme.primary;
    }
    return Icon(icon, color: color, size: 22);
  }

  Widget _buildTypeBadge(GpuAdapterInfo adapter, ColorScheme colorScheme) {
    Color bg;
    Color fg;
    if (adapter.isDedicated) {
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.deepOrange;
    } else if (adapter.isIntegrated) {
      bg = Colors.blue.withValues(alpha: 0.15);
      fg = Colors.blue;
    } else {
      bg = Colors.grey.withValues(alpha: 0.15);
      fg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        adapter.typeTag,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerificationCard(ThemeData theme, ColorScheme colorScheme) {
    final verification = _manager.verifyWithHardware();

    return Card(
      elevation: 0,
      color: verification.verified
          ? Colors.green.withValues(alpha: 0.08)
          : Colors.amber.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: verification.verified
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  verification.verified ? Icons.verified : Icons.warning_amber,
                  color: verification.verified ? Colors.green : Colors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本机实际硬件对比校验结果',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: verification.verified ? Colors.green.shade800 : Colors.amber.shade900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _loadGpus(force: true),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('重新比对'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              verification.statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '校验基准：Windows Kernel PnP 设备树 + DXGI/Direct3D 11 图形子系统 (与设备管理器、dxdiag 100% 对齐)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontSize: 11,
              ),
            ),
            if (verification.details.isNotEmpty) ...[
              const Divider(height: 16),
              ...verification.details.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    d,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceOptimizationCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'PC 深度渲染与性能调优',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Direct3D 11 Flip 翻转呈现模型'),
              subtitle: const Text(
                '利用 DXGI 现代翻转交换链直接向桌面管理器递交画面，降低 1 帧渲染延迟，根治窗口化与双显卡切换时的微掉帧（推荐开启）。',
                style: TextStyle(fontSize: 12),
              ),
              value: _d3d11FlipModel,
              onChanged: (val) async {
                setState(() => _d3d11FlipModel = val);
                await GStorage.setting.put(SettingBoxKey.d3d11FlipModel, val);
              },
            ),
            const Divider(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('显存预算自适应 (Adaptive VRAM)'),
              subtitle: const Text(
                '独显大显存环境自动分配 256MB+ 高速前向解复用缓存与 CAS 锐化；核显/低显存环境自动收敛内存占用（96MB~128MB），防止爆显存与 TDR 崩溃。',
                style: TextStyle(fontSize: 12),
              ),
              value: _adaptiveGpuVram,
              onChanged: (val) async {
                setState(() => _adaptiveGpuVram = val);
                await GStorage.setting.put(SettingBoxKey.adaptiveGpuVram, val);
              },
            ),
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '同卡零拷贝硬解协同：当选择特定 GPU 时，MPV D3D11VA 解码器与渲染器自动强制绑定到同一物理设备，彻底消除跨 PCIe 总线内存搬运延迟。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
