# RMA (Returns) Feature — Design

Date: 2026-09-03
API reference: https://api-docs.bagisto.com/api/graphql-api/shop/returns/

## Goal

Let a logged-in customer request returns/cancellations for eligible order items,
track their return requests, converse with the store, and act on a return
(cancel / reopen / mark solved) — using the Bagisto shop GraphQL Returns API,
following the app's existing account-feature architecture and UI standard.

## API surface used

Queries:
- `customerReturns(first, after, status)` — cursor-paginated list (Relay style)
- `customerReturn(id: ID!)` — IRI id `/api/shop/returns/{id}`
- `returnableItems(orderId: Int!)` — eligible items + qty caps
- `returnReasons(resolutionType: String!)` — `return` | `cancel_items`
- `customerReturnMessages(returnId: Int!)` — conversation thread

Mutations:
- `createCustomerReturn(input: {orderId, orderItemId, rmaQty, resolutionType, rmaReasonId, information?, packageCondition?, agreement})`
- `cancelCustomerReturn(id: ID!)` (IRI)
- `reopenCustomerReturn(input: {id})` (IRI)
- `closeCustomerReturn(input: {id})` (IRI)
- `createCustomerReturnMessage(input: {returnId, message})`

Out of scope (documented follow-up): image upload on create and message
attachments — the GraphQL API cannot transmit files; Bagisto exposes these only
via REST multipart endpoints.

## Architecture (mirrors orders feature)

New files:
- `lib/core/graphql/returns_queries.dart` — `ReturnsQueries`, raw query strings
  (own file; returns is its own API domain, keeps 1045-line `account_queries.dart` from growing)
- `lib/features/account/data/models/returns_models.dart` — `CustomerReturn`,
  `ReturnItemInfo`, `ReturnImage`, `ReturnableItem`, `ReturnReason`,
  `ReturnMessage`; hand-written defensive `fromJson`, no codegen, no Flutter imports
- `lib/features/account/presentation/bloc/returns_bloc.dart` — list bloc
  (events + state + bloc in one file, cursor pagination like `orders_bloc.dart`)
- `lib/features/account/presentation/bloc/return_detail_bloc.dart` — detail +
  messages + cancel/close/reopen/send-message
- `lib/features/account/presentation/bloc/create_return_bloc.dart` — form data
  (returnable items, reasons per resolution type) + submit
- `lib/features/account/presentation/pages/returns_page.dart` — list, mirrors `orders_page.dart`
- `lib/features/account/presentation/pages/return_detail_page.dart` — `static navigate`,
  status row, item card, info, images, message thread + composer, bottom action bar
- `lib/features/account/presentation/pages/create_return_page.dart` — `static navigate(orderId)`,
  item picker, resolution toggle, qty stepper, reason dropdown, package condition,
  info text, agreement checkbox, submit
- `test/returns_bloc_test.dart`, `test/returns_models_test.dart`

Modified files:
- `lib/features/account/data/repository/account_repository.dart` — returns API
  methods added to the account repository (house pattern: one repo per feature
  subtree, provided via `context.read<AccountRepository>()`)
- `lib/features/account/presentation/pages/account_menu_page.dart` — "Return Requests"
  menu item + `AccountMenuAction.returns` + navigation case
- `lib/l10n/app_*.arb` (all 10) + regenerated `lib/l10n/app_localizations*.dart`

Entry point (matches web storefront `customer/account/rma`, verified live
2026-09-03 against the demo): the "Create Request" action lives on the Returns
LIST page (app-bar `+` and an empty-state button), NOT on order detail. The
order-detail page has no RMA button. The create page is a two-step flow: pick an
order (order selector, backed by `getCustomerOrders`), then the item/resolution/
qty/reason form — mirroring the web `rma/create` → `get-order-items/{id}` →
`get-resolution-reasons/{type}` → `store` sequence.

Web RMA list columns (confirmed from the datagrid): RMA ID, Order Reference,
Request Status, Quantity, Created At. After a successful create the app opens
My Returns (fresh `customerReturns` load, newest-first) so the new request
appears in the list.

## Behavior decisions

- Status chip: use API-provided `statusColor` hex when parseable (bg = color
  at low alpha, text/border = color); fall back to the neutral chip style.
- Cancel button shown unless status is terminal
  (canceled/declined/solved/closed/rejected); Close shown when `canClose`;
  Reopen shown when `canReopen`. Cancel/Close confirm via AlertDialog.
- Messages displayed oldest→newest; composer at the bottom; customer bubbles
  right/primary, admin bubbles left/neutral.
- "Return Request" entry on every order detail; if the order has no eligible
  items the create page shows an empty state.
- Create form: single item selection (API accepts one `orderItemId` per
  request), qty capped by `forReturnQuantity` / `forCancelQuantity` depending
  on resolution; reasons re-fetched when resolution changes; agreement checkbox
  required; package condition + information optional.
- IRI ids: `/api/shop/returns/{numericId}` for view/cancel/close/reopen.
- Errors go through `ErrorMapper.getUserMessage`, thrown as `AccountException`,
  surfaced as red floating snackbars — same as orders.
