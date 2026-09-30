# Review video attachments are stored with an unplayable extension

Reported: 2026-09-17
Server: `https://test-delivery.bagisto.com`
Affected API: `createProductReview` (`attachments` input)

## Summary

When a review attachment is uploaded as a Base64 data URI, the server builds
the stored file's extension from the MIME subtype. For `video/quicktime` this
produces a `.quicktime` file, and the web server then serves it without a
`Content-Type` header. iOS (AVFoundation) cannot open such a file, so the video
never plays in the mobile app.

## Steps to reproduce

1. Call `createProductReview` with an attachment such as
   `data:video/quicktime;base64,<bytes of a .mov recorded on an iPhone>`.
2. Approve the review, then query it:

   ```bash
   curl -s https://test-delivery.bagisto.com/api/graphql \
     -H 'Content-Type: application/json' \
     -H 'X-STOREFRONT-KEY: <storefront key>' \
     -d '{"query":"{ productReviews(first: 50) { edges { node { _id attachments } } } }"}'
   ```

   Review `2` returns:
   `https://test-delivery.bagisto.com/storage/review/2/6aabd0314b929.quicktime`

3. Inspect the file:

   ```bash
   curl -sI https://test-delivery.bagisto.com/storage/review/2/6aabd0314b929.quicktime
   ```

   Result: `HTTP/2 200`, `accept-ranges: bytes`, `content-length: 349477`, and
   **no `content-type` header**. Image attachments on the same server correctly
   return `content-type: image/png` / `image/jpeg`.

## Evidence

- The stored bytes are a valid QuickTime movie (`ftypqt` header).
- AVFoundation playability check on the same bytes:
  - `clip.quicktime` → `Cannot Open`
  - remote `.quicktime` URL → `Cannot Open`
  - `clip.mov` → playable
  - `clip.mp4` → playable

## Expected behaviour

Stored files use the standard extension for their MIME type and are served with
the matching `Content-Type`:

| MIME type | Expected extension |
|---|---|
| `video/quicktime` | `.mov` |
| `video/x-m4v` | `.m4v` |
| `video/x-matroska` | `.mkv` |
| `video/3gpp` | `.3gp` |

A MIME-to-extension map (for example Symfony's `MimeTypes::getExtensions()`)
avoids deriving the extension from the subtype string.

## Current app workaround

The mobile app now uploads `.mov` and `.m4v` files as `video/mp4`, so they are
stored as `.mp4` and play on iOS. Files already stored with a `.quicktime`
extension (such as review `2`) stay unplayable until they are renamed on the
server or re-uploaded. The workaround can be removed once the backend fix ships.
