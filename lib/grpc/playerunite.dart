import 'package:PiliPlus/grpc/bilibili/app/playerunite/v1.pb.dart'
    show PlayViewUniteReply, PlayViewUniteReq;
import 'package:PiliPlus/grpc/bilibili/playershared.pb.dart'
    show CodeType, PlayCtrl, VideoVod;
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/url.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:fixnum/fixnum.dart';

abstract final class PlayerUniteGrpc {
  static Future<LoadingState<PlayUrlModel>> playViewUnite({
    required int aid,
    required int cid,
    int? qn,
    int fnval = 4048,
    bool isNeedTrial = true,
    String fromScene = 'ugc',
    Map<String, String>? extraContent,
  }) async {
    final req = PlayViewUniteReq(
      vod: VideoVod(
        aid: Int64(aid),
        cid: Int64(cid),
        qn: Int64(qn ?? 80),
        fnver: 0,
        fnval: fnval,
        download: 0,
        forceHost: 2,
        fourk: true,
        preferCodecType: CodeType.NOCODE,
        voiceBalance: Int64(1),
        isNeedTrial: isNeedTrial,
      ),
      spmid: 'main.ugc-video-detail.0.0',
      fromSpmid: 'main.ugc-video-detail.0.0',
      playCtrl: PlayCtrl.PLAY_CTRL_DEFAULT,
      fromScene: fromScene,
      extraContent: extraContent?.entries,
    );

    final res = await GrpcReq.request(
      GrpcUrl.playViewUnite,
      req,
      PlayViewUniteReply.fromBuffer,
      isPhone: true,
    );

    if (res case Success(:final response)) {
      if (!response.hasVodInfo()) {
        return const Error('playviewunite: vod_info is empty');
      }
      return Success(PlayUrlModel.fromVodInfo(response.vodInfo));
    } else if (res case Error(:final errMsg, :final code)) {
      return Error(errMsg, code: code);
    } else {
      return LoadingState.loading();
    }
  }
}
