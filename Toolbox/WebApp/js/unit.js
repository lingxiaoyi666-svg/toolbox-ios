/* 单位换算 —— 7 类常用单位，全部本地计算 */
(function () {
  'use strict';
  var T = window.TB;
  var app = T.$('#app');
  if (!app) return;

  // 每类选一个基准单位，其余给「1 个该单位 = 多少基准单位」的系数
  var CATS = {
    '长度': {
      base: '米',
      units: { '毫米': 0.001, '厘米': 0.01, '分米': 0.1, '米': 1, '千米': 1000, '英寸': 0.0254, '英尺': 0.3048, '码': 0.9144, '英里': 1609.344, '海里': 1852 }
    },
    '面积': {
      base: '平方米',
      units: { '平方厘米': 0.0001, '平方米': 1, '公顷': 10000, '平方千米': 1000000, '亩': 666.6666666667, '平方英尺': 0.09290304, '平方英里': 2589988.110336 }
    },
    '重量': {
      base: '千克',
      units: { '毫克': 0.000001, '克': 0.001, '千克': 1, '吨': 1000, '市斤': 0.5, '两': 0.05, '磅': 0.45359237, '盎司': 0.028349523125 }
    },
    '温度': {
      base: '摄氏度',
      temperature: true,
      units: { '摄氏度': 1, '华氏度': 1, '开尔文': 1 }
    },
    '数据': {
      base: '字节',
      units: { '比特': 0.125, '字节': 1, 'KB': 1024, 'MB': 1048576, 'GB': 1073741824, 'TB': 1099511627776, 'PB': 1125899906842624 }
    },
    '时间': {
      base: '秒',
      units: { '毫秒': 0.001, '秒': 1, '分钟': 60, '小时': 3600, '天': 86400, '周': 604800, '月(30天)': 2592000, '年(365天)': 31536000 }
    },
    '速度': {
      base: '米/秒',
      units: { '米/秒': 1, '千米/小时': 0.2777777777778, '英里/小时': 0.44704, '节': 0.5144444444444, '英尺/秒': 0.3048, '马赫(海平面)': 340.29 }
    }
  };

  var catSel = T.$('#cat'), fromSel = T.$('#from'), valEl = app.querySelector('[data-k=val]');

  /* ---------- 数字美观 ---------- */
  function nice(v) {
    if (!isFinite(v)) return '—';
    var a = Math.abs(v);
    if (a === 0) return '0';
    if (a >= 1e15 || a < 1e-9) return v.toExponential(6).replace(/\.?0+e/, 'e');
    var digits = Math.max(1, Math.floor(Math.log10(a)) + 1);
    var dec = Math.max(0, Math.min(6, 6 - digits));
    var s = a >= 1 ? v.toFixed(dec) : v.toFixed(Math.min(9, 6 - Math.floor(Math.log10(a))));
    s = String(s);
    if (s.indexOf('.') >= 0) s = s.replace(/0+$/, '').replace(/\.$/, '');
    return group(s);
  }
  function group(s) {
    if (s.indexOf('e') >= 0) return s;
    var neg = s.charAt(0) === '-';
    if (neg) s = s.slice(1);
    var p = s.split('.');
    p[0] = p[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return (neg ? '-' : '') + p.join('.');
  }

  /* ---------- 温度 ---------- */
  function tempToC(v, u) {
    if (u === '华氏度') return (v - 32) * 5 / 9;
    if (u === '开尔文') return v - 273.15;
    return v;
  }
  function tempFromC(c, u) {
    if (u === '华氏度') return c * 9 / 5 + 32;
    if (u === '开尔文') return c + 273.15;
    return c;
  }

  /* ---------- 初始化 ----------
     顺序有讲究：先把「类别」选项建出来，bindForm 才回填得进去；
     再按回填后的类别填「单位」选项，否则第二次打开时 from 会指向上一个类别的单位（值为空 → 结果全 NaN）。 */
  Object.keys(CATS).forEach(function (k) {
    var o = document.createElement('option');
    o.value = k; o.textContent = k;
    catSel.appendChild(o);
  });

  T.bindForm('unit', app);
  if (!CATS[catSel.value]) catSel.value = T.store.get('unit:cat', '长度');
  if (!CATS[catSel.value]) catSel.value = '长度';

  function fillUnits(keep) {
    var cat = CATS[catSel.value];
    fromSel.innerHTML = '';
    Object.keys(cat.units).forEach(function (u) {
      var o = document.createElement('option');
      o.value = u; o.textContent = u;
      fromSel.appendChild(o);
    });
    var want = keep || T.store.get('unit:from', cat.base);
    fromSel.value = cat.units[want] !== undefined ? want : cat.base;
  }
  fillUnits(null);

  /* ---------- 渲染 ---------- */
  function render() {
    var cat = CATS[catSel.value];
    var from = fromSel.value;
    var v = T.parseNum(valEl);
    var out = [];

    Object.keys(cat.units).forEach(function (u) {
      var res;
      if (cat.temperature) res = tempFromC(tempToC(v, from), u);
      else res = v * cat.units[from] / cat.units[u];
      var label = u === cat.base ? u + '（基准）' : u;
      out.push('<div><dt>' + label + '</dt><dd class="num' + (u === from ? ' accent' : '') + '" data-copy="' + res + '">' + nice(res) + '</dd></div>');
    });

    T.$('#o-all').innerHTML = out.join('');
    T.$$('#o-all dd').forEach(function (d) {
      d.style.cursor = 'pointer';
      d.addEventListener('click', function () {
        copy(d.getAttribute('data-copy'));
      });
    });
    T.store.set('unit:cat', catSel.value);
    T.store.set('unit:from', from);
  }

  var toastTimer = null;
  function copy(txt) {
    var done = function () {
      var el = T.$('#o-toast');
      el.textContent = '已复制 ' + txt;
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () { el.textContent = ''; }, 1500);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(txt).then(done, function () { done(); });
    } else {
      var ta = document.createElement('textarea');
      ta.value = txt; document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(ta);
      done();
    }
  }

  catSel.addEventListener('change', function () { fillUnits(null); render(); });
  fromSel.addEventListener('change', render);
  valEl.addEventListener('input', render);

  render();
})();
