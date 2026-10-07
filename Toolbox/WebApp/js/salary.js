/* 工资到手 —— 累计预扣法（TCA），与「个人所得税」App 同源算法，可交叉验证 */
(function () {
  'use strict';
  var T = window.TB;
  var app = T.$('#app');
  if (!app) return;

  T.bindForm('salary', app);

  // 累计预扣预缴税率表：[上限, 税率, 速算扣除数]
  var BRACKETS = [
    [36000, 0.03, 0],
    [144000, 0.10, 2520],
    [300000, 0.20, 16920],
    [420000, 0.25, 31920],
    [660000, 0.30, 52920],
    [960000, 0.35, 85920],
    [Infinity, 0.45, 181920]
  ];

  function taxOf(cum) {
    if (cum <= 0) return 0;
    for (var i = 0; i < BRACKETS.length; i++) {
      if (cum <= BRACKETS[i][0]) return cum * BRACKETS[i][1] - BRACKETS[i][2];
    }
    return 0;
  }

  function v(k) { return T.parseNum(app.querySelector('[data-k=' + k + ']')); }

  function render() {
    var gross = v('gross');
    var baseRaw = app.querySelector('[data-k=base]').value;
    var base = String(baseRaw).trim() === '' ? gross : T.parseNum(app.querySelector('[data-k=base]'));
    var extra = v('extra');
    var yanglao = base * v('yanglao') / 100;
    var yiliao = base * v('yiliao') / 100;
    var shiye = base * v('shiye') / 100;
    var gjj = base * v('gjj') / 100;
    var social = yanglao + yiliao + shiye;
    var deduct = social + gjj;
    var monthlyTaxable = gross - deduct - 5000 - extra;

    // 逐月累计预扣
    var months = [], cumTaxPaid = 0, yearTax = 0, yearNet = 0;
    for (var m = 1; m <= 12; m++) {
      var cum = monthlyTaxable * m;
      var cumTax = taxOf(cum);
      var tax = Math.max(0, cumTax - cumTaxPaid);
      cumTaxPaid = cumTax;
      var net = gross - deduct - tax;
      months.push([m, T.money(Math.max(0, cum)), T.money(tax), T.money(net)]);
      yearTax += tax;
      yearNet += net;
    }

    var netAvg = yearNet / 12;
    T.$('#o-net').textContent = gross > 0 ? T.money(netAvg) : '—';

    var lines = [];
    lines.push(['税前月薪', '<dd class="num">' + T.money(gross) + ' 元</dd>']);
    if (Math.abs(base - gross) > 0.5) lines.push(['缴纳基数', '<dd class="num">' + T.money(base) + ' 元</dd>']);
    lines.push(['养老保险', '<dd class="num">' + T.money(yanglao) + ' 元</dd>']);
    lines.push(['医疗保险', '<dd class="num">' + T.money(yiliao) + ' 元</dd>']);
    lines.push(['失业保险', '<dd class="num">' + T.money(shiye) + ' 元</dd>']);
    lines.push(['住房公积金', '<dd class="num">' + T.money(gjj) + ' 元</dd>']);
    lines.push(['五险一金合计', '<dd class="num">' + T.money(deduct) + ' 元</dd>']);
    lines.push(['月应纳税所得额', '<dd class="num">' + T.money(Math.max(0, monthlyTaxable)) + ' 元</dd>']);
    lines.push(['全年个税', '<dd class="num warn">' + T.money(yearTax) + ' 元</dd>']);
    lines.push(['月均个税', '<dd class="num">' + T.money(yearTax / 12) + ' 元</dd>']);
    lines.push(['全年到手', '<dd class="num ok">' + T.money(yearNet) + ' 元</dd>']);
    lines.push(['实际税负率', '<dd class="num">' + T.pct(gross > 0 ? yearTax / (gross * 12) * 100 : 0) + '</dd>']);
    lines.push(['到手 / 税前', '<dd class="num">' + T.pct(gross > 0 ? netAvg / gross * 100 : 0) + '</dd>']);
    T.$('#o-rows').innerHTML = lines.map(function (x) { return '<div><dt>' + x[0] + '</dt>' + x[1] + '</div>'; }).join('');
    T.fillTable(T.$('#o-months'), months);
  }

  T.live(app, render);
})();
