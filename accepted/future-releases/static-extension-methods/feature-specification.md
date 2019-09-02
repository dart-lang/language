extension SmartIterable<T> on Iterable<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (var e in this) smart(e);
  }
}
extension SmartList<T> on List<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (int i = 0; i < length; i++) smart(this[i]);
  }
}
...
  List<int> x = ....;
  x.doTheSmartThing(print);
