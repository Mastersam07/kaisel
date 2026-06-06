import 'package:kaisel_core/framework.dart';
import 'package:test/test.dart';

/// Concrete subclass that exposes [notifyListeners] (which is `@protected`)
/// as a public method so tests can drive notifications directly.
class _ExposedNotifier extends KaiselChangeNotifier {
  void fire() => notifyListeners();

  /// Re-expose [isDisposed] (also `@protected`) for assertions.
  bool get disposed => isDisposed;
}

void main() {
  group('KaiselChangeNotifier (live)', () {
    test('delivers notifications to registered listeners', () {
      final notifier = _ExposedNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier.addListener(listener);

      notifier.fire();
      notifier.fire();

      expect(calls, 2);
    });

    test('removeListener stops further delivery', () {
      final notifier = _ExposedNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier.addListener(listener);

      notifier.fire();
      notifier.removeListener(listener);
      notifier.fire();

      expect(calls, 1);
    });
  });

  group('KaiselChangeNotifier (dispose guards)', () {
    test('isDisposed flips to true after dispose', () {
      final notifier = _ExposedNotifier();
      expect(notifier.disposed, isFalse);

      notifier.dispose();

      expect(notifier.disposed, isTrue);
    });

    test('addListener throws StateError after dispose', () {
      final notifier = _ExposedNotifier();
      notifier.dispose();

      expect(() => notifier.addListener(() {}), throwsStateError);
    });

    test('notifyListeners throws StateError after dispose', () {
      final notifier = _ExposedNotifier();
      notifier.dispose();

      expect(notifier.fire, throwsStateError);
    });

    test('removeListener is a safe no-op after dispose', () {
      final notifier = _ExposedNotifier();
      void listener() {}
      notifier.addListener(listener);
      notifier.dispose();

      // Must not throw even though the notifier is disposed.
      expect(() => notifier.removeListener(listener), returnsNormally);
    });
  });

  group('KaiselChangeNotifier (snapshot-iteration safety)', () {
    test('a listener removing another listener mid-dispatch is safe', () {
      final notifier = _ExposedNotifier();
      var secondCalls = 0;
      void second() => secondCalls++;

      // The first listener removes `second` during dispatch. Because
      // notify iterates a snapshot, `second` still runs for this round.
      notifier.addListener(() => notifier.removeListener(second));
      notifier.addListener(second);

      notifier.fire();
      expect(secondCalls, 1, reason: 'snapshot keeps second alive this round');

      // On the next round `second` is gone.
      notifier.fire();
      expect(secondCalls, 1);
    });

    test('a listener removing itself mid-dispatch is safe', () {
      final notifier = _ExposedNotifier();
      var selfCalls = 0;
      late void Function() self;
      self = () {
        selfCalls++;
        notifier.removeListener(self);
      };
      notifier.addListener(self);

      // First dispatch runs `self` once and removes it.
      notifier.fire();
      expect(selfCalls, 1);

      // Second dispatch: nothing left to call.
      notifier.fire();
      expect(selfCalls, 1);
    });
  });
}
