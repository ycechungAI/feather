(() => {
  const desc = Object.getOwnPropertyDescriptor(HTMLVideoElement.prototype, 'disablePictureInPicture');
  if (desc && desc.configurable) {
    Object.defineProperty(HTMLVideoElement.prototype, 'disablePictureInPicture',
      { configurable: true, enumerable: desc.enumerable, get() { return false; }, set() {} });
  }
  const setAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (name, value) {
    if (this instanceof HTMLVideoElement && String(name).toLowerCase() === 'disablepictureinpicture') return;
    return setAttribute.call(this, name, value);
  };

  let wanted = null, swappedAt = 0;
  const swapped = () => { swappedAt = Date.now(); };
  document.addEventListener('emptied', swapped, true);
  document.addEventListener('loadstart', swapped, true);
  const changed = e => {
    const v = e.target;
    if (!(v instanceof HTMLVideoElement)) return;
    if (document.pictureInPictureElement === v || v.webkitPresentationMode === 'picture-in-picture') {
      wanted = v;
      return;
    }
    if (v !== wanted) return;
    const ad = document.querySelector('.html5-video-player.ad-showing');
    if (ad || Date.now() - swappedAt < 3000) {
      window.webkit?.messageHandlers?.featherPiP?.postMessage('restore');
    } else {
      wanted = null;
    }
  };
  document.addEventListener('webkitpresentationmodechanged', changed, true);
  document.addEventListener('enterpictureinpicture', changed, true);
  document.addEventListener('leavepictureinpicture', e => setTimeout(() => changed(e), 0), true);
})();
