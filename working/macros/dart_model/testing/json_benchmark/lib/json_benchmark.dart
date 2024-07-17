import 'dart:io';

import 'json_buffer_subject.dart';
import 'json_subject.dart';

class JsonBenchmark {
  Future<void> run() async {
    final jsonSubject = JsonSubject();

    print('Subject,Scenario,Data size/bytes,Time per/ms');
    for (final subject in [
      JsonBufferSubject(),
      JsonBufferSubject(),
      JsonBufferSubject(),
      JsonBufferSubject(),
      JsonBufferSubject(), /*JsonSubject()*/
    ]) {
      for (final size in [256]) {
        final neutralData = jsonSubject.createData(libraryCount: size);
        final subjectData = subject.deepCopyIn(neutralData);
        final byteData = subject.serialize(subjectData);
        final byteLength = byteData.length;

        await benchmark(subject.name, 'create', byteLength,
            () => subject.createData(libraryCount: size));
        await benchmark(subject.name, 'deepCopyIn', byteLength,
            () => subject.deepCopyIn(neutralData));
        await benchmark(subject.name, 'serialize', byteLength,
            () => subject.serialize(subjectData));
        await benchmark(subject.name, 'writeSync', byteLength,
            () => File('/tmp/benchmark').writeAsBytesSync(byteData));
        await benchmark(
            subject.name,
            'copySerializeWrite',
            byteLength,
            () => File('/tmp/benchmark').writeAsBytesSync(
                subject.serialize(subject.deepCopyIn(neutralData))));
        await benchmark(
            subject.name,
            'createSerializeWrite',
            byteLength,
            () => File('/tmp/benchmark').writeAsBytesSync(
                subject.serialize(subject.createData(libraryCount: size))));

        await benchmark(
            subject.name, 'process', byteLength, () => process(subjectData));
        await benchmark(subject.name, 'deepCopyOut', byteLength,
            () => subject.deepCopyOut(subjectData));
        await benchmark(subject.name, 'readSync', byteLength,
            () => File('/tmp/benchmark').readAsBytesSync());
        await benchmark(subject.name, 'deserialize', byteLength,
            () => subject.deserialize(byteData));
        await benchmark(
            subject.name,
            'readDeserializeCopy',
            byteLength,
            () => subject.deepCopyOut(
                subject.deserialize(File('/tmp/benchmark').readAsBytesSync())));
        await benchmark(
            subject.name,
            'readDeserializeProcess',
            byteLength,
            () => process(
                subject.deserialize(File('/tmp/benchmark').readAsBytesSync())));
      }
    }
  }

  int process(Map<String, Object?> data) {
    var result = 0;
    for (final entry in data.entries) {
      final key = entry.key;
      result ^= key.hashCode;
      var value = entry.value;
      if (value is Map<String, Object?>) {
        result ^= process(value);
      } else {
        result ^= value.hashCode;
      }
    }
    return result;
  }

  Future<void> benchmark(String subjectName, String scenarioName, int length,
      Function subject) async {
    final repetitions = 100;
    for (var i = 0; i != repetitions; ++i) {
      subject();
    }
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i != repetitions; ++i) {
      subject();
    }
    final elapsed = stopwatch.elapsedMilliseconds;
    print('$subjectName,$scenarioName,$length,${elapsed / repetitions}');
  }
}
