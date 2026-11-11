#!/usr/bin/env python3
"""生成一个用于开发 / 截图测试的模拟影视库（NFO + 海报 + 剧照 + 可播放的测试视频）。

用法：python3 tool/make_demo_library.py <输出目录>
依赖：Pillow；有 ffmpeg 时会生成可播放的测试视频（含双音轨、内封 ASS、外挂 SRT）。
海报和剧照是程序生成的抽象图，不含任何真实影片素材。
"""
import colorsys
import os
import random
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = sys.argv[1]
FONT_PATH = next((f for f in ['/System/Library/Fonts/PingFang.ttc', '/System/Library/Fonts/STHeiti Medium.ttc'] if os.path.exists(f)), None)


def font(size):
    return ImageFont.truetype(FONT_PATH, size) if FONT_PATH else ImageFont.load_default()


def art(path, w, h, seed, title='', sub=''):
    """柔和的光斑渐变，带一点颗粒，像失焦的电影画面。"""
    rnd = random.Random(seed)
    hue = rnd.random()
    small = Image.new('RGB', (64, int(64 * h / w)))
    d = ImageDraw.Draw(small)
    sw, sh = small.size
    for y in range(sh):
        t = y / sh
        r, g, b = colorsys.hls_to_rgb((hue + t * 0.08) % 1, 0.08 + 0.20 * (1 - t), 0.32)
        d.line([(0, y), (sw, y)], fill=(int(r * 255), int(g * 255), int(b * 255)))
    for _ in range(5):
        cx, cy, rr = rnd.randint(0, sw), rnd.randint(0, sh), rnd.randint(sw // 6, sw // 2)
        r, g, b = colorsys.hls_to_rgb((hue + rnd.choice([0.0, 0.06, 0.5])) % 1, rnd.uniform(0.3, 0.55), 0.38)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(int(r * 255), int(g * 255), int(b * 255)))
    im = small.filter(ImageFilter.GaussianBlur(6)).resize((w, h), Image.BICUBIC)
    if title:
        dr = ImageDraw.Draw(im)
        fs = max(18, w // 10)
        dr.text((w * 0.08, h * 0.74), title, font=font(fs), fill=(242, 240, 236))
        if sub:
            dr.text((w * 0.08, h * 0.74 + fs * 1.35), sub, font=font(max(12, fs // 2)), fill=(210, 208, 204))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, quality=88)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def touch(path, size=2048):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(b'\0' * size)


MOVIES = [
    ('星际穿越', 'Interstellar', 2014, 9.4, 169, ['科幻', '冒险', '剧情'], '克里斯托弗·诺兰', '一队探险家利用他们针对虫洞的新发现，超越人类太空旅行的极限，在广袤的宇宙中进行星际航行。', ['马修·麦康纳', '安妮·海瑟薇', '杰西卡·查斯坦'], '爱是唯一可以超越时间与空间的事物。'),
    ('盗梦空间', 'Inception', 2010, 9.4, 148, ['科幻', '悬疑', '动作'], '克里斯托弗·诺兰', '道姆·柯布与同事们是一群专门从他人梦境中窃取机密的盗贼。', ['莱昂纳多·迪卡普里奥', '约瑟夫·高登-莱维特'], ''),
    ('阿凡达', 'Avatar', 2009, 8.8, 162, ['科幻', '动作', '冒险'], '詹姆斯·卡梅隆', '战斗中双腿瘫痪的前海军陆战队员杰克被派往潘多拉星球。', ['萨姆·沃辛顿', '佐伊·索尔达娜'], ''),
    ('千与千寻', '千と千尋の神隠し', 2001, 9.4, 125, ['动画', '奇幻'], '宫崎骏', '少女千寻误入神灵世界，为了拯救变成猪的父母而在汤屋工作。', ['柊瑠美', '入野自由'], ''),
    ('霸王别姬', '', 1993, 9.6, 171, ['剧情', '爱情'], '陈凯歌', '段小楼与程蝶衣是一对打小一起长大的师兄弟。', ['张国荣', '张丰毅', '巩俐'], ''),
    ('肖申克的救赎', 'The Shawshank Redemption', 1994, 9.7, 142, ['剧情', '犯罪'], '弗兰克·德拉邦特', '银行家安迪被冤枉谋杀妻子，在肖申克监狱中度过了漫长岁月。', ['蒂姆·罗宾斯', '摩根·弗里曼'], '希望是美好的事物。'),
    ('流浪地球', 'The Wandering Earth', 2019, 7.9, 125, ['科幻', '灾难'], '郭帆', '太阳即将毁灭，人类开启"流浪地球"计划。', ['吴京', '屈楚萧'], ''),
    ('沙丘', 'Dune', 2021, 7.7, 155, ['科幻', '冒险'], '丹尼斯·维伦纽瓦', '保罗·厄崔迪前往危险的沙漠星球厄拉科斯。', ['提莫西·查拉梅', '丽贝卡·弗格森'], ''),
    ('寄生虫', '기생충', 2019, 8.8, 132, ['剧情', '喜剧'], '奉俊昊', '全家失业的基宇一家与富有的朴社长一家之间发生的故事。', ['宋康昊', '李善均'], ''),
    ('银翼杀手2049', 'Blade Runner 2049', 2017, 8.3, 164, ['科幻', '惊悚'], '丹尼斯·维伦纽瓦', '新一代银翼杀手K发现了一个埋藏已久的秘密。', ['瑞恩·高斯林', '哈里森·福特'], ''),
    ('让子弹飞', '', 2010, 8.9, 132, ['剧情', '喜剧', '动作'], '姜文', '民国年间，麻匪张牧之劫了县长的马车，冒充县长来到鹅城。', ['姜文', '葛优', '周润发'], ''),
    ('疯狂动物城', 'Zootopia', 2016, 9.2, 108, ['动画', '喜剧', '冒险'], '拜伦·霍华德', '兔子朱迪成为动物城第一位兔子警官。', ['金妮弗·古德温', '杰森·贝特曼'], ''),
]

SHOWS = [('绝命毒师', 2008, 9.6, ['剧情', '犯罪'], [7, 6]), ('庆余年', 2019, 7.9, ['古装', '剧情'], [6, 4]), ('黑镜', 2011, 8.7, ['科幻', '惊悚'], [3, 3, 6])]


def main():
    for i, (t, ot, y, r, rt, gs, dr, plot, actors, tagline) in enumerate(MOVIES):
        d = os.path.join(ROOT, '电影', f'{t} ({y})')
        base = f'{t} ({y})'
        touch(os.path.join(d, base + '.mkv'), 4096 * (i + 1))
        acts = ''.join(f'<actor><name>{a}</name><role>角色{j + 1}</role><order>{j}</order></actor>' for j, a in enumerate(actors))
        write(os.path.join(d, base + '.nfo'),
              f'<?xml version="1.0" encoding="UTF-8"?>\n<movie><title>{t}</title><originaltitle>{ot or t}</originaltitle>'
              f'<year>{y}</year><rating>{r}</rating><runtime>{rt}</runtime><plot>{plot}</plot><tagline>{tagline}</tagline>'
              + ''.join(f'<genre>{g}</genre>' for g in gs) + f'<country>示例</country><director>{dr}</director>{acts}</movie>')
        if i != 4:  # 霸王别姬：故意没有海报和剧照，测试占位与虚化背景
            art(os.path.join(d, 'poster.jpg'), 600, 900, i, t, str(y))
            if i != 3:  # 千与千寻：只有海报没有剧照
                art(os.path.join(d, 'fanart.jpg'), 1920, 1080, i + 100)
        art(os.path.join(d, '.actors', actors[0].replace(' ', '_') + '.jpg'), 200, 200, i * 7)
    touch(os.path.join(ROOT, '电影', '散落文件', 'The.Matrix.1999.1080p.BluRay.x264.mkv'))
    touch(os.path.join(ROOT, '电影', '散落文件', 'Heat.1995.2160p.UHD.mkv'))

    for k, (t, y, r, gs, seasons) in enumerate(SHOWS):
        d = os.path.join(ROOT, '剧集', f'{t} ({y})')
        write(os.path.join(d, 'tvshow.nfo'),
              f'<tvshow><title>{t}</title><year>{y}</year><rating>{r}</rating><plot>{t}的剧情简介示例。</plot>'
              + ''.join(f'<genre>{g}</genre>' for g in gs) + '<status>Ended</status></tvshow>')
        art(os.path.join(d, 'poster.jpg'), 600, 900, 50 + k, t, str(y))
        art(os.path.join(d, 'fanart.jpg'), 1920, 1080, 150 + k)
        for s, n in enumerate(seasons, start=1):
            art(os.path.join(d, f'season{s:02d}-poster.jpg'), 400, 600, 60 + k * 10 + s, f'{t} S{s}')
            for e in range(1, n + 1):
                base = f'{t} - S{s:02d}E{e:02d}'
                touch(os.path.join(d, f'Season {s}', base + '.mkv'))
                if e <= 3:
                    write(os.path.join(d, f'Season {s}', base + '.nfo'),
                          f'<episodedetails><title>第{s}季第{e}集标题</title><season>{s}</season><episode>{e}</episode>'
                          f'<plot>这一集里发生了很多事情，这是一段用来测试排版的剧情简介示例文本。</plot><aired>{y + s - 1}-0{e}-01</aired></episodedetails>')
                    art(os.path.join(d, f'Season {s}', base + '-thumb.jpg'), 480, 270, k * 100 + s * 10 + e)

    if shutil.which('ffmpeg'):
        movie = os.path.join(ROOT, '电影', '星际穿越 (2014)', '星际穿越 (2014).mkv')
        ass = os.path.join(ROOT, '.sub.ass')
        write(ass, """[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,PingFang SC,54,&H0000D7FF,&H000000FF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,3,1,2,20,20,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:01:00.00,Default,,0,0,0,,内封 ASS 特效字幕
""")
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=24:duration=60',
                        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=60', '-f', 'lavfi', '-i', 'sine=frequency=660:duration=60',
                        '-i', ass, '-map', '0:v', '-map', '1:a', '-map', '2:a', '-map', '3:s', '-c:v', 'libx264', '-preset', 'ultrafast',
                        '-crf', '30', '-c:a', 'aac', '-b:a', '64k', '-c:s', 'ass',
                        '-metadata:s:a:0', 'language=eng', '-metadata:s:a:0', 'title=English',
                        '-metadata:s:a:1', 'language=chi', '-metadata:s:a:1', 'title=国语',
                        '-metadata:s:s:0', 'language=chi', '-metadata:s:s:0', 'title=简中特效', movie], check=True)
        os.remove(ass)
        write(movie[:-4] + '.chs.srt', '1\n00:00:00,500 --> 00:01:00,000\n外挂 SRT 字幕（简体）\n')
        for e in (1, 2):
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=24:duration=20',
                            '-f', 'lavfi', '-i', f'sine=frequency={300 + e * 100}:duration=20', '-c:v', 'libx264', '-preset', 'ultrafast',
                            '-crf', '32', '-c:a', 'aac', '-b:a', '48k', '-shortest',
                            os.path.join(ROOT, '剧集', '绝命毒师 (2008)', 'Season 1', f'绝命毒师 - S01E0{e}.mkv')], check=True)
    print('ok:', ROOT)


if __name__ == '__main__':
    main()
