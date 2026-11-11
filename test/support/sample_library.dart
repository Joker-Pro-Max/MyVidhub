import 'dart:io';

import 'package:path/path.dart' as p;

/// 在 [root] 下生成一个模拟媒体库（视频是空文件，图片是占位文件）。
/// 覆盖：标准电影目录、同目录多部电影、CD 分段、剧集 + 季目录、散装剧集、忽略目录。
void createSampleLibrary(String root) {
  void f(String rel, [String content = '']) {
    final file = File(p.join(root, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  // 标准电影目录：片名 (年份)/片名 (年份).mkv + 同名 nfo + poster/fanart
  f('电影/阿凡达 (2009)/阿凡达 (2009).mkv');
  f('电影/阿凡达 (2009)/阿凡达 (2009).nfo', '''<?xml version="1.0" encoding="UTF-8"?>
<movie><title>阿凡达</title><originaltitle>Avatar</originaltitle><year>2009</year>
<rating>7.9</rating><runtime>162</runtime><genre>动作</genre><genre>科幻</genre>
<plot>潘多拉星球上的冒险。</plot><director>詹姆斯·卡梅隆</director><set><name>测试合集</name></set>
<actor><name>Sam Worthington</name><role>Jake</role></actor></movie>''');
  f('电影/阿凡达 (2009)/poster.jpg');
  f('电影/阿凡达 (2009)/fanart.jpg');
  f('电影/阿凡达 (2009)/.actors/Sam_Worthington.jpg');
  f('电影/阿凡达 (2009)/extras/幕后花絮.mkv');
  f('电影/阿凡达 (2009)/阿凡达-sample.mkv');

  // movie.nfo + 两个版本
  f('电影/盗梦空间 (2010)/Inception.2010.1080p.mkv');
  f('电影/盗梦空间 (2010)/Inception.2010.2160p.mkv');
  f('电影/盗梦空间 (2010)/movie.nfo',
      '<movie><title>盗梦空间</title><year>2010</year><genre>科幻 / 悬疑</genre><set>测试合集</set></movie>');
  f('电影/盗梦空间 (2010)/folder.jpg');

  // 同一目录多部电影，图片用 片名-poster.jpg
  f('电影/合集/The.Matrix.1999.1080p.mkv');
  f('电影/合集/The.Matrix.1999.1080p-poster.jpg');
  f('电影/合集/The.Matrix.Reloaded.2003.mkv');
  f('电影/合集/The.Matrix.Reloaded.2003.nfo', '<movie><title>黑客帝国2：重装上阵</title></movie>');

  // CD 分段
  f('电影/老电影 (1994)/Old Movie CD1.avi');
  f('电影/老电影 (1994)/Old Movie CD2.avi');

  // 标准剧集
  f('剧集/绝命毒师 (2008)/tvshow.nfo',
      '<tvshow><title>绝命毒师</title><year>2008</year><genre>剧情</genre></tvshow>');
  f('剧集/绝命毒师 (2008)/poster.jpg');
  f('剧集/绝命毒师 (2008)/season01-poster.jpg');
  f('剧集/绝命毒师 (2008)/Season 1/Breaking.Bad.S01E01.mkv');
  f('剧集/绝命毒师 (2008)/Season 1/Breaking.Bad.S01E01.nfo',
      '<episodedetails><title>试播集</title><season>1</season><episode>1</episode></episodedetails>');
  f('剧集/绝命毒师 (2008)/Season 1/Breaking.Bad.S01E01-thumb.jpg');
  f('剧集/绝命毒师 (2008)/Season 1/Breaking.Bad.S01E02.mkv');
  f('剧集/绝命毒师 (2008)/Season 2/Breaking.Bad.S02E01.mkv');
  f('剧集/绝命毒师 (2008)/Season 2/poster.jpg');

  // 无 NFO，只有季目录
  f('剧集/庆余年/第一季/庆余年 第01集.mp4');
  f('剧集/庆余年/第一季/庆余年 第02集.mp4');
  f('剧集/庆余年/第二季/庆余年 第二季 第01集.mp4');

  // 散装剧集（同一目录）
  f('剧集/Friends/Friends.S01E01.mkv');
  f('剧集/Friends/Friends.S01E02.mkv');
  f('剧集/Friends/Friends.S01E03.mkv');

  // 系统垃圾目录
  f('@eaDir/x.mkv');
}
