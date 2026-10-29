//! The bookmarks bar, read-only: the Swift build's `bookmarks.json`, top-level items as buttons,
//! folders as pop-up menus, and a » menu for whatever doesn't fit. No editing or drag and drop.

use std::cell::{Cell, OnceCell, RefCell};
use std::rc::Rc;

use objc2::rc::{Retained, Weak};
use objc2::runtime::AnyObject;
use objc2::{define_class, msg_send, sel, DefinedClass, MainThreadMarker, MainThreadOnly};
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSBezelStyle, NSBox, NSBoxType, NSButton, NSFont, NSImage, NSMenu, NSMenuItem,
    NSView,
};
use objc2_foundation::{
    ns_string, NSArray, NSData, NSDictionary, NSHomeDirectory, NSJSONReadingOptions, NSJSONSerialization,
    NSPoint, NSRect, NSSize, NSString,
};

use crate::Tab;

pub const BAR_HEIGHT: f64 = 28.0;
const MARGIN: f64 = 6.0;
const SPACING: f64 = 2.0;
const OVERFLOW_WIDTH: f64 = 24.0;

pub enum Node {
    Bookmark { title: String, url: String },
    Folder { title: String, children: Vec<Node> },
}

impl Node {
    fn title(&self) -> &str {
        match self {
            Node::Bookmark { title, .. } | Node::Folder { title, .. } => title,
        }
    }
}

thread_local! {
    /// Read once at launch; the prototype can't change bookmarks.
    static BOOKMARKS: OnceCell<Rc<Vec<Node>>> = const { OnceCell::new() };
}

fn bookmarks() -> Rc<Vec<Node>> {
    BOOKMARKS.with(|b| b.get_or_init(|| Rc::new(load())).clone())
}

/// `~/Library/Application Support/Feather/bookmarks.json` inside the sandbox container, in the
/// format of the Swift build's `BookmarkNode` (`{"kind": "bookmark"|"folder", ...}`).
fn load() -> Vec<Node> {
    let path = format!("{}/Library/Application Support/Feather/bookmarks.json", NSHomeDirectory());
    let Some(data) = NSData::dataWithContentsOfFile(&NSString::from_str(&path)) else { return Vec::new() };
    let options = NSJSONReadingOptions::empty();
    let Ok(json) = NSJSONSerialization::JSONObjectWithData_options_error(&data, options) else { return Vec::new() };
    nodes(&json)
}

fn nodes(list: &AnyObject) -> Vec<Node> {
    let Some(list) = list.downcast_ref::<NSArray>() else { return Vec::new() };
    list.iter().filter_map(|item| node(&item)).collect()
}

fn node(item: &AnyObject) -> Option<Node> {
    let kind = string(item, "kind")?;
    let body = field(item, &kind)?;
    let title = string(&body, "title").unwrap_or_default();
    match &*kind {
        "bookmark" => Some(Node::Bookmark { title, url: string(&body, "url")? }),
        "folder" => Some(Node::Folder { title, children: field(&body, "children").map(|c| nodes(&c)).unwrap_or_default() }),
        _ => None,
    }
}

fn field(object: &AnyObject, key: &str) -> Option<Retained<AnyObject>> {
    object.downcast_ref::<NSDictionary>()?.valueForKey(&NSString::from_str(key))
}

fn string(object: &AnyObject, key: &str) -> Option<String> {
    Some(field(object, key)?.downcast_ref::<NSString>()?.to_string())
}

/// Long titles are cut like the Swift bar's: 23 characters and "…".
fn short(title: &str) -> String {
    if title.chars().count() > 24 {
        title.chars().take(23).chain(std::iter::once('…')).collect()
    } else {
        title.into()
    }
}

pub struct BarIvars {
    tab: Weak<Tab>,
    nodes: Rc<Vec<Node>>,
    /// One button per top-level node, in order.
    buttons: OnceCell<Vec<Retained<NSButton>>>,
    overflow: OnceCell<Retained<NSButton>>,
    /// Index of the first node that didn't fit (its button is hidden).
    first_hidden: Cell<usize>,
    /// Menus open from the bar, kept alive while shown.
    menu: RefCell<Option<Retained<NSMenu>>>,
}

define_class!(
    #[unsafe(super(NSView))]
    #[thread_kind = MainThreadOnly]
    #[ivars = BarIvars]
    pub struct BookmarkBar;

    impl BookmarkBar {
        #[unsafe(method(setFrameSize:))]
        fn set_frame_size(&self, size: NSSize) {
            let _: () = unsafe { msg_send![super(self), setFrameSize: size] };
            self.relayout();
        }

        /// A top-level button: open the bookmark, or pop up the folder's menu.
        #[unsafe(method(clickItem:))]
        fn click_item(&self, sender: &NSButton) {
            let nodes = self.ivars().nodes.clone();
            match nodes.get(sender.tag() as usize) {
                Some(Node::Bookmark { url, .. }) => self.open(url),
                Some(Node::Folder { children, .. }) => self.pop_up(children, sender),
                None => {}
            }
        }

        #[unsafe(method(showOverflow:))]
        fn show_overflow(&self, sender: &NSButton) {
            let nodes = self.ivars().nodes.clone();
            self.pop_up(&nodes[self.ivars().first_hidden.get().min(nodes.len())..], sender);
        }

        #[unsafe(method(openMenuItem:))]
        fn open_menu_item(&self, sender: &NSMenuItem) {
            let url = sender.representedObject().and_then(|o| o.downcast::<NSString>().ok());
            if let Some(url) = url {
                self.open(&url.to_string());
            }
        }
    }
);

impl BookmarkBar {
    pub fn create(tab: &Tab, frame: NSRect) -> Retained<Self> {
        let mtm = MainThreadMarker::from(tab);
        let bar = mtm.alloc::<Self>().set_ivars(BarIvars {
            tab: Weak::new(tab),
            nodes: bookmarks(),
            buttons: OnceCell::new(),
            overflow: OnceCell::new(),
            first_hidden: Cell::new(usize::MAX),
            menu: RefCell::new(None),
        });
        let bar: Retained<Self> = unsafe { msg_send![super(bar), initWithFrame: frame] };
        bar.setAutoresizingMask(NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewMinYMargin);

        let font = NSFont::systemFontOfSize(12.0);
        let buttons: Vec<_> = bar
            .ivars()
            .nodes
            .iter()
            .enumerate()
            .map(|(i, node)| {
                let folder = matches!(node, Node::Folder { .. });
                let title = short(node.title()) + if folder { " ▾" } else { "" };
                let button = unsafe {
                    NSButton::buttonWithTitle_target_action(&NSString::from_str(&title), Some(&bar), Some(sel!(clickItem:)), mtm)
                };
                button.setBezelStyle(NSBezelStyle::Push);
                button.setBordered(false);
                button.setFont(Some(&font));
                button.setTag(i as isize);
                if let Node::Bookmark { title, url } = node {
                    button.setToolTip(Some(&NSString::from_str(&format!("{title}\n{url}"))));
                }
                button.sizeToFit();
                bar.addSubview(&button);
                button
            })
            .collect();
        let _ = bar.ivars().buttons.set(buttons);

        let image = NSImage::imageWithSystemSymbolName_accessibilityDescription(
            ns_string!("chevron.right.2"),
            Some(ns_string!("More Bookmarks")),
        )
        .expect("SF Symbol");
        let overflow = unsafe { NSButton::buttonWithImage_target_action(&image, Some(&bar), Some(sel!(showOverflow:)), mtm) };
        overflow.setBordered(false);
        overflow.setToolTip(Some(ns_string!("More bookmarks")));
        bar.addSubview(&overflow);
        let _ = bar.ivars().overflow.set(overflow);

        let line = NSBox::new(mtm);
        line.setBoxType(NSBoxType::Separator);
        line.setFrame(NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(frame.size.width, 1.0)));
        line.setAutoresizingMask(NSAutoresizingMaskOptions::ViewWidthSizable);
        bar.addSubview(&line);

        bar.relayout();
        bar
    }

    /// Lays the buttons out left to right and hides the ones that don't fit behind ».
    fn relayout(&self) {
        let (Some(buttons), Some(overflow)) = (self.ivars().buttons.get(), self.ivars().overflow.get()) else { return };
        let bounds = self.bounds();
        let center = |height: f64| ((bounds.size.height - height) / 2.0).max(0.0);
        let all: f64 = buttons.iter().map(|b| b.frame().size.width + SPACING).sum();
        let fits_all = MARGIN + all <= bounds.size.width - MARGIN;
        let limit = if fits_all { bounds.size.width - MARGIN } else { bounds.size.width - MARGIN - OVERFLOW_WIDTH - 4.0 };
        let mut x = MARGIN;
        let mut first_hidden = buttons.len();
        for (i, button) in buttons.iter().enumerate() {
            let size = button.frame().size;
            let visible = first_hidden == buttons.len() && x + size.width <= limit;
            if visible {
                button.setFrameOrigin(NSPoint::new(x, center(size.height)));
                x += size.width + SPACING;
            } else if first_hidden == buttons.len() {
                first_hidden = i;
            }
            button.setHidden(!visible);
        }
        if crate::probing() && first_hidden != self.ivars().first_hidden.get() {
            eprintln!("bookmarks: {} shown of {}, width {}", first_hidden, buttons.len(), bounds.size.width);
        }
        self.ivars().first_hidden.set(first_hidden);
        overflow.setHidden(first_hidden == buttons.len());
        overflow.setFrame(NSRect::new(
            NSPoint::new(bounds.size.width - MARGIN - OVERFLOW_WIDTH, center(20.0)),
            NSSize::new(OVERFLOW_WIDTH, 20.0),
        ));
    }

    fn open(&self, url: &str) {
        if let Some(tab) = self.ivars().tab.load() {
            tab.load(url);
        }
    }

    fn pop_up(&self, nodes: &[Node], under: &NSButton) {
        let menu = self.menu(nodes);
        menu.popUpMenuPositioningItem_atLocation_inView(None, NSPoint::new(0.0, under.bounds().size.height + 4.0), Some(under));
        *self.ivars().menu.borrow_mut() = Some(menu);
    }

    fn menu(&self, nodes: &[Node]) -> Retained<NSMenu> {
        let mtm = self.mtm();
        let menu = NSMenu::new(mtm);
        menu.setAutoenablesItems(false);
        for node in nodes {
            let item = NSMenuItem::new(mtm);
            item.setTitle(&NSString::from_str(&short(node.title())));
            match node {
                Node::Bookmark { url, .. } => {
                    unsafe {
                        item.setTarget(Some(self));
                        item.setAction(Some(sel!(openMenuItem:)));
                        item.setRepresentedObject(Some(&NSString::from_str(url)));
                    }
                    item.setToolTip(Some(&NSString::from_str(url)));
                }
                Node::Folder { children, .. } => item.setSubmenu(Some(&self.menu(children))),
            }
            menu.addItem(&item);
        }
        if nodes.is_empty() {
            let empty = NSMenuItem::new(mtm);
            empty.setTitle(ns_string!("Empty"));
            empty.setEnabled(false);
            menu.addItem(&empty);
        }
        menu
    }
}
