extension ListSortBy<E> on List<E> {
  /// Sorts in place by [key] in ascending natural order.
  void sortBy<K extends Comparable<K>>(K Function(E) key) {
    sort((a, b) => key(a).compareTo(key(b)));
  }
}
