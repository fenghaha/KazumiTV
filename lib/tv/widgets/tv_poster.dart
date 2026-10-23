import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

String tvBangumiTitle(BangumiItem item) =>
    item.nameCn.isNotEmpty ? item.nameCn : item.name;

class TvPoster extends StatelessWidget {
  const TvPoster({
    super.key,
    required this.item,
    required this.onPressed,
    this.width = 150,
    this.subtitle,
    this.focusNode,
    this.autofocus = false,
  });

  final BangumiItem item;
  final VoidCallback onPressed;
  final double width;
  final String? subtitle;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final title = tvBangumiTitle(item);
    final imageHeight = width * 1.34;
    return SizedBox(
      width: width + 18,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        semanticLabel: subtitle == null ? title : '$title，$subtitle',
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                NetworkImgLayer(
                  src: item.images['large'] ?? item.images['common'],
                  width: width,
                  height: imageHeight,
                  borderRadius: BorderRadius.circular(7),
                ),
                if (item.ratingScore > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xED101C2C),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        item.ratingScore.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEBC889),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle ?? (item.airDate.isEmpty ? '查看详情' : item.airDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFFAAB9CB)),
            ),
          ],
        ),
      ),
    );
  }
}
