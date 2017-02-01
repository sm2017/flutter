// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

typedef void AlternatingListCallback<T, U>(T odd, U even);

class AlternatingList<T, U> {
  AlternatingList() : _oddEntries = <T>[], _evenEntries = <U>[];

  AlternatingList.pair(T odd, U even) {
    _oddEntries = <T>[odd];
    _evenEntries = <U>[even];
  }

  AlternatingList.from(AlternatingList<T, U> other) {
    _oddEntries = new List<T>.from(other._oddEntries);
    _evenEntries = new List<U>.from(other._evenEntries);
  }

  AlternatingList.prepend(T odd, U even, { @required AlternatingList<T, U> to }) {
    _oddEntries = new List<T>.from(to._oddEntries);
    _oddEntries.insert(0, odd);
    _evenEntries = new List<U>.from(to._evenEntries);
    _evenEntries.insert(0, even);
  }

  List<T> _oddEntries;
  List<U> _evenEntries;

  int get length => _oddEntries.length;

  bool get sealed => _sealed;
  bool _sealed = false;

  void seal() {
    _sealed = true;
  }

  void addPair(T odd, U even) {
    assert(!_sealed);
    _oddEntries.add(odd);
    _evenEntries.add(even);
  }

  void forEach(AlternatingListCallback<T, U> callback) {
    assert(_sealed);
    assert(_oddEntries.length == _evenEntries.length);
    for (int index = 0; index < length; index += 1)
      callback(_oddEntries[index], _evenEntries[index]);
  }

  bool contains(dynamic target) {
    return _oddEntries.contains(target) || _evenEntries.contains(target);
  }
}
