import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/video/controller.dart';

class SearchAllController extends SearchVideoController with SearchVideoMixin {
  SearchAllController({
    required super.keyword,
    required super.searchType,
    required super.tag,
  });

  List<SearchUser>? searchUser;
  List<SearchPgcItemModel>? searchMediaBgm;
  List<SearchPgcItemModel>? searchMediaFt;
  List<SearchActivity>? searchActivity;

  @override
  bool customHandleResponse(bool isRefresh, Success<SearchVideoData> response) {
    final res = response.response;
    if (isRefresh) {
      searchUser = res.searchUser;
      searchMediaBgm = res.searchMediaBgm;
      searchMediaFt = res.searchMediaFt;
      searchActivity = res.searchActivity;
      searchType_ = .video;
    }
    return super.customHandleResponse(isRefresh, response);
  }

  @override
  late var searchType_ = searchType;

  void _computeActualSearchType() {
    if (order.isNotEmpty ||
        videoDurationType != .all ||
        videoZoneType != .all ||
        pubBegin != null ||
        pubEnd != null) {
      searchType_ = .video;
      return;
    }
    searchType_ = .all;
  }

  @override
  Future<void> onRefresh() {
    _computeActualSearchType();
    searchUser = null;
    searchMediaBgm = null;
    searchMediaFt = null;
    searchActivity = null;
    return super.onRefresh();
  }
}
