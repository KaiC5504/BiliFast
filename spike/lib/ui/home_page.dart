import 'package:flutter/material.dart';

import '../api/models.dart';
import '../services.dart';
import 'swipe_back_route.dart';
import 'theme.dart';
import 'video_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _cards = <FeedCard>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _load();
    });
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = refresh ? 0 : _page;
      final cards = await Services.client.recommendFeed(page);
      if (!mounted) return;
      setState(() {
        if (refresh) _cards.clear();
        final seen = _cards.map((c) => c.bvid).toSet();
        _cards.addAll(cards.where((c) => seen.add(c.bvid)));
        _page = page + 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(FeedCard card) {
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => VideoPage(card: card)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Bili.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _TopBar(),
            const _Tabs(),
            Expanded(
              child: RefreshIndicator(
                color: Bili.pink,
                onRefresh: () => _load(refresh: true),
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.93,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => FeedCardView(card: _cards[i], onTap: () => _open(_cards[i])),
                          childCount: _cards.length,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: _error != null
                              ? TextButton(onPressed: _load, child: Text('加载失败，点击重试\n$_error', textAlign: TextAlign.center))
                              : _loading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Bili.pink))
                                  : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomBar(),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          const CircleAvatar(radius: 15, backgroundColor: Bili.pinkTint, child: Icon(Icons.person, size: 18, color: Bili.pink)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(color: Bili.field, borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Row(children: [
                Icon(Icons.search, size: 18, color: Bili.grey),
                SizedBox(width: 6),
                Text('搜索视频、番剧或up主', style: TextStyle(color: Bili.grey, fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.mail_outline, color: Bili.grey, size: 22),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    const tabs = ['直播', '推荐', '热门', '动画', '影视'];
    return Container(
      color: Colors.white,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(t,
                      style: TextStyle(
                        fontSize: t == '推荐' ? 16 : 15,
                        fontWeight: t == '推荐' ? FontWeight.w600 : FontWeight.normal,
                        color: t == '推荐' ? Bili.pink : const Color(0xFF61666D),
                      )),
                  const SizedBox(height: 4),
                  Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(color: t == '推荐' ? Bili.pink : Colors.transparent, borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),
            ),
          const Spacer(),
          const Icon(Icons.menu, color: Bili.grey, size: 20),
        ],
      ),
    );
  }
}

class FeedCardView extends StatelessWidget {
  const FeedCardView({super.key, required this.card, required this.onTap});

  final FeedCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = card.cover.startsWith('//') ? 'https:${card.cover}' : card.cover;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Bili.card, borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Bili.greyLight),
                  if (cover.isNotEmpty)
                    Image.network('$cover@480w_300h_1c.webp', fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.6, 1],
                        colors: [Colors.transparent, Color(0xAA000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 4,
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      child: Row(children: [
                        const Icon(Icons.play_circle_outline, size: 13, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(Bili.count(card.views)),
                        const SizedBox(width: 8),
                        const Icon(Icons.subtitles_outlined, size: 13, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(Bili.count(card.danmaku)),
                        const Spacer(),
                        Text(Bili.duration(card.duration)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 0),
              child: Text(card.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.35, color: Bili.text)),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 2, 4),
              child: Row(children: [
                if (card.reason != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(color: Bili.pinkTint, borderRadius: BorderRadius.circular(2)),
                    child: Text(card.reason!, style: const TextStyle(color: Bili.pink, fontSize: 10)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(border: Border.all(color: Bili.grey, width: 0.6), borderRadius: BorderRadius.circular(2)),
                    child: const Text('UP', style: TextStyle(color: Bili.grey, fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(card.ownerName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Bili.grey, fontSize: 11)),
                ),
                const Icon(Icons.more_vert, size: 16, color: Bili.grey),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, {bool selected = false}) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: selected ? Bili.pink : const Color(0xFF61666D)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: selected ? Bili.pink : const Color(0xFF61666D))),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Bili.greyLight, width: 0.5))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(children: [
            item(Icons.home_filled, '首页', selected: true),
            item(Icons.people_outline, '关注'),
            Expanded(
              child: Center(
                child: Container(
                  width: 44,
                  height: 32,
                  decoration: BoxDecoration(color: Bili.pink, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
            ),
            item(Icons.chat_bubble_outline, '消息'),
            item(Icons.person_outline, '我的'),
          ]),
        ),
      ),
    );
  }
}
