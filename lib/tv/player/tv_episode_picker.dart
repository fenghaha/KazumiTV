import 'package:flutter/material.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

typedef TvEpisodeSelection = ({int episode, int road});

Future<TvEpisodeSelection?> showTvEpisodePicker(
  BuildContext context, {
  required List<Road> roads,
  required int selectedRoad,
  required int selectedEpisode,
}) => showDialog<TvEpisodeSelection>(
  context: context,
  builder: (_) => TvEpisodePicker(
    roads: roads,
    selectedRoad: selectedRoad,
    selectedEpisode: selectedEpisode,
  ),
);

class TvEpisodePicker extends StatefulWidget {
  const TvEpisodePicker({
    super.key,
    required this.roads,
    required this.selectedRoad,
    required this.selectedEpisode,
  });
  final List<Road> roads;
  final int selectedRoad;
  final int selectedEpisode;

  @override
  State<TvEpisodePicker> createState() => _TvEpisodePickerState();
}

class _TvEpisodePickerState extends State<TvEpisodePicker> {
  late int _road =
      widget.selectedRoad >= 0 && widget.selectedRoad < widget.roads.length
      ? widget.selectedRoad
      : 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final road = widget.roads.isEmpty ? null : widget.roads[_road];
    return Dialog(
      backgroundColor: const Color(0xFF101C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 50, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * .85,
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    '选集',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TvFocusable(
                    onPressed: () => Navigator.of(context).pop(),
                    semanticLabel: '关闭选集',
                    child: const Row(
                      children: [
                        Icon(Icons.close_rounded),
                        SizedBox(width: 8),
                        Text('返回播放'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.roads.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvFocusable(
                          selected: i == _road,
                          onPressed: () {
                            setState(() => _road = i);
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                          },
                          child: Text(
                            widget.roads[i].name.isEmpty
                                ? '线路 ${i + 1}'
                                : widget.roads[i].name,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${road?.data.length ?? 0} 集  ·  方向键选择，确认播放',
                style: const TextStyle(color: Color(0xFFAAB9CB), fontSize: 17),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    if (road == null || road.data.isEmpty) {
                      return const Center(child: Text('这条线路暂时没有剧集'));
                    }
                    final columns = bounds.maxWidth >= 1000
                        ? 6
                        : bounds.maxWidth >= 680
                        ? 4
                        : 3;
                    final width =
                        (bounds.maxWidth - (columns - 1) * 12) / columns;
                    // Eager focus nodes keep D-pad traversal continuous across rows.
                    return SingleChildScrollView(
                      controller: _scroll,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List.generate(road.data.length, (index) {
                          final episode = index + 1;
                          final selected =
                              _road == widget.selectedRoad &&
                              episode == widget.selectedEpisode;
                          final name =
                              index < road.identifier.length &&
                                  road.identifier[index].isNotEmpty
                              ? road.identifier[index]
                              : '第 $episode 集';
                          return SizedBox(
                            width: width,
                            child: TvFocusable(
                              key: ValueKey('tv-episode-$_road-$episode'),
                              autofocus:
                                  selected ||
                                  (widget.selectedEpisode <= 0 && index == 0),
                              selected: selected,
                              semanticLabel: '$name${selected ? '，当前播放' : ''}',
                              padding: const EdgeInsets.all(16),
                              onPressed: () =>
                                  Navigator.of(context).pop<TvEpisodeSelection>(
                                    (episode: episode, road: _road),
                                  ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    episode.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
