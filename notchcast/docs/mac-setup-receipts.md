# Mac Setup receipt engine

`MacSetupReceiptStore` journals opaque target values before any write. A transport must return
the exact stored bytes, use a stable target identifier, and interpret `nil` as absence (deletion
on restore). It must reject unsupported targets before calling Apply. Defaults domains, host
scopes, and privileged verbs must have distinct target identifiers.

All reads finish before the initial receipt is persisted. Each attempted write is journaled
first, including a write whose transport may mutate and then throw. Apply failure restores the
attempted prefix in reverse order. A failed restore retains the receipt; Undo can be retried
after relaunch. An outstanding receipt blocks another Apply. File persistence uses atomic
replacement; callers must supply a private bundle-scoped path with an existing parent folder.

The engine requires exclusive ownership of its journal and serialized access. A transport's
restore operation must be idempotent, including deletion of an already absent preference.

This WIP does not connect the engine to preset execution, the fork store, feature switches or
Settings. Mac Setup, AI-off and privacy remain unwired. No system changes are exercised by its
harness, `notchcast-mac-setup-receipt-test`.
