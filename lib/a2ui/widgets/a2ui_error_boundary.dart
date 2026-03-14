import 'package:flutter/material.dart';

/// An error boundary widget that catches exceptions thrown during the build
/// phase of its child widget tree and displays a graceful fallback instead
/// of a red error screen.
///
/// This is used to isolate A2UI rendering failures so they don't crash
/// the entire chat application.
class A2uiErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, Object error) fallbackBuilder;

  const A2uiErrorBoundary({
    required this.child,
    required this.fallbackBuilder,
    super.key,
  });

  @override
  State<A2uiErrorBoundary> createState() => _A2uiErrorBoundaryState();
}

class _A2uiErrorBoundaryState extends State<A2uiErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallbackBuilder(context, _error!);
    }

    // Wrap child in a Builder + ErrorWidget.builder override to catch
    // build-phase errors without the red screen.
    return _ErrorCatcher(
      onError: (error) {
        // Schedule the setState for after the current build frame completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _error = error);
          }
        });
      },
      child: widget.child,
    );
  }
}

/// Internal widget that uses a custom [ErrorWidget.builder] scoped to this
/// subtree to intercept build errors.
class _ErrorCatcher extends StatelessWidget {
  final Widget child;
  final void Function(Object error) onError;

  const _ErrorCatcher({required this.child, required this.onError});

  @override
  Widget build(BuildContext context) {
    // Save and restore the global error builder
    final originalBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      onError(details.exception);
      // Return a minimal placeholder so the framework doesn't crash
      return const SizedBox.shrink();
    };

    // Build the child and immediately restore the builder
    final result = Builder(builder: (context) {
      // Restore immediately — the builder override only needs to be active
      // for this one build pass
      ErrorWidget.builder = originalBuilder;
      return child;
    });

    return result;
  }
}
