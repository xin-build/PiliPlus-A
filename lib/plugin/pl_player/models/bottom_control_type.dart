import 'package:PiliPlus/models/common/enum_with_label.dart';

enum BottomControlType implements EnumWithLabel {
  playOrPause('播放/暂停'),
  time('时间进度'),
  pre('上一集'),
  next('下一集'),
  episode('选集'),
  fit('画面比例'),
  aiTranslate('AI原声翻译'),
  subtitle('字幕'),
  speed('倍速'),
  fullscreen('全屏'),
  viewPoints('高能看点'),
  superResolution('超分辨率/CAS'),
  dmChart('弹幕趋势图'),
  qa('画质');

  @override
  final String label;
  const BottomControlType(this.label);
}
