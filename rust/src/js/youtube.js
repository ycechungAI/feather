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
