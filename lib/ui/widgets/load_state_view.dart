import 'package:flutter/material.dart';

import '../load_state.dart';
import 'failure_view.dart';

/// Draws the four states of a [Loader] so screens do not each rewrite the
/// spinner, the error and the retry button.
///
/// The `switch` is exhaustive because LoadState is sealed: if a fifth state
/// ever appears, this stops compiling instead of silently rendering nothing.
class LoadStateView<T> extends StatelessWidget {
  const LoadStateView({
    super.key,
    required this.loader,
    required this.builder,
    this.onRetry,
  });

  final Loader<T> loader;
  final Widget Function(BuildContext context, T value) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loader,
      builder: (context, _) => switch (loader.state) {
        Idle<T>() || Loading<T>() =>
          const Center(child: CircularProgressIndicator()),
        Failed<T>(:final error) => FailureView(
            error: error,
            onRetry: onRetry ?? loader.load,
          ),
        Ready<T>(:final value) => builder(context, value),
      },
    );
  }
}
