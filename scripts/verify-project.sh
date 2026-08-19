#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

fail() {
    echo "Verification failed: $*" >&2
    exit 1
}

control_value() {
    sed -n "s/^$1:[[:space:]]*//p" control
}

package_id=$(control_value Package)
version=$(control_value Version)
architecture=$(control_value Architecture)

[ "$package_id" = "com.ssiswent.wcliquidglass" ] || fail "unexpected package id: $package_id"
[ -n "$version" ] || fail "control has no version"
[ "$architecture" = "iphoneos-arm64" ] || fail "unexpected architecture: $architecture"
scripts/release-version.sh --tag "$version" >/dev/null

for source_file in ./*.m ./*.xm ./*.c; do
    [ -f "$source_file" ] || continue
    source_name=${source_file#./}
    grep -Fq "$source_name" Makefile || fail "$source_name is missing from Makefile"
done

grep -Fq 'WCLiquidGlassStartCrashMarker' WCLiquidGlassCrashLogger.m || fail "fixed signal crash marker is missing"
grep -Fq 'NSSetUncaughtExceptionHandler(WCLiquidGlassHandleException)' WCLiquidGlassCrashLogger.m || fail "uncaught exception handler is missing"
grep -Fq 'enableCrashReporterAndReturnError' WCLiquidGlassCrashLogger.m || fail "PLCrashReporter enable path is missing"
grep -Fq 'installEarlyCrashCapture' WCLiquidGlassCrashLogger.h || fail "early crash capture API is missing"
if grep -Fq 'shouldRegisterUncaughtExceptionHandler:YES' WCLiquidGlassCrashLogger.m; then
    fail "PLCrashReporter must not own the process exception handler"
fi
custom_data_assignments=$(grep -c 'reporter.customData =' WCLiquidGlassCrashLogger.m || true)
[ "$custom_data_assignments" -eq 0 ] || fail "legacy PLCrashReporter customData path must remain disabled"
grep -Fq '@".failed"' WCLiquidGlassCrashLogger.m || fail "failed pending crash report isolation is missing"
early_logger_line=$(grep -nF '[WCLiquidGlassCrashLogger.sharedLogger installEarlyCrashCapture];' Tweak.xm | head -n 1 | cut -d: -f1)
preferences_line=$(grep -nF '[WCLiquidGlassPreferences registerDefaults];' Tweak.xm | head -n 1 | cut -d: -f1)
[ -n "$early_logger_line" ] || fail "early crash capture is missing"
[ -n "$preferences_line" ] || fail "preference registration is missing"
[ "$early_logger_line" -lt "$preferences_line" ] || fail "crash logger must start before preference registration"
if grep -Fq 'q7ar2wl2d3z44fwr25h2f2lx' WCLiquidGlassMenu.m; then
    fail "hardcoded WCGlass settings controller remains"
fi
for resolver_marker in \
    'WCLiquidGlassWCGlassControllerClassName' \
    'NSClassFromString(@"WCPluginsMgr")' \
    'NSSelectorFromString(@"sharedInstance")' \
    'NSSelectorFromString(@"plugins")' \
    'NSSelectorFromString(@"isController")' \
    'NSSelectorFromString(@"title")' \
    'NSSelectorFromString(@"controller")' \
    '@"WCGlass"'; do
    grep -Fq "$resolver_marker" WCLiquidGlassMenu.m || fail "WCGlass registry resolver marker is missing: $resolver_marker"
done
resolver_calls=$(grep -c 'WCLiquidGlassWCGlassControllerClassName()' WCLiquidGlassMenu.m || true)
[ "$resolver_calls" -ge 2 ] || fail "WCGlass registry resolver must be used by availability and execute paths"
grep -Fq 'WCLiquidGlassOpenControllerNamed(@[@"WCPluginsViewController"])' WCLiquidGlassMenu.m || fail "WCGlass plugin-list fallback is missing"
if grep -Fq 'purgePendingCrashReport' WCLiquidGlassCrashLogger.m; then
    fail "single-slot purgePendingCrashReport path remains"
fi
if grep -Eq 'WCGlassEntry|WCLiquidGlassCaptureWCGlassRegistration|WCLiquidGlassObserveWCGlassPluginListNavigation' Tweak.xm WCLiquidGlass*.h WCLiquidGlass*.m; then
    fail "temporary WCGlass entry diagnostics remain"
fi
grep -Fq 'WCLiquidGlassLayoutChatToolbarForInput(self);' Tweak.xm || fail "MMInputToolView per-input toolbar attach is missing"
grep -Fq '@interface WCLiquidGlassChatToolbarView' WCLiquidGlassMenu.m || fail "chat toolbar view definition is missing"
grep -Fq '@interface WCLiquidGlassToolbarButton : UIButton' WCLiquidGlassMenu.m || fail "chat toolbar must use native UIButton controls"
grep -Fq 'WCLiquidGlassChatToolbarButtonSide = 40.0' WCLiquidGlassMenu.m || fail "chat toolbar compact button size is missing"
grep -Fq 'WCLiquidGlassChatToolbarGap = 8.0' WCLiquidGlassMenu.m || fail "chat toolbar gap is missing"
grep -Fq 'WCLiquidGlassChatToolbarHorizontalMargin = 8.0' WCLiquidGlassMenu.m || fail "chat toolbar fixed horizontal margin is missing"
if grep -Eq 'WCLiquidGlassFindInputEdgeControls|WCLiquidGlassInputRowFrameForMountingView' WCLiquidGlassMenu.m; then
    fail "chat toolbar must not derive geometry from input row controls"
fi
grep -Fq '![actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]' WCLiquidGlassMenu.m || fail "chat toolbar must hide voice transcription"
grep -Fq '![actionIdentifier isEqualToString:WCLiquidGlassActionDoutuAssistant]' WCLiquidGlassMenu.m || fail "chat toolbar must hide doutu assistant"
if grep -Eq 'WCLiquidGlassToggleVoiceTranscription|WCLiquidGlassSharedVoiceTranscription|VoiceTranscriptionStateDidChangeNotification|WCLiquidGlassVoiceControlAssociationKey|WCLiquidGlassActiveChatInputToolView' WCLiquidGlassMenu.m; then
    fail "toolbar-specific shared voice transcription code remains"
fi
grep -Fq 'background.strokeWidth = 0.0' WCLiquidGlassMenu.m || fail "chat toolbar active icon must not add a border"
grep -Fq -- '- (void)updateToolViewHeight:(BOOL)animated' Tweak.xm || fail "MMInputToolView native height hook is missing"
grep -Fq -- '- (void)layoutSubviews' Tweak.xm || fail "MMInputToolView layout hook is missing"
grep -Fq -- '- (void)didMoveToWindow' Tweak.xm || fail "MMInputToolView window migration synchronization is missing"
grep -Fq -- '- (void)didMoveToSuperview' Tweak.xm || fail "MMInputToolView reparent synchronization is missing"
grep -Fq 'WCLiquidGlassChatToolbarEnabledKey' WCLiquidGlassPreferences.m || fail "chat toolbar preference definition is missing"
grep -Fq 'BOOL inputAvailable = WCLiquidGlassPreferences.enabled &&' WCLiquidGlassMenu.m || fail "chat toolbar master preference gate is missing"
grep -Fq 'WCLiquidGlassUpdateChatTableBottomInset' WCLiquidGlassMenu.m || fail "chat table bottom inset integration is missing"
grep -Fq 'WCLiquidGlassChatTableInsetForHost' WCLiquidGlassMenu.h || fail "chat table host inset composition API is missing"
grep -Fq '%hook MMTableView' Tweak.xm || fail "chat table inset hook is missing"
grep -Fq 'setScrollIndicatorInsets:(UIEdgeInsets)insets' Tweak.xm || fail "chat table scroll-indicator tracking is missing"
grep -Fq 'WCLiquidGlassChatTableInsetForHost(table, inset, NO)' Tweak.xm || fail "chat table content inset composition is missing"
grep -Fq 'WCLiquidGlassChatTableInsetForHost(table, insets, YES)' Tweak.xm || fail "chat table indicator inset composition is missing"
if grep -Eq 'setContentSize:\(CGSize\)size|setContentOffset:\(CGPoint\)offset|WCLiquidGlassChatTableDidMutate|WCLiquidGlassChatTableOffsetForInput|WCLiquidGlassReanchorChatTableForInput|WCLiquidGlassKeyboardTransitionActive|WCLiquidGlassKeyboardOffsetRepairDepth' Tweak.xm WCLiquidGlassMenu.h WCLiquidGlassMenu.m; then
    fail "chat table active offset/content-size correction remains"
fi
if grep -Fq 'UIScrollViewContentInsetAdjustmentNever' WCLiquidGlassMenu.m; then
    fail "chat table must not override UIKit inset adjustment behavior"
fi
grep -Fq 'verticalScrollIndicatorInsets' WCLiquidGlassMenu.m || fail "chat table indicator inset integration is missing"
if grep -Fq 'buttonsByAction' WCLiquidGlassMenu.m; then
    fail "chat toolbar still keys buttons by action"
fi
if grep -Fq '@interface WCLiquidGlassToolbarButton : UIControl' WCLiquidGlassMenu.m ||
   grep -Fq 'button.glassView.effect' WCLiquidGlassMenu.m; then
    fail "chat toolbar still nests custom glass buttons"
fi
if grep -Eq 'WCLiquidGlassCurrentChatInputToolFrames|chatToolbarRefreshQueued|chatToolbarSuppressed|wc_refreshChatToolbarAnimated|wc_scheduleChatToolbarLayoutAnimated|wc_layoutChatToolbarAnimated|beginChatToolbarAppearanceTransition|endChatToolbarAppearanceTransition|hideChatToolbarImmediately|resumeChatToolbarImmediately' Tweak.xm WCLiquidGlass*.h WCLiquidGlass*.m; then
    fail "obsolete global chat toolbar lifecycle remains"
fi
for runtime_file in Tweak.xm WCLiquidGlass*.h WCLiquidGlass*.m WCLiquidGlass*.xm; do
    [ -f "$runtime_file" ] || continue
    if grep -Fq 'fullCrashReportsEnabled' "$runtime_file" ||
       grep -Fq 'WCLiquidGlassFullCrashReportsEnabledKey' "$runtime_file"; then
        fail "obsolete full crash reports preference remains in $runtime_file"
    fi
done

plist_output=$(plutil -p WCLiquidGlass.plist)
printf '%s\n' "$plist_output" | grep -Fq '"com.tencent.xin"' || fail "main WeChat bundle is missing from filter plist"
printf '%s\n' "$plist_output" | grep -Fq '"com.tencent.xin.sharetimeline"' || fail "share timeline bundle is missing from filter plist"

package_file=${1:-}
if [ -n "$package_file" ]; then
    [ -f "$package_file" ] || fail "package not found: $package_file"
    archive_members=$(ar -t "$package_file")
    printf '%s\n' "$archive_members" | grep -Fxq 'control.tar.gz' || fail "package has no control archive"
    printf '%s\n' "$archive_members" | grep -Fxq 'data.tar.lzma' || fail "package has no data archive"

    packaged_control=$(ar -p "$package_file" control.tar.gz | tar -xzOf - ./control)
    printf '%s\n' "$packaged_control" | grep -Fxq "Package: $package_id" || fail "package id differs from control"
    printf '%s\n' "$packaged_control" | grep -Fxq "Version: $version" || fail "package version differs from control"
    printf '%s\n' "$packaged_control" | grep -Fxq "Architecture: $architecture" || fail "package architecture differs from control"

    data_members=$(ar -p "$package_file" data.tar.lzma | tar -tJf -)
    printf '%s\n' "$data_members" | grep -Fxq 'var/jb/Library/MobileSubstrate/DynamicLibraries/WCLiquidGlass.dylib' || fail "rootless dylib is missing"
    printf '%s\n' "$data_members" | grep -Fxq 'var/jb/Library/MobileSubstrate/DynamicLibraries/WCLiquidGlass.plist' || fail "filter plist is missing"
fi

echo "Verified WCLiquidGlass $version${package_file:+ and $(basename "$package_file")}"
