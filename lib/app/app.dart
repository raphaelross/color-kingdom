import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
	const App({super.key});

	@override
	Widget build(BuildContext context) {
		return ProviderScope(
			child: MaterialApp.router(
				title: 'Color Kingdom',
				debugShowCheckedModeBanner: false,
				theme: AppTheme.light,
				routerConfig: AppRouter.router,
			),
		);
	}
}
