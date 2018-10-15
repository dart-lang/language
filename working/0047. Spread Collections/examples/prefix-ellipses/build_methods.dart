// flutter/examples/flutter_gallery/lib/demo/cupertino/cupertino_navigation_demo.dart
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: const Text('Support Chat'),
        trailing: const ExitButton(),
      ),
      child: ListView(
        children: [
          Tab2Header(),
          ...buildTab2Conversation()
        ],
      ),
    );
  }

// flutter/examples/flutter_gallery/lib/demo/pesto_demo.dart
  Widget build(BuildContext context) {
    return Material(
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 40.0),
          child: Table(
            columnWidths: const <int, TableColumnWidth>{
              0: const FixedColumnWidth(64.0)
            },
            children: [
              TableRow(
                children: [
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Image.asset(
                      recipe.ingredientsImagePath,
                      package: recipe.ingredientsImagePackage,
                      width: 32.0,
                      height: 32.0,
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown
                    )
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Text(recipe.name, style: titleStyle)
                  ),
                ]
              ),
              TableRow(
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Text(recipe.description, style: descriptionStyle)
                  ),
                ]
              ),
              TableRow(
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 4.0),
                    child: Text('Ingredients', style: headingStyle)
                  ),
                ]
              ),
              ...recipe.ingredients.map(
                (RecipeIngredient ingredient) {
                  return _buildItemRow(ingredient.amount, ingredient.description);
                }
              ),
              TableRow(
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 4.0),
                    child: Text('Steps', style: headingStyle)
                  ),
                ]
              ),
              ...recipe.steps.map(
                (RecipeStep step) {
                  return _buildItemRow(step.duration ?? '', step.description);
                }
              )
            ]
          ),
        ),
      ),
    );
  }

// flutter/examples/flutter_gallery/lib/gallery/demo.dart
Widget build(BuildContext context) {
  return DefaultTabController(
    length: demos.length,
    child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...?actions,
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.description),
                tooltip: 'Show example code',
                onPressed: () {
                  _showExampleCode(context);
                },
              );
            },
          )
        ]
      ),
    ),
  );
}

// flutter/examples/flutter_gallery/lib/gallery/options.dart
return DefaultTextStyle(
  style: theme.primaryTextTheme.subhead,
  child: ListView(
    padding: const EdgeInsets.only(bottom: 124.0),
    children: [
      const _Heading('Display'),
      _ThemeItem(options, onOptionsChanged),
      _TextScaleFactorItem(options, onOptionsChanged),
      _TextDirectionItem(options, onOptionsChanged),
      _TimeDilationItem(options, onOptionsChanged),
      const Divider(),
      const _Heading('Platform mechanics'),
      _PlatformItem(options, onOptionsChanged),
      ..._enabledDiagnosticItems(),
      const Divider(),
      const _Heading('Flutter gallery'),
      _ActionItem('About Flutter Gallery', () {
        showGalleryAboutDialog(context);
      }),
      _ActionItem('Send feedback', onSendFeedback),
    ],
  ),
);

// packages/flutter_document_picker-1.1.0/example/lib/main.dart
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 24.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headline,
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

// packages/rebloc-0.0.5/listexample/lib/main.dart
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rebloc list example')),
      body: ViewModelSubscriber<AppState, NameListViewModel>(
        converter: (state) =>
            NameListViewModel(state.namesAndCounts.keys.toList()),
        builder: (context, dispatcher, viewModel) {
          final dateStr = _formatTime(DateTime.now());

          final listRows = viewModel.names
              .map<Widget>((name) => NameAndCount(name, key: ValueKey(name)));

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 16.0),
                Text('Rebuilt at $dateStr'),
                SizedBox(height: 16.0),
                ...listRows
              ],
            ),
          );
        },
      ),
    );
  }

// packages/loader_search_bar-1.0.0+1/lib/src/SearchBarBuilder.dart
  List<Widget> _buildBaseBarContent(
      Widget leading, Widget search, List<Widget> actions) {
    return [
      Container(width: _attrs.searchBarPadding),
      leading,
      search,
      Container(width: _attrs.searchBarPadding),
      ...?actions,
    ]..removeWhere((it) => it == null);
  }
