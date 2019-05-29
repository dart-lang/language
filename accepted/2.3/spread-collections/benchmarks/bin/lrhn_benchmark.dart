import"dart:collection";
void copy1(Map<String, int> from, Map<String, int> to) {
  for (var entry in from.entries) {
    to[entry.key] = entry.value;
  }
}
void copy2(Map<String, int> from, Map<String, int> to) {
  for (var key in from.keys) {
    to[key] = from[key];
  }
}
void copy3(Map<String, int> from, Map<String, int> to) {
  var tmp = to;
  from.forEach((key, value) {
    tmp[key] = value;
  });
  tmp = null;
}
void copy4(Map<String, int> from, Map<String, int> to) {
  to.addAll(from);
}

main() {
  for (int i = 0; i < 5; i++) {
    bench("entries", copy1);
    bench("keys", copy2);
    bench("forEach", copy3);
    bench("addAll", copy4);
  }
}

int id(int x)=>x;
var maps = List.generate(100, (n) {
  var map = Map<String, int>.fromIterable(Iterable.generate(n * 10), key: (n) =>"#$n");
  if (n % 4 == 1) map = SplayTreeMap<String, int>.from(map);
  if (n % 4 == 2) map = HashMap<String, int>.from(map);
  return map;
});

void bench(String name, void Function(Map<String, int>, Map<String, int>) action) {
  var e = 0;
  var c = 0;
  var sw = Stopwatch()..start();
  do {
    for (var from in maps) {
      var to = <String, int>{};
      action(from, to);
      c += from.length;
    }
    e = sw.elapsedMilliseconds;
  } while (e < 2000);
  print("$name: ${c/e} entries/ms");
}
