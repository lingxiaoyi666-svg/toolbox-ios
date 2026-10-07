/* 日期天数 —— 相差天数 / 日历月差 / 日期推算 / 倒计时（纯本地计算，不联网） */
(function () {
  'use strict';
  var T = window.TB;
  var app = T.$('#app');
  if (!app) return;

  var WEEK = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  var MS = 86400000;

  function today() { var d = new Date(); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
  function fmt(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function cn(d) { return d.getFullYear() + ' 年 ' + (d.getMonth() + 1) + ' 月 ' + d.getDate() + ' 日'; }

  // 从 'YYYY-MM-DD' 造本地日期，避开 new Date(str) 的 UTC 歧义
  function readDate(el) {
    var s = String(el && el.value || '').trim();
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
    if (!m) return null;
    var d = new Date(+m[1], +m[2] - 1, +m[3]);
    return isNaN(d.getTime()) ? null : d;
  }

  function days(a, b) { return Math.round((b - a) / MS); }

  function workdays(a, b) { // 不含周六周日
    if (b < a) { var t = a; a = b; b = t; }
    var n = 0, d = new Date(a.getTime());
    while (d < b) { var w = d.getDay(); if (w !== 0 && w !== 6) n++; d.setDate(d.getDate() + 1); }
    return n;
  }

  function addMonths(d, n) {
    var y = d.getFullYear(), m = d.getMonth() + n, day = d.getDate();
    var last = new Date(y, m + 1, 0).getDate();
    return new Date(y, m, Math.min(day, last));
  }

  function addBy(d, n, unit) {
    if (unit === 'day') { var x = new Date(d.getTime()); x.setDate(x.getDate() + n); return x; }
    if (unit === 'week') { var y2 = new Date(d.getTime()); y2.setDate(y2.getDate() + n * 7); return y2; }
    if (unit === 'month') return addMonths(d, n);
    return addMonths(d, n * 12);
  }

  function monthDiff(a, b) {
    var sign = 1;
    if (b < a) { var t = a; a = b; b = t; sign = -1; }
    var months = (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
    var anchor = addMonths(a, months);
    if (anchor > b) { months -= 1; anchor = addMonths(a, months); }
    return { months: months * sign, restDays: days(anchor, b) * sign };
  }

  function dayOfYear(d) { return days(new Date(d.getFullYear(), 0, 1), d) + 1; }
  function weekOfYear(d) { // ISO 周
    var t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7));
    var first = new Date(t.getFullYear(), 0, 4);
    first.setDate(first.getDate() + 3 - ((first.getDay() + 6) % 7));
    return 1 + Math.round((t - first) / (7 * MS));
  }

  function rows(html) { return html.map(function (x) { return '<div><dt>' + x[0] + '</dt>' + x[1] + '</div>'; }).join(''); }
  function dd(v, cls) { return '<dd class="num ' + (cls || '') + '">' + v + '</dd>'; }

  /* ---------- 默认日期 ---------- */
  var t0 = today();
  if (!app.querySelector('[data-k=d1]').value) app.querySelector('[data-k=d1]').value = fmt(t0);
  if (!app.querySelector('[data-k=d2]').value) app.querySelector('[data-k=d2]').value = fmt(addBy(t0, 100, 'day'));
  if (!app.querySelector('[data-k=d3]').value) app.querySelector('[data-k=d3]').value = fmt(t0);
  if (!app.querySelector('[data-k=d4]').value) app.querySelector('[data-k=d4]').value = fmt(new Date(t0.getFullYear() + 1, 0, 1));
  T.bindForm('datecalc', app);
  var unitSeg = T.segment(T.$('[data-seg=unit]', app), render);

  /* ---------- 渲染 ---------- */
  function render() {
    var d1 = readDate(app.querySelector('[data-k=d1]'));
    var d2 = readDate(app.querySelector('[data-k=d2]'));
    var out = [];

    if (d1 && d2) {
      var n = days(d1, d2);
      var md = monthDiff(d1, d2);
      out.push(['相差', dd(Math.abs(n) + ' 天（' + (n < 0 ? '往前' : '往后') + '）', 'accent')]);
      out.push(['折合', dd(T.num(Math.abs(n) / 7, 2) + ' 周')]);
      out.push(['日历', dd(Math.abs(md.months) + ' 个月' + (md.restDays ? ' 零 ' + Math.abs(md.restDays) + ' 天' : ''))]);
      out.push(['工作日', dd(workdays(d1, d2) + ' 天（不含周末）')]);
      out.push(['含周末', dd(Math.abs(n) + ' 天')]);
      out.push(['起止星期', dd(WEEK[d1.getDay()].slice(2) + ' → ' + WEEK[d2.getDay()].slice(2))]);
    } else {
      out.push(['提示', dd('请填两个有效日期')]);
    }
    T.$('#o-diff').innerHTML = rows(out);

    // 日期推算
    var d3 = readDate(app.querySelector('[data-k=d3]'));
    var nAdd = Math.round(T.parseNum(app.querySelector('[data-k=n]')));
    var u = unitSeg.value();
    if (d3) {
      var r = addBy(d3, nAdd, u);
      T.$('#o-date').textContent = fmt(r);
      T.$('#o-date-note').textContent = cn(r) + ' ' + WEEK[r.getDay()] +
        '　（从 ' + fmt(d3) + ' 起' + (nAdd >= 0 ? '加' : '减') + Math.abs(nAdd) + ' ' +
        ({ day: '天', week: '周', month: '个月', year: '年' })[u] +
        '，第 ' + dayOfYear(r) + ' 天）';
    } else {
      T.$('#o-date').textContent = '—';
    }

    // 倒计时
    var d4 = readDate(app.querySelector('[data-k=d4]'));
    var c = [];
    if (d4) {
      var left = days(t0, d4);
      c.push(['距 ' + fmt(d4), dd(Math.abs(left) + ' 天', left >= 0 ? 'ok' : '')]);
      c.push(['还有', dd(left >= 0 ? T.num(left / 7, 1) + ' 周' : '已过去 ' + Math.abs(left) + ' 天')]);
      c.push(['工作日', dd(left >= 0 ? workdays(t0, d4) + ' 天' : '—')]);
      c.push(['那天', dd(WEEK[d4.getDay()])]);
    }
    T.$('#o-count').innerHTML = rows(c);

    // 今天
    var yd = new Date(t0.getFullYear(), 11, 31);
    T.$('#o-today').innerHTML = rows([
      ['今天', dd(cn(t0))],
      ['星期', dd(WEEK[t0.getDay()])],
      ['今年第', dd(dayOfYear(t0) + ' 天 / ' + (dayOfYear(yd) === 366 ? 366 : 365) + ' 天')],
      ['第几周', dd('第 ' + weekOfYear(t0) + ' 周')],
      ['季度', dd('第 ' + (Math.floor(t0.getMonth() / 3) + 1) + ' 季度')],
      ['今年还剩', dd(days(t0, yd) + ' 天', 'warn')]
    ]);
  }

  T.live(app, render);
})();
