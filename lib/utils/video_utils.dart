import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class VideoUtils {
  static CDNService cdnService = Pref.defaultCDNService;
  static String? liveCdnUrl = Pref.liveCdnUrl;
  static bool disableAudioCDN = Pref.disableAudioCDN;

  static const _proxyTf = 'proxy-tf-all-ws.bilivideo.com';

  static final _mirrorRegex = RegExp(
    r'^https?://(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)/upgcxcode',
  );

  static final _mCdnTfRegex = RegExp(
    r'^https?://(?:(?:(?:\d{1,3}\.){3}\d{1,3}|[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))(?:\:\d{1,5})?/v\d/resource)',
  );

  static String getCdnUrl(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    if (urls.isEmpty) return '';

    defaultCDNService ??= cdnService;

    if (defaultCDNService == CDNService.baseUrl) {
      return urls.first;
    }

    String? uposUrl;
    String? mcdnUpgcxcode;
    String? mcdnTf;

    String last = '';
    for (final url in urls) {
      last = url;
      if (_mirrorRegex.hasMatch(url) ||
          url.contains('.bilivideo.com/upgcxcode/') ||
          url.contains('.akamaized.net/upgcxcode/')) {
        final uri = Uri.parse(url);
        if (uri.queryParameters['os'] == 'mcdn') {
          mcdnUpgcxcode = url;
        } else {
          uposUrl = url;
          break;
        }
      } else if (_mCdnTfRegex.hasMatch(url)) {
        mcdnTf = url;
      } else if (url.contains('/upgcxcode/')) {
        mcdnUpgcxcode = url;
      }
    }

    final targetUrl = uposUrl ?? mcdnUpgcxcode ?? (mcdnTf != null ? null : last);

    if (defaultCDNService == CDNService.backupUrl ||
        (isAudio && disableAudioCDN)) {
      return targetUrl ?? last;
    }

    if (targetUrl != null && defaultCDNService.host != null && targetUrl.contains('/upgcxcode/')) {
      final uri = Uri.parse(targetUrl);
      String path = uri.path;
      if (path.contains('/v1/resource/upgcxcode/')) {
        path = path.substring(path.indexOf('/upgcxcode/'));
      }
      return uri.replace(
        scheme: 'https',
        host: defaultCDNService.host,
        port: 443,
        path: path,
      ).toString();
    }

    if (mcdnTf != null) {
      return Uri(
        scheme: 'https',
        host: _proxyTf,
        queryParameters: {'url': mcdnTf},
      ).toString();
    }

    return targetUrl ?? last;
  }

  static String getLiveCdnUrl(CodecItem e, {int index = 0}) {
    final urlInfo = e.urlInfo.getOrFirst(index);
    return (liveCdnUrl ?? urlInfo.host) + e.baseUrl + urlInfo.extra;
  }

  static VideoDecodeFormatType selectCodec(
    Iterable<String> codecs,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    if (preferCodecs.isNotEmpty) {
      int bestIndex = preferCodecs.length;
      for (final e in codecs) {
        for (int i = 0; i < bestIndex; i++) {
          if (preferCodecs[i].codes.any(e.startsWith)) {
            bestIndex = i;
            if (bestIndex == 0) {
              return preferCodecs[0];
            }
            break;
          }
        }
      }
      if (bestIndex < preferCodecs.length) {
        return preferCodecs[bestIndex];
      }
    }
    return VideoDecodeFormatType.fromString(codecs.first);
  }
}
