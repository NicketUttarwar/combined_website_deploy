/**
 * Portfolio pages only: tune image loading so below-the-fold lazy images stay low priority.
 * Uttarwar Art does not include this script.
 */
(function () {
  document.querySelectorAll('img.nav-logo-img').forEach((img) => {
    img.fetchPriority = 'high';
    if (!img.decoding) img.decoding = 'async';
  });
  document.querySelectorAll('img[loading="lazy"]').forEach((img) => {
    if (img.classList.contains('nav-logo-img')) return;
    img.fetchPriority = 'low';
    if (!img.decoding) img.decoding = 'async';
  });
})();
