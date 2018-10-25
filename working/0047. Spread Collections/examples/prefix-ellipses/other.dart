// flutter/packages/flutter/test/services/message_codecs_test.dart
_checkEncoding<dynamic>(
  standard,
  Uint8List(253),
  [8, 253, ...List.filled(253, 0)],
);

// flutter/packages/flutter_driver/lib/src/common/find.dart
Map<String, String> serialize() => {
  ...super.serialize(),
  'text': text,
};

// packages/angel_framework-1.1.5+1/lib/src/core/service.dart
post(
    '/:id',
    (RequestContext req, res) => req.lazyBody().then((body) => this.update(
        toId(req.params['id']),
        body,
        {
          'query': req.query,
          ...restProvider,
          ...req.serviceParams
        })),
    middleware: [
      ...handlers,
      ...?updateMiddleware?.handlers
    ]);

// packages/aqueduct-3.0.1/lib/src/db/schema/schema_table.dart
var diffs = [
  ..._differingColumns.expand((diff) => diff.errorMessages),
  ...?uniqueSetDifference?.errorMessages
];

// packages/aqueduct-3.0.1/test/auth/auth_code_controller_test.dart:
var m = {...form, "response_type": "code"};

// packages/aws_client-0.1.2/lib/src/request.dart
String canonical = [
  method.toUpperCase(),
  uri.path,
  canonicalQuery,
  ...canonicalHeaders,
  '',
  signedHeaders,
  payloadHash
].join('\n');

// packages/build_runner-0.10.2/lib/src/entrypoint/test.dart
var outputMap = {...?options.outputMap, tempPath: null};

// packages/build_web_compilers-0.4.3+1/lib/src/dart2js_bootstrap.dart
args = [
  ...dart2JsArgs,
  '--packages=$packageFile',
  '-o$jsOutputPath',
  dartPath,
  ..._shouldAddNoSyncAsyncFlag(enableSyncAsync) ? ['--no-sync-async'] : []
];

// packages/dartdoc-0.21.1/lib/src/model.dart
_allInstanceProperties = [
  ...instanceProperties.toList()..sort(byName),
  ...inheritedProperties.toList()..sort(byName),
]

// packages/dartis-0.2.0/lib/src/command/commands.dart
  Future<int> geoadd(K key,
          {GeoItem<V> item, Iterable<GeoItem<V>> items = const []}) =>
      run<int>([
        r'GEOADD',
        key,
        ..._expandGeoItem(item),
        ...items.expand(_expandGeoItem)
      ]);

// packages/dartis-0.2.0/lib/src/command/commands.dart
    return run<int>(<Object>[
      r'SORT',
      key,
      by == null ? null : r'BY',
      by,
      offset == null ? null : r'LIMIT',
      offset,
      count,
      ...get.expand((pattern) => [r'GET', pattern]),
      order?.name,
      alpha ? r'ALPHA' : null,
      r'STORE',
      destination
    ];

// packages/sass-1.14.0/lib/src/executable/watch.dart
  var directoriesToWatch = [
    ...options.sourceDirectoriesToDestinations.keys,
    ...options.sourcesToDestinations.keys.map(p.dirname),
    ...options.loadPaths
  ];
