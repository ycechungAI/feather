const active = document.pictureInPictureElement
    || [...document.querySelectorAll('video')].find(v => v.webkitPresentationMode === 'picture-in-picture');
if (active) {
    if (document.pictureInPictureElement) await document.exitPictureInPicture();
    else active.webkitSetPresentationMode('inline');
    return 'exited';
}
