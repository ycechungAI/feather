//! Minimal Rust port of the Feather shell, to measure what the shell's language costs.
//! One window group of native macOS tabs, a toolbar, and WKWebView configured as in
//! `Sources/Feather/BrowserWindowController.swift` (`makeConfiguration`, `applyMemoryPreferences`).

use std::cell::{Cell, OnceCell, RefCell};

use block2::RcBlock;
use objc2::rc::{Allocated, Retained};
use objc2::runtime::{AnyObject, NSObject, NSObjectProtocol, ProtocolObject, Sel};
use objc2::{define_class, msg_send, sel, DefinedClass, MainThreadMarker, MainThreadOnly, Message};
use objc2_app_kit::{
    NSAlert, NSApplication, NSApplicationActivationPolicy, NSApplicationDelegate, NSAutoresizingMaskOptions,
    NSBackingStoreType, NSBezelStyle, NSButton, NSEventModifierFlags, NSImage, NSLineBreakMode, NSMenu,
    NSMenuItem, NSTextField, NSTextFieldBezelStyle, NSToolbar, NSToolbarDelegate, NSToolbarDisplayMode,
    NSToolbarFlexibleSpaceItemIdentifier, NSToolbarItem, NSToolbarItemVisibilityPriorityHigh, NSView, NSWindow,
    NSWindowDelegate, NSWindowOrderingMode, NSWindowStyleMask, NSWindowTabbingMode, NSWindowTitleVisibility,
    NSWindowToolbarStyle,
};
use objc2_foundation::{
    ns_string, NSArray, NSDictionary, NSError, NSKeyValueObservingOptions, NSNotification, NSNumber,
    NSObjectNSDelayedPerforming, NSObjectNSKeyValueCoding, NSObjectNSKeyValueObserverRegistration, NSPoint,
    NSProcessInfo, NSRect, NSSize, NSString, NSURLRequest, NSURL,
};
use objc2_web_kit::{
    WKContentRuleList, WKContentRuleListStore, WKContentWorld, WKNavigationAction, WKNavigationDelegate,
    WKPreferences, WKScriptMessage, WKScriptMessageHandler, WKUIDelegate, WKUserContentController, WKUserScript,
    WKUserScriptInjectionTime, WKWebView, WKWebViewConfiguration, WKWebsiteDataStore, WKWindowFeatures,
};

const HOME: &str = "https://www.google.com";
const SEARCH: &str = "https://www.google.com/search?q=";
const PIP_MESSAGE: &str = "featherPiP";

const PIP_KEEPER: &str = include_str!("js/pip-keeper.js");
const YOUTUBE: &str = include_str!("js/youtube.js");
const PIP_TOGGLE: &str = concat!(include_str!("js/pip-toggle.js"), include_str!("js/pip-enter.js"));
const DEBUG_PROBE: &str = "const v = document.querySelector('video'); \
    return v ? `t=${v.currentTime.toFixed(1)} paused=${v.paused} ${v.videoWidth}x${v.videoHeight} vis=${document.visibilityState} focus=${document.hasFocus()} ad=${!!document.querySelector('.ad-showing')}` : 'none';";
const PIP_RESTORE: &str = concat!(include_str!("js/pip-restore.js"), include_str!("js/pip-enter.js"));

thread_local! {
    /// Open tabs. A tab (and its window) lives until its window closes.
    static TABS: RefCell<Vec<Retained<Tab>>> = const { RefCell::new(Vec::new()) };
    /// The ad-blocking rules the Swift build already compiled into the shared container.
    static RULES: RefCell<Option<Retained<WKContentRuleList>>> = const { RefCell::new(None) };
    static PIP_HANDLER: OnceCell<Retained<PipKeeper>> = const { OnceCell::new() };
}

// MARK: App delegate

define_class!(
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    struct AppDelegate;

    unsafe impl NSObjectProtocol for AppDelegate {}

    unsafe impl NSApplicationDelegate for AppDelegate {
        #[unsafe(method(applicationDidFinishLaunching:))]
        fn did_finish_launching(&self, _: &NSNotification) {
            let mtm = self.mtm();
            let app = NSApplication::sharedApplication(mtm);
            app.setMainMenu(Some(&main_menu(mtm)));
            // Like Shields.prepare: look up the rules before the first tab opens.
            load_rules(mtm, move || {
                // `Feather https://example.com` from Terminal.
                let arg = std::env::args().skip(1).find(|a| !a.starts_with('-'));
                let url = arg.as_deref().map(resolve).unwrap_or_else(|| HOME.into());
                Tab::open(mtm, Some(&url), None, None);
            });
            #[allow(deprecated)]
            app.activateIgnoringOtherApps(true);
        }

        #[unsafe(method(applicationShouldTerminateAfterLastWindowClosed:))]
        fn should_terminate(&self, _: &NSApplication) -> bool {
            true
        }
    }
);

/// Finds the compiled `feather-*` rule list (no compiling here), then calls `done`.
fn load_rules(mtm: MainThreadMarker, done: impl Fn() + 'static) {
    let store = unsafe { WKContentRuleListStore::defaultStore(mtm) }.expect("rule store");
    let found = RcBlock::new(move |list: *mut WKContentRuleList, _: *mut NSError| {
        if let Some(list) = unsafe { Retained::retain(list) } {
            RULES.with(|r| *r.borrow_mut() = Some(list));
        }
        done();
    });
    let lookup = store.clone();
    let ids = RcBlock::new(move |ids: *mut NSArray<NSString>| {
        let id = unsafe { ids.as_ref() }
            .and_then(|ids| ids.iter().find(|id| id.to_string().starts_with("feather-")))
            .unwrap_or_else(|| ns_string!("feather-none").retain());
        unsafe { lookup.lookUpContentRuleListForIdentifier_completionHandler(Some(&id), Some(&found)) };
    });
    unsafe { store.getAvailableContentRuleListIdentifiers(Some(&ids)) };
}

fn main_menu(mtm: MainThreadMarker) -> Retained<NSMenu> {
    let bar = NSMenu::new(mtm);
    let add = |menu: &NSMenu, title: &str, action: Option<Sel>, key: &str| {
        let item = unsafe {
            NSMenuItem::initWithTitle_action_keyEquivalent(
                NSMenuItem::alloc(mtm),
                &NSString::from_str(title),
                action,
                &NSString::from_str(key),
            )
        };
        menu.addItem(&item);
        item
    };
    let submenu = |title: &str| {
        let menu = NSMenu::initWithTitle(NSMenu::alloc(mtm), &NSString::from_str(title));
        add(&bar, title, None, "").setSubmenu(Some(&menu));
        menu
    };
    let app = submenu("Feather");
    add(&app, "Quit Feather", Some(sel!(terminate:)), "q");
    let file = submenu("File");
    add(&file, "New Tab", Some(sel!(newWindowForTab:)), "t");
    add(&file, "Open Location", Some(sel!(focusAddress:)), "l");
    add(&file, "Close Tab", Some(sel!(performClose:)), "w");
    let edit = submenu("Edit");
    add(&edit, "Undo", Some(sel!(undo:)), "z");
    add(&edit, "Redo", Some(sel!(redo:)), "Z");
    add(&edit, "Cut", Some(sel!(cut:)), "x");
    add(&edit, "Copy", Some(sel!(copy:)), "c");
    add(&edit, "Paste", Some(sel!(paste:)), "v");
    add(&edit, "Select All", Some(sel!(selectAll:)), "a");
    let view = submenu("View");
    add(&view, "Reload", Some(sel!(reloadPage:)), "r");
    add(&view, "Back", Some(sel!(goBack:)), "[");
    add(&view, "Forward", Some(sel!(goForward:)), "]");
    let window = submenu("Window");
    add(&window, "Minimize", Some(sel!(performMiniaturize:)), "m");
    add(&window, "Show Next Tab", Some(sel!(selectNextTab:)), "}")
        .setKeyEquivalentModifierMask(NSEventModifierFlags::Command | NSEventModifierFlags::Shift);
    add(&window, "Show Previous Tab", Some(sel!(selectPreviousTab:)), "{")
        .setKeyEquivalentModifierMask(NSEventModifierFlags::Command | NSEventModifierFlags::Shift);
    NSApplication::sharedApplication(mtm).setWindowsMenu(Some(&window));
    bar
}

// MARK: Tab

struct TabIvars {
    window: OnceCell<Retained<NSWindow>>,
    web_view: OnceCell<Retained<WKWebView>>,
    address: OnceCell<Retained<NSTextField>>,
    /// Back, Forward, Reload, Home, PiP.
    buttons: OnceCell<[Retained<NSButton>; 5]>,
    /// PiP restore attempts in progress (0 = none).
    restoring_pip: Cell<u8>,
}

const OBSERVED: [&str; 4] = ["title", "URL", "canGoBack", "canGoForward"];

define_class!(
    /// One browser tab: a window in the native tab group, with its toolbar and web view.
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    #[ivars = TabIvars]
    struct Tab;

    impl Tab {
        #[unsafe(method(goBack:))]
        fn go_back(&self, _: Option<&AnyObject>) {
            unsafe { self.web_view().goBack() };
        }

        #[unsafe(method(goForward:))]
        fn go_forward(&self, _: Option<&AnyObject>) {
            unsafe { self.web_view().goForward() };
        }

        #[unsafe(method(reloadPage:))]
        fn reload_page(&self, _: Option<&AnyObject>) {
            let web_view = self.web_view();
            unsafe {
                if web_view.isLoading() {
                    web_view.stopLoading();
                } else {
                    web_view.reload();
                }
            }
        }

        #[unsafe(method(goHome:))]
        fn go_home(&self, _: Option<&AnyObject>) {
            self.load(HOME);
        }

        #[unsafe(method(focusAddress:))]
        fn focus_address(&self, _: Option<&AnyObject>) {
            let address = self.address();
            self.window().makeFirstResponder(Some(address));
            unsafe { address.selectText(None) };
        }

        #[unsafe(method(addressEntered:))]
        fn address_entered(&self, sender: &NSTextField) {
            let text = sender.stringValue().to_string();
            if !text.trim().is_empty() {
                self.load(&resolve(&text));
                self.window().makeFirstResponder(Some(self.web_view()));
            }
        }

        /// Picture in Picture for the page's main video, including YouTube's, which hides the
        /// built-in option. Unlike the Swift build this only looks in the main frame.
        #[unsafe(method(togglePictureInPicture:))]
        fn toggle_pip(&self, _: Option<&AnyObject>) {
            let tab = self.retain();
            self.call_js(PIP_TOGGLE, move |result| {
                let message = match result.as_deref() {
                    Some("none") => "No video found on this page. Start the video playing, then try again.",
                    Some(r) if r.starts_with("error:") => "This video can't play in Picture in Picture.",
                    None => "Picture in Picture didn't start.",
                    _ => return,
                };
                let alert = NSAlert::new(tab.mtm());
                alert.setMessageText(&NSString::from_str(message));
                alert.beginSheetModalForWindow_completionHandler(tab.window(), None);
            });
        }

        /// Reopens the floating window after a YouTube ad closed it, retrying while the video
        /// loads its next source.
        #[unsafe(method(restorePictureInPicture))]
        fn restore_pip(&self) {
            let tab = self.retain();
            self.call_js(PIP_RESTORE, move |result| {
                let attempt = tab.ivars().restoring_pip.get();
                if result.as_deref() == Some("entered") || attempt >= 5 {
                    tab.ivars().restoring_pip.set(0);
                } else {
                    tab.ivars().restoring_pip.set(attempt + 1);
                    unsafe { tab.performSelector_withObject_afterDelay(sel!(restorePictureInPicture), None, 1.0) };
                }
            });
        }

        /// FEATHER_PROBE=1: logs the page's video state every 10 seconds, to confirm playback.
        #[unsafe(method(debugProbe))]
        fn debug_probe(&self) {
            self.call_js(DEBUG_PROBE, |result| eprintln!("video: {}", result.unwrap_or_default()));
            unsafe { self.performSelector_withObject_afterDelay(sel!(debugProbe), None, 10.0) };
        }

        /// The tab bar's + button and ⌘T.
        #[unsafe(method(newWindowForTab:))]
        fn new_window_for_tab(&self, _: Option<&AnyObject>) {
            Tab::open(self.mtm(), Some(HOME), Some(self.window()), None);
        }

        #[unsafe(method(observeValueForKeyPath:ofObject:change:context:))]
        fn observe(
            &self,
            _: Option<&NSString>,
            _: Option<&AnyObject>,
            _: Option<&AnyObject>,
            _: *mut std::ffi::c_void,
        ) {
            self.refresh();
        }
    }

    unsafe impl NSObjectProtocol for Tab {}

    unsafe impl NSWindowDelegate for Tab {
        #[unsafe(method(windowWillClose:))]
        fn window_will_close(&self, _: &NSNotification) {
            let web_view = self.web_view();
            unsafe {
                for key in OBSERVED {
                    web_view.removeObserver_forKeyPath(self, &NSString::from_str(key));
                }
                web_view.configuration().userContentController().removeAllScriptMessageHandlers();
                web_view.setNavigationDelegate(None);
                web_view.setUIDelegate(None);
            }
            let me: *const Tab = self;
            TABS.with(|t| t.borrow_mut().retain(|tab| !std::ptr::eq(&**tab, me)));
        }
    }

    unsafe impl NSToolbarDelegate for Tab {
        #[unsafe(method_id(toolbarDefaultItemIdentifiers:))]
        fn default_items(&self, _: &NSToolbar) -> Retained<NSArray<NSString>> {
            toolbar_items()
        }

        #[unsafe(method_id(toolbarAllowedItemIdentifiers:))]
        fn allowed_items(&self, _: &NSToolbar) -> Retained<NSArray<NSString>> {
            toolbar_items()
        }

        #[unsafe(method_id(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:))]
        fn item(&self, _: &NSToolbar, id: &NSString, _: bool) -> Option<Retained<NSToolbarItem>> {
            self.toolbar_item(id)
        }
    }

    unsafe impl WKNavigationDelegate for Tab {}

    unsafe impl WKUIDelegate for Tab {
        /// Links that open a new window (target=_blank, window.open) open as a new tab.
        #[unsafe(method_id(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:))]
        fn create_web_view(
            &self,
            _: &WKWebView,
            config: &WKWebViewConfiguration,
            _: &WKNavigationAction,
            _: &WKWindowFeatures,
        ) -> Option<Retained<WKWebView>> {
            let tab = Tab::open(self.mtm(), None, Some(self.window()), Some(config));
            Some(tab.web_view().clone())
        }
    }
);

fn toolbar_items() -> Retained<NSArray<NSString>> {
    let flexible = unsafe { NSToolbarFlexibleSpaceItemIdentifier };
    NSArray::from_slice(&[
        ns_string!("back"),
        ns_string!("forward"),
        ns_string!("reload"),
        ns_string!("home"),
        ns_string!("pip"),
        flexible,
        ns_string!("address"),
        flexible,
    ])
}

impl Tab {
    fn open(
        mtm: MainThreadMarker,
        url: Option<&str>,
        host: Option<&NSWindow>,
        config: Option<&WKWebViewConfiguration>,
    ) -> Retained<Tab> {
        let window = unsafe {
            NSWindow::initWithContentRect_styleMask_backing_defer(
                NSWindow::alloc(mtm),
                NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(1280.0, 820.0)),
                NSWindowStyleMask::Titled
                    | NSWindowStyleMask::Closable
                    | NSWindowStyleMask::Miniaturizable
                    | NSWindowStyleMask::Resizable,
                NSBackingStoreType::Buffered,
                true,
            )
        };
        // The tab owns the window; AppKit must not release it a second time on close.
        unsafe { window.setReleasedWhenClosed(false) };
        window.setTabbingMode(NSWindowTabbingMode::Preferred);
        window.setTabbingIdentifier(ns_string!("feather"));
        window.setTitleVisibility(NSWindowTitleVisibility::Hidden);
        window.setFrameAutosaveName(ns_string!("FeatherWindow"));
        window.setMinSize(NSSize::new(480.0, 320.0));
        window.setTitle(ns_string!("New Tab"));

        let config = config.map(|c| c.retain()).unwrap_or_else(|| make_configuration(mtm));
        let web_view = unsafe {
            WKWebView::initWithFrame_configuration(WKWebView::alloc(mtm), window.contentLayoutRect(), &config)
        };
        web_view.setAutoresizingMask(
            NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewHeightSizable,
        );
        unsafe {
            web_view.setAllowsBackForwardNavigationGestures(true);
            web_view.setAllowsMagnification(true);
            // The Web Inspector can read page state, so only builds run with FEATHER_DEBUG=1 get it.
            let env = NSProcessInfo::processInfo().environment();
            web_view.setInspectable(env.objectForKey(ns_string!("FEATHER_DEBUG")).is_some());
        }
        window.setContentView(Some(&web_view));

        let tab = mtm.alloc::<Tab>().set_ivars(TabIvars {
            window: OnceCell::new(),
            web_view: OnceCell::new(),
            address: OnceCell::new(),
            buttons: OnceCell::new(),
            restoring_pip: Cell::new(0),
        });
        let tab: Retained<Tab> = unsafe { msg_send![super(tab), init] };
        let button = |symbol: &str, label: &str, action: Sel| {
            let image = NSImage::imageWithSystemSymbolName_accessibilityDescription(
                &NSString::from_str(symbol),
                Some(&NSString::from_str(label)),
            )
            .expect("SF Symbol");
            let b = unsafe { NSButton::buttonWithImage_target_action(&image, Some(&tab), Some(action), mtm) };
            b.setBezelStyle(NSBezelStyle::Toolbar);
            b.setBordered(false);
            b.setToolTip(Some(&NSString::from_str(label)));
            b
        };
        let buttons = [
            button("chevron.left", "Back", sel!(goBack:)),
            button("chevron.right", "Forward", sel!(goForward:)),
            button("arrow.clockwise", "Reload", sel!(reloadPage:)),
            button("house", "Home", sel!(goHome:)),
            button("pip.enter", "Picture in Picture", sel!(togglePictureInPicture:)),
        ];
        let address = NSTextField::new(mtm);
        address.setPlaceholderString(Some(ns_string!("Search or enter website")));
        address.setBezelStyle(NSTextFieldBezelStyle::RoundedBezel);
        address.setLineBreakMode(NSLineBreakMode::ByTruncatingTail);
        address.setUsesSingleLineMode(true);
        if let Some(cell) = address.cell() {
            cell.setScrollable(true);
        }
        unsafe {
            address.setTarget(Some(&tab));
            address.setAction(Some(sel!(addressEntered:)));
        }

        let ivars = tab.ivars();
        let _ = ivars.window.set(window.clone());
        let _ = ivars.web_view.set(web_view.clone());
        let _ = ivars.address.set(address);
        let _ = ivars.buttons.set(buttons);

        window.setDelegate(Some(ProtocolObject::from_ref(&*tab)));
        unsafe {
            web_view.setNavigationDelegate(Some(ProtocolObject::from_ref(&*tab)));
            web_view.setUIDelegate(Some(ProtocolObject::from_ref(&*tab)));
            for key in OBSERVED {
                web_view.addObserver_forKeyPath_options_context(
                    &tab,
                    &NSString::from_str(key),
                    NSKeyValueObservingOptions::empty(),
                    std::ptr::null_mut(),
                );
            }
        }
        let toolbar = NSToolbar::initWithIdentifier(NSToolbar::alloc(mtm), ns_string!("FeatherToolbar"));
        toolbar.setDelegate(Some(ProtocolObject::from_ref(&*tab)));
        toolbar.setDisplayMode(NSToolbarDisplayMode::IconOnly);
        toolbar.setAllowsUserCustomization(false);
        window.setToolbar(Some(&toolbar));
        window.setToolbarStyle(NSWindowToolbarStyle::Unified);

        TABS.with(|t| t.borrow_mut().push(tab.clone()));
        if let Some(host) = host {
            host.addTabbedWindow_ordered(&window, NSWindowOrderingMode::Above);
        }
        window.makeKeyAndOrderFront(None);
        if let Some(url) = url {
            tab.load(url);
        }
        if probing() {
            unsafe { tab.performSelector_withObject_afterDelay(sel!(debugProbe), None, 10.0) };
        }
        tab.refresh();
        tab
    }

    fn toolbar_item(&self, id: &NSString) -> Option<Retained<NSToolbarItem>> {
        let item = NSToolbarItem::initWithItemIdentifier(NSToolbarItem::alloc(self.mtm()), id);
        let buttons = self.ivars().buttons.get().unwrap();
        let (view, label): (&NSView, &str) = match &*id.to_string() {
            "back" => (&*buttons[0], "Back"),
            "forward" => (&*buttons[1], "Forward"),
            "reload" => (&*buttons[2], "Reload"),
            "home" => (&*buttons[3], "Home"),
            "pip" => (&*buttons[4], "Picture in Picture"),
            "address" => {
                let field = self.address();
                item.setVisibilityPriority(NSToolbarItemVisibilityPriorityHigh);
                // Centered and capped, shrinking with the window down to a compact minimum.
                let width = field.widthAnchor();
                width.constraintGreaterThanOrEqualToConstant(160.0).setActive(true);
                width.constraintLessThanOrEqualToConstant(560.0).setActive(true);
                let preferred = width.constraintEqualToConstant(560.0);
                preferred.setPriority(250.0);
                preferred.setActive(true);
                (field, "Address")
            }
            _ => return None,
        };
        item.setView(Some(view));
        item.setLabel(&NSString::from_str(label));
        Some(item)
    }

    fn window(&self) -> &NSWindow {
        self.ivars().window.get().unwrap()
    }

    fn web_view(&self) -> &Retained<WKWebView> {
        self.ivars().web_view.get().unwrap()
    }

    fn address(&self) -> &NSTextField {
        self.ivars().address.get().unwrap()
    }

    fn load(&self, url: &str) {
        if let Some(url) = NSURL::URLWithString(&NSString::from_str(url)) {
            unsafe { self.web_view().loadRequest(&NSURLRequest::requestWithURL(&url)) };
        }
    }

    /// Title, address and Back/Forward state, after the page changes any of them.
    fn refresh(&self) {
        let web_view = self.web_view();
        let url = unsafe { web_view.URL() };
        let title = unsafe { web_view.title() }.map(|t| t.to_string()).unwrap_or_default();
        let title = if title.is_empty() {
            url.as_ref().and_then(|u| u.host()).map(|h| h.to_string()).unwrap_or_else(|| "New Tab".into())
        } else {
            title
        };
        if probing() {
            let address = url.as_ref().and_then(|u| u.absoluteString()).map(|s| s.to_string());
            eprintln!("tab: {title} | {}", address.unwrap_or_default());
        }
        self.window().setTitle(&NSString::from_str(&title));
        // Don't overwrite what you're typing.
        let address = self.address();
        if address.currentEditor().is_none() {
            let text = url
                .as_ref()
                .and_then(|u| u.absoluteString())
                .map(|s| s.to_string())
                .filter(|s| !s.starts_with("about:"))
                .unwrap_or_default();
            address.setStringValue(&NSString::from_str(&text));
        }
        let buttons = self.ivars().buttons.get().unwrap();
        unsafe {
            buttons[0].setEnabled(web_view.canGoBack());
            buttons[1].setEnabled(web_view.canGoForward());
        }
    }

    /// Runs an async function body in the page's main frame; the callback gets a string result.
    fn call_js(&self, body: &str, done: impl Fn(Option<String>) + 'static) {
        let block = RcBlock::new(move |value: *mut AnyObject, error: *mut NSError| {
            if let Some(error) = unsafe { error.as_ref() } {
                if probing() {
                    let info = error.userInfo();
                    let message = info.objectForKey(ns_string!("WKJavaScriptExceptionMessage"));
                    eprintln!("script failed: {:?}", message.and_then(|m| m.downcast::<NSString>().ok()));
                }
            }
            let value = unsafe { value.as_ref() }
                .and_then(|v| v.downcast_ref::<NSString>())
                .map(|s| s.to_string());
            done(value);
        });
        unsafe {
            self.web_view().callAsyncJavaScript_arguments_inFrame_inContentWorld_completionHandler(
                &NSString::from_str(body),
                None,
                None,
                &WKContentWorld::pageWorld(self.mtm()),
                Some(&block),
            );
        }
    }
}

/// FEATHER_PROBE=1 logs tab titles, script errors and video state to stderr, for rust/measure.py.
fn probing() -> bool {
    std::env::var_os("FEATHER_PROBE").is_some()
}

// MARK: Web view configuration

/// The same choices as the Swift build's `makeConfiguration` for a normal (non-private) tab.
/// Not ported: extensions, per-site shield exceptions and the addons.mozilla.org script.
fn make_configuration(mtm: MainThreadMarker) -> Retained<WKWebViewConfiguration> {
    unsafe {
        let config = WKWebViewConfiguration::new(mtm);
        config.setWebsiteDataStore(&WKWebsiteDataStore::defaultDataStore(mtm));
        config.setApplicationNameForUserAgent(Some(&NSString::from_str(&user_agent_suffix())));
        let prefs = config.preferences();
        prefs.setFraudulentWebsiteWarningEnabled(true);
        prefs.setJavaScriptCanOpenWindowsAutomatically(false);
        prefs.setElementFullscreenEnabled(true);
        // WebKit keeps Picture in Picture off for apps unless this (non-public) preference is set.
        set_private_pref(&prefs, "allowsPictureInPictureMediaPlayback", true);
        config.setAllowsAirPlayForMediaPlayback(true);
        apply_memory_preferences(&prefs);

        let content = config.userContentController();
        let handler = PIP_HANDLER.with(|h| h.get_or_init(|| PipKeeper::create(mtm)).clone());
        content.addScriptMessageHandler_name(ProtocolObject::from_ref(&*handler), &NSString::from_str(PIP_MESSAGE));
        content.addUserScript(&user_script(mtm, PIP_KEEPER, WKUserScriptInjectionTime::AtDocumentStart, false));
        if let Some(rules) = RULES.with(|r| r.borrow().clone()) {
            content.addContentRuleList(&rules);
            content.addUserScript(&user_script(mtm, YOUTUBE, WKUserScriptInjectionTime::AtDocumentEnd, true));
        }
        config
    }
}

/// WebKit's (non-public) memory and power preferences, as in the Swift build's
/// `applyMemoryPreferences`.
fn apply_memory_preferences(prefs: &WKPreferences) {
    for (key, value) in [
        ("usesPageCache", false),
        ("lowPowerVideoAudioBufferSizeEnabled", true),
        ("hiddenPageDOMTimerThrottlingEnabled", true),
        ("hiddenPageDOMTimerThrottlingAutoIncreases", true),
        ("pageVisibilityBasedProcessSuppressionEnabled", true),
    ] {
        set_private_pref(prefs, key, value);
    }
}

/// Sets a preference through KVC, skipped when WebKit no longer has its `_set…:` setter.
fn set_private_pref(prefs: &WKPreferences, key: &str, value: bool) {
    let setter = format!("_set{}{}:", key[..1].to_uppercase(), &key[1..]);
    let setter = Sel::register(&std::ffi::CString::new(setter).unwrap());
    if prefs.respondsToSelector(setter) {
        unsafe { prefs.setValue_forKey(Some(&NSNumber::new_bool(value)), &NSString::from_str(key)) };
    }
}

fn user_script(
    mtm: MainThreadMarker,
    source: &str,
    time: WKUserScriptInjectionTime,
    main_frame_only: bool,
) -> Retained<WKUserScript> {
    unsafe {
        WKUserScript::initWithSource_injectionTime_forMainFrameOnly(
            WKUserScript::alloc(mtm),
            &NSString::from_str(source),
            time,
            main_frame_only,
        )
    }
}

/// Present as current Safari so sites (YouTube in particular) serve their full experience.
fn user_agent_suffix() -> String {
    #[allow(deprecated)]
    let plist = unsafe {
        NSDictionary::<NSString, AnyObject>::dictionaryWithContentsOfFile(ns_string!(
            "/Applications/Safari.app/Contents/Info.plist"
        ))
    };
    let version = plist
        .and_then(|p| p.objectForKey(ns_string!("CFBundleShortVersionString")))
        .and_then(|v| v.downcast::<NSString>().ok())
        .map(|v| v.to_string())
        .unwrap_or_else(|| "26.0".into());
    format!("Version/{version} Safari/605.1.15")
}

// MARK: PiP keeper

define_class!(
    /// Receives the page script's "restore" message when a YouTube ad closed the PiP window.
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    struct PipKeeper;

    unsafe impl NSObjectProtocol for PipKeeper {}

    unsafe impl WKScriptMessageHandler for PipKeeper {
        #[unsafe(method(userContentController:didReceiveScriptMessage:))]
        fn did_receive(&self, _: &WKUserContentController, message: &WKScriptMessage) {
            let Some(web_view) = (unsafe { message.webView() }) else { return };
            let tab = TABS.with(|t| t.borrow().iter().find(|t| **t.web_view() == *web_view).cloned());
            if let Some(tab) = tab {
                if tab.ivars().restoring_pip.get() == 0 {
                    tab.ivars().restoring_pip.set(1);
                    unsafe { tab.performSelector_withObject_afterDelay(sel!(restorePictureInPicture), None, 0.4) };
                }
            }
        }
    }
);

impl PipKeeper {
    fn create(mtm: MainThreadMarker) -> Retained<Self> {
        let this: Allocated<Self> = mtm.alloc();
        unsafe { msg_send![this, init] }
    }
}

// MARK: Address bar

/// Turns address-bar text into a URL: a full URL, a bare domain, or a Google search.
fn resolve(input: &str) -> String {
    let text = input.trim();
    let lower = text.to_lowercase();
    if ["http://", "https://", "file:", "about:"].iter().any(|p| lower.starts_with(p)) {
        return text.into();
    }
    if !text.contains(' ') {
        if lower.starts_with("localhost") || lower.starts_with("127.0.0.1") {
            return format!("http://{text}");
        }
        if text.contains('.') {
            return format!("https://{text}");
        }
    }
    let mut query = String::new();
    for b in text.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => query.push(b as char),
            b' ' => query.push('+'),
            _ => query.push_str(&format!("%{b:02X}")),
        }
    }
    format!("{SEARCH}{query}")
}

fn main() {
    let mtm = MainThreadMarker::new().expect("must run on the main thread");
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Regular);
    NSWindow::setAllowsAutomaticWindowTabbing(true, mtm);
    let delegate: Retained<AppDelegate> = unsafe { msg_send![mtm.alloc::<AppDelegate>(), init] };
    app.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
    app.run();
}
