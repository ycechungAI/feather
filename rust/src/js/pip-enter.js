// Candidate videos: must have data and be visible.
let videos = [...document.querySelectorAll('video')]
    .filter(v => v.readyState > 0 && v.offsetWidth > 0 && v.offsetHeight > 0);
// On YouTube, prefer the main player video over ads/previews.
const ytVideo = document.querySelector('#movie_player video, .html5-main-video');
if (ytVideo && videos.includes(ytVideo)) {
    videos = [ytVideo, ...videos.filter(v => v !== ytVideo)];
}
const area = v => v.offsetWidth * v.offsetHeight;
const video = videos.find(v => !v.paused)
    || videos.sort((a, b) => area(b) - area(a))[0];
if (!video) return 'none';
// YouTube disables PiP on its video element; clear both the property and the attribute.
video.disablePictureInPicture = false;
video.removeAttribute('disablepictureinpicture');
let lastError = '';
if (typeof video.requestPictureInPicture === 'function') {
    try {
        await video.requestPictureInPicture();
        return 'entered';
    } catch (e) { lastError = e.message || String(e); }
} else {
    lastError = 'requestPictureInPicture not available';
}
try {
    if (video.webkitSupportsPresentationMode
        && video.webkitSupportsPresentationMode('picture-in-picture')) {
        video.webkitSetPresentationMode('picture-in-picture');
        return 'entered';
    }
    lastError += ' | webkit PiP not supported';
} catch (e) { lastError += ' | ' + (e.message || e); }
return 'error:' + lastError;
