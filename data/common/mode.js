// Adds a "Device mode" card to the page of the multi-mode firmware:
// switch the controller between BBQ and greenhouse. Each mode keeps its own settings.
(function () {
	var names = {bbq: 'BBQ / smoker', greenhouse: 'Greenhouse'};

	function post(mode) {
		return fetch('/mode', {
			method: 'POST',
			headers: {'Content-Type': 'application/x-www-form-urlencoded'},
			body: 'set=' + encodeURIComponent(mode)
		}).then(function (r) { return r.json(); });
	}

	// the controller restarts in the new mode; reload once it answers again
	function reloadWhenBack() {
		setTimeout(function check() {
			fetch('/info', {cache: 'no-store'})
				.then(function (r) { return r.ok ? location.reload() : setTimeout(check, 2000); })
				.catch(function () { setTimeout(check, 2000); });
		}, 4000);
	}

	function render(info) {
		var app = document.querySelector('.app');
		if (!app) { return; }
		var card = document.createElement('section');
		card.className = 'card';
		card.style.marginTop = '12px';
		card.innerHTML = '<h2>Device mode</h2>'
			+ '<p class="muted" style="margin:0 0 12px">This controller can run as a BBQ / smoker controller or as a greenhouse controller. '
			+ 'Each mode keeps its own settings. Switching restarts the controller.</p>'
			+ '<div class="chips" id="mode-choices"></div>';
		app.appendChild(card);
		var choices = card.querySelector('#mode-choices');
		info.modes.forEach(function (mode) {
			var button = document.createElement('button');
			button.className = mode == info.mode ? 'btn' : 'btn ghost';
			button.textContent = (names[mode] || mode) + (mode == info.mode ? ' (active)' : '');
			button.disabled = mode == info.mode;
			button.onclick = function () {
				if (!confirm('Restart the controller as ' + (names[mode] || mode) + '?')) { return; }
				post(mode).then(function () {
					button.textContent = 'Restarting…';
					reloadWhenBack();
				}).catch(function () { alert('Could not reach the controller'); });
			};
			choices.appendChild(button);
		});
	}

	fetch('/mode', {cache: 'no-store'})
		.then(function (r) { return r.ok ? r.json() : null; })
		.then(function (info) { if (info && info.modes) { render(info); } })
		.catch(function () {});
})();
