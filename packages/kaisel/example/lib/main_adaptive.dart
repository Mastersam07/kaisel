// Adaptive layout demo for the kaisel router.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_adaptive.dart
//
// What this shows
// ---------------
// A book catalogue with master-detail behaviour at wide widths. The
// route stack stays the same regardless of width; only the rendering
// changes. At wide widths (>= 700px), the detail route absorbs the
// list into a single rendered page laid out side by side. At narrow
// widths, the detail appears as a normal stacked push above the
// list.
//
// Things worth observing as you resize the window:
//
// 1. At wide widths, selecting a different book from the list does
//    NOT trigger a Navigator slide transition. The detail pane just
//    updates in place. That's the AdaptiveKey identity trick:
//    [List, DetailA] and [List, DetailB] produce pages keyed on the
//    same lowest absorbed entry, so the Navigator treats them as the
//    same page with a new child.
//
// 2. At narrow widths, pushes and pops animate normally.
//
// 3. The "Reviews" button inside the detail pushes a new route on
//    top of the absorbing master-detail page. That entry is NOT
//    absorbed, so it slides on top regardless of width. Pop unwinds
//    it as a normal stacked pop.
//
// 4. Android back at the absorbed `[List, Detail]` state pops the
//    Detail, leaving `[List]`. The popRoute fallthrough in the
//    delegate handles the case where the visible Navigator has only
//    one page (see v0.8 changelog).

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class BookRoute extends KaiselRoute {
  const BookRoute();
}

final class BookList extends BookRoute {
  const BookList();
}

final class BookDetail extends BookRoute {
  const BookDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class BookReviewsRoute extends BookRoute {
  const BookReviewsRoute(this.bookId);
  final String bookId;
  @override
  List<Object?> get props => [bookId];
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.blurb,
    required this.price,
  });

  final String id;
  final String title;
  final String author;
  final String blurb;
  final double price;
}

const _books = <Book>[
  Book(
    id: '1',
    title: 'The Pragmatic Programmer',
    author: 'Hunt & Thomas',
    blurb:
        'A foundational text on the craft of software engineering. Equal '
        'parts taste and technique.',
    price: 35.00,
  ),
  Book(
    id: '2',
    title: 'Design Patterns',
    author: 'Gang of Four',
    blurb:
        'The original catalogue of OO patterns. Reads like a reference now '
        'but the framing still holds.',
    price: 45.00,
  ),
  Book(
    id: '3',
    title: 'Refactoring',
    author: 'Martin Fowler',
    blurb:
        'A taxonomy of small structural transformations. The thing most '
        'IDEs are still slowly catching up to.',
    price: 40.00,
  ),
  Book(
    id: '4',
    title: 'Clean Code',
    author: 'Robert C. Martin',
    blurb:
        'Strongly opinionated. Disagree with half of it and you still come '
        'out a better engineer.',
    price: 30.00,
  ),
  Book(
    id: '5',
    title: 'Working Effectively with Legacy Code',
    author: 'Michael Feathers',
    blurb:
        'A field manual for the maintenance phase. The seam concept alone '
        'is worth the cover price.',
    price: 42.00,
  ),
];

const _reviews = <String, List<String>>{
  '1': [
    'Reread it every two years. Catches something new each time.',
    'Some idioms are dated but the mindset chapters age well.',
  ],
  '2': [
    'A reference, not a tutorial. Treat it as such.',
    'The Visitor chapter alone justified the price for me.',
  ],
  '3': ['Changed how I think about code shape. Hard to overstate.'],
  '4': [
    'Strong opinions, sometimes too strong. Take the principles, leave the '
        'religion.',
    'The function-length stuff is overblown but the naming chapter is gold.',
  ],
  '5': [
    'The only book that taught me to be brave with a legacy codebase.',
    'Characterisation tests are the unsung hero of this book.',
  ],
};

Book _bookById(String id) => _books.firstWhere((b) => b.id == id);

class BookListScreen extends StatelessWidget {
  const BookListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookshelf')),
      body: ListView.separated(
        itemCount: _books.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final book = _books[i];
          return ListTile(
            title: Text(book.title),
            subtitle: Text(book.author),
            trailing: Text('\$${book.price.toStringAsFixed(2)}'),
            onTap: () => _selectBook(context, book.id),
          );
        },
      ),
    );
  }
}

// Tapping a book in the list calls [pushOrReplaceTop] (new in
// v0.11). It pushes the new detail when there's no detail on top
// yet, and replaces the top entry when a detail is already there.
//
// - From `[BookList]`: stack becomes `[BookList, BookDetail(id)]`.
//   At narrow widths this slides in; at wide widths the absorbing
//   arm collapses the pair into a master-detail page.
//
// - From `[BookList, BookDetail(other)]`: stack stays at depth 2,
//   just swaps the top route. Both states key on BookList's entry
//   id, so the Navigator treats them as the same page and the
//   master-detail's detail pane updates in place without a slide.
//
// The default predicate "replace if current has the same runtime
// type as [route]" matches here, since every detail variant shares
// the `BookDetail` type. Pass an explicit `when:` for finer
// control.
void _selectBook(BuildContext context, String id) =>
    context.router<BookRoute>().pushOrReplaceTop(BookDetail(id));

class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final book = _bookById(id);
    // No AppBar.leading back arrow when this is rendered as the
    // only page in the rendered stack (i.e., absorbed inside the
    // master-detail frame at wide widths). v0.12's KaiselPageScope
    // exposes the page's navigation context to descendants. At
    // wide widths the BookDetail page absorbs BookList, so the
    // rendered Navigator has ONE page total and the scope reports
    // isBottom=true. At narrow widths the rendered stack is
    // [BookList, BookDetail], so BookDetail's scope reports
    // isBottom=false and we want the back arrow.
    final isOnlyPage = KaiselPageScope.maybeOf(context)?.isBottom ?? false;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isOnlyPage,
        title: Text(book.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.reviews_outlined),
            tooltip: 'Reviews',
            onPressed: () =>
                context.router<BookRoute>().push(BookReviewsRoute(book.id)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              book.author,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '\$${book.price.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            Text(book.blurb, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class EmptyDetailPane extends StatelessWidget {
  const EmptyDetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Select a book',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookReviewsScreen extends StatelessWidget {
  const BookReviewsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final book = _bookById(bookId);
    final reviews = _reviews[bookId] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text('Reviews · ${book.title}')),
      body: reviews.isEmpty
          ? const Center(child: Text('No reviews yet.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: reviews.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(reviews[i]),
              ),
            ),
    );
  }
}

class AdaptiveBookApp extends StatefulWidget {
  const AdaptiveBookApp({super.key});

  @override
  State<AdaptiveBookApp> createState() => _AdaptiveBookAppState();
}

class _AdaptiveBookAppState extends State<AdaptiveBookApp> {
  late final KaiselRouter<BookRoute> _router;
  late final KaiselRouterDelegate<BookRoute> _delegate;

  @override
  void initState() {
    super.initState();
    _router = KaiselRouter<BookRoute>(initial: const BookList());
    _delegate = KaiselRouterDelegate<BookRoute>.adaptive(
      router: _router,
      builder: (context, route, stack) {
        final wide = MediaQuery.sizeOf(context).width >= 700;
        return _buildPage(route, stack, wide: wide);
      },
    );
  }

  KaiselPageResult _buildPage(
    BookRoute route,
    KaiselStackContext<BookRoute> stack, {
    required bool wide,
  }) {
    return switch ((route, stack.previous, wide)) {
      // Wide + Detail with List below: absorb into master-detail.
      (BookDetail(:final id), BookList(), true) => KaiselAbsorbingPage(
        widget: KaiselMasterDetailScaffold(
          master: const BookListScreen(),
          detail: BookDetailScreen(id: id),
        ),
        absorbing: 1,
      ),

      // Wide + List alone: show the master-detail frame with a
      // "Select a book" placeholder on the right. Same page key as
      // the absorbing case, so transitioning between this and the
      // detail-selected state doesn't animate.
      (BookList(), _, true) => const KaiselStandalonePage(
        KaiselMasterDetailScaffold(
          master: BookListScreen(),
          detail: EmptyDetailPane(),
        ),
      ),

      // Narrow + Detail (or detail with something other than List
      // below it): standalone push. Back arrow shows.
      (BookDetail(:final id), _, _) => KaiselStandalonePage(
        BookDetailScreen(id: id),
      ),

      // Narrow + List: plain list.
      (BookList(), _, _) => const KaiselStandalonePage(BookListScreen()),

      // Reviews: always standalone on top, regardless of width. This
      // demonstrates that absorbing only applies to specific
      // (route, prev) pairs; routes outside the master-detail pair
      // still stack normally.
      (BookReviewsRoute(:final bookId), _, _) => KaiselStandalonePage(
        BookReviewsScreen(bookId: bookId),
      ),
    };
  }

  @override
  void dispose() {
    _delegate.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'kaisel adaptive demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF14141C),
        useMaterial3: true,
      ),
      routerDelegate: _delegate,
      routeInformationParser: _NoopParser(_router),
    );
  }
}

/// Parser that hands the router's current stack back so the
/// platform's initial route information doesn't clobber the demo's
/// in-memory state. The stack-diff in `applyFromInformation` becomes
/// a no-op when fed the current stack.
class _NoopParser extends RouteInformationParser<KaiselConfig<BookRoute>> {
  _NoopParser(this.router);

  final KaiselRouter<BookRoute> router;

  @override
  Future<KaiselConfig<BookRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => KaiselConfig<BookRoute>(mainStack: router.stack);
}

void main() {
  runApp(const AdaptiveBookApp());
}
