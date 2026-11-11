# Forms, Loading and Feedback

Read when: building any form, any async screen or action, or any success, error, info or warning message. Goal: the user sees the same pattern for the same situation everywhere in the app.

## Loading: one pattern per situation

| Situation | Pattern | Component |
|---|---|---|
| First load of a screen or list | **Skeleton** shaped like the content (spinner if the shape is unknown) | `AppSkeleton`, `LoadingView` |
| Refresh (pull-to-refresh, retry with data present) | Keep the **old data visible**; show the refresh indicator only | `RefreshIndicator`, `skipLoadingOnRefresh` |
| Loading more (pagination) | Footer loader at the end of the list | `LoadMoreFooter` |
| Button-triggered action (submit, pay) | Spinner **inside the button**, button disabled, label kept for screen readers | `PrimaryButton(isLoading: true)` |
| Full-screen blocking operation (rare: payment confirm) | Modal progress with text, not dismissible, with a timeout path | `showBlockingProgress` |
| Background sync | A small non-blocking indicator or status chip | `SyncStatusChip` |
| Remote image loading or failure | Skeleton at the final size, fade-in; on failure a fallback with tap-to-retry | `AppNetworkImage` (`ui-guidelines.md`) |

Rules:
- All of these live in `design_system/components/feedback`. Features never use a bare `CircularProgressIndicator`.
- Don't flash: show a skeleton only if loading exceeds ~150 ms, and once shown keep it for at least ~300 ms (constants in `AppDurations`).
- Always give loading a way out: timeout then error with retry.
- Announce to screen readers when loading starts and finishes (`accessibility.md`).

## Success feedback

Failures are typed, so successes get a consistent shape too. Pick by situation, never ad hoc:

| Situation | Feedback |
|---|---|
| A background or minor action succeeded (saved, copied, added to cart) | Snackbar, 4 s, optional **Undo** for reversible actions |
| A form submit succeeded and the user stays on the screen | Inline confirmation near the form, or snackbar |
| A form submit succeeded and the flow is finished (profile saved) | Pop or navigate back, then a snackbar on the destination |
| A major or irreversible result (order placed, payment completed, account created) | A dedicated **success screen** with a summary and a next action |
| Something happened that needs a decision | Dialog |

One helper, used everywhere:

```dart
enum FeedbackKind { success, error, info, warning }

abstract final class AppFeedback {
  static void show(
    BuildContext context, {
    required FeedbackKind kind,
    required String message, // always from context.l10n
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(kind.icon(context)),
            AppSpacing.gapSm,
            Expanded(child: Text(message)),
          ]),
          backgroundColor: kind.background(context), // from ColorScheme / AppColorsExtension
          duration: AppDurations.snackbar,
          action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }
}
```
(`icon` and `background` are extension methods on `FeedbackKind` in the same file, reading only theme roles.)

Rules:
- Messages are ARB keys, written as a result in plain words ("Address saved"), not "Success!".
- Success and error use the **same component**, so only the kind differs.
- Trigger feedback from a listener on a one-shot event, never from `build` (`state-management.md`).
- Error feedback follows `error-handling.md`; the failure-to-message mapping is the only source of error text.
- Snackbars are announced by screen readers; don't add a second announcement unless testing shows silence.
- Never claim success before the operation is confirmed (optimistic UI only with a rollback path).
- At most one snackbar at a time; a newer one replaces the older.

## Forms

State lives in the state holder, not scattered across widgets. Controllers for text input live in the widget (`StatefulWidget`), and values flow to the state holder on change.

### Validators

Pure functions returning a typed error, never an English string:

```dart
// core/utils/validators.dart
enum FieldError { required, invalidEmail, tooShort, tooLong, mismatch, invalidFormat }

abstract final class Validators {
  static FieldError? required(String? v) => (v == null || v.trim().isEmpty) ? FieldError.required : null;
  static FieldError? email(String? v) =>
      required(v) ?? (RegExp(AppLimits.emailPattern).hasMatch(v!.trim()) ? null : FieldError.invalidEmail);
  static FieldError? minLength(String? v, int min) => (v ?? '').length < min ? FieldError.tooShort : null;
}

// presentation: one exhaustive mapping to localized text
extension FieldErrorL10n on FieldError {
  String message(AppLocalizations l10n) => switch (this) {
        FieldError.required => l10n.validationRequired,
        FieldError.invalidEmail => l10n.validationEmail,
        FieldError.tooShort => l10n.validationTooShort,
        FieldError.tooLong => l10n.validationTooLong,
        FieldError.mismatch => l10n.validationMismatch,
        FieldError.invalidFormat => l10n.validationFormat,
      };
}
```
Limits and patterns (`emailPattern`, min lengths) are constants in `AppLimits`. Business rules that matter (age limit, allowed amount) belong in the domain layer, and the form calls them.

### Timing (the same on every form)

1. **Before the first interaction:** no errors.
2. **On leaving a field (blur):** validate that field.
3. **After a field shows an error:** re-validate on every change, so the error clears as soon as the input becomes valid.
4. **On submit:** validate all fields. If any is invalid, show all errors and **move focus to the first invalid field** (and announce the error).
5. **Server errors:** `ValidationFailure.fieldErrors` map to the matching fields. A server error on a field clears when the user edits that field.

### Submit button

Don't disable the submit button just because the form is invalid. A disabled button gives no explanation and screen-reader users can't discover the reason. Keep it enabled, show the errors on tap. Disable it **only while submitting** (`isLoading`).

### Other rules

- Visible labels, not placeholder-only. Correct `keyboardType`, `textInputAction`, `autofillHints`. Password fields use `PasswordField` with a visibility toggle and no suggestions or autocorrect.
- The form state is immutable, with a sealed submit status (idle, submitting, success, failure).
- **Async checks** (username taken, coupon valid): debounce (`AppDurations.debounce`), cancel stale calls, show a pending indicator on the field, and never block submit on them. The server stays the authority.
- Preserve input on failure. Never clear a form because a submit failed.
- Guard unsaved changes with `PopScope` and a confirm dialog.
- Multi-step forms keep their draft in the state holder (and in storage if the process may be killed).
- Use Flutter's `Form` + `AutovalidateMode.onUserInteraction` for simple one-off forms. Use the state-holder pattern when there are cross-field rules, server errors or async checks.

```dart
@immutable
class LoginFormState {
  const LoginFormState({this.email = '', this.password = '', this.errors = const {}, this.status = SubmitStatus.idle});
  final String email;
  final String password;
  final Map<LoginField, FieldError> errors;
  final SubmitStatus status;
}
enum LoginField { email, password }
enum SubmitStatus { idle, submitting, success, failure }
```

## Testing

- Validators: table-driven (empty, whitespace, boundary lengths, unicode).
- Form state holder: timing rules (no error before blur, error clears on valid change, all errors on submit, server field errors).
- Widgets: first invalid field receives focus; submit shows loading and then the result; errors have semantics.
- `AppFeedback`: right icon, color and text per kind; replaces the previous snackbar.
