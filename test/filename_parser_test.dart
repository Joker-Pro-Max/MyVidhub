import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/domain/filename_parser.dart';
import 'package:myvidhub/domain/media_extensions.dart';

void main() {
  void check(String name, String title, {int? year, int? season, int? episode}) {
    final p = FilenameParser.parse(name);
    expect(p.title, title, reason: name);
    expect(p.year, year, reason: '$name year');
    expect(p.season, season, reason: '$name season');
    expect(p.episode, episode, reason: '$name episode');
  }

  test('电影文件名', () {
    check('阿凡达 (2009)', '阿凡达', year: 2009);
    check('The.Dark.Knight.2008.1080p.BluRay.x264-GROUP', 'The Dark Knight', year: 2008);
    check('1917.2019.2160p.UHD.BluRay', '1917', year: 2019);
    check('2012 (2009)', '2012', year: 2009);
    check('Blade Runner 2049 (2017) [2160p]', 'Blade Runner 2049', year: 2017);
    check('[字幕组] 千与千寻 2001 1080p', '千与千寻', year: 2001);
    check('Inception', 'Inception');
    check('流浪地球.The.Wandering.Earth.2019.WEB-DL.4K', '流浪地球 The Wandering Earth', year: 2019);
  });

  test('剧集文件名', () {
    check('Breaking.Bad.S01E02.720p', 'Breaking Bad', season: 1, episode: 2);
    check('绝命毒师 - S02E10 - 标题', '绝命毒师', season: 2, episode: 10);
    check('Friends 3x07', 'Friends', season: 3, episode: 7);
    check('庆余年 第二季 第05集', '庆余年', season: 2, episode: 5);
    check('Show.Name.EP12.1080p', 'Show Name', episode: 12);
    check('Mr. Robot S01E01', 'Mr. Robot', season: 1, episode: 1);
  });

  test('季目录名', () {
    expect(seasonFromDirName('Season 1'), 1);
    expect(seasonFromDirName('S02'), 2);
    expect(seasonFromDirName('第十二季'), 12);
    expect(seasonFromDirName('Specials'), 0);
    expect(seasonFromDirName('Movies'), isNull);
  });

  test('视频文件判断', () {
    expect(isVideoFile('a.mkv'), isTrue);
    expect(isVideoFile('a-sample.mkv'), isFalse);
    expect(isVideoFile('._a.mkv'), isFalse);
    expect(isVideoFile('a.nfo'), isFalse);
  });
}
