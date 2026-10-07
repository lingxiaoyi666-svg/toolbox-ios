/* 房贷计算 —— 等额本息 / 等额本金 + 提前还款试算（纯前端，离线可用） */
(function () {
  'use strict';
  var T = window.TB;
  var app = T.$('#app');
  if (!app) return;

  T.bindForm('mortgage', app);
  var modeSeg = T.segment(T.$('[data-seg=mode]', app), render);
  var planSeg = T.segment(T.$('[data-seg=plan]', app), render);

  /* ---------- 核心公式 ---------- */
  // 等额本息：月供 = P·r·(1+r)^n / ((1+r)^n − 1)
  function equalInstallment(P, annualRate, n) {
    var r = annualRate / 100 / 12;
    if (n <= 0) return { monthly: 0, total: 0, interest: 0, r: r };
    if (r <= 0) return { monthly: P / n, total: P, interest: 0, r: 0 };
    var pow = Math.pow(1 + r, n);
    var monthly = P * r * pow / (pow - 1);
    return { monthly: monthly, total: monthly * n, interest: monthly * n - P, r: r };
  }

  // 等额本息：还了 paid 期之后还剩多少本金
  function balanceAfter(P, r, monthly, paid) {
    if (paid <= 0) return P;
    if (r <= 0) return Math.max(0, P - monthly * paid);
    var pow = Math.pow(1 + r, paid);
    return Math.max(0, P * pow - monthly * (pow - 1) / r);
  }

  // 等额本息月供不变，反解还清期数
  function periodsFor(P, r, monthly) {
    if (P <= 0) return 0;
    if (r <= 0) return Math.ceil(P / monthly);
    if (monthly <= P * r) return Infinity; // 月供连利息都不够
    return Math.ceil(Math.log(monthly / (monthly - P * r)) / Math.log(1 + r));
  }

  /* ---------- 渲染 ---------- */
  function render() {
    var amount = T.parseNum(app.querySelector('[data-k=amount]')) * 10000; // 万元 → 元
    var rate = T.parseNum(app.querySelector('[data-k=rate]'));
    var years = Math.max(1, Math.round(T.parseNum(app.querySelector('[data-k=years]'))));
    var mode = modeSeg.value();
    var n = years * 12;

    var first, monthly, total, interest, rows = [], monthlyNote = '元 / 月';
    var r = rate / 100 / 12;
    var principalPerMonth = mode === 'principal' ? amount / n : 0;

    if (mode === 'equal') {
      var e = equalInstallment(amount, rate, n);
      monthly = first = e.monthly; total = e.total; interest = e.interest;
      var bal = amount;
      for (var k = 1; k <= Math.min(6, n); k++) {
        var it = bal * r, pr = monthly - it;
        bal -= pr;
        rows.push([k, T.money(monthly), T.money(pr), T.money(it), T.money(bal)]);
      }
    } else {
      var tot = 0, lastPay = 0, b2 = amount;
      var limit = Math.min(6, n);
      for (var j = 1; j <= n; j++) {
        var it2 = b2 * r;
        var pay = principalPerMonth + it2;
        tot += pay;
        if (j === 1) first = pay;
        if (j === n) lastPay = pay;
        if (j <= limit) {
          rows.push([j, T.money(pay), T.money(principalPerMonth), T.money(it2), T.money(Math.max(0, b2 - principalPerMonth))]);
        }
        b2 -= principalPerMonth;
      }
      monthly = first; total = tot; interest = tot - amount;
      monthlyNote = '元 / 月（首月，逐月递减）';
    }

    T.$('#o-monthly').textContent = amount > 0 ? T.money(monthly) : '—';
    T.$('#o-monthly-tag').textContent = monthlyNote;

    var rl = [];
    if (mode === 'principal' && amount > 0) {
      rl.push(['末月月供', '<dd class="num">' + T.money(lastPay) + ' 元</dd>']);
      rl.push(['每月递减', '<dd class="num">' + T.money(principalPerMonth * r) + ' 元</dd>']);
    }
    rl.push(['贷款总额', '<dd class="num">' + T.money(amount) + ' 元</dd>']);
    rl.push(['还款总额', '<dd class="num">' + T.money(total) + ' 元</dd>']);
    rl.push(['支付利息', '<dd class="num warn">' + T.money(interest) + ' 元</dd>']);
    rl.push(['利息 / 本金', '<dd class="num">' + T.pct(amount > 0 ? interest / amount * 100 : 0) + '</dd>']);
    rl.push(['还款期数', '<dd class="num">' + n + ' 期（' + years + ' 年）</dd>']);
    T.$('#o-rows').innerHTML = rl.map(function (x) { return '<div><dt>' + x[0] + '</dt>' + x[1] + '</div>'; }).join('');
    T.fillTable(T.$('#o-schedule'), rows);
    T.$('#o-schedule-note').textContent = n > 6
      ? '等额本息每月月供相同；等额本金本金均摊、利息随剩余本金递减，所以月供逐月下降。'
      : '';

    renderPrepay(amount, rate, n, mode, monthly, principalPerMonth, mode === 'principal' ? lastPay : 0);
  }

  /* ---------- 提前还款 ---------- */
  function renderPrepay(amount, rate, n, mode, monthly, principalPerMonth, lastPay) {
    var paid = Math.max(0, Math.round(T.parseNum(app.querySelector('[data-k=paid]'))));
    var prepay = T.parseNum(app.querySelector('[data-k=prepay]')) * 10000;
    var plan = planSeg.value();
    var out = T.$('#o-prepay');
    var hint = T.$('#o-plan-hint');

    if (amount <= 0) { out.innerHTML = ''; return; }
    if (paid >= n) {
      out.innerHTML = '<div><dt>状态</dt><dd>贷款已还完</dd></div>';
      return;
    }

    var r = rate / 100 / 12;
    var left = n - paid;
    var balance, baseMonthly, baseLeftInterest;

    if (mode === 'equal') {
      balance = balanceAfter(amount, r, monthly, paid);
      baseMonthly = monthly;
    } else {
      balance = Math.max(0, amount - principalPerMonth * paid);
      baseMonthly = principalPerMonth + balance * r;
    }
    baseLeftInterest = (mode === 'equal')
      ? baseMonthly * left - balance
      : (function () { // 等额本金剩余利息 = 剩余各期利息之和
          var s = 0, b = balance;
          for (var i = 0; i < left; i++) { s += b * r; b -= principalPerMonth; }
          return s;
        })();

    var usePrepay = Math.min(prepay, balance);
    var after = Math.max(0, balance - usePrepay);

    var newInterest, newMonthly = 0, newPeriods = 0, label = '';

    if (plan === 'shorten') {
      if (mode === 'equal') {
        newPeriods = periodsFor(after, r, baseMonthly);
        newInterest = isFinite(newPeriods) ? baseMonthly * newPeriods - after : Infinity;
      } else {
        newPeriods = Math.ceil(after / principalPerMonth);
        var s2 = 0, b2 = after;
        for (var i2 = 0; i2 < newPeriods; i2++) { s2 += b2 * r; b2 -= principalPerMonth; }
        newInterest = s2;
      }
      newMonthly = mode === 'equal' ? baseMonthly : principalPerMonth + after * r;
      label = '月供不变，' + left + ' 期 → ' + (isFinite(newPeriods) ? newPeriods : '∞') + ' 期';
    } else {
      newPeriods = left;
      if (mode === 'equal') {
        if (r > 0) {
          var pow = Math.pow(1 + r, newPeriods);
          newMonthly = after * r * pow / (pow - 1);
        } else newMonthly = after / newPeriods;
        newInterest = newMonthly * newPeriods - after;
      } else {
        var pp = after / newPeriods;
        newMonthly = pp + after * r;
        var s3 = 0, b3 = after;
        for (var i3 = 0; i3 < newPeriods; i3++) { s3 += b3 * r; b3 -= pp; }
        newInterest = s3;
      }
      label = '年限不变，月供 ' + T.money(baseMonthly) + ' → ' + T.money(newMonthly) + ' 元';
    }

    hint.textContent = plan === 'shorten'
      ? '月供保持 ' + T.money(baseMonthly) + ' 元，还完更快、总利息更省。'
      : '剩余 ' + left + ' 期不变，每月压力更小、总利息省得少一些。';

    var save = baseLeftInterest - newInterest;
    var lines = [];
    lines.push(['当前剩余本金', '<dd class="num">' + T.money(balance) + ' 元</dd>']);
    lines.push(['提前还款', '<dd class="num">' + T.money(usePrepay) + ' 元</dd>']);
    lines.push(['还款后剩余本金', '<dd class="num">' + T.money(after) + ' 元</dd>']);
    lines.push(['原计划剩余利息', '<dd class="num">' + T.money(baseLeftInterest) + ' 元</dd>']);
    lines.push(['新方案剩余利息', '<dd class="num">' + T.money(newInterest) + ' 元</dd>']);
    lines.push(['节省利息', '<dd class="num ' + (save > 0 ? 'ok' : '') + '">' + T.money(save) + ' 元</dd>']);
    lines.push(['新方案', '<dd style="font-size:14px;font-weight:500">' + label + '</dd>']);
    out.innerHTML = lines.map(function (x) { return '<div><dt>' + x[0] + '</dt>' + x[1] + '</div>'; }).join('');
  }

  T.live(app, render);
})();
