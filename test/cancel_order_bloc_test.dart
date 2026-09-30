import 'package:bagisto_flutter/features/account/data/models/account_models.dart';
import 'package:bagisto_flutter/features/account/data/repository/account_repository.dart';
import 'package:bagisto_flutter/features/account/presentation/bloc/order_detail_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

void main() {
  group('OrderDetail.canCancel', () {
    OrderDetail order(String status) =>
        OrderDetail(status: status, grandTotal: 0);

    test('is true for pending/processing, false otherwise', () {
      expect(order('pending').canCancel, true);
      expect(order('pending_payment').canCancel, true);
      expect(order('processing').canCancel, true);
      expect(order('completed').canCancel, false);
      expect(order('canceled').canCancel, false);
      expect(order('closed').canCancel, false);
    });
  });

  test('CancelOrder success emits cancelSuccess with refreshed order', () async {
    final repository = _FakeCancelRepository(
      result: (
        success: true,
        message: 'Order has been canceled successfully',
        orderId: 5,
        status: 'canceled',
      ),
      refreshed: OrderDetail(status: 'canceled', grandTotal: 0, numericId: 5),
    );
    final bloc = OrderDetailBloc(repository: repository);

    bloc.add(const CancelOrder(5));

    final state = await bloc.stream.firstWhere(
      (s) => s.status == OrderDetailStatus.cancelSuccess,
    );

    expect(state.successMessage, 'Order has been canceled successfully');
    expect(state.order?.status, 'canceled');
    expect(repository.canceledOrderIds, [5]);
    await bloc.close();
  });

  test('CancelOrder failure (success:false) emits error with message', () async {
    final repository = _FakeCancelRepository(
      result: (
        success: false,
        message: 'Order cannot be canceled',
        orderId: 5,
        status: 'processing',
      ),
      refreshed: OrderDetail(status: 'processing', grandTotal: 0),
    );
    final bloc = OrderDetailBloc(repository: repository);

    bloc.add(const CancelOrder(5));

    final state = await bloc.stream.firstWhere(
      (s) => s.status == OrderDetailStatus.error,
    );

    expect(state.errorMessage, 'Order cannot be canceled');
    await bloc.close();
  });
}

class _FakeCancelRepository extends AccountRepository {
  final ({bool success, String message, int orderId, String status}) result;
  final OrderDetail refreshed;
  final List<int> canceledOrderIds = [];

  _FakeCancelRepository({required this.result, required this.refreshed})
    : super(
        client: GraphQLClient(
          link: HttpLink('https://example.com/graphql'),
          cache: GraphQLCache(store: InMemoryStore()),
        ),
      );

  @override
  Future<({bool success, String message, int orderId, String status})>
  cancelOrder({required int orderId}) async {
    canceledOrderIds.add(orderId);
    return result;
  }

  @override
  Future<OrderDetail> getCustomerOrder(int orderId) async => refreshed;
}
