# Shop `categories` query returns categories disabled in admin

Reported: 2026-09-17
Server: `https://test-delivery.bagisto.com`
Affected API: Shop GraphQL `categories`

## Summary

Categories disabled in the admin panel are still returned by the shop
`categories` query. The `treeCategories` query filters them out correctly, so
the two queries disagree.

## Steps to reproduce

1. In admin, disable a category (all categories were disabled on the test
   server at the time of this report).
2. Run:

   ```bash
   curl -s https://test-delivery.bagisto.com/api/graphql \
     -H 'Content-Type: application/json' \
     -H 'X-STOREFRONT-KEY: <storefront key>' \
     -d '{"query":"{ categories { edges { node { _id status translation { name } } } } treeCategories { _id status } }"}'
   ```

## Actual result

- `categories` returns every category, each with `"status": "0"`
  (Root, Men, Winter Wear, bangles, books, bottles).
- `treeCategories` returns `[]`.

## Expected result

Shop (storefront) queries return only active categories. `categories` should
filter by `status = 1`, the same as `treeCategories`.

## Current app workaround

The mobile app now requests `status` in its `categories` query and hides
categories whose status is not active (home carousel and search). It also
filters `treeCategories` results and their children, in case that behaviour
changes.
