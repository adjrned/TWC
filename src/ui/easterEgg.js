// Easter egg: the "bla" button in the sidebar footer sets a cat loose to drift
// around the window, bouncing off the edges like the old DVD screensaver.
// Click again to stop it. Purely decorative — it never takes pointer events and
// is hidden from screen readers. Also callable from the console as bla().
import blaUrl from '../assets/bla.webp';

const SIZE = 64;
const SPEED = 190;      // px/s, constant — no gravity, like the DVD logo
const EDGE_CLASS = 'hit'; // brief flash on every wall hit
// How close to the other edge a wall hit must be to count as a corner. An exact
// hit is near-impossible, so allow a slice of the window — generous enough to
// actually happen, small enough to stay a treat. Scaled so a small window
// doesn't turn every bounce into a corner.
const cornerSlop = () => Math.min(56, Math.min(window.innerWidth, window.innerHeight) * 0.06);
const CORNER_COOLDOWN = 1200; // ms, so one near-corner can't fire twice
const SPARK_COLORS = ['#f5a623', '#7cc5a1', '#fff3d6', '#e8736b', '#74a7f0'];

let el = null;
let raf = null;
let x = 0, y = 0, vx = 0, vy = 0, last = 0, lastCorner = 0;

function element() {
  if (el) return el;
  el = document.createElement('img');
  el.src = blaUrl;
  el.alt = '';
  el.id = 'blaCat';
  el.setAttribute('aria-hidden', 'true');
  document.body.appendChild(el);
  return el;
}

const bounds = () => [window.innerWidth - SIZE, window.innerHeight - SIZE];

// ── Fireworks, for the rare corner hit ────────────────────────
let sparkLayer = null;

function layer() {
  if (sparkLayer) return sparkLayer;
  sparkLayer = document.createElement('div');
  sparkLayer.id = 'blaSparks';
  sparkLayer.setAttribute('aria-hidden', 'true');
  document.body.appendChild(sparkLayer);
  return sparkLayer;
}

function burst(cx, cy, count = 30) {
  const host = layer();

  // Shockwave: one quick expanding ring to sell the impact.
  const ring = document.createElement('i');
  ring.className = 'bla-ring';
  host.appendChild(ring);
  ring.animate([
    { transform: `translate(${cx}px, ${cy}px) scale(0.2)`, opacity: 0.85 },
    { transform: `translate(${cx}px, ${cy}px) scale(2.6)`, opacity: 0 },
  ], { duration: 520, easing: 'cubic-bezier(.1,.75,.3,1)', fill: 'forwards' }).onfinish = () => ring.remove();

  for (let i = 0; i < count; i++) {
    const spark = document.createElement('i');
    spark.className = 'bla-spark';
    spark.style.color = SPARK_COLORS[(Math.random() * SPARK_COLORS.length) | 0]; // fill + glow
    const size = 5 + Math.random() * 8;
    spark.style.width = spark.style.height = `${size.toFixed(1)}px`;
    spark.style.margin = `${(-size / 2).toFixed(1)}px 0 0 ${(-size / 2).toFixed(1)}px`;
    host.appendChild(spark);
    const angle = Math.random() * Math.PI * 2;
    const dist = 60 + Math.random() * 150;
    const dx = Math.cos(angle) * dist;
    const dy = Math.sin(angle) * dist;
    const anim = spark.animate([
      { transform: `translate(${cx}px, ${cy}px) scale(1)`, opacity: 1 },
      { transform: `translate(${cx + dx}px, ${cy + dy + 60}px) scale(0.2)`, opacity: 0 },
    ], { duration: 750 + Math.random() * 650, easing: 'cubic-bezier(.12,.7,.3,1)', fill: 'forwards' });
    anim.onfinish = () => spark.remove();
  }
}

/** Three staggered bursts around the corner the cat just nailed. */
export function cornerFireworks(cx = window.innerWidth / 2, cy = window.innerHeight / 2) {
  const host = layer();
  host.classList.add('flash');
  setTimeout(() => host.classList.remove('flash'), 420);
  burst(cx, cy);
  setTimeout(() => burst(cx + (Math.random() - 0.5) * 120, cy + (Math.random() - 0.5) * 120, 20), 160);
  setTimeout(() => burst(cx + (Math.random() - 0.5) * 160, cy + (Math.random() - 0.5) * 160, 16), 340);
}

function frame(now) {
  const dt = Math.min((now - last) / 1000, 1 / 30); // clamp after a tab switch
  last = now;
  const [maxX, maxY] = bounds();

  x += vx * dt;
  y += vy * dt;

  let hitX = false, hitY = false;
  if (x <= 0 && vx < 0) { x = 0; vx = -vx; hitX = true; }
  if (x >= maxX && vx > 0) { x = maxX; vx = -vx; hitX = true; }
  if (y <= 0 && vy < 0) { y = 0; vy = -vy; hitY = true; }
  if (y >= maxY && vy > 0) { y = maxY; vy = -vy; hitY = true; }
  const hit = hitX || hitY;
  // The payoff: both edges at once, or one edge while hugging the other.
  const slop = cornerSlop();
  const nearX = x <= slop || x >= maxX - slop;
  const nearY = y <= slop || y >= maxY - slop;
  if (((hitX && hitY) || (hitX && nearY) || (hitY && nearX)) && now - lastCorner > CORNER_COOLDOWN) {
    lastCorner = now;
    cornerFireworks(x + SIZE / 2, y + SIZE / 2);
  }
  // A resized window can leave it outside; walk it back in.
  x = Math.min(Math.max(x, 0), Math.max(maxX, 0));
  y = Math.min(Math.max(y, 0), Math.max(maxY, 0));

  el.style.transform = `translate3d(${Math.round(x)}px, ${Math.round(y)}px, 0)`;
  if (hit) {
    el.classList.remove(EDGE_CLASS);
    void el.offsetWidth; // restart the flash
    el.classList.add(EDGE_CLASS);
  }
  raf = requestAnimationFrame(frame);
}

export function isBlaRunning() {
  return raf !== null;
}

export function stopBla() {
  if (raf !== null) cancelAnimationFrame(raf);
  raf = null;
  el?.classList.remove('show', EDGE_CLASS);
  sparkLayer?.replaceChildren();
  syncButtons();
}

export function startBla() {
  if (raf !== null) return;
  const cat = element();
  const [maxX, maxY] = bounds();
  x = Math.random() * Math.max(maxX, 0);
  y = Math.random() * Math.max(maxY, 0);
  // Diagonal, like the DVD logo: equal-ish speed on both axes, random corner.
  const angle = (Math.random() * 0.5 + 0.25) * (Math.PI / 2); // 22.5°–67.5°
  vx = Math.cos(angle) * SPEED * (Math.random() < 0.5 ? -1 : 1);
  vy = Math.sin(angle) * SPEED * (Math.random() < 0.5 ? -1 : 1);
  cat.style.transform = `translate3d(${Math.round(x)}px, ${Math.round(y)}px, 0)`;
  cat.classList.add('show');
  last = performance.now();
  raf = requestAnimationFrame(frame);
  syncButtons();
}

/** Toggles the cat. Exposed on window as bla(). */
export function bla() {
  isBlaRunning() ? stopBla() : startBla();
}

function syncButtons() {
  for (const btn of document.querySelectorAll('[data-bla]')) {
    btn.setAttribute('aria-pressed', String(isBlaRunning()));
  }
}

export function initEasterEgg() {
  document.addEventListener('click', e => {
    if (e.target.closest('[data-bla]')) bla();
  });
  // Nothing to animate while the tab is hidden.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') stopBla();
  });
  window.bla = bla;
  window.blaCorner = cornerFireworks; // see the fireworks without waiting for a corner
}
