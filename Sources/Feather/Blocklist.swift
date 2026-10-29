/// Built-in blocking data. Kept deliberately small; larger community lists can be dropped
/// into the blocklist folder (Shields ▸ Open Blocklist Folder) without rebuilding the app.
enum Blocklist {
    static let domains: [String] = [
        // Ad networks & exchanges
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "rubiconproject.com", "pubmatic.com",
        "openx.net", "casalemedia.com", "indexww.com", "criteo.com", "criteo.net", "taboola.com",
        "outbrain.com", "revcontent.com", "mgid.com", "zergnet.com", "media.net", "contextweb.com",
        "lijit.com", "sovrn.com", "33across.com", "3lift.com", "sharethrough.com", "teads.tv",
        "yieldmo.com", "gumgum.com", "undertone.com", "smartadserver.com", "adform.net",
        "bidswitch.net", "mathtag.com", "adroll.com", "advertising.com", "ads.yahoo.com",
        "popads.net", "popcash.net", "propellerads.com", "exoclick.com", "juicyads.com",
        "trafficjunky.net", "adcolony.com", "unityads.unity3d.com", "moatads.com",
        "adsafeprotected.com", "doubleverify.com", "zedo.com",
        // Trackers, analytics & data brokers
        "google-analytics.com", "googletagmanager.com", "app-measurement.com", "scorecardresearch.com",
        "quantserve.com", "imrworldwide.com", "chartbeat.com", "chartbeat.net", "hotjar.com",
        "mouseflow.com", "fullstory.com", "crazyegg.com", "clarity.ms", "bat.bing.com",
        "demdex.net", "omtrdc.net", "everesttech.net", "bluekai.com", "krxd.net", "exelator.com",
        "rlcdn.com", "agkn.com", "crwdcntrl.net", "liadm.com", "id5-sync.com", "tapad.com",
        "ads-twitter.com", "analytics.twitter.com", "ads.linkedin.com", "px.ads.linkedin.com",
        "analytics.tiktok.com", "ads.tiktok.com", "connect.facebook.net", "an.facebook.com",
        "nr-data.net", "hs-analytics.net",
    ]

    /// Path-level rules for first-party ad endpoints (WebKit regex: no `|` alternation).
    static let urlFilters: [String] = [
        "^https?://([^/]+\\.)?youtube\\.com/pagead/",
        "^https?://([^/]+\\.)?youtube\\.com/api/stats/ads",
        "^https?://([^/]+\\.)?youtube\\.com/ptracking",
        "^https?://([^/]+\\.)?youtube\\.com/get_midroll_",
        "^https?://([^/]+\\.)?facebook\\.com/tr[/?]",
        "^https?://([^/]+\\.)?google\\.com/pagead/",
    ]

    /// Blocked domains that specific sites need in order to work, as (domain, sites). Twitch's
    /// player reports each ad to Amazon's ad servers and fails with "Error #3000" when the ad
    /// ends if it can't; the ads themselves are part of the stream either way.
    static let siteExceptions: [(domain: String, sites: [String])] = [
        ("amazon-adsystem.com", ["twitch.tv"]),
    ]

    /// Hides leftover empty ad boxes.
    static let cosmeticSelectors: [String] = [
        ".adsbygoogle", "[id^='google_ads_iframe']", "[id^='div-gpt-ad']",
        ".ad-banner", ".ad-slot", "#ad-banner", ".advertisement",
    ]

    /// YouTube serves video ads from its own domain, so network rules alone can't stop them.
    /// This hides ad slots and fast-forwards/skip-clicks any video ad that still plays.
    /// It polls once a second and watches only the player element, to stay cheap.
    static let youtubeScript = #"""
    (() => {
      if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;
      const style = document.createElement('style');
      style.textContent = `
        ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer,
        ytd-statement-banner-renderer, ytd-display-ad-renderer, ytd-promoted-sparkles-web-renderer,
        ytd-player-legacy-desktop-watch-ads-renderer, ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],
        #player-ads, #masthead-ad, .ytp-ad-overlay-container, .ytp-featured-product,
        ytd-rich-item-renderer:has(ytd-ad-slot-renderer) { display: none !important; }`;
      (document.head || document.documentElement).appendChild(style);

      let watched = null, mutedByUs = false;
      const check = () => {
        const player = watched;
        const video = player && player.querySelector('video');
        if (!video) return;
        if (player.classList.contains('ad-showing')) {
          if (!video.muted) { video.muted = true; mutedByUs = true; }
          if (isFinite(video.duration) && video.duration > 0) video.currentTime = video.duration;
          const skip = player.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
          if (skip) skip.click();
        } else if (mutedByUs) {
          video.muted = false; mutedByUs = false;
        }
      };
      const observer = new MutationObserver(check);
      setInterval(() => {
        const player = document.querySelector('.html5-video-player');
        if (player && player !== watched) {
          observer.disconnect();
          watched = player;
          observer.observe(player, { attributes: true, attributeFilter: ['class'] });
        }
        check();
      }, 1000);
    })();
    """#
}
