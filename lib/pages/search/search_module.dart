import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/utils/search_parser.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/home/tv_home_page.dart';

void _provideSearchController(Scoped scoped) {
  scoped.add<SearchPageController>(SearchPageController.new);
}

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        provide: _provideSearchController,
        child: (context, state) => TvMode.enabled
            ? TvHomePage(
                startInSearch: true,
                initialQuery: state.uri.queryParameters['query'] ?? '',
              )
            : SearchPage(
          controller: context.read<SearchPageController>(),
          initialQuery: state.uri.queryParameters['query'] ?? '',
        ),
      )
      ..route(
        '/image',
        provide: _provideSearchController,
        child: (context, state) => ImageSearchPage(
          controller: context.read<SearchPageController>(),
        ),
      )
      ..route(
        '/:tag',
        provide: _provideSearchController,
        child: (context, state) => TvMode.enabled
            ? TvHomePage(
                startInSearch: true,
                initialQuery: SearchParser.fromFilterState(SearchFilterState(
                    tags: [Uri.decodeComponent(state['tag'] ?? '')])),
              )
            : SearchPage(
          controller: context.read<SearchPageController>(),
          initialQuery: SearchParser.fromFilterState(SearchFilterState(
              tags: [Uri.decodeComponent(state['tag'] ?? '')])),
        ),
      );
  },
);
