import 'dart:collection';

const trialMs = 100;
const lengths = [0, 1, 2, 5, 10, 20, 50, 100, 1000];

var csv = StringBuffer();

class CustomList<T> extends ListBase<T> {
  final List<T> _inner;

  int get length => _inner.length;

  set length(int value) => _inner.length = value;

  CustomList(this._inner);

  T operator [](int index) => _inner[index];

  void operator []=(int index, T value) => _inner[index] = value;
}

void main() {
  for (var length in lengths) {
    var baseline = runBench("iterate", length, iterate);
    runBench("List for", length, addList, baseline);
    runBench("resize and set", length, resizeAndSet, baseline);
    runBench("addAll()", length, addAll, baseline);
    runBench("forEach()", length, forEach, baseline);
    print("");
  }

//  print("");
//  print(csv);
}

double runBench(
    String name, int length, void Function(List<String>, List<String>) action,
    [double baseline]) {
  var from = <String>[];
  for (var i = 0; i < length; i++) {
    from.add(String.fromCharCode(i % 26 + 65));
  }

  var froms = [from, CustomList(from)];

  var rate = benchBest(froms, action);

  if (baseline == null) {
    print("${length.toString().padLeft(4)} ${name.padRight(15)} "
        "${rate.toStringAsFixed(2).padLeft(10)} spreads/ms "
        "                 ${'-' * 20}");
  } else {
    var comparison = rate / baseline;
    var bar = "=" * (comparison * 20).toInt();
    if (comparison > 4.0) bar = "!!!";
    print("${length.toString().padLeft(4)} ${name.padRight(15)} "
        "${rate.toStringAsFixed(2).padLeft(10)} spreads/ms "
        "${comparison.toStringAsFixed(2).padLeft(6)}x baseline $bar");
  }

  csv.writeln("$length,$name,$rate");
  return rate;
}

/// Runs [bench] a number of times and returns the best (highest) result.
double benchBest(
    List<List<String>> froms, void Function(List<String>, List<String>) action) {
  var best = 0.0;
  for (var i = 0; i < 4; i++) {
    var result = bench(froms, action);
    if (result > best) best = result;
  }

  return best;
}

/// Spreads each list in [froms] into the middle of a list using [action].
///
/// Returns the number of times it was able to do this per millisecond, on
/// average. Higher is better.
double bench(List<List<String>> froms,
    void Function(List<String>, List<String>) action) {
  var elapsed = 0;
  var count = 0;
  var watch = Stopwatch()..start();
  do {
    for (var i = 0; i < froms.length; i++) {
      var from = froms[i];
      var to = <String>["a", "b"];

      action(from, to);
      to.add("b");
      to.add("c");

      count++;
    }
    elapsed = watch.elapsedMilliseconds;
  } while (elapsed < trialMs);

  return count / elapsed;
}

void iterate(List<String> from, List<String> to) {
  for (var e in from) {
    to.add(e);
  }
}

void addList(List<String> from, List<String> to) {
  var length = from.length;
  for (var i = 0; i < length; i++) {
    to.add(from[i]);
  }
}

void resizeAndSet(List<String> from, List<String> to) {
  var length = from.length;
  var j = to.length;
  to.length = to.length + length;
  for (var i = 0; i < length; i++) {
    to[j] = from[i];
  }
}

void addAll(List<String> from, List<String> to) {
  to.addAll(from);
}

void forEach(List<String> from, List<String> to) {
  var temp = to;
  from.forEach((s) {
    temp.add(s);
  });
  temp = null;
}
