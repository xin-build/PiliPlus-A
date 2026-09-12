import 'dart:io' show Directory, File, Process;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;

abstract final class StorageUtils {
  static Future<void> saveBytes2File({
    required String name,
    required Uint8List bytes,
    required List<String> allowedExtensions,
    FileType type = FileType.custom,
  }) async {
    try {
      final path = await FilePicker.saveFile(
        allowedExtensions: allowedExtensions,
        type: type,
        fileName: name,
        bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
      );
      if (path == null) {
        SmartDialog.showToast("取消保存");
        return;
      }
      if (PlatformUtils.isDesktop) {
        await File(path.toFilePath()).writeAsBytes(bytes);
      }
      SmartDialog.showToast("已保存");
    } catch (e) {
      SmartDialog.showToast("保存失败: $e");
    }
  }

  static Future<void> exportVideo(BiliDownloadEntryInfo entry) async {
    final videoDir = p.join(entry.entryDirPath, entry.typeTag ?? '');
    final videoDirObj = Directory(videoDir);
    if (!videoDirObj.existsSync()) {
      SmartDialog.showToast('缓存目录不存在');
      return;
    }

    final videoM4s = File(p.join(videoDir, PathUtils.videoNameType2));
    final audioM4s = File(p.join(videoDir, PathUtils.audioNameType2));
    final videoMp4 = File(p.join(videoDir, PathUtils.videoNameType1));

    final sanitizedTitle =
        entry.showTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final defaultFileName = '$sanitizedTitle.mp4';

    try {
      final savePath = await FilePicker.saveFile(
        dialogTitle: '选择导出路径',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['mp4'],
        bytes: Uint8List(0),
      );

      if (savePath == null) {
        SmartDialog.showToast('已取消导出');
        return;
      }

      final outPath = savePath.toFilePath();
      SmartDialog.showLoading(msg: '正在导出视频...');

      if (videoMp4.existsSync()) {
        await videoMp4.copy(outPath);
      } else if (videoM4s.existsSync() && audioM4s.existsSync()) {
        bool merged = false;
        try {
          final result = await Process.run('ffmpeg', [
            '-y',
            '-i',
            videoM4s.path,
            '-i',
            audioM4s.path,
            '-c',
            'copy',
            outPath,
          ]);
          if (result.exitCode == 0 && File(outPath).existsSync()) {
            merged = true;
          }
        } catch (_) {}

        if (!merged) {
          await videoM4s.copy(outPath);
          final audioOutPath = outPath.replaceAll(
            RegExp(r'\.mp4$', caseSensitive: false),
            '_audio.m4s',
          );
          await audioM4s.copy(audioOutPath);
          SmartDialog.dismiss();
          SmartDialog.showToast('未检测到 ffmpeg，已分别导出视频轨与音频轨');
          return;
        }
      } else if (videoM4s.existsSync()) {
        await videoM4s.copy(outPath);
      } else {
        SmartDialog.dismiss();
        SmartDialog.showToast('未找到缓存媒体文件');
        return;
      }

      SmartDialog.dismiss();
      SmartDialog.showToast('导出成功');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导出失败: $e');
    }
  }
}
