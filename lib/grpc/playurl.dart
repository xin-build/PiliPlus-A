import 'package:PiliPlus/grpc/bilibili/app/playurl/v1.pb.dart'
    show PlayViewReply, PlayViewReq;
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/url.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:fixnum/fixnum.dart';

abstract final class PlayUrlGrpc {
  static Future<LoadingState<PlayUrlModel>> playView({
    required int aid,
    required int cid,
    int? qn,
    int fnval = 4048,
    bool fourk = true,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.playView,
      PlayViewReq(
        aid: Int64(aid),
        cid: Int64(cid),
        qn: Int64(qn ?? 80),
        fnval: fnval,
        fourk: fourk,
        fnver: 0,
        forceHost: 2,
        voiceBalance: Int64.ONE,
      ),
      PlayViewReply.fromBuffer,
    );

    if (res case Success(:final response)) {
      if (!response.hasVideoInfo()) {
        return const Error('playview: video_info is empty');
      }
      return Success(PlayUrlModel.fromPlayViewReply(response));
    } else if (res case Error(:final errMsg, :final code)) {
      return Error(errMsg, code: code);
    } else {
      return LoadingState.loading();
    }
  }
}
