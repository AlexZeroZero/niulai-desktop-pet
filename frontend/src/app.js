const App = () => window.go.main.App;
const stage = document.querySelector('#stage');
const canvas = document.querySelector('#pet-canvas');
const visibleCtx = canvas.getContext('2d', { alpha: true });
const renderBuffer = document.createElement('canvas');
renderBuffer.width = 256;
renderBuffer.height = 256;
const ctx = renderBuffer.getContext('2d', { alpha: true });
const form = document.querySelector('#form');
const CELL = 256;
const FRAME_COUNT = 48;
const IDLE_FRAME_COUNT = 145;
const IDLE_COLUMNS = 24;
const IDLE_FPS = 24;
const IDLE_PING_PONG_FRAMES = (IDLE_FRAME_COUNT - 1) * 2;
const RUN_FRAME_COUNT = 145;
const RUN_COLUMNS = 24;
const RUN_FPS = 24;
const RUN_DURATION_MS = RUN_FRAME_COUNT / RUN_FPS * 1000;
const DOWN_FRAME_COUNT = 193;
const DOWN_COLUMNS = 24;
const DOWN_FPS = 24;
const DOWN_DURATION_MS = DOWN_FRAME_COUNT / DOWN_FPS * 1000;
const UP_VOICE_DELAY_MS = 1450;
const DOWN_VOICE_DELAY_MS = 3250;
const atlasRows = { idle: 0, up: 1, down: 2, closed: 3, lunch: 3, drag: 4 };
// The Vidu reaction is 145 distinct frames at 24 fps. It plays once rather
// than looping across a mismatched first/last pose, then returns to idle.
const cycleMs = { idle: IDLE_PING_PONG_FRAMES / IDLE_FPS * 1000, up: RUN_DURATION_MS, down: DOWN_DURATION_MS, closed: 2400, lunch: 2400, drag: 1600 };
const atlas = new Image();
atlas.decoding = 'async';
const idleAtlas = new Image();
idleAtlas.decoding = 'async';
const runAtlas = new Image();
runAtlas.decoding = 'async';
const downAtlas = new Image();
downAtlas.decoding = 'async';
const ATLAS_VERSION = 'vidu-v3-idle-down-random-dash';
const defaultAssets = Object.freeze({ niulaiAudio: '/audio/niulai.mp3', mamaAudio: '/audio/mama.mp3', mieAudio: '/audio/mie.mp3' });

let settings;
let assets = { ...defaultAssets };
let state = 'idle';
let stateStartedAt = performance.now();
let facing = 1;
let noDataSince = 0;
let manualAwakeUntil = 0;
let talking = false;
let lastQuote;
let lastExpressed = '';
let lastExpressionAt = 0;
let quoteTimer;
let dragging = false;
let beforeDragState = 'idle';
let dragHintShown = false;
let controlsTimer;
let bubbleTimer;
let idleQuoteTimer;
let numberTweenId = 0;
let displayedPrice;
let displayedPercent;
let quoteHistory = [];
let interactionAudio;
let pointerHeld = false;
let pointerStartX = 0;
let pointerStartY = 0;
let pointerLastX = 0;
let pointerLastY = 0;
let pointerStartClientX = 0;
let pointerStartClientY = 0;
let lastTapAt = 0;
let riseStreak = 0;
let fallStreak = 0;
let lastMarketCaptionAt = 0;
let lastMarketCaptionCategory = '';

const idleQuotes = [
  '今天这根K线，像我尾巴画的。',
  '我没摸鱼，我在研究牛市。',
  '再看一眼就涨……大概吧。',
  '别问，问就是技术性发呆。',
  '我的角不是天线，收不到内幕。',
  '绿得挺环保，就是不太友好。',
  '本牛申请把周一改成休市日。',
  '你盯盘，我盯着你盯盘。',
  '牛市什么时候来？我不是已经来了吗。',
  '先喝口水，行情不会因为你眨眼就跑。',
  '我刚掐指一算，发现我没有手指。',
  '横盘也是盘，煎一下应该挺香。',
  '账户可以躺平，牛角必须支棱起来。',
  '庄家在下棋，我在旁边啃棋盘。',
  '今天适合看盘，不适合看余额。',
  '别催，牛市堵在路上了。',
  '我不是困，我在闭眼看趋势。',
  '如果沉默是金，那横盘已经发财了。',
  'K线不说话，但它挺会气人。',
  '先别激动，也可能只是网线抖了一下。',
  '赚钱靠运气，亏钱靠实力，本牛很有实力。',
  '你负责判断方向，我负责把气氛搞起来。',
  '今天的目标：少亏一点也算赢。',
  '再横盘一会儿，我就要长蘑菇了。',
  '本牛没有内幕，只有一肚子牢骚。'
];

const marketQuotes = {
  rapidRise: [
    '卧槽！卧槽！又涨了！',
    '红线踩油门了，快扶住我！',
    '这速度，K线装火箭了？',
    '慢点涨，我的小心脏跟不上！',
    '谁在后面拿鞭子赶行情？',
    '一眨眼又上去了，讲不讲牛德！'
  ],
  continuousRise: [
    '别他妈的睡了，都涨上天了！',
    '一根接一根，这是要搭天梯？',
    '牛来了！谁也别拦我！',
    '今天空气里都是红色钞票味。',
    '连续上涨！我先跑两圈压压惊！',
    '还在涨！这次真不是幻觉！',
    '扶稳了，这趟电梯只按了向上！'
  ],
  surge: [
    '我靠，这不是涨，这是起飞！',
    '天花板呢？刚才被顶穿了！',
    '兄弟们系好安全带！',
    '再涨我就申请飞行执照了！',
    '牛角已经碰到云层了！',
    '这高度，恐高的先别看账户！'
  ],
  suddenFall: [
    '他妈的！又套在山顶了！',
    '谁把电梯钢丝绳剪了？',
    '刚才还好好的，怎么突然自由落体！',
    '这根绿柱子是来索命的吗？',
    '接住啊！怎么没人接盘！',
    '卧槽，地板怎么又往下开门了！'
  ],
  continuousFall: [
    '楼太高！我看不见！',
    '我要找牛妈妈寻安慰！',
    '别跌了，再跌牛角都要当了！',
    '一层一层地下楼，电梯都没这么快！',
    '还在跌？我先蹲会儿，腿软！',
    '绿得这么认真，考虑过本牛感受吗？',
    '连续下跌，钱包已经开始写遗书了！'
  ],
  deepFall: [
    '山顶风大，我的账户更凉！',
    '这不是回调，这是跳楼机！',
    '妈妈，这根K线欺负牛！',
    '牛皮还在，钱包快没了！',
    '跌成这样，庄家是赶着下班吗？',
    '我宣布：今天先假装没打开账户！'
  ],
  rise: [
    '有点意思，红起来了！',
    '小涨也是爱，别嫌人家含蓄。',
    '稳住，先别急着数钱。',
    '牛鼻子闻到一点上涨的味道。'
  ],
  fall: [
    '怎么又绿了，谁把灯关一下。',
    '问题不大……让我先哭两秒。',
    '回调可以，别拿我当滑梯。',
    '钱包说它想静静。'
  ]
};

function loadAtlas() {
  const loadImage = (image, url) => new Promise((resolve, reject) => {
    image.onload = resolve;
    image.onerror = reject;
    image.src = url;
  });
  return Promise.all([
    loadImage(atlas, `/sprites/niulai-atlas.png?v=${ATLAS_VERSION}`),
    loadImage(idleAtlas, `/sprites/niulai-idle-look-vidu-v3.webp?v=${ATLAS_VERSION}`),
    loadImage(runAtlas, `/sprites/niulai-run-vidu-v2.webp?v=${ATLAS_VERSION}`),
    loadImage(downAtlas, `/sprites/niulai-down-cry-vidu-v3.webp?v=${ATLAS_VERSION}`)
  ]);
}

function paintFrame(index, opacity = 1, frameState = state) {
  ctx.globalAlpha = opacity;
  ctx.drawImage(atlas, index * CELL, atlasRows[frameState] * CELL, CELL, CELL, 8, 0, CELL - 16, CELL - 16);
  ctx.globalAlpha = 1;
}

function paintRunFrame(index) {
  const column = index % RUN_COLUMNS;
  const row = Math.floor(index / RUN_COLUMNS);
  ctx.drawImage(runAtlas, column * CELL, row * CELL, CELL, CELL, 8, 0, CELL - 16, CELL - 16);
}

function paintVideoFrame(image, index, columns) {
  const column = index % columns;
  const row = Math.floor(index / columns);
  ctx.drawImage(image, column * CELL, row * CELL, CELL, CELL, 8, 0, CELL - 16, CELL - 16);
}

function idleFrameAt(elapsed) {
  const phase = Math.floor(elapsed * IDLE_FPS / 1000) % IDLE_PING_PONG_FRAMES;
  return phase < IDLE_FRAME_COUNT ? phase : IDLE_PING_PONG_FRAMES - phase;
}

function paintMouth(jaw) {
  const mouths = {
    idle: { x: 128, y: 72, rx: 7 },
    up: { x: 114, y: 69, rx: 6 },
    down: { x: 126, y: 79, rx: 8 }
  };
  const mouth = mouths[state] || mouths.idle;
  ctx.save();
  ctx.globalAlpha = 0.78;
  ctx.fillStyle = '#4b1716';
  ctx.beginPath();
  ctx.ellipse(mouth.x, mouth.y, mouth.rx, 1.1 + jaw * 1.5, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 0.45;
  ctx.strokeStyle = '#f3a18b';
  ctx.lineWidth = 0.8;
  ctx.beginPath();
  ctx.arc(mouth.x, mouth.y + 1, mouth.rx - 1, 0.15, Math.PI - 0.15);
  ctx.stroke();
  ctx.restore();
}

function animate(now) {
  ctx.clearRect(0, 0, CELL, CELL);
  if (!atlas.complete || !idleAtlas.complete || !runAtlas.complete || !downAtlas.complete) {
    requestAnimationFrame(animate);
    return;
  }
  const elapsed = Math.max(0, now - stateStartedAt);
  const duration = cycleMs[state] || 1333;
  const cycleProgress = (elapsed % duration) / duration;
  const current = Math.floor(cycleProgress * FRAME_COUNT);
  const t = now / 1000;
  ctx.save();
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  // Keep every sprite on an integer, fixed-size canvas. Sub-pixel transforms
  // made transparent fur edges shimmer even when the source frame was stable.
  if (facing < 0) {
    ctx.translate(CELL, 0);
    ctx.scale(-1, 1);
  }
  if (state === 'idle') {
    // The authored clip ends on a different glance from its first frame.
    // Playing it forward and backward preserves all real in-between frames
    // and removes the visible pose jump at the loop boundary.
    paintVideoFrame(idleAtlas, idleFrameAt(elapsed), IDLE_COLUMNS);
  } else if (state === 'up' && elapsed < RUN_DURATION_MS) {
    paintRunFrame(Math.min(RUN_FRAME_COUNT - 1, Math.floor(elapsed * RUN_FPS / 1000)));
  } else if (state === 'up') {
    paintVideoFrame(idleAtlas, idleFrameAt(elapsed - RUN_DURATION_MS), IDLE_COLUMNS);
  } else if (state === 'down') {
    // Play the complete fall reaction once and hold its final readable crouch.
    const index = Math.min(DOWN_FRAME_COUNT - 1, Math.floor(elapsed * DOWN_FPS / 1000));
    paintVideoFrame(downAtlas, index, DOWN_COLUMNS);
  } else {
    paintFrame(current);
  }
  // The Vidu rise reaction already contains authored, audio-synchronised mouth
  // motion. The procedural mouth remains for the other sprite animations.
  if (talking && state !== 'up' && state !== 'down' && state !== 'closed' && state !== 'lunch' && state !== 'drag') {
    paintMouth((Math.sin(t * 24) + 1) * 0.5);
  }
  ctx.restore();
  ctx.globalAlpha = 1;
  visibleCtx.globalCompositeOperation = 'copy';
  visibleCtx.drawImage(renderBuffer, 0, 0);
  requestAnimationFrame(animate);
}

function drawBrandIcon() {
  const icon = document.querySelector('#brand-cow');
  const iconCtx = icon.getContext('2d');
  iconCtx.clearRect(0, 0, icon.width, icon.height);
  iconCtx.drawImage(atlas, 54, 11, 147, 134, 0, 0, icon.width, icon.height);
}

function drawTrendLine(kind) {
  const chart = document.querySelector('#trend-line');
  const chartCtx = chart.getContext('2d');
  chartCtx.clearRect(0, 0, chart.width, chart.height);
  if (!quoteHistory.length) return;
  const values = quoteHistory.length === 1 ? [quoteHistory[0], quoteHistory[0]] : quoteHistory;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || Math.max(Math.abs(max) * 0.001, 1);
  const color = kind === 'rising' ? '#ff5b65' : kind === 'falling' ? '#2bdd88' : '#f5bd4a';
  chartCtx.beginPath();
  values.forEach((value, index) => {
    const x = 2 + index / (values.length - 1) * (chart.width - 5);
    const y = chart.height - 3 - (value - min) / range * (chart.height - 7);
    if (index === 0) chartCtx.moveTo(x, y); else chartCtx.lineTo(x, y);
  });
  chartCtx.strokeStyle = color;
  chartCtx.lineWidth = 1.5;
  chartCtx.shadowColor = color;
  chartCtx.shadowBlur = 4;
  chartCtx.stroke();
  chartCtx.shadowBlur = 0;
  const endY = chart.height - 3 - (values.at(-1) - min) / range * (chart.height - 7);
  chartCtx.beginPath();
  chartCtx.arc(chart.width - 2, endY, 1.8, 0, Math.PI * 2);
  chartCtx.fillStyle = color;
  chartCtx.fill();
}

function animateQuoteNumbers(quote) {
  const id = ++numberTweenId;
  const fromPrice = Number.isFinite(displayedPrice) ? displayedPrice : quote.price;
  const fromPercent = Number.isFinite(displayedPercent) ? displayedPercent : quote.percent;
  const startedAt = performance.now();
  const tick = now => {
    if (id !== numberTweenId) return;
    const progress = Math.min(1, (now - startedAt) / 650);
    const eased = 1 - Math.pow(1 - progress, 3);
    displayedPrice = fromPrice + (quote.price - fromPrice) * eased;
    displayedPercent = fromPercent + (quote.percent - fromPercent) * eased;
    document.querySelector('#quote-value').textContent = price(displayedPrice);
    document.querySelector('#quote-percent').textContent = `${displayedPercent >= 0 ? '+' : ''}${displayedPercent.toFixed(2)}%`;
    if (progress < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function revealControls() {
  const controls = document.querySelector('#pet-controls');
  controls.classList.add('visible');
  clearTimeout(controlsTimer);
  controlsTimer = setTimeout(() => controls.classList.remove('visible'), 4200);
}

function playInteractionVoice() {
  if (!settings?.voiceEnabled) return;
  if (interactionAudio) {
    interactionAudio.pause();
    interactionAudio.currentTime = 0;
  }
  interactionAudio = new Audio(assets.niulaiAudio);
  interactionAudio.volume = settings.volume;
  talking = true;
  stage.classList.add('talking');
  bubble('牛来！', 900);
  const currentAudio = interactionAudio;
  const finish = () => {
    if (interactionAudio !== currentAudio) return;
    talking = false;
    stage.classList.remove('talking');
  };
  interactionAudio.onended = interactionAudio.onerror = finish;
  interactionAudio.play().catch(finish);
}

function bubble(text, duration = 1800) {
  const element = document.querySelector('#speech');
  clearTimeout(bubbleTimer);
  element.textContent = text;
  element.classList.add('show');
  stage.classList.add('captioning');
  bubbleTimer = setTimeout(() => {
    element.classList.remove('show');
    stage.classList.remove('captioning');
  }, duration);
}

function scheduleIdleQuote() {
  clearTimeout(idleQuoteTimer);
  idleQuoteTimer = setTimeout(() => {
    const canChat = state === 'idle' && !dragging && !talking && !document.body.classList.contains('settings-open');
    if (canChat) bubble(idleQuotes[Math.floor(Math.random() * idleQuotes.length)], 3200);
    scheduleIdleQuote();
  }, 35000 + Math.random() * 35000);
}

function randomQuote(category) {
  const choices = marketQuotes[category] || [];
  return choices[Math.floor(Math.random() * choices.length)] || '';
}

function marketCaption(quote, previous) {
  if (!previous || quote.phase !== 'open') {
    riseStreak = 0;
    fallStreak = 0;
    return '';
  }

  const delta = quote.percent - previous.percent;
  const crypto = settings.provider === 'binance';
  const meaningfulStep = crypto ? 0.08 : 0.025;
  const fastStep = crypto ? 0.32 : 0.12;
  const dramaticPercent = crypto ? 4 : 2;

  if (delta >= meaningfulStep) {
    riseStreak += 1;
    fallStreak = 0;
  } else if (delta <= -meaningfulStep) {
    fallStreak += 1;
    riseStreak = 0;
  } else {
    riseStreak = 0;
    fallStreak = 0;
  }

  let category = '';
  if (fallStreak >= 3) category = 'continuousFall';
  else if (delta <= -fastStep * 1.8) category = 'suddenFall';
  else if (quote.percent <= -dramaticPercent) category = 'deepFall';
  else if (riseStreak >= 3) category = 'continuousRise';
  else if (delta >= fastStep * 1.8) category = 'rapidRise';
  else if (quote.percent >= dramaticPercent) category = 'surge';
  else if (delta >= fastStep) category = 'rapidRise';
  else if (delta <= -fastStep) category = 'suddenFall';
  else if (delta >= meaningfulStep && quote.percent >= settings.riseThreshold) category = 'rise';
  else if (delta <= -meaningfulStep && quote.percent <= settings.fallThreshold) category = 'fall';
  if (!category) return '';

  const now = Date.now();
  const severe = ['rapidRise', 'continuousRise', 'surge', 'suddenFall', 'continuousFall', 'deepFall'].includes(category);
  const cooldown = severe ? 12000 : 28000;
  if (now - lastMarketCaptionAt < cooldown) return '';
  if (category === lastMarketCaptionCategory && now - lastMarketCaptionAt < 75000) return '';
  lastMarketCaptionAt = now;
  lastMarketCaptionCategory = category;
  return randomQuote(category);
}

function setState(next) {
  if (next === state) return;
  state = next;
  stateStartedAt = performance.now();
  stage.dataset.state = next;
  document.body.dataset.petState = next;
}

function setTrend(kind) {
  const card = document.querySelector('#market-orbit');
  card.className = `market-orbit ${kind}`;
  void card.offsetWidth;
  card.classList.add('flash');
  setTimeout(() => card.classList.remove('flash'), 520);
  document.querySelector('#trend-arrow').textContent = kind === 'rising' ? '↗' : kind === 'falling' ? '↘' : '•';
}

function play(url) {
  return new Promise(resolve => {
    const audio = new Audio(url);
    audio.volume = settings.volume;
    audio.onended = audio.onerror = resolve;
    const promise = audio.play();
    if (promise) promise.catch(resolve);
    setTimeout(resolve, 9000);
  });
}

async function speak(kind) {
  talking = true;
  stage.classList.add('talking');
  const minimum = new Promise(resolve => setTimeout(resolve, 1400));
  const sequence = (async () => {
    const voice = kind === 'up' ? assets.niulaiAudio : assets.mamaAudio;
    if (settings.voiceEnabled) {
      if (kind === 'up') await new Promise(resolve => setTimeout(resolve, UP_VOICE_DELAY_MS));
      if (kind === 'down') await new Promise(resolve => setTimeout(resolve, DOWN_VOICE_DELAY_MS));
      if (state === kind) await play(voice);
    }
    if (settings.soundEnabled) await play(assets.mieAudio);
  })();
  await Promise.all([minimum, sequence]);
  talking = false;
  stage.classList.remove('talking');
}

function express(next, caption = '') {
  if (dragging) return;
  if (Date.now() < manualAwakeUntil && (next === 'closed' || next === 'lunch')) next = 'idle';
  setState(next);
  const now = Date.now();
  if ((next === 'up' || next === 'down') && (lastExpressed !== next || now - lastExpressionAt > 300000)) {
    lastExpressed = next;
    lastExpressionAt = now;
    const line = caption || (next === 'up' ? randomQuote('rise') : randomQuote('fall'));
    bubble(line, Math.min(4800, 2200 + line.length * 85));
    speak(next);
    if (next === 'up') App().StartDash(facing);
  } else if (caption) {
    bubble(caption, Math.min(4800, 2200 + caption.length * 85));
  }
  if (next !== 'up') App().StopDash();
}

function decide(quote) {
  if (quote.phase === 'lunch') return 'lunch';
  if (quote.phase === 'closed') return 'closed';
  if (quote.percent >= settings.riseThreshold) return 'up';
  if (quote.percent <= settings.fallThreshold) return 'down';
  return 'idle';
}

function price(value) {
  if (!Number.isFinite(value)) return '--';
  if (Math.abs(value) >= 1000) return value.toLocaleString('zh-CN', { maximumFractionDigits: 2 });
  if (Math.abs(value) < 1) return value.toFixed(5);
  return value.toFixed(2);
}

function normalizeCryptoSymbol(value) {
  const compact = String(value || 'BTC').toUpperCase().replace(/[\s/_-]/g, '');
  const quotes = ['FDUSD', 'USDT', 'USDC', 'TUSD', 'BUSD', 'BTC', 'ETH'];
  return quotes.some(quote => compact.length > quote.length && compact.endsWith(quote)) ? compact : `${compact || 'BTC'}USDT`;
}

function normalizeStockSymbol(value) {
  let compact = String(value || '').toUpperCase().trim().replace(/[\s_-]/g, '');
  if (/^[01]\.\d{6}$/.test(compact)) return compact;
  let market = '';
  if (compact.startsWith('SH')) { market = '1'; compact = compact.slice(2); }
  else if (compact.startsWith('SZ') || compact.startsWith('BJ')) { market = '0'; compact = compact.slice(2); }
  if (!/^\d{6}$/.test(compact)) return '';
  if (!market) market = compact.startsWith('6') ? '1' : '0';
  return `${market}.${compact}`;
}

function updateCryptoPreview() {
  const field = form.elements.cryptoSymbol;
  const preview = document.querySelector('#crypto-normalized');
  if (field && preview) preview.textContent = `将读取：${normalizeCryptoSymbol(field.value)}`;
}

function updateStockPreview() {
  const field = form.elements.symbol;
  const preview = document.querySelector('#stock-normalized');
  if (!field || !preview) return;
  const normalized = normalizeStockSymbol(field.value);
  preview.textContent = normalized ? `将读取：${normalized}` : '请输入6位股票代码';
  preview.classList.toggle('invalid', !normalized);
}

const soundSlots = {
  up: { setting: 'customUpSound', asset: 'niulaiAudio', fallback: defaultAssets.niulaiAudio, defaultLabel: '内置“牛来”' },
  down: { setting: 'customDownSound', asset: 'mamaAudio', fallback: defaultAssets.mamaAudio, defaultLabel: '内置“妈妈”' },
  cow: { setting: 'customCowSound', asset: 'mieAudio', fallback: defaultAssets.mieAudio, defaultLabel: '内置牛叫' }
};

function fileName(path) {
  return String(path || '').split(/[\\/]/).pop();
}

function updateSoundRow(kind, path) {
  const slot = soundSlots[kind];
  const label = document.querySelector(`#${kind}-sound-name`);
  if (!slot || !label) return;
  label.textContent = path ? `自定义 · ${fileName(path)}` : slot.defaultLabel;
  label.title = path || '';
}

async function loadCustomSound(kind, path) {
  const slot = soundSlots[kind];
  if (!slot) return;
  assets[slot.asset] = slot.fallback;
  updateSoundRow(kind, path);
  if (!path) return;
  try {
    const dataUrl = await App().LoadCustomSound(path);
    if (dataUrl) assets[slot.asset] = dataUrl;
  } catch {
    updateSoundRow(kind, '');
  }
}

async function syncCustomSounds(data) {
  await Promise.all(Object.entries(soundSlots).map(([kind, slot]) => loadCustomSound(kind, data?.[slot.setting])));
}

async function refresh() {
  try {
    const quote = await App().GetQuote();
    const previousQuote = lastQuote;
    noDataSince = 0;
    document.querySelector('#quote-name').textContent = quote.name || settings.displayName;
    const trend = quote.percent > 0 ? 'rising' : quote.percent < 0 ? 'falling' : 'resting';
    if (!lastQuote || lastQuote.percent !== quote.percent) setTrend(trend);
    quoteHistory.push(quote.price);
    if (quoteHistory.length > 18) quoteHistory.shift();
    drawTrendLine(trend);
    animateQuoteNumbers(quote);
    const caption = marketCaption(quote, previousQuote);
    lastQuote = quote;
    const next = decide(quote);
    document.querySelector('#mood').textContent = next === 'lunch' ? '午间休市' : next === 'closed' ? '休市睡觉' : next === 'up' ? '开心慢跑' : next === 'down' ? '委屈哭哭' : '行情平稳';
    express(next, caption);
  } catch (error) {
    if (!noDataSince) noDataSince = Date.now();
    document.querySelector('#quote-name').textContent = '等待行情';
    document.querySelector('#quote-value').textContent = '…';
    document.querySelector('#quote-percent').textContent = '';
    document.querySelector('#mood').textContent = '暂时没行情';
  }
}

function schedule() {
  clearInterval(quoteTimer);
  refresh();
  quoteTimer = setInterval(refresh, Math.max(5, settings.pollSeconds) * 1000);
}

setInterval(() => {
  if (noDataSince && Date.now() - noDataSince >= settings.staleSleepMinutes * 60000 && Date.now() > manualAwakeUntil) {
    document.querySelector('#mood').textContent = '没行情 · 睡觉中';
    express('closed');
  }
}, 1000);

function beginDrag(event) {
  if (event.button !== 0 || document.body.classList.contains('settings-open')) return;
  pointerHeld = true;
  pointerStartX = pointerLastX = event.screenX;
  pointerStartY = pointerLastY = event.screenY;
  pointerStartClientX = event.clientX;
  pointerStartClientY = event.clientY;
}

function moveDrag(event) {
  if (!pointerHeld) return;
  const total = Math.hypot(event.clientX - pointerStartClientX, event.clientY - pointerStartClientY);
  if (!dragging && total >= 5) {
    stage.setPointerCapture?.(event.pointerId);
    dragging = true;
    beforeDragState = state;
    App().StopDash();
    setState('drag');
    stage.classList.add('dragging');
    document.querySelector('#mood').textContent = '被拎起来了…';
    if (!dragHintShown) {
      dragHintShown = true;
      bubble('轻一点嘛…', 1300);
    }
  }
  if (!dragging) return;
  const dx = Math.round(event.screenX - pointerLastX);
  const dy = Math.round(event.screenY - pointerLastY);
  pointerLastX = event.screenX;
  pointerLastY = event.screenY;
  if (dx || dy) App().MoveBy(dx, dy);
}

function finishPointer(event) {
  if (!pointerHeld) return;
  pointerHeld = false;
  stage.releasePointerCapture?.(event.pointerId);
  if (dragging) {
    endDrag();
  } else {
    revealControls();
    playInteractionVoice();
    const now = Date.now();
    if (now - lastTapAt < 360) {
      lastTapAt = 0;
      wakePet();
    } else {
      lastTapAt = now;
    }
  }
}

function endDrag() {
  if (!dragging) return;
  dragging = false;
  stage.classList.remove('dragging');
  const fallback = lastQuote ? decide(lastQuote) : beforeDragState;
  setState(fallback === 'drag' ? 'idle' : fallback);
  setTimeout(refresh, 180);
}

stage.addEventListener('pointerdown', beginDrag);
stage.addEventListener('pointermove', moveDrag);
stage.addEventListener('pointerup', finishPointer);
stage.addEventListener('pointercancel', finishPointer);
function wakePet() {
  endDrag();
  manualAwakeUntil = Date.now() + 90000;
  noDataSince = 0;
  setState('idle');
  bubble('醒啦！', 1200);
  document.querySelector('#mood').textContent = '醒来看看';
  setTimeout(refresh, 1000);
}
stage.addEventListener('dblclick', event => {
  event.preventDefault();
  wakePet();
});

document.querySelector('#refresh').onclick = refresh;
document.querySelector('#quit').onclick = () => App().Quit();
document.querySelector('#sound').onclick = async () => {
  const enabled = !(settings.soundEnabled || settings.voiceEnabled);
  settings.soundEnabled = enabled;
  settings.voiceEnabled = enabled;
  settings = await App().SaveSettings(settings);
  syncSound();
};
document.querySelector('#settings').onclick = async () => {
  hydrate(settings);
  document.body.classList.add('settings-open');
  document.querySelector('#settings-panel').ariaHidden = 'false';
  await App().OpenSettings();
};
document.querySelector('#settings-close').onclick = closeSettings;
document.querySelector('#sponsor-link').onclick = event => {
  event.preventDefault();
  App().OpenSponsor();
};
document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key === ',') {
    event.preventDefault();
    document.querySelector('#settings').click();
  } else if (event.key === 'Escape' && document.body.classList.contains('settings-open')) {
    closeSettings();
  }
});

async function closeSettings() {
  document.body.classList.remove('settings-open');
  document.querySelector('#settings-panel').ariaHidden = 'true';
  setSettingsStatus('');
  await syncCustomSounds(settings);
  await App().CloseSettings();
}

function syncSound() { document.querySelector('#sound').textContent = settings.soundEnabled || settings.voiceEnabled ? '♪' : '∅'; }
window.runtime?.EventsOn('pet-direction', direction => { facing = direction >= 0 ? 1 : -1; });

function showProvider(value) {
  document.querySelectorAll('.provider-panel').forEach(panel => panel.classList.toggle('active', panel.dataset.provider === value));
}

function hydrate(data) {
  for (const [key, value] of Object.entries(data)) {
    const field = form.elements.namedItem(key);
    if (!field) continue;
    if (field instanceof RadioNodeList) {
      const input = [...field].find(item => item.value === value);
      if (input) input.checked = true;
    } else if (field.type === 'checkbox') field.checked = !!value;
    else field.value = value ?? '';
  }
  showProvider(data.provider);
  updateCryptoPreview();
  document.querySelector('#volume-output').textContent = `${Math.round(data.volume * 100)}%`;
  const preset = document.querySelector('#preset');
  const option = [...preset.options].find(item => item.value.startsWith(`${data.symbol}|`));
  preset.value = option?.value || 'custom-stock';
  if (!option && /^[01]\.\d{6}$/.test(form.elements.symbol.value)) form.elements.symbol.value = form.elements.symbol.value.slice(2);
  updateStockPreview();
  Object.entries(soundSlots).forEach(([kind, slot]) => updateSoundRow(kind, data?.[slot.setting]));
}

function serialize() {
  const output = { ...settings };
  new FormData(form).forEach((value, key) => output[key] = value);
  ['soundEnabled', 'voiceEnabled', 'alwaysOnTop', 'runOnStartup'].forEach(key => output[key] = form.elements[key].checked);
  ['pollSeconds', 'staleSleepMinutes', 'riseThreshold', 'fallThreshold', 'volume'].forEach(key => output[key] = Number(output[key]));
  output.cryptoSymbol = normalizeCryptoSymbol(output.cryptoSymbol);
  if (output.provider === 'eastmoney') output.symbol = normalizeStockSymbol(output.symbol) || output.symbol;
  return output;
}

form.addEventListener('change', event => { if (event.target.name === 'provider') showProvider(event.target.value); });
form.volume.addEventListener('input', () => document.querySelector('#volume-output').textContent = `${Math.round(form.volume.value * 100)}%`);
form.cryptoSymbol.addEventListener('input', updateCryptoPreview);
form.symbol.addEventListener('input', () => {
  document.querySelector('#preset').value = 'custom-stock';
  updateStockPreview();
});
document.querySelector('#preset').onchange = event => {
  if (event.target.value === 'custom-stock') {
    form.symbol.focus();
    updateStockPreview();
    return;
  }
  const [symbol, name] = event.target.value.split('|');
  form.symbol.value = symbol;
  form.displayName.value = name;
  updateStockPreview();
};

function setSettingsStatus(message, isError = false) {
  const element = document.querySelector('#settings-status');
  element.textContent = message;
  element.classList.toggle('error', isError);
}

document.querySelectorAll('.choose-sound').forEach(button => {
  button.onclick = async () => {
    const kind = button.dataset.kind;
    const slot = soundSlots[kind];
    setSettingsStatus('请选择一个不超过 12 MB 的音频文件…');
    try {
      const path = await App().PickCustomSound(kind);
      if (!path) {
        setSettingsStatus('');
        return;
      }
      form.elements[slot.setting].value = path;
      await loadCustomSound(kind, path);
      setSettingsStatus(`已选择：${fileName(path)}`);
    } catch (error) {
      setSettingsStatus(String(error), true);
    }
  };
});

document.querySelectorAll('.clear-sound').forEach(button => {
  button.onclick = () => {
    const kind = button.dataset.kind;
    const slot = soundSlots[kind];
    form.elements[slot.setting].value = '';
    loadCustomSound(kind, '');
    setSettingsStatus('已恢复内置声音，保存后生效');
  };
});

form.onsubmit = async event => {
  event.preventDefault();
  setSettingsStatus('正在保存…');
  try {
    settings = await App().SaveSettings(serialize());
    await syncCustomSounds(settings);
    document.body.dataset.petSize = settings.petSize;
    quoteHistory = [];
    lastQuote = undefined;
    riseStreak = 0;
    fallStreak = 0;
    displayedPrice = undefined;
    displayedPercent = undefined;
    syncSound();
    schedule();
    await closeSettings();
  } catch (error) {
    setSettingsStatus(String(error), true);
  }
};
document.querySelector('#test-up').onclick = () => { closeSettings(); express('up'); };
document.querySelector('#test-down').onclick = () => { closeSettings(); express('down'); };

window.addEventListener('DOMContentLoaded', async () => {
  await loadAtlas();
  drawBrandIcon();
  settings = await App().GetSettings();
  document.body.dataset.petSize = settings.petSize;
  hydrate(settings);
  await syncCustomSounds(settings);
  syncSound();
  requestAnimationFrame(animate);
  schedule();
  scheduleIdleQuote();
});
