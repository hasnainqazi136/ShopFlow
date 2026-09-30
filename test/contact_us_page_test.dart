import 'package:bagisto_flutter/features/account/presentation/bloc/contact_us_cubit.dart';
import 'package:bagisto_flutter/features/account/presentation/pages/contact_us_page.dart';
import 'package:bagisto_flutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('required contact fields are marked with an asterisk', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider(
            create: (_) => ContactUsCubit(),
            child: const ContactUsPage(),
          ),
        ),
      ),
    );

    for (final label in ['Name', 'Email', 'Contact', 'Message']) {
      expect(
        find.text('$label *', findRichText: true),
        findsOneWidget,
        reason: label,
      );
    }
  });
}
