import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/domain/nfo_parser.dart';

void main() {
  test('标准 Kodi 电影 NFO', () {
    final d = NfoParser.parse('''﻿<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<movie>
  <title>阿凡达</title>
  <originaltitle>Avatar</originaltitle>
  <ratings>
    <rating name="imdb" max="10"><value>7.9</value></rating>
    <rating name="tmdb" max="10" default="true"><value>7.6</value></rating>
  </ratings>
  <year>2009</year>
  <plot>战斗中双腿瘫痪的前海军陆战队员杰克……</plot>
  <runtime>162</runtime>
  <thumb aspect="poster">https://image.tmdb.org/t/p/original/a.jpg</thumb>
  <fanart><thumb>https://image.tmdb.org/t/p/original/b.jpg</thumb></fanart>
  <uniqueid type="tmdb" default="true">19995</uniqueid>
  <uniqueid type="imdb">tt0499549</uniqueid>
  <genre>动作</genre>
  <genre>科幻</genre>
  <country>美国</country>
  <set><name>阿凡达（系列）</name></set>
  <director>詹姆斯·卡梅隆</director>
  <actor><name>萨姆·沃辛顿</name><role>杰克</role><order>0</order><thumb>https://x/1.jpg</thumb></actor>
  <actor><name>佐伊·索尔达娜</name><role>奈蒂莉</role><order>1</order></actor>
</movie>''')!;
    expect(d.kind, NfoKind.movie);
    expect(d.title, '阿凡达');
    expect(d.originalTitle, 'Avatar');
    expect(d.year, 2009);
    expect(d.rating, 7.6);
    expect(d.runtime, 162);
    expect(d.genres, ['动作', '科幻']);
    expect(d.setName, '阿凡达（系列）');
    expect(d.uniqueIds, {'tmdb': '19995', 'imdb': 'tt0499549'});
    expect(d.actors.map((a) => a.name), ['萨姆·沃辛顿', '佐伊·索尔达娜']);
    expect(d.actors.first.role, '杰克');
    expect(d.posterUrl, 'https://image.tmdb.org/t/p/original/a.jpg');
    expect(d.fanartUrl, 'https://image.tmdb.org/t/p/original/b.jpg');
  });

  test('未转义 & 、合并类型、旧格式 rating、年份来自 premiered', () {
    final d = NfoParser.parse('''<movie>
<title>Tom & Jerry</title>
<rating>8,5</rating>
<premiered>2021-02-26</premiered>
<genre>动画 / 喜剧</genre>
<set>猫和老鼠</set>
</movie>''')!;
    expect(d.title, 'Tom & Jerry');
    expect(d.rating, 8.5);
    expect(d.year, 2021);
    expect(d.genres, ['动画', '喜剧']);
    expect(d.setName, '猫和老鼠');
  });

  test('XML 后附带 URL（旧版 Kodi）', () {
    final d = NfoParser.parse('<movie><title>X</title><year>1999</year></movie>\n'
        'https://www.themoviedb.org/movie/603')!;
    expect(d.title, 'X');
    expect(d.year, 1999);
  });

  test('剧集与单集 NFO', () {
    final show = NfoParser.parse(
        '<tvshow><title>绝命毒师</title><premiered>2008-01-20</premiered><status>Ended</status></tvshow>')!;
    expect(show.kind, NfoKind.tvshow);
    expect(show.year, 2008);
    expect(show.status, 'Ended');

    final ep = NfoParser.parse('''<episodedetails><title>试播集</title><season>1</season>
<episode>1</episode><aired>2008-01-20</aired></episodedetails>
<episodedetails><title>第二集</title><season>1</season><episode>2</episode></episodedetails>''')!;
    expect(ep.kind, NfoKind.episode);
    expect(ep.title, '试播集');
    expect(ep.season, 1);
    expect(ep.episode, 1);
  });

  test('结构损坏时正则兜底', () {
    final d = NfoParser.parse('<movie><title>坏掉的文件</title><year>2010</year><plot>没有闭合')!;
    expect(d.title, '坏掉的文件');
    expect(d.year, 2010);
  });

  test('非 NFO 内容返回 null', () {
    expect(NfoParser.parse('https://www.imdb.com/title/tt0111161/'), isNull);
    expect(NfoParser.parse(''), isNull);
  });
}
