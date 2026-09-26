(function () {
  'use strict';

  var config = window.GOOFER_CONFIG || {};
  var SVG_NS = 'http://www.w3.org/2000/svg';
  var RADIUS = 190;
  var COLORS = ['accent', 'paper', 'green', 'gold'];

  // Made-up wallets for the demo wheel. Swap for real holder data once the token is live.
  var DEMO_HOLDERS = [
    { address: '0x3f2a9c41d0b7e6f5a8c3d2e1f0a9b8c7d6e5a1', balance: 48000000 },
    { address: '0x9c0b12aa7f3e6d5c4b3a29180f7e6d5c4b3a07', balance: 36000000 },
    { address: '0x21e4c5d6a7b8c9d0e1f2a3b4c5d6e7f8a9b0e4', balance: 27500000 },
    { address: '0xb85d6e7f8091a2b3c4d5e6f708192a3b4c5d5d', balance: 21000000 },
    { address: '0x07c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8c2', balance: 16000000 },
    { address: '0xe19a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e9a', balance: 12500000 },
    { address: '0x5a33b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e733', balance: 9800000 },
    { address: '0xd4f0e1d2c3b4a5968778695a4b3c2d1e0f1ad4', balance: 7200000 },
    { address: '0x88aa0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e88', balance: 5400000 },
    { address: '0x6b1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c1e', balance: 4100000 },
    { address: '0xc07d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b7d', balance: 3000000 },
    { address: '0x4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d5f', balance: 2200000 },
    { address: '0xa1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8b2', balance: 1500000 },
    { address: '0x0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a9e', balance: 900000 },
  ];

  var you = null;
  var rotation = 0;
  var spinning = false;
  var slices = [];

  function $(id) { return document.getElementById(id); }
  function short(address) { return address.slice(0, 4) + '…' + address.slice(-2); }
  function fmt(n) { return Math.round(n).toLocaleString('en-US'); }
  function pct(share) {
    var p = share * 100;
    return (p >= 10 ? p.toFixed(1) : p >= 0.1 ? p.toFixed(2) : p.toPrecision(2)) + '%';
  }

  function point(angleDeg, r) {
    var a = angleDeg * Math.PI / 180;
    return [r * Math.sin(a), -r * Math.cos(a)];
  }

  function el(tag, attrs) {
    var node = document.createElementNS(SVG_NS, tag);
    Object.keys(attrs).forEach(function (k) { node.setAttribute(k, attrs[k]); });
    return node;
  }

  function holders() {
    return you ? DEMO_HOLDERS.concat([you]) : DEMO_HOLDERS;
  }

  // Each slice's angle is proportional to that wallet's share of all $GOOFER on the wheel.
  function buildSlices() {
    var list = holders();
    var total = list.reduce(function (sum, h) { return sum + h.balance; }, 0);
    var start = 0;
    slices = list.map(function (h, i) {
      var share = h.balance / total;
      var sweep = share * 360;
      var slice = { holder: h, share: share, start: start, end: start + sweep, color: h.isYou ? 'you' : COLORS[i % COLORS.length] };
      start += sweep;
      return slice;
    });
    return total;
  }

  function drawWheel() {
    var total = buildSlices();
    var group = $('wheel-slices');
    while (group.firstChild) group.removeChild(group.firstChild);

    slices.forEach(function (s, i) {
      var sweep = s.end - s.start;
      var shape;
      if (sweep >= 359.999) {
        shape = el('circle', { r: RADIUS });
      } else {
        var p0 = point(s.start, RADIUS);
        var p1 = point(s.end, RADIUS);
        shape = el('path', {
          d: 'M0 0 L' + p0[0].toFixed(2) + ' ' + p0[1].toFixed(2) +
             ' A' + RADIUS + ' ' + RADIUS + ' 0 ' + (sweep > 180 ? 1 : 0) + ' 1 ' +
             p1[0].toFixed(2) + ' ' + p1[1].toFixed(2) + ' Z',
        });
      }
      shape.setAttribute('class', 'slice slice-' + s.color);
      shape.setAttribute('data-index', i);
      group.appendChild(shape);

      // Labels run along the radius so thin slices still fit; left-half labels flip to stay readable.
      if (sweep >= 9) {
        var mid = (s.start + s.end) / 2;
        var pos = point(mid, 118);
        var turn = mid < 180 ? mid - 90 : mid + 90;
        var label = el('text', {
          x: pos[0].toFixed(1), y: pos[1].toFixed(1),
          transform: 'rotate(' + turn.toFixed(1) + ' ' + pos[0].toFixed(1) + ' ' + pos[1].toFixed(1) + ')',
          'text-anchor': 'middle', 'dominant-baseline': 'middle',
          fill: s.color === 'green' ? '#F6F1E7' : '#17161B',
          class: 'slice-label',
        });
        label.textContent = s.holder.isYou ? 'YOU' : short(s.holder.address);
        group.appendChild(label);
      }
    });

    $('stat-wallets').textContent = fmt(slices.length);
    drawLegend();
    return total;
  }

  function legendRow(swatchClass, name, share) {
    var li = document.createElement('li');
    [['swatch ' + swatchClass, ''], ['addr', name], ['pct', share]].forEach(function (part) {
      var span = document.createElement('span');
      span.className = part[0];
      span.textContent = part[1];
      li.appendChild(span);
    });
    return li;
  }

  function drawLegend() {
    var list = $('legend-list');
    while (list.firstChild) list.removeChild(list.firstChild);
    var sorted = slices.slice().sort(function (a, b) { return b.share - a.share; });
    var shown = sorted.slice(0, 6);
    var yours = slices.filter(function (s) { return s.holder.isYou; })[0];
    if (yours && shown.indexOf(yours) === -1) shown.push(yours);

    shown.forEach(function (s) {
      list.appendChild(legendRow('sw-' + s.color, s.holder.isYou ? 'You' : short(s.holder.address), pct(s.share)));
    });

    var rest = sorted.slice(6).filter(function (s) { return shown.indexOf(s) === -1; });
    if (rest.length) {
      var restShare = rest.reduce(function (sum, s) { return sum + s.share; }, 0);
      list.appendChild(legendRow('sw-rest', rest.length + ' more wallets', pct(restShare)));
    }
  }

  function randomUnit() {
    if (window.crypto && window.crypto.getRandomValues) {
      var buf = new Uint32Array(1);
      window.crypto.getRandomValues(buf);
      return buf[0] / 4294967296;
    }
    return Math.random();
  }

  function spin() {
    if (spinning) return;
    spinning = true;
    var btn = $('spin-btn');
    btn.disabled = true;
    $('spin-result').textContent = 'Spinning…';
    document.querySelectorAll('.slice-win').forEach(function (n) { n.classList.remove('slice-win'); });

    // Pick a random spot on the wheel. Bigger slices cover more of it, so they win more often.
    var target = randomUnit() * 360;
    var winnerIndex = 0;
    slices.forEach(function (s, i) { if (target >= s.start && target < s.end) winnerIndex = i; });
    var winner = slices[winnerIndex];

    // Rotate so the chosen spot ends up under the pointer at the top.
    var current = ((rotation % 360) + 360) % 360;
    var extra = (((360 - target) - current) % 360 + 360) % 360;
    rotation += 360 * 6 + extra;

    var wheel = $('wheel-spin');
    var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    wheel.style.transform = 'rotate(' + rotation + 'deg)';

    setTimeout(function () {
      var shape = document.querySelector('.slice[data-index="' + winnerIndex + '"]');
      if (shape) shape.classList.add('slice-win');
      $('spin-result').textContent = winner.holder.isYou
        ? 'It landed on you! (' + pct(winner.share) + ' slice. Demo only, no real payout.)'
        : 'Landed on ' + short(winner.holder.address) + ' with a ' + pct(winner.share) + ' slice. Demo only.';
      spinning = false;
      btn.disabled = false;
    }, reduced ? 50 : 5600);
  }

  function onSliceCheck(event) {
    event.preventDefault();
    var raw = $('balance-input').value.replace(/[\s,_]/g, '');
    var out = $('slice-output');
    var balance = Number(raw);
    if (!raw || !isFinite(balance) || balance <= 0) {
      you = null;
      drawWheel();
      out.textContent = 'Enter a number bigger than 0, like 2500000.';
      return;
    }
    if (balance > 1e15) {
      out.textContent = "That's more $GOOFER than anyone could hold. Try a smaller number.";
      return;
    }
    you = { address: 'you', balance: balance, isYou: true };
    drawWheel();
    var yours = slices[slices.length - 1];
    out.textContent = 'With ' + fmt(balance) + ' $GOOFER you get a ' + pct(yours.share) +
      ' slice of the demo wheel, so about a 1 in ' + fmt(Math.max(1, 1 / yours.share)) + ' chance each spin.';
  }

  function applyConfig() {
    document.querySelectorAll('[data-config]').forEach(function (node) {
      var value = config[node.getAttribute('data-config')];
      if (value) node.textContent = value + (node.getAttribute('data-suffix') || '');
    });

    var copyBtn = $('copy-btn');
    if (config.contractAddress) {
      $('contract-value').textContent = config.contractAddress;
      copyBtn.disabled = false;
      copyBtn.addEventListener('click', function () {
        var done = function () { copyBtn.textContent = 'Copied'; setTimeout(function () { copyBtn.textContent = 'Copy'; }, 1800); };
        if (navigator.clipboard) navigator.clipboard.writeText(config.contractAddress).then(done, function () { copyBtn.textContent = 'Copy failed'; });
      });
    }

    var xLink = $('x-link');
    if (config.xHandle) {
      xLink.href = 'https://x.com/' + config.xHandle;
      xLink.textContent = 'Follow on X · @' + config.xHandle;
      xLink.rel = 'noopener';
      xLink.target = '_blank';
    }
    var tgLink = $('tg-link');
    if (config.telegramUrl) {
      tgLink.href = config.telegramUrl;
      tgLink.rel = 'noopener';
      tgLink.target = '_blank';
    }
    var buyLink = $('buy-link');
    if (buyLink && config.buyUrl) {
      buyLink.href = config.buyUrl;
      buyLink.hidden = false;
    }
    $('year').textContent = String(new Date().getFullYear());
  }

  document.addEventListener('DOMContentLoaded', function () {
    applyConfig();
    drawWheel();
    $('spin-btn').addEventListener('click', spin);
    $('slice-form').addEventListener('submit', onSliceCheck);
  });
})();
