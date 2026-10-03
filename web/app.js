(() => {
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dice_game';
  const $ = (id) => document.getElementById(id);
  const post = (name, data = {}) =>
    fetch(`https://${RES}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    }).catch(() => {});

  const state = {
    view: null,
    cur: '$',
    min: 1,
    max: 1,
    selected: null,
    revealMs: 2600,
    mineRolled: false,
    oppRolled: false,
    ended: false,
    confirmLeave: false,
    timers: [],
    soloTimer: null,
  };

  const fmt = (n) => `${state.cur}${Number(n || 0).toLocaleString()}`;
  const later = (fn, ms) => state.timers.push(setTimeout(fn, ms));
  const clearTimers = () => { state.timers.forEach(clearTimeout); state.timers = []; };

  /* ---------------- dice ---------------- */

  const PIPS = { 1: [5], 2: [1, 9], 3: [1, 5, 9], 4: [1, 3, 7, 9], 5: [1, 3, 5, 7, 9], 6: [1, 3, 4, 6, 7, 9] };
  // Opposite faces sum to 7
  const FACES = { front: 1, back: 6, right: 2, left: 5, top: 3, bottom: 4 };
  // Cube rotation [x, y] that brings each value to the front
  const ORIENT = { 1: [0, 0], 6: [0, 180], 2: [0, -90], 5: [0, 90], 3: [-90, 0], 4: [90, 0] };
  const TILT = 'rotateX(-24deg) rotateY(32deg)';

  function buildDie() {
    const scene = document.createElement('div');
    scene.className = 'scene';
    const die = document.createElement('div');
    die.className = 'die idle';
    for (const [side, n] of Object.entries(FACES)) {
      const face = document.createElement('div');
      face.className = `face f-${side}`;
      for (let c = 1; c <= 9; c++) {
        const cell = document.createElement('span');
        cell.className = 'cell';
        if (PIPS[n].includes(c)) {
          const pip = document.createElement('i');
          pip.className = 'pip';
          cell.appendChild(pip);
        }
        face.appendChild(cell);
      }
      die.appendChild(face);
    }
    die.style.transform = TILT;
    die._bx = 0;
    die._by = 0;
    scene.appendChild(die);
    return { scene, die };
  }

  function rollDie(die, value, ms) {
    const [tx, ty] = ORIENT[value];
    // Extra full turns keep the spin going the same direction; final angle lands on the face
    die._bx += 360 * (2 + Math.floor(Math.random() * 2));
    die._by += 360 * (2 + Math.floor(Math.random() * 3));
    die.classList.remove('idle');
    die.style.transitionDuration = `${ms}ms`;
    die.style.transform = `rotateX(${die._bx + tx}deg) rotateY(${die._by + ty}deg)`;
  }

  function resetDie(die) {
    die.classList.add('idle');
    die.style.transitionDuration = '0ms';
    die.style.transform = TILT;
    die._bx = 0;
    die._by = 0;
  }

  const lanes = {};
  for (const [key, laneId, totalId] of [['me', 'lane-me', 'total-me'], ['opp', 'lane-opp', 'total-opp'], ['solo', 'lane-solo', 'total-solo']]) {
    const box = $(laneId).querySelector('.dice');
    const dice = [buildDie(), buildDie()];
    dice.forEach((d) => box.appendChild(d.scene));
    lanes[key] = { box, dice: dice.map((d) => d.die), total: $(totalId) };
  }

  function resetLanes() {
    for (const lane of Object.values(lanes)) {
      lane.dice.forEach(resetDie);
      lane.total.textContent = '–';
      lane.box.classList.remove('toss');
    }
  }

  /* ---------------- views ---------------- */

  const VIEWS = ['setup', 'solo', 'waiting', 'invite', 'game', 'message'];

  function show(view) {
    state.view = view;
    VIEWS.forEach((v) => $(`view-${v}`).classList.toggle('hidden', v !== view));
  }

  const showApp = () => $('app').classList.remove('hidden');
  const hideApp = () => { clearTimers(); $('app').classList.add('hidden'); };

  function setBalance(n) {
    if (n !== undefined && n !== null) $('balance').textContent = fmt(n);
  }
  const setStatus = (t) => { $('status').textContent = t; };

  function toast(message, kind) {
    const el = document.createElement('div');
    el.className = `toast ${kind || ''}`;
    el.textContent = message;
    $('toasts').appendChild(el);
    setTimeout(() => el.remove(), 3500);
  }

  function takeConfig(d) {
    if (d.currency) state.cur = d.currency;
    if (d.min !== undefined) state.min = d.min;
    if (d.max !== undefined) state.max = d.max;
    if (d.revealMs) state.revealMs = d.revealMs;
    $('cur').textContent = state.cur;
  }

  /* ---------------- setup ---------------- */

  function renderSetup(players, d) {
    const list = $('player-list');
    list.innerHTML = '';
    state.selected = null;
    $('btn-send').disabled = true;

    const hasPlayers = players.length > 0;
    $('bet-block').classList.toggle('hidden', !hasPlayers);
    $('btn-send').classList.toggle('hidden', !hasPlayers);
    $('btn-solo').className = hasPlayers ? 'ghost' : 'primary';

    $('setup-hint').textContent = hasPlayers
      ? 'Roll on your own, or pick someone nearby and set a bet.'
      : `Nobody is within ${d.distance} m, so it's a solo roll with no betting. To bet, stand next to another player and use /${d.command} again.`;

    players.forEach((p) => {
      const li = document.createElement('li');
      const label = document.createElement('label');
      const radio = document.createElement('input');
      radio.type = 'radio';
      radio.name = 'opponent';
      radio.value = p.id;
      const name = document.createElement('span');
      name.textContent = p.name;
      const id = document.createElement('small');
      id.textContent = `ID ${p.id}`;
      label.append(radio, name, id);
      li.appendChild(label);
      radio.addEventListener('change', () => {
        state.selected = p.id;
        list.querySelectorAll('li').forEach((x) => x.classList.remove('selected'));
        li.classList.add('selected');
        $('btn-send').disabled = false;
      });
      list.appendChild(li);
    });

    const quick = $('quick');
    quick.innerHTML = '';
    const amounts = [...new Set([state.min, 100, 500, 1000, state.max])]
      .filter((n) => n >= state.min && n <= state.max)
      .sort((a, b) => a - b);
    amounts.forEach((n) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = fmt(n);
      b.addEventListener('click', () => { $('bet').value = n; });
      quick.appendChild(b);
    });

    const bet = $('bet');
    bet.min = state.min;
    bet.max = state.max;
    bet.value = Math.min(Math.max(100, state.min), state.max);
  }

  function clampBet() {
    let n = Math.floor(Number($('bet').value) || state.min);
    n = Math.min(Math.max(n, state.min), state.max);
    $('bet').value = n;
    return n;
  }

  /* ---------------- leaving ---------------- */

  function dismiss() {
    if (state.view === 'invite') post('respond', { accept: false });
    else if ((state.view === 'game' && !state.ended) || state.view === 'waiting') post('leave');
    hideApp();
    post('close');
  }

  function requestLeave() {
    if (state.view === 'game' && !state.ended && (state.mineRolled || state.oppRolled) && !state.confirmLeave) {
      state.confirmLeave = true;
      $('btn-leave').textContent = 'Forfeit and leave';
      setStatus('Leaving now hands the pot to your opponent.');
      return;
    }
    dismiss();
  }

  /* ---------------- messages from the game ---------------- */

  const handlers = {
    open(d) {
      takeConfig(d);
      state.ended = false;
      $('heading').textContent = 'Dice table';
      setBalance(d.balance);
      renderSetup(d.players || [], d);
      show('setup');
      showApp();
    },

    waiting(d) {
      takeConfig(d);
      $('waiting-text').textContent = `Waiting for ${d.name} to accept your ${fmt(d.bet)} bet…`;
      show('waiting');
      showApp();
    },

    invite(d) {
      takeConfig(d);
      setBalance(d.balance);
      $('invite-text').textContent = `${d.name} wants to roll dice for ${fmt(d.bet)} each.`;
      const bar = $('countdown-bar');
      bar.style.setProperty('--t', `${d.timeout}s`);
      bar.style.animation = 'none';
      void bar.offsetWidth;
      bar.style.animation = '';
      show('invite');
      showApp();
    },

    start(d) {
      takeConfig(d);
      clearTimers();
      state.mineRolled = false;
      state.oppRolled = false;
      state.ended = false;
      state.confirmLeave = false;
      $('heading').textContent = 'Dice table';
      $('name-opp').textContent = d.opponent;
      $('pot').textContent = fmt(d.pot);
      $('round').textContent = '';
      setBalance(d.balance);
      resetLanes();
      $('banner').classList.add('hidden');
      $('btn-roll').disabled = false;
      $('btn-leave').textContent = 'Leave table';
      setStatus(`${fmt(d.bet)} each. Roll when you are ready.`);
      show('game');
      showApp();
    },

    rolled(d) {
      const lane = d.mine ? lanes.me : lanes.opp;
      const ms = Math.max(state.revealMs - 500, 600);

      if (d.mine) state.mineRolled = true; else state.oppRolled = true;

      lane.dice.forEach((die, i) => rollDie(die, d.dice[i], ms));
      lane.box.classList.remove('toss');
      void lane.box.offsetWidth;
      lane.box.classList.add('toss');
      later(() => { lane.total.textContent = d.dice[0] + d.dice[1]; }, ms);

      if (d.mine) $('btn-roll').disabled = true;

      if (state.mineRolled && state.oppRolled) setStatus('Counting up…');
      else if (state.mineRolled) setStatus('Waiting for your opponent to roll…');
      else setStatus('Your opponent has rolled. Your turn.');
    },

    tie(d) {
      resetLanes();
      state.mineRolled = false;
      state.oppRolled = false;
      state.confirmLeave = false;
      $('btn-leave').textContent = 'Leave table';
      $('btn-roll').disabled = false;
      $('round').textContent = `Round ${d.round}`;
      setStatus('Tie. The pot stays on the table. Roll again.');
    },

    result(d) {
      state.ended = true;
      setBalance(d.balance);
      $('btn-roll').disabled = true;
      const banner = $('banner');
      banner.classList.toggle('lost', !d.won);
      $('banner-title').textContent = d.won ? 'You win' : 'You lose';
      $('banner-sub').textContent = d.won
        ? `+${fmt(d.net)} (pot paid ${fmt(d.amount)})`
        : `-${fmt(d.amount)}`;
      banner.classList.remove('hidden');
    },

    cancelled(d) {
      clearTimers();
      state.ended = true;
      setBalance(d.balance);
      $('message-text').textContent = d.message;
      show('message');
      showApp();
    },

    soloRolled(d) {
      const lane = lanes.solo;
      const ms = Math.max(state.revealMs - 500, 600);

      lane.dice.forEach((die, i) => rollDie(die, d.dice[i], ms));
      lane.box.classList.remove('toss');
      void lane.box.offsetWidth;
      lane.box.classList.add('toss');
      lane.total.textContent = '–';
      $('solo-status').textContent = 'Rolling…';

      clearTimeout(state.soloTimer);
      later(() => {
        lane.total.textContent = d.dice[0] + d.dice[1];
        $('solo-status').textContent = d.dice[0] === d.dice[1]
          ? `Doubles! ${d.dice[0]} and ${d.dice[1]}.`
          : `You rolled ${d.dice[0]} and ${d.dice[1]}.`;
      }, ms);
      state.soloTimer = setTimeout(() => { $('btn-solo-roll').disabled = false; }, state.revealMs + 100);
    },

    toast(d) { toast(d.message, d.kind); },
  };

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (handlers[d.action]) handlers[d.action](d);
  });

  /* ---------------- buttons ---------------- */

  $('btn-send').addEventListener('click', () => {
    if (state.selected === null) return;
    const bet = clampBet();
    $('btn-send').disabled = true;
    post('invite', { target: state.selected, bet });
    // If the server rejects it, a toast explains why; let the player try again.
    setTimeout(() => { if (state.view === 'setup') $('btn-send').disabled = state.selected === null; }, 800);
  });

  function soloRoll() {
    $('btn-solo-roll').disabled = true;
    clearTimeout(state.soloTimer);
    // If the server ignores a too-early request, don't leave the button stuck
    state.soloTimer = setTimeout(() => { $('btn-solo-roll').disabled = false; }, state.revealMs + 700);
    post('solo');
  }

  $('btn-solo').addEventListener('click', () => {
    resetLanes();
    $('heading').textContent = 'Dice table';
    $('solo-status').textContent = 'Just for fun. No bets, no money.';
    show('solo');
    soloRoll();
  });
  $('btn-solo-roll').addEventListener('click', soloRoll);
  $('btn-solo-close').addEventListener('click', dismiss);

  $('bet').addEventListener('blur', clampBet);
  $('btn-cancel').addEventListener('click', dismiss);
  $('btn-accept').addEventListener('click', () => post('respond', { accept: true }));
  $('btn-decline').addEventListener('click', dismiss);
  $('btn-roll').addEventListener('click', () => { $('btn-roll').disabled = true; post('roll'); });
  $('btn-leave').addEventListener('click', requestLeave);
  $('btn-done').addEventListener('click', dismiss);
  $('btn-message-ok').addEventListener('click', dismiss);
  $('btn-close').addEventListener('click', requestLeave);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('app').classList.contains('hidden')) requestLeave();
  });
})();
