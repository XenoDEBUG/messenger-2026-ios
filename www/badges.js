/* Значки профиля Messenger: rab, boost, halloween2026, winter2027.
   Подключение: <script src="badges.js"></script> перед </body> */
(function () {
  if (window.badgesHTML) return;

  var CSS = [
    '.vb{display:inline-flex;align-items:center;justify-content:center;gap:3px;width:18px;height:18px;border-radius:50%;margin-left:5px;vertical-align:middle;cursor:pointer;flex:none;box-sizing:border-box;transition:transform .15s;user-select:none}',
    '.vb svg{width:12px;height:12px;flex:none}',
    '.vb:hover{transform:scale(1.12)}',
    '.vb-pill{width:auto;height:18px;border-radius:9px;padding:0 7px 0 4px}',
    '.vb-pill b{font:700 9px/1 system-ui,sans-serif;letter-spacing:.4px}',
    '.vb-rab{background:linear-gradient(135deg,#ffffff,#7d7d88);color:#0b0b0e;box-shadow:0 0 8px rgba(255,255,255,.25)}',
    '.vb-boost{background:linear-gradient(90deg,#ffffff,#8e8e99,#ffffff);background-size:200% 100%;color:#0b0b0e;box-shadow:0 0 10px rgba(255,255,255,.3);animation:vbShine 3s linear infinite}',
    '.vb-halloween2026{background:radial-gradient(circle at 30% 25%,#34343c,#0b0b0e);color:#f2f2f6;box-shadow:0 0 0 1px rgba(242,242,246,.85),0 0 10px rgba(255,255,255,.3)}',
    '.vb-winter2027{background:radial-gradient(circle at 30% 25%,#ffffff,#8f98a8);color:#161b28;box-shadow:0 0 10px rgba(200,215,255,.55)}',
    '.vb-halloween2026 svg{animation:vbFloat 2.4s ease-in-out infinite}',
    '.vb-winter2027 svg{animation:vbSpin 9s linear infinite}',
    '@keyframes vbShine{to{background-position:200% 0}}',
    '@keyframes vbFloat{50%{transform:translateY(-1.5px)}}',
    '@keyframes vbSpin{to{transform:rotate(360deg)}}'
  ].join('\n');

  var style = document.createElement('style');
  style.id = 'vb-styles';
  style.textContent = CSS;
  document.head.appendChild(style);

  var BADGES = {
    rab:           { title: 'Verified developer', text: 'Подтверждённый разработчик Messenger', label: '' },
    boost:         { title: 'Boost', text: 'Этот человек купил подписку Boost', label: 'BOOST' },
    halloween2026: { title: 'Хэллоуин 2026', text: 'Участвовал в обновлении «Хэллоуин 2026»', label: '2026' },
    winter2027:    { title: 'Зима 2027', text: 'Участвовал в обновлении «Зима 2027»', label: '2027' }
  };

  var SVG = {
    rab: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16"/></svg>',
    boost: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/></svg>',
    halloween2026: '<svg viewBox="0 0 24 24"><path d="M12 7.2c-4.6-1.8-8.8.9-8.8 5.4 0 4.4 3.8 7.6 8.8 7.6s8.8-3.2 8.8-7.6c0-4.5-4.2-7.2-8.8-5.4z" fill="currentColor"/><path d="M12 7.5v12.2M8.4 8.6c-.8 2.6-.8 6.6.2 9.6M15.6 8.6c.8 2.6.8 6.6-.2 9.6" fill="none" stroke="#0b0b0e" stroke-width=".9" opacity=".35"/><path d="M11.4 7.4V4.6c0-.6.4-1 1-1.1 0 .9.3 1.6.9 2.1" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M7.4 11.6l2.2 1.2-2.2 1.2zM16.6 11.6l-2.2 1.2 2.2 1.2z" fill="#0b0b0e"/><path d="M8.6 15.6l1.2-1.3 1.2 1.3 1.1-1.3 1.2 1.3 1.1-1.3 1.2 1.3 1.1-1.3" fill="none" stroke="#0b0b0e" stroke-width="1.2" stroke-linejoin="round"/></svg>',
    winter2027: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.5v19M3.6 7.2l16.8 9.6M20.4 7.2L3.6 16.8"/><path d="M9.8 4.6L12 2.5l2.2 2.1M9.8 19.4L12 21.5l2.2-2.1"/></svg>'
  };

  // Список значков пользователя: галочка разработчика (verified) и выданные значки (badges)
  function badgeList(u) {
    var list = [];
    if (u && u.verified) list.push('rab');
    if (u && Array.isArray(u.badges)) {
      u.badges.forEach(function (b) {
        if (BADGES[b] && list.indexOf(b) < 0) list.push(b);
      });
    }
    return list;
  }

  // Вставляйте в шаблоны: ${badgesHTML(user)}
  window.badgesHTML = function (u) {
    return badgeList(u).map(function (b) {
      var i = BADGES[b];
      return '<span class="vb vb-' + b + (i.label ? ' vb-pill' : '') + '" data-badge="' + b +
        '" title="' + i.title + '">' + SVG[b] + (i.label ? '<b>' + i.label + '</b>' : '') + '</span>';
    }).join('');
  };

  // Нажатие на значок показывает пояснение и не открывает профиль
  document.addEventListener('click', function (e) {
    var el = e.target.closest && e.target.closest('.vb');
    if (!el) return;
    e.stopPropagation();
    e.preventDefault();
    var i = BADGES[el.getAttribute('data-badge')];
    if (!i) return;
    var msg = i.title + ': ' + i.text;
    if (typeof toast === 'function') toast(msg); else alert(msg);
  }, true);
})();
