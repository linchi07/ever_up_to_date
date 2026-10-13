import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EverUpToDate singleton lifecycle integration test', (WidgetTester tester) async {
    final updater = EverUpToDate.instance;
    expect(updater.currentState, isA<UpdateIdleState>());

    updater.initialize(
      const UpdateOptions(
        manifestUrl: 'https://example.com/appcast.json',
      ),
    );
    expect(updater.currentState, isA<UpdateIdleState>());
  });
}
