/**
 * Mobile nav: close drawer after following a link, Escape to dismiss, sync aria-expanded and scroll lock.
 */
(function () {
	var toggle = document.getElementById('nav-toggle');
	var panel = document.getElementById('site-nav-menu');
	var label = document.querySelector('label.nav-toggle[for="nav-toggle"]');
	if (!toggle || !panel) return;

	function syncAria() {
		if (label) label.setAttribute('aria-expanded', toggle.checked ? 'true' : 'false');
	}

	function syncScrollLock() {
		document.body.classList.toggle('nav-drawer-open', toggle.checked);
	}

	function closeNav() {
		toggle.checked = false;
		syncAria();
		syncScrollLock();
	}

	toggle.addEventListener('change', function () {
		syncAria();
		syncScrollLock();
	});
	syncAria();
	syncScrollLock();

	panel.querySelectorAll('a').forEach(function (link) {
		link.addEventListener('click', function () {
			if (window.matchMedia('(max-width: 768px)').matches) closeNav();
		});
	});

	document.addEventListener('keydown', function (e) {
		if (e.key !== 'Escape' || !toggle.checked) return;
		closeNav();
		if (label) label.focus();
	});
})();
