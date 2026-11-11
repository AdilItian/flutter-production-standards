# Forms, Loading and Feedback

Read when: building any form, any async screen or action, or any success, error, info or warning message. Goal: the user sees the same pattern for the same situation everywhere in the app.

## Loading: one pattern per situation

| Situation | Pattern | Component |
|---|---|---|
| First load of a screen or list | **Skeleton** shaped like the content (spinner if the shape is unknown) | `AppSkeleton`, `AppLoader.page()` |
| Refresh (pull-to-refresh, retry with data present) | Keep the **old data visible**; show the refresh indicator only | `RefreshIndicator`, `skipLoadingOnRefresh` |
| Loading more (pagination) | Footer loader at the end of the list | `LoadMoreFooter` |
| Button-triggered action (submit, pay) | Spinner **inside the button**, button disabled, label kept for screen readers | `PrimaryButton(isLoading: true)` |
| Full-screen blocking operation (rare: payment confirm) | Modal progress with text, not dismissible, with a timeout path | `AppLoader.overlay()` |
| Background sync | A small non-blocking indicator or status chip | `SyncStatusChip` |
| Remote image loading or failure | Skeleton at the final size, fade-in; on failure a fallback with tap-to-retry | `AppNetworkImage` (`ui-guidelines.md`) |

Rules:
- All of these live in `design_system/components/feedback`. Features never use a bare `CircularProgressIndicator`.
- Don't flash: show a skeleton only if loading exceeds ~150 ms, and once shown keep it for at least ~300 ms (constants in `AppDurations`).
- Always give loading a way out: timeout then error with retry.
- Announce to screen readers when loading starts and finishes (`accessibility.md`).

## Toasts: minimal, black, text only

Success and error feedback looks like a native snackbar: a **black background with text only**. No icon, no title, no color per kind, no card, no emoji. The wording carries the meaning, so nothing depends on color alone (accessibility). One component, `AppToast`, is the only way to show one (`audit.sh` flags raw `SnackBar`, `showSnackBar`, `Get.snackbar` and toast packages in feature code).

| Property | Value |
|---|---|
| Background | `AppColors.toastBackground`: black in light theme; near-black (for example `#1C1C1E`) in dark theme so it stays distinct from a dark screen. Defined as a token, set in `SnackBarThemeData`. |
| Text | `AppColors.onToast` (white), theme `bodyMedium`, **max 2 lines**, ellipsis |
| Shape | Floating, small radius (`AppRadius.sm`), bottom, margin from `AppSpacing`, elevation 0 or low |
| Duration | success and info `AppDurations.toastShort` (~2.5 s), error `AppDurations.toast` (~4 s) |
| Action | Optional single **text** action (Undo, Retry) in the same color, no button chrome |
| Behavior | A new toast replaces the current one; never stacks; no close icon |
| Kinds | `success`, `error`, `info`: identical look, different default duration and the same screen-reader announcement. Kind exists for call-site clarity and analytics, not for color |

```dart
// design_system/components/feedback/app_toast.dart
abstract final class AppMessenger {
  /// Passed to GetMaterialApp/MaterialApp as scaffoldMessengerKey, so toasts need no BuildContext.
  static final GlobalKey<ScaffoldMessengerState> key = GlobalKey<ScaffoldMessengerState>();
}

abstract final class AppToast {
  static void success(String message, {String? actionLabel, VoidCallback? onAction}) =>
      _show(message, AppDurations.toastShort, actionLabel, onAction);
  static void info(String message, {String? actionLabel, VoidCallback? onAction}) =>
      _show(message, AppDurations.toastShort, actionLabel, onAction);
  static void error(String message, {String? actionLabel, VoidCallback? onAction}) =>
      _show(message, AppDurations.toast, actionLabel, onAction);

  static void _show(String message, Duration duration, String? actionLabel, VoidCallback? onAction) {
    AppMessenger.key.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          duration: duration,
          action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }
}

// In AppTheme: every visual property comes from the theme, not from the toast
snackBarTheme: SnackBarThemeData(
  behavior: SnackBarBehavior.floating,
  backgroundColor: AppColors.toastBackground,
  contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.onToast),
  actionTextColor: AppColors.onToast,
  showCloseIcon: false,
  elevation: AppElevation.none,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
),
```
`AppMessenger.key` requires the `scaffoldMessengerKey` parameter on the app widget (`MaterialApp` and `GetMaterialApp` both expose it; confirm in the installed version).

### Which feedback for which situation

| Situation | Feedback |
|---|---|
| A background or minor action succeeded (saved, copied, added) | Toast, optional Undo for reversible actions |
| An action failed and the user can try again | Toast with a Retry action, or inline error near the control |
| A change was saved offline and will sync | Toast: "Saved. Will sync when you're online." |
| A form submit succeeded and the flow is finished | Pop or navigate, then a toast on the destination |
| A major or irreversible result (order placed, payment completed, account created) | A dedicated **success screen** with a summary and a next action |
| Something needs a decision | Dialog |
| No data to show (first load failed, no cache) | `NoInternetView` / `ServerUnavailableView` / `ErrorView`, not a toast |

### Copy rules

- At most about 60 characters, sentence case, plain words. "Address saved", "Couldn't save. Try again.", "Added to watchlist", "Saved. Will sync when you're online."
- No "Error:" or "Success!" prefixes, no status codes, no technical terms, no exclamation spam, no emoji.
- Every message is an ARB key (`localization.md`); failure text comes from the failure-to-message mapping (`error-handling.md`).
- Trigger toasts from a listener on a one-shot event, never from `build` (`state-management.md`).
- Never claim success before the operation is confirmed (optimistic UI only with a rollback path).
- Repeated identical failures (a retry loop, many background syncs failing) show one toast, then only the chip. Never a toast storm.

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
- `AppToast`: uses the theme (black background, text only), max 2 lines, replaces the previous toast, optional action; no icon rendered.
