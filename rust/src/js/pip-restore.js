if (document.pictureInPictureElement
    || [...document.querySelectorAll('video')].some(v => v.webkitPresentationMode === 'picture-in-picture')) {
    return 'entered';
}
