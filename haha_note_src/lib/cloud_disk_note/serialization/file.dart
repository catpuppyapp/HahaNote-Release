import 'dart:io';

abstract class IoFile<T> {
  void writeToFile(File file);

  T readFromFile(File file);
}
