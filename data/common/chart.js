// Small offline replacement for the Highcharts line chart.
// Keeps the same API that index.html uses:
//   chartT.series[i].data.length
//   chartT.series[i].addPoint([x, y], redraw, shift)
// so the page works on the soft-AP network without internet.

function MiniChart(options) {
	var self = this;
	this.container = document.getElementById(options.chart.renderTo);
	this.background = options.chart.backgroundColor || '#808080';
	this.textColor = options.chart.textColor || '#ffffff';
	this.gridColor = options.chart.gridColor || 'rgba(255,255,255,0.25)';
	if (options.chart.height) { this.heightOption = options.chart.height; }
	this.title = options.title.text;
	this.yTitle = options.yAxis.title.text;
	this.valueSuffix = (options.tooltip && options.tooltip.valueSuffix) || '';
	this.height = this.heightOption || 400;
	this.hoverIndex = -1;
	this.hoverX = null;

	this.canvas = document.createElement('canvas');
	this.canvas.style.display = 'block';
	this.canvas.style.width = '100%';
	this.canvas.style.height = this.height + 'px';
	this.container.appendChild(this.canvas);
	this.ctx = this.canvas.getContext('2d');

	this.series = options.series.map(function (s, index) {
		return {
			name: s.name,
			color: s.color,
			visible: true,
			data: [],
			addPoint: function (point, redraw, shift) {
				this.data.push(point);
				if (shift) {
					this.data.shift();
				}
				if (redraw !== false) {
					self.redraw();
				}
			}
		};
	});

	this.canvas.addEventListener('mousemove', function (e) { self.onHover(e.clientX); });
	this.canvas.addEventListener('touchstart', function (e) { self.onHover(e.touches[0].clientX); }, {passive: true});
	this.canvas.addEventListener('touchmove', function (e) { self.onHover(e.touches[0].clientX); }, {passive: true});
	this.canvas.addEventListener('mouseleave', function () { self.hoverX = null; self.redraw(); });
	this.canvas.addEventListener('click', function (e) { self.onClick(e); });
	window.addEventListener('resize', function () { self.redraw(); });
	this.redraw();
}

MiniChart.prototype.pad2 = function (n) {
	return (n < 10 ? '0' : '') + n;
};

MiniChart.prototype.formatTime = function (t) {
	var d = new Date(t);
	return this.pad2(d.getHours()) + ':' + this.pad2(d.getMinutes()) + ':' + this.pad2(d.getSeconds());
};

// picks a "nice" step (1, 2, 5 x 10^n) for the y axis
MiniChart.prototype.niceStep = function (range, ticks) {
	var raw = range / ticks;
	var power = Math.pow(10, Math.floor(Math.log10(raw)));
	var steps = [1, 2, 5, 10];
	for (var i = 0; i < steps.length; i++) {
		if (raw <= steps[i] * power) {
			return steps[i] * power;
		}
	}
	return 10 * power;
};

MiniChart.prototype.onHover = function (clientX) {
	var rect = this.canvas.getBoundingClientRect();
	this.hoverX = clientX - rect.left;
	this.redraw();
};

// clicking a legend item hides/shows that series, like Highcharts
MiniChart.prototype.onClick = function (e) {
	var rect = this.canvas.getBoundingClientRect();
	var x = e.clientX - rect.left;
	var y = e.clientY - rect.top;
	for (var i = 0; i < this.legendBoxes.length; i++) {
		var b = this.legendBoxes[i];
		if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
			this.series[i].visible = !this.series[i].visible;
			this.redraw();
			return;
		}
	}
};

MiniChart.prototype.redraw = function () {
	var ratio = window.devicePixelRatio || 1;
	var width = this.container.clientWidth || 300;
	var height = this.height;
	if (this.canvas.width !== Math.round(width * ratio) || this.canvas.height !== Math.round(height * ratio)) {
		this.canvas.width = Math.round(width * ratio);
		this.canvas.height = Math.round(height * ratio);
	}
	var ctx = this.ctx;
	ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
	ctx.clearRect(0, 0, width, height);
	if (this.background !== 'transparent') {
		ctx.fillStyle = this.background;
		ctx.fillRect(0, 0, width, height);
	}
	ctx.font = '12px Arial';
	ctx.textBaseline = 'middle';

	// title
	ctx.fillStyle = this.textColor;
	ctx.textAlign = 'center';
	ctx.font = '18px Arial';
	if (this.title) {
		ctx.fillText(this.title, width / 2, 22);
	}
	ctx.font = '12px Arial';

	// legend (bottom)
	this.legendBoxes = [];
	var legendWidth = 0;
	var items = [];
	for (var i = 0; i < this.series.length; i++) {
		var w = 20 + ctx.measureText(this.series[i].name).width + 16;
		items.push(w);
		legendWidth += w;
	}
	var lx = Math.max(4, (width - legendWidth) / 2);
	var ly = height - 16;
	for (var i = 0; i < this.series.length; i++) {
		var s = this.series[i];
		ctx.globalAlpha = s.visible ? 1 : 0.35;
		ctx.strokeStyle = s.color;
		ctx.lineWidth = 2;
		ctx.beginPath();
		ctx.moveTo(lx, ly);
		ctx.lineTo(lx + 14, ly);
		ctx.stroke();
		ctx.fillStyle = this.textColor;
		ctx.globalAlpha = s.visible ? 1 : 0.4;
		ctx.textAlign = 'left';
		ctx.fillText(s.name, lx + 18, ly);
		this.legendBoxes.push({x: lx, y: ly - 9, w: items[i] - 8, h: 18});
		lx += items[i];
	}
	ctx.globalAlpha = 1;

	// data range
	var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
	this.series.forEach(function (s) {
		if (!s.visible) { return; }
		s.data.forEach(function (p) {
			if (p[0] < minX) { minX = p[0]; }
			if (p[0] > maxX) { maxX = p[0]; }
			if (p[1] < minY) { minY = p[1]; }
			if (p[1] > maxY) { maxY = p[1]; }
		});
	});
	var hasData = minX !== Infinity;
	if (!hasData) {
		var now = Date.now();
		minX = now - 60000; maxX = now; minY = 0; maxY = 100;
	}
	if (maxX === minX) { minX -= 30000; maxX += 30000; }
	if (maxY === minY) { minY -= 5; maxY += 5; }
	var step = this.niceStep(maxY - minY, 5);
	minY = Math.floor(minY / step) * step;
	maxY = Math.ceil(maxY / step) * step;

	// plot area
	var left = 62, right = width - 14, top = this.title ? 44 : 16, bottom = height - 58;
	var plotW = Math.max(10, right - left), plotH = Math.max(10, bottom - top);
	function px(x) { return left + (x - minX) / (maxX - minX) * plotW; }
	function py(y) { return bottom - (y - minY) / (maxY - minY) * plotH; }

	// y grid + labels
	ctx.textAlign = 'right';
	ctx.strokeStyle = this.gridColor;
	ctx.lineWidth = 1;
	for (var v = minY; v <= maxY + step / 2; v += step) {
		var y = Math.round(py(v)) + 0.5;
		ctx.beginPath();
		ctx.moveTo(left, y);
		ctx.lineTo(right, y);
		ctx.stroke();
		ctx.fillStyle = this.textColor;
		ctx.fillText(+v.toFixed(2), left - 6, y);
	}
	// y title
	ctx.save();
	ctx.translate(14, top + plotH / 2);
	ctx.rotate(-Math.PI / 2);
	ctx.textAlign = 'center';
	ctx.fillText(this.yTitle, 0, 0);
	ctx.restore();

	// x labels
	var xTicks = Math.max(2, Math.floor(plotW / 90));
	for (var t = 0; t <= xTicks; t++) {
		var xv = minX + (maxX - minX) * t / xTicks;
		// keep the last label inside the canvas
		ctx.textAlign = t === xTicks ? 'right' : 'center';
		ctx.fillText(this.formatTime(xv), t === xTicks ? width - 4 : px(xv), bottom + 14);
	}
	ctx.textAlign = 'center';
	ctx.strokeStyle = this.gridColor;
	ctx.beginPath();
	ctx.moveTo(left, bottom + 0.5);
	ctx.lineTo(right, bottom + 0.5);
	ctx.stroke();

	if (!hasData) {
		return;
	}

	// lines
	ctx.save();
	ctx.beginPath();
	ctx.rect(left, top - 2, plotW, plotH + 4);
	ctx.clip();
	this.series.forEach(function (s) {
		if (!s.visible || s.data.length === 0) { return; }
		ctx.strokeStyle = s.color;
		ctx.lineWidth = 2;
		ctx.lineJoin = 'round';
		ctx.beginPath();
		s.data.forEach(function (p, idx) {
			if (idx === 0) { ctx.moveTo(px(p[0]), py(p[1])); }
			else { ctx.lineTo(px(p[0]), py(p[1])); }
		});
		ctx.stroke();
	});
	ctx.restore();

	// tooltip: nearest point of each series to the cursor/finger
	if (this.hoverX === null || this.hoverX < left || this.hoverX > right) {
		return;
	}
	var hoverTime = minX + (this.hoverX - left) / plotW * (maxX - minX);
	var lines = [];
	var self = this;
	this.series.forEach(function (s) {
		if (!s.visible || s.data.length === 0) { return; }
		var best = s.data[0];
		for (var i = 1; i < s.data.length; i++) {
			if (Math.abs(s.data[i][0] - hoverTime) < Math.abs(best[0] - hoverTime)) {
				best = s.data[i];
			}
		}
		lines.push({s: s, p: best});
	});
	if (lines.length === 0) { return; }
	var lineX = px(lines[0].p[0]);
	ctx.strokeStyle = this.gridColor;
	ctx.beginPath();
	ctx.moveTo(Math.round(lineX) + 0.5, top);
	ctx.lineTo(Math.round(lineX) + 0.5, bottom);
	ctx.stroke();
	var text = [this.formatTime(lines[0].p[0])];
	lines.forEach(function (l) {
		text.push(l.s.name + ': ' + l.p[1] + self.valueSuffix);
		ctx.fillStyle = l.s.color;
		ctx.beginPath();
		ctx.arc(px(l.p[0]), py(l.p[1]), 4, 0, 2 * Math.PI);
		ctx.fill();
	});
	var boxW = 0;
	text.forEach(function (t) { boxW = Math.max(boxW, ctx.measureText(t).width); });
	boxW += 16;
	var boxH = text.length * 16 + 8;
	var bx = lineX + 10;
	if (bx + boxW > right) { bx = lineX - 10 - boxW; }
	if (bx < 2) { bx = 2; }
	var by = top + 4;
	ctx.fillStyle = 'rgba(247,247,247,0.92)';
	ctx.fillRect(bx, by, boxW, boxH);
	ctx.strokeStyle = '#999999';
	ctx.strokeRect(bx + 0.5, by + 0.5, boxW, boxH);
	ctx.textAlign = 'left';
	text.forEach(function (t, i) {
		ctx.fillStyle = i === 0 ? '#333333' : lines[i - 1].s.color;
		if (i > 0) {
			ctx.fillRect(bx + 8, by + 12 + i * 16 - 3, 6, 6);
			ctx.fillStyle = '#333333';
		}
		ctx.fillText(t, bx + (i === 0 ? 8 : 18), by + 12 + i * 16);
	});
};
