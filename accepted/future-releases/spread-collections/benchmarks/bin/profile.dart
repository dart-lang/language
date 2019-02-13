import 'dart:collection';
import 'dart:math' as math;

/// The minimum amount of time it will spend running the benchmark in a loop.
///
/// Setting this to a larger number increases the time the benchmarks take to
/// run, but also tends to lower the deviation and increases the consistency
/// of the results.
const _trialMicros = 100 * 1000;

final iterables = <Iterable<String>>[];
final lists = <List<String>>[];
final maps = <Map<String, int>>[];
final mapsWithSplay = <Map<String, int>>[];

String _configuration;
int _length;
bool _csvOutput = false;
bool _warmingUp = true;

final _runs = <String, List<double>>{};

void main(List args) {
  // TODO(rnystrom): Workaround https://github.com/dart-lang/sdk/issues/35925.
  var arguments = List<String>.from(args);

  if (arguments.remove("--csv")) _csvOutput = true;

  if (arguments.length != 2) {
    print("Usage: profile.dart <config name> <collection size> [--csv]");
    return;
  }

  _configuration = arguments[0];
  _length = int.parse(arguments[1]);

  // Create objects to be spread.
  var list = <String>[];
  var map = <String, int>{};
  for (var i = 0; i < _length; i++) {
    var string = String.fromCharCode(i % 26 + 65);
    list.add(string);
    map[string] = i;
  }

  iterables.add(list.map((n) => n));
  iterables.add(list.where((i) => true));
  iterables.add(list);
  iterables.add(CustomList(list));

  lists.add(list);
  lists.add(CustomList(list));

  maps.add(map);
  maps.add(HashMap.of(map));

  // Since SplayTreeMap has very different performance, do a separate set of
  // polymorphic map benchmarks using it and LinkedHashMap.
  mapsWithSplay.add(map);
  mapsWithSplay.add(SplayTreeMap.of(map));

  // Do a single warm-up run. Since each benchmark is invoked many times, this
  // is enough for the optimizer to kick in. Performing multiple warm-up rounds
  // does not seem to noticeably lower the deviation of the results.
  if (!_csvOutput) print("Warming up...");
  benchmarkAll();
  _warmingUp = false;

  // Run a number of trials of the benchmark. This lets us see not just
  // performance, but get an estimate of the deviation of the benchmarks.
  if (!_csvOutput) print("Running trials...");
  for (var i = 0; i < 5; i++) {
    benchmarkAll();
    if (!_csvOutput) print(".");
  }

  if (!_csvOutput) {
    print("Collection / method            ops/ms   - overhead      μs/op   "
        "stddev      rel");
    print("------------------------   ----------   ----------   --------   "
        "------   ------ ----------");
  }

  var iterableOverhead = bestTime("Iterable", "noop");
  var iterableBaseline = bestTime("Iterable", "iterator");
  show("Iterable", "iterator", iterableOverhead, iterableBaseline);
  show("Iterable", "forEach", iterableOverhead, iterableBaseline);
  show("Iterable", "check type", iterableOverhead, iterableBaseline);
  if (!_csvOutput) print("");

  var listOverhead = bestTime("List", "noop");
  var listBaseline = bestTime("List", "iterator");
  show("List", "[]", listOverhead, listBaseline);
  show("List", "forEach", listOverhead, listBaseline);
  if (!_csvOutput) print("");

  var mapOverhead = bestTime("Map", "noop");
  var mapBaseline = bestTime("Map", "entries");
  show("Map", "entries", mapOverhead, mapBaseline);
  show("Map", "keys", mapOverhead, mapBaseline);
  show("Map", "forEach", mapOverhead, mapBaseline);
  if (!_csvOutput) print("");

  var mapSplayOverhead = bestTime("Map+Splay", "noop");
  var mapSplayBaseline = bestTime("Map+Splay", "entries");
  show("Map+Splay", "entries", mapSplayOverhead, mapSplayBaseline);
  show("Map+Splay", "keys", mapSplayOverhead, mapSplayBaseline);
  show("Map+Splay", "forEach", mapSplayOverhead, mapSplayBaseline);
  if (!_csvOutput) print("");
}

void benchmarkAll() {
  // Calculate how much time we spend just iterating over the benchmarked lists
  // and building the result. This is fixed overhead independent of how we
  // spread the collection, so we subtract it from the other benchmarks.
  var iterableOverhead = benchmarkIterable("noop", iterableNoop);
  benchmarkIterable("iterator", iterableIterator, iterableOverhead);
  benchmarkIterable("forEach", iterableForEach, iterableOverhead);
  benchmarkIterable("check type", iterableCheckType, iterableOverhead);

  var listOverhead = benchmarkList("noop", listNoop);
  benchmarkList("iterator", listIterator, listOverhead);
  benchmarkList("[]", listSubscript, listOverhead);
  benchmarkList("forEach", listForEach, listOverhead);

  benchmarkMaps("Map", maps);
  benchmarkMaps("Map+Splay", mapsWithSplay);
}

void benchmarkMaps(String collection, List<Map<String, int>> maps) {
  var overhead = benchmarkMap(collection, "noop", maps, mapNoop);
  benchmarkMap(collection, "entries", maps, mapEntries, overhead);
  benchmarkMap(collection, "keys", maps, mapKeys, overhead);
  benchmarkMap(collection, "forEach", maps, mapForEach, overhead);
}

double benchmarkIterable(
    String method, void Function(Iterable<String>, List<String>) action,
    [double overhead]) {
  var time = bench(() {
    for (var i = 0; i < lists.length; i++) {
      var from = lists[i];
      var to = <String>["a", "b"];

      action(from, to);

      to.add("b");
      to.add("c");
    }
  });

  if (!_warmingUp) _runs.putIfAbsent("Iterable $method", () => []).add(time);
  return time;
}

double benchmarkList(
    String method, void Function(List<String>, List<String>) action,
    [double overhead]) {
  var time = bench(() {
    for (var i = 0; i < lists.length; i++) {
      var from = lists[i];
      var to = <String>["a", "b"];

      action(from, to);

      to.add("b");
      to.add("c");
    }
  });

  if (!_warmingUp) _runs.putIfAbsent("List $method", () => []).add(time);
  return time;
}

double benchmarkMap(
    String collection,
    String method,
    List<Map<String, int>> maps,
    void Function(Map<String, int>, Map<String, int>) action,
    [double overhead]) {
  var time = bench(() {
    for (var i = 0; i < maps.length; i++) {
      var from = maps[i];
      var to = <String, int>{"a": 1, "b": 2};

      action(from, to);

      to["b"] = 3;
      to["c"] = 4;
    }
  });

  if (!_warmingUp) _runs.putIfAbsent("$collection $method", () => []).add(time);
  return time;
}

/// Estimates the time in fractional milliseconds to execute [action] once.
///
/// Since action might be very fast, it runs the action multiple times. It
/// guesses how many times to run it by trying larger and larger numbers until
/// it hits some minimum elapsed time.
double bench(void Function() action) {
  var iterations = 1;
  for (;;) {
    var watch = Stopwatch()..start();

    for (var i = 0; i < iterations; i++) {
      action();
    }

    watch.stop();

    var elapsed = watch.elapsedMicroseconds;
    if (elapsed >= _trialMicros) return elapsed / iterations;

    iterations *= 2;
  }
}

void show(String collection, String method, double overhead, double baseline) {
  var best = bestTime(collection, method);
  var deviation = standardDeviation(collection, method);
  var adjusted = best - overhead;

  var output = "$collection / $method".padRight(24);

  var perMs = (1000 / best).toStringAsFixed(2);
  output += "   ${perMs.padLeft(10)}";

  var adjustedPerMs = (1000 / adjusted).toStringAsFixed(2);
  output += "   ${adjustedPerMs.padLeft(10)}";

  output += "   ${best.toStringAsFixed(4).padLeft(8)}";
  output += "   ${deviation.toStringAsFixed(4).padLeft(6)}";

  var relative = (baseline - overhead) / adjusted;
  var bar = "!!!";
  if (relative < 10.0) bar = "=" * (relative * 10).toInt();

  output += "   ${relative.toStringAsFixed(2).padLeft(5)}x";
  output += " $bar";

  if (_csvOutput) {
    print("$_configuration,$_length,$collection,$method,"
        "${relative.toStringAsFixed(3)}");
  } else {
    print(output);
  }
}

double bestTime(String collection, String method) {
  var runs = _runs["$collection $method"];
  var min = runs.first;
  for (var i = 1; i < runs.length; i++) {
    if (runs[i] < min) min = runs[i];
  }

  return min;
}

double standardDeviation(String collection, String method) {
  var runs = _runs["$collection $method"];

  var mean = runs.fold<double>(0.0, (a, b) => a + b) / runs.length;

  // Sum the squares of the differences from the mean.
  var result = 0.0;
  for (var time in runs) {
    result += math.pow(time - mean, 2);
  }

  return math.sqrt(result / runs.length);
}

void iterableNoop(Iterable<String> from, List<String> to) {}

void iterableIterator(Iterable<String> from, List<String> to) {
  for (var e in from) {
    to.add(e);
  }
}

void iterableForEach(Iterable<String> from, List<String> to) {
  var temp = to;
  from.forEach((s) {
    temp.add(s);
  });
  temp = null;
}

void iterableCheckType(Iterable<String> from, List<String> to) {
  if (from is List<String>) {
    var length = from.length;
    for (var i = 0; i < length; i++) {
      to.add(from[i]);
    }
  } else {
    for (var e in from) {
      to.add(e);
    }
  }
}

void listNoop(List<String> from, List<String> to) {}

void listIterator(List<String> from, List<String> to) {
  for (var e in from) {
    to.add(e);
  }
}

void listSubscript(List<String> from, List<String> to) {
  var length = from.length;
  for (var i = 0; i < length; i++) {
    to.add(from[i]);
  }
}

void listForEach(List<String> from, List<String> to) {
  var temp = to;
  from.forEach((s) {
    temp.add(s);
  });
  temp = null;
}

void mapNoop(Map<String, int> from, Map<String, int> to) {}

void mapEntries(Map<String, int> from, Map<String, int> to) {
  for (var e in from.entries) {
    to[e.key] = e.value;
  }
}

void mapKeys(Map<String, int> from, Map<String, int> to) {
  for (var key in from.keys) {
    to[key] = from[key];
  }
}

void mapForEach(Map<String, int> from, Map<String, int> to) {
  var temp = to;
  from.forEach((key, value) {
    temp[key] = value;
  });
  temp = null;
}

class CustomList<T> extends ListBase<T> {
  final List<T> _inner;

  int get length => _inner.length;

  set length(int value) => _inner.length = value;

  CustomList(this._inner);

  T operator [](int index) => _inner[index];

  void operator []=(int index, T value) => _inner[index] = value;
}
