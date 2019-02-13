import 'dart:collection';

const trials = 2000;
const rounds = 4;

var csv = StringBuffer();

bool warmup = true;

//class CustomMap<K, V> extends MapBase<K, V> {
//  final Map<K, V> _inner;
//
//  CustomMap(this._inner);
//
//  operator [](Object key) => _inner[key];
//
//  void operator []=(key, value) => _inner[key] = value;
//
//  void clear() => throw "not implemented";
//
//  Iterable<K> get keys => _inner.keys;
//
//  remove(Object key) => throw "not implemented";
//}

void main() {
  benchmarks();
}

void benchmarks() {
  final maps = makeMaps([0, 1, 2, 5, 10, 20, 50, 100], (map) {
    return [
      map,
      SplayTreeMap.of(map),
      HashMap.of(map),
    ];
  });

  for (var i = 1; i <= rounds; i++) {
    warmup = i < rounds;

    var baseline = bench("addEntries", maps, addEntries);
    var entriesMap =
        bench("iterate entries into map", maps, iterateEntriesIntoNewMap, baseline);
    var keysMap = bench("iterate keys into map", maps, iterateKeysIntoNewMap, baseline);
    var forEachMap = bench("forEach into map", maps, forEachIntoNewMap, baseline);

    log();

    var justEntries = bench("just iterate entries", maps, iterateEntries);
    var justKeys = bench("just iterate keys", maps, iterateKeys);
    var justForEach = bench("just forEach", maps, forEach);

    log();

    log("(entries insertion overhead)", entriesMap - justEntries);
    log("(keys insertion overhead)", keysMap - justKeys);
    log("(forEach insertion overhead)", forEachMap - justForEach);
  }
}

Map<String, int> makeMap(int size) {
  var result = <String, int>{};
  for (var i = 0; i < size; i++) {
    var key = "";
    var n = i + 1;
    while (n > 0) {
      key += String.fromCharCode((n % 26) + 65);
      n ~/= 26;
    }

    result[key] = i;
  }

  return result;
}

List<Map<String, int>> makeMaps(List<int> sizes,
    List<Map<String, int>> Function(Map<String, int>) callback) {
  var maps = <Map<String, int>>[];
  for (var size in sizes) {
    var map = makeMap(size);
    maps.addAll(callback(map));
  }

  return maps;
}

double bench(String label, List<Map<String, int>> maps,
    void Function(Map<String, int>) action, [double baseline]) {
  var watch = Stopwatch()..start();
  for (var i = 0; i < trials; i++) {
    for (var i = 0; i < maps.length; i++) {
      action(maps[i]);
    }
  }

  watch.stop();
  var microPerTrial = watch.elapsedMicroseconds / (trials * maps.length);
  log(label, microPerTrial, baseline);
  return microPerTrial;
}

void log([String label, double microseconds, double baseline]) {
  if (warmup) return;

  if (microseconds != null) {
    var perMs = (1000 / microseconds).toStringAsFixed(2);
    var output = "${label.padLeft(30)} ${perMs.padLeft(10)} spreads/ms";
    if (baseline != null) {
      var relative = baseline / microseconds;
      output += " ${relative.toStringAsFixed(2).padLeft(5)}x";
    }
    print(output);
  } else if (label != null) {
    print("--- $label ---");
  } else {
    print("");
  }
}

void iterateEntries(Map<String, int> from) {
  var sum = 0;
  for (var entry in from.entries) {
    sum += entry.value;
  }

  preventOptimization(sum);
}

void iterateEntriesIntoNewMap(Map<String, int> from) {
  var to = <String, int>{"a": 1, "b": 2};

  for (var entry in from.entries) {
    to[entry.key] = entry.value;
  }

  to["b"] = 3;
  to["c"] = 4;

  preventOptimization(to.length);
}

void iterateKeys(Map<String, int> from) {
  var sum = 0;
  for (var key in from.keys) {
    sum += from[key];
  }

  preventOptimization(sum);
}

void iterateKeysIntoNewMap(Map<String, int> from) {
  var to = <String, int>{"a": 1, "b": 2};

  for (var key in from.keys) {
    to[key] = from[key];
  }

  to["b"] = 3;
  to["c"] = 4;

  preventOptimization(to.length);
}

void forEach(Map<String, int> from) {
  var sum = 0;
  from.forEach((key, value) {
    sum += value;
  });

  preventOptimization(sum);
}

void forEachIntoNewMap(Map<String, int> from) {
  var to = <String, int>{"a": 1, "b": 2};

  var temp = to;
  from.forEach((key, value) {
    temp[key] = value;
  });
  temp = null;

  to["b"] = 3;
  to["c"] = 4;

  preventOptimization(to.length);
}

void addEntries(Map<String, int> from) {
  var to = <String, int>{"a": 1, "b": 2};

  to.addEntries(from.entries);

  to["b"] = 3;
  to["c"] = 4;

  preventOptimization(to.length);
}

/// Ensure [obj] is used in some way so that the optimizer doesn't eliminate
/// the code that produces it.
void preventOptimization(Object obj) {
  if (obj == "it will never be this") print("!");
}

//double runBench(String name, int length,
//    void Function(Map<String, int>, Map<String, int>) action,
//    [double baseline]) {
//  var from = <String, int>{};
//  for (var i = 0; i < length; i++) {
//    from[String.fromCharCode(i % 26 + 65)] = i;
//  }
//
//  var froms = [from, CustomMap(from)];
//
//  var rate = benchBest(froms, action);
//
//  if (baseline == null) {
//    print("${length.toString().padLeft(4)} ${name.padRight(15)} "
//        "${rate.toStringAsFixed(2).padLeft(10)} spreads/ms "
//        "                 ${'-' * 20}");
//  } else {
//    var comparison = rate / baseline;
//    var bar = "=" * (comparison * 20).toInt();
//    if (comparison > 4.0) bar = "!!!";
//    print("${length.toString().padLeft(4)} ${name.padRight(15)} "
//        "${rate.toStringAsFixed(2).padLeft(10)} spreads/ms "
//        "${comparison.toStringAsFixed(2).padLeft(6)}x baseline $bar");
//  }
//
//  csv.writeln("$length,$name,$rate");
//  return rate;
//}
//
///// Runs [bench] a number of times and returns the best (highest) result.
//double benchBest(List<Map<String, int>> froms,
//    void Function(Map<String, int>, Map<String, int>) action) {
//  var best = 0.0;
//  for (var i = 0; i < 4; i++) {
//    var result = bench(froms, action);
//    if (result > best) best = result;
//  }
//
//  return best;
//}
//
//double bench(List<Map<String, int>> froms,
//    void Function(Map<String, int>, Map<String, int>) action) {
//  var elapsed = 0;
//  var count = 0;
//  var watch = Stopwatch()..start();
//  do {
//    for (var i = 0; i < froms.length; i++) {
//      var from = froms[i];
//      var to = <String, int>{"a": 1, "b": 2};
//
//      action(from, to);
//      to["b"] = 3;
//      to["c"] = 4;
//
//      count++;
//    }
//    elapsed = watch.elapsedMilliseconds;
//  } while (elapsed < trialMs);
//
//  return count / elapsed;
//}
//
//void iterateEntries(Map<String, int> from, Map<String, int> to) {
//  for (var entry in from.entries) {
//    to[entry.key] = entry.value;
//  }
//}

//void addList(Map<String, int> from, Map<String, int> to) {
//  var length = from.length;
//  for (var i = 0; i < length; i++) {
//    to.add(from[i]);
//  }
//}
//
//void resizeAndSet(Map<String, int> from, Map<String, int> to) {
//  var length = from.length;
//  var j = to.length;
//  to.length = to.length + length;
//  for (var i = 0; i < length; i++) {
//    to[j] = from[i];
//  }
//}
//
//void addAll(Map<String, int> from, Map<String, int> to) {
//  to.addAll(from);
//}
//
//void forEach(Map<String, int> from, Map<String, int> to) {
//  var temp = to;
//  from.forEach((s) {
//    temp.add(s);
//  });
//  temp = null;
//}
