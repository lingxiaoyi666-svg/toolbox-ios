/* 离线工具箱 —— 共享脚本
   三件事：数字格式化、localStorage 记忆（每个工具各自存）、分段控件的通用行为。 */
(function (global) {
  'use strict';

  var NS = 'tbox:';

  /* ---------- 数字 ---------- */
  function num(v, d) {
    if (v === null || v === undefined || v === '' || isNaN(v)) return '—';
    if (!isFinite(v)) return '∞';
    return Number(v).toLocaleString('zh-CN', {
      minimumFractionDigits: d === undefined ? 2 : d,
      maximumFractionDigits: d === undefined ? 2 : d
    });
  }
  // 金额：默认 2 位；把 -0.00 归一成 0.00
  function money(v) {
    var s = num(v, 2);
    return s === '-0.00' ? '0.00' : s;
  }
  function yuan(v) { return money(v) + ' 元'; }
  function pct(v) { return num(v, 2) + '%'; }

  function parseNum(el) {
    var raw = String(el && el.value !== undefined ? el.value : '').trim();
    if (raw === '') return 0;
    var n = Number(raw);
    return isFinite(n) ? n : 0;
  }

  /* ---------- 存储 ---------- */
  var store = {
    get: function (key, def) {
      try {
        var v = global.localStorage.getItem(NS + key);
        return v === null ? def : JSON.parse(v);
      } catch (e) { return def; }
    },
    set: function (key, val) {
      try { global.localStorage.setItem(NS + key, JSON.stringify(val)); } catch (e) {}
    },
    keys: function () {
      var out = [];
      try {
        for (var i = 0; i < global.localStorage.length; i++) {
          var k = global.localStorage.key(i);
          if (k && k.indexOf(NS) === 0) out.push(k.slice(NS.length));
        }
      } catch (e) {}
      return out.sort();
    },
    dump: function () {
      var o = {};
      this.keys().forEach(function (k) { o[k] = store.get(k, null); }, this);
      return o;
    },
    clear: function () {
      this.keys().forEach(function (k) {
        try { global.localStorage.removeItem(NS + k); } catch (e) {}
      });
    }
  };

  /* ---------- 表单记忆 ----------
     用法：bindForm('mortgage', rootEl) —— 输入变化即存，页面打开时自动回填。 */
  function bindForm(name, root) {
    if (!root) return;
    var saved = store.get(name, null) || {};
    root.querySelectorAll('[data-k]').forEach(function (el) {
      var k = el.getAttribute('data-k');
      if (!(k in saved)) return;
      if (el.type === 'checkbox') el.checked = !!saved[k];
      else el.value = saved[k];
    });
    function save() {
      var o = {};
      root.querySelectorAll('[data-k]').forEach(function (el) {
        var k = el.getAttribute('data-k');
        o[k] = el.type === 'checkbox' ? el.checked : el.value;
      });
      store.set(name, o);
    }
    root.addEventListener('input', save);
    root.addEventListener('change', save);
  }

  /* ---------- 分段控件 ----------
     用法：<div class="seg" data-seg="mode"><button data-v="a">A</button>…</div>
     返回取值函数 value()。 */
  function segment(segEl, onChange) {
    var btns = Array.prototype.slice.call(segEl.querySelectorAll('button'));
    function set(v, fire) {
      btns.forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-v') === v));
      });
      segEl.setAttribute('data-value', v);
      if (fire && onChange) onChange(v);
    }
    btns.forEach(function (b) {
      b.addEventListener('click', function () { set(b.getAttribute('data-v'), true); });
    });
    var first = btns.filter(function (b) { return b.getAttribute('aria-pressed') === 'true'; })[0] || btns[0];
    set(first ? first.getAttribute('data-v') : '', false);
    return { value: function () { return segEl.getAttribute('data-value'); }, set: set };
  }

  /* ---------- 一堆小工具 ---------- */
  // 给输入框挂「改了就算」的实时监听
  function live(root, fn) {
    root.addEventListener('input', fn);
    root.addEventListener('change', fn);
    fn();
  }

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function fillTable(tbody, rows) {
    tbody.innerHTML = rows.map(function (r) {
      return '<tr>' + r.map(function (c) { return '<td>' + c + '</td>'; }).join('') + '</tr>';
    }).join('');
  }

  global.TB = {
    num: num, money: money, yuan: yuan, pct: pct, parseNum: parseNum,
    store: store, bindForm: bindForm, segment: segment, live: live,
    $: $, $$: $$, fillTable: fillTable, NS: NS
  };
})(window);
