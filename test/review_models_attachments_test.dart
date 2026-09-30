import 'package:bagisto_flutter/core/graphql/account_queries.dart';
import 'package:bagisto_flutter/core/graphql/queries.dart';
import 'package:bagisto_flutter/features/account/data/models/account_models.dart'
    as account;
import 'package:bagisto_flutter/features/account/data/models/review_attachment.dart';
import 'package:bagisto_flutter/features/category/data/models/product_model.dart'
    as category;
import 'package:flutter_test/flutter_test.dart';

const _raw =
    '[{"type":"image","url":"https://x.test/p.webp"},{"type":"video","url":"https://x.test/v.mp4"}]';

void main() {
  test('account ProductReview parses attachments', () {
    final review = account.ProductReview.fromJson({
      'id': '/api/shop/reviews/1',
      'name': 'Ann',
      'title': 'Nice',
      'rating': 5,
      'comment': 'Good',
      'attachments': _raw,
    });

    expect(review.attachments, hasLength(2));
    expect(review.attachments.last.type, ReviewAttachmentType.video);
  });

  test('account ProductReview defaults to no attachments', () {
    final review = account.ProductReview.fromJson({
      'name': 'Ann',
      'title': 'Nice',
      'rating': 5,
      'comment': 'Good',
    });

    expect(review.attachments, isEmpty);
    expect(
      const account.ProductReview(
        name: 'a',
        title: 'b',
        rating: 1,
        comment: 'c',
      ).attachments,
      isEmpty,
    );
  });

  test('category ProductReview parses attachments', () {
    final review = category.ProductReview.fromJson({
      'id': '1',
      'rating': 4,
      'attachments': _raw,
    });

    expect(review.attachments.map((a) => a.url), [
      'https://x.test/p.webp',
      'https://x.test/v.mp4',
    ]);
  });

  test('review queries request attachments', () {
    expect(AccountQueries.createProductReview, contains('attachments'));
    expect(AccountQueries.getProductReviews, contains('attachments'));
    // CustomerReview has no attachments field on the server.
    expect(AccountQueries.getCustomerReviews, isNot(contains('attachments')));
    expect(
      ProductQueries.getProductByUrlKeyByType(null),
      contains('attachments'),
    );
    expect(ProductQueries.getProductByUrlKey, contains('attachments'));
    expect(ProductQueries.getProductById, contains('attachments'));
  });

  test('product detail queries read the product own reviews', () {
    // approvedReviews ignores the product on the server and returns every
    // approved review in the store, so the product's own reviews are used.
    final detailQueries = [
      ProductQueries.getProductByUrlKeyByType(null),
      ProductQueries.getProductByUrlKey,
      ProductQueries.getProductById,
    ];
    for (final query in detailQueries) {
      expect(query, matches(RegExp(r'\breviews\s*\{')));
      expect(query, isNot(contains('approvedReviews')));
    }
  });
}
