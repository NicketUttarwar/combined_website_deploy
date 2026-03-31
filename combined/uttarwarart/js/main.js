/**
 * WebGL art portfolio: sections fly in from off-screen, snap together, then fly out.
 * Single-page scroll; data from output_defaults via art-index.json.
 */

import * as THREE from 'three';

const BASE_URL = 'output_defaults';
const DATA_URL = 'data/art-index.json';

// Scroll layout: about = 0.5 intro + 3 culture blocks (1 viewport each) = 3.5; then artwork
const ABOUT_VIEWPORTS = 3.5;
const ABOUT_FLY_IN_RATIO = 0.32; // same as paintings: first 32% of each block = fly-in
const SCREENS_PER_PIECE = 3;
const FLY_IN_RATIO = 0.32;
const HOLD_RATIO = 0.36;
const FLY_OUT_RATIO = 1 - FLY_IN_RATIO - HOLD_RATIO;
const SCROLL_TRAVEL_MULTIPLIER = 2.25;
const NAV_SCROLL_DURATION_MULTIPLIER = 0.45;
const ARTWORK_MAX_HEIGHT = 3.75;

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

function clamp(x, a, b) {
  return Math.max(a, Math.min(b, x));
}

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** Return off-screen direction for section index (cycle left/right/top/bottom) */
function offScreenDirection(index) {
  const d = ['left', 'right', 'top', 'bottom'];
  return d[index % 4];
}

/**
 * For pieces where multiple sections come from the same side, compute stagger
 * delay per section index so they animate in/out separately. Returns a map
 * sectionIndex -> { staggerDelay, pieceMaxStagger } (only for pieces with 2+
 * sections on any side); otherwise section gets staggerDelay 0, pieceMaxStagger 0.
 */
function computeStaggerForPiece(sections) {
  const byDir = { left: [], right: [], top: [], bottom: [] };
  for (const sec of sections) {
    const dir = offScreenDirection(sec.index);
    byDir[dir].push(sec.index);
  }
  const STAGGER_STEP = 0.28; // delay between each section on the same side
  let pieceMaxStagger = 0;
  const delayByIndex = new Map();
  for (const dir of Object.keys(byDir)) {
    const indices = byDir[dir];
    if (indices.length < 2) continue;
    indices.sort((a, b) => a - b);
    indices.forEach((idx, i) => {
      const delay = i * STAGGER_STEP;
      delayByIndex.set(idx, delay);
      pieceMaxStagger = Math.max(pieceMaxStagger, delay);
    });
  }
  return (sectionIndex) => {
    const staggerDelay = delayByIndex.get(sectionIndex) ?? 0;
    return { staggerDelay, pieceMaxStagger };
  };
}

/** Culinary carousel: continuous scroll is CSS-driven (no dots, no JS). */
function initCarousel() {
  /* Carousel uses CSS animation for infinite scroll; no JS needed. */
}

/** Build scene and scroll-driven animation */
async function init() {
  initCarousel();
  const indexRes = await fetch(DATA_URL);
  if (!indexRes.ok) throw new Error('Failed to load art index');
  const artIndex = await indexRes.json();
  if (!artIndex.length) throw new Error('No pieces in art index');

  const viewport = { width: window.innerWidth, height: window.innerHeight };
  const scrollSpacer = document.getElementById('scroll-spacer');
  const aboutSection = document.getElementById('about');
  const aboutIntro = aboutSection?.querySelector('.about-intro');
  const cultureBlocks = aboutSection ? [...aboutSection.querySelectorAll('.culture-block')] : [];
  const getScrollUnit = () => window.innerHeight / SCROLL_TRAVEL_MULTIPLIER;
  function updateLayoutHeights() {
    const scrollUnit = getScrollUnit();
    if (aboutSection) aboutSection.style.minHeight = `${ABOUT_VIEWPORTS * scrollUnit}px`;
    if (aboutIntro) aboutIntro.style.minHeight = `${0.5 * scrollUnit}px`;
    cultureBlocks.forEach((block) => {
      block.style.minHeight = `${scrollUnit}px`;
    });
  }
  function updateScrollHeight() {
    const screenH = getScrollUnit();
    const artworkHeight = artIndex.length * SCREENS_PER_PIECE * screenH;
    scrollSpacer.style.height = artworkHeight + 'px';
  }
  updateLayoutHeights();
  updateScrollHeight();

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0a0a0b);

  const aspect = viewport.width / viewport.height;
  const camera = new THREE.OrthographicCamera(
    -2.5 * aspect, 2.5 * aspect, 2.5, -2.5, 0.1, 100
  );
  camera.position.z = 5;

  const canvasWrap = document.getElementById('canvas-wrap');
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setSize(viewport.width, viewport.height);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  canvasWrap.appendChild(renderer.domElement);

  const pieces = [];
  const textureLoader = new THREE.TextureLoader();

  for (let i = 0; i < artIndex.length; i++) {
    const piece = artIndex[i];
    const cw = piece.composite_width_px;
    const ch = piece.composite_height_px;
    const compositeAspect = cw / ch;
    const viewAspect = viewport.width / viewport.height;
    let scaleH = ARTWORK_MAX_HEIGHT;
    let scaleW = ARTWORK_MAX_HEIGHT * compositeAspect;
    if (scaleW > ARTWORK_MAX_HEIGHT * viewAspect) {
      scaleW = ARTWORK_MAX_HEIGHT * viewAspect;
      scaleH = scaleW / compositeAspect;
    }
    const offDist = 2.2;
    const getStagger = computeStaggerForPiece(piece.sections);

    const group = new THREE.Group();
    group.visible = false;
    scene.add(group);

    const sectionData = [];
    for (const sec of piece.sections) {
      const b = sec.bounds_px;
      const cx = b.x + b.width / 2;
      const cy = b.y + b.height / 2;
      const nx = (cx / cw - 0.5) * scaleW;
      const ny = (0.5 - cy / ch) * scaleH;
      const sw = (b.width / cw) * scaleW;
      const sh = (b.height / ch) * scaleH;

      const endPos = new THREE.Vector3(nx, ny, 0);
      const dir = offScreenDirection(sec.index);
      const startPos = new THREE.Vector3();
      if (dir === 'left') startPos.set(-offDist - sw / 2, ny, 0);
      else if (dir === 'right') startPos.set(offDist + sw / 2, ny, 0);
      else if (dir === 'top') startPos.set(nx, offDist + sh / 2, 0);
      else startPos.set(nx, -offDist - sh / 2, 0);

      const { staggerDelay, pieceMaxStagger } = getStagger(sec.index);

      const url = `${BASE_URL}/${piece.folder}/${sec.filename}`;
      const texture = await new Promise((resolve, reject) => {
        textureLoader.load(url, resolve, undefined, reject);
      });
      texture.colorSpace = THREE.SRGBColorSpace;
      texture.minFilter = THREE.LinearMipmapLinearFilter;
      texture.magFilter = THREE.LinearFilter;

      const geometry = new THREE.PlaneGeometry(sw, sh);
      const material = new THREE.MeshBasicMaterial({
        map: texture,
        transparent: true,
        depthTest: true,
        depthWrite: true,
        side: THREE.DoubleSide,
      });
      const mesh = new THREE.Mesh(geometry, material);
      mesh.position.copy(startPos);
      mesh.userData = { startPos, endPos };
      group.add(mesh);
      sectionData.push({ mesh, startPos, endPos, staggerDelay, pieceMaxStagger });
    }

    pieces.push({
      group,
      sectionData,
      sourceFilename: piece.source_filename,
      food: piece.food || '',
    });
  }

  // Progress dots: three About (Mumbai, London, SF) under ABOUT, one per artwork under ARTWORKS
  const dotsAboutEl = document.getElementById('progress-dots-about');
  const dotsArtworksEl = document.getElementById('progress-dots-artworks');
  const labelEl = document.getElementById('piece-label');
  const pieceLabelNoteEl = document.getElementById('piece-label-note');
  /** Optional captions keyed by `food` from art-index.json */
  const ARTWORK_NOTES_BY_FOOD = {
    'Gulab jamun': 'Painted in Cincinnati, Ohio.',
    'Bread pudding': 'Made with cousins & friends.',
    'Irish coffee': 'Made with cousins.',
    'High tea':
      'The dog paw print is Junior’s — in Cupertino. The “collaboration” took place while the painting was drying in the garage.',
  };
  const aboutLabels = ['Mumbai', 'London', 'San Francisco'];
  aboutLabels.forEach((label, i) => {
    const dot = document.createElement('button');
    dot.type = 'button';
    dot.className = 'dot dot-about';
    dot.setAttribute('data-section', 'about');
    dot.setAttribute('data-culture', i);
    dot.setAttribute('title', label);
    dot.setAttribute('aria-label', `Scroll to ${label} section`);
    dotsAboutEl.appendChild(dot);
  });
  artIndex.forEach((piece, i) => {
    const dot = document.createElement('button');
    dot.type = 'button';
    dot.className = 'dot';
    dot.setAttribute('data-index', i);
    dot.setAttribute('title', piece.food || '');
    dot.setAttribute('aria-label', `Scroll to artwork ${i + 1}${piece.food ? `: ${piece.food}` : ''}`);
    dotsArtworksEl.appendChild(dot);
  });

  const aboutHeight = () => ABOUT_VIEWPORTS * getScrollUnit();

  function getTotalScrollHeight() {
    const screenH = getScrollUnit();
    const aboutPx = ABOUT_VIEWPORTS * screenH;
    const artworkPx = artIndex.length * SCREENS_PER_PIECE * screenH;
    return aboutPx + artworkPx;
  }

  let activeAutoScroll = null;

  function stopAutoScroll() {
    if (!activeAutoScroll) return;
    cancelAnimationFrame(activeAutoScroll.rafId);
    activeAutoScroll = null;
  }

  function easeScrollTo(targetY) {
    const maxScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 0);
    const finalTargetY = clamp(targetY, 0, maxScroll);

    if (prefersReducedMotion()) {
      stopAutoScroll();
      window.scrollTo(0, finalTargetY);
      return;
    }

    const startY = window.scrollY;
    const distance = finalTargetY - startY;
    if (Math.abs(distance) < 2) {
      window.scrollTo(0, finalTargetY);
      return;
    }

    stopAutoScroll();
    const duration = clamp((450 + Math.abs(distance) * 0.2) * NAV_SCROLL_DURATION_MULTIPLIER, 180, 700);
    const startTime = performance.now();

    const step = (now) => {
      if (!activeAutoScroll) return;
      const elapsed = now - startTime;
      const progress = clamp(elapsed / duration, 0, 1);
      const eased = easeInOutCubic(progress);
      window.scrollTo(0, startY + distance * eased);

      if (progress < 1) {
        activeAutoScroll.rafId = requestAnimationFrame(step);
      } else {
        window.scrollTo(0, finalTargetY);
        activeAutoScroll = null;
      }
    };

    activeAutoScroll = { rafId: requestAnimationFrame(step) };
  }

  function getAboutTargetScroll(cultureIndex) {
    const blockCenters = [1, 2, 3];
    return blockCenters[cultureIndex] * getScrollUnit();
  }

  function getArtworkTargetScroll(pieceIndex) {
    const holdCenterRatio = FLY_IN_RATIO + HOLD_RATIO / 2;
    return aboutHeight() + pieceIndex * SCREENS_PER_PIECE * getScrollUnit()
      + holdCenterRatio * SCREENS_PER_PIECE * getScrollUnit();
  }

  function bindNavigatorClicks() {
    dotsAboutEl.querySelectorAll('.dot').forEach((dot) => {
      dot.addEventListener('click', () => {
        const cultureIndex = Number(dot.getAttribute('data-culture'));
        if (Number.isNaN(cultureIndex)) return;
        easeScrollTo(getAboutTargetScroll(cultureIndex));
      });
    });

    dotsArtworksEl.querySelectorAll('.dot').forEach((dot) => {
      dot.addEventListener('click', () => {
        const pieceIndex = Number(dot.getAttribute('data-index'));
        if (Number.isNaN(pieceIndex)) return;
        easeScrollTo(getArtworkTargetScroll(pieceIndex));
      });
    });
  }

  function getScrollState() {
    const scrollY = window.scrollY;
    const screenH = getScrollUnit();
    const aboutHeightPx = aboutHeight();
    const artworkScroll = scrollY - aboutHeightPx;
    const segment = SCREENS_PER_PIECE * screenH;
    const pieceIndex = artworkScroll < 0
      ? -1
      : clamp(Math.floor(artworkScroll / segment), 0, artIndex.length - 1);
    const localScroll = artworkScroll < 0 ? 0 : artworkScroll - pieceIndex * segment;
    const t = clamp(localScroll / segment, 0, 1);

    let phase; let tPhase;
    if (t < FLY_IN_RATIO) {
      phase = 'in';
      tPhase = t / FLY_IN_RATIO;
    } else if (t < FLY_IN_RATIO + HOLD_RATIO) {
      phase = 'hold';
      tPhase = 1;
    } else {
      phase = 'out';
      tPhase = (t - FLY_IN_RATIO - HOLD_RATIO) / FLY_OUT_RATIO;
    }

    const totalHeight = getTotalScrollHeight();
    return {
      pieceIndex,
      phase,
      tPhase: easeInOutCubic(tPhase),
      screenH,
      segment,
      scrollY,
      aboutHeightPx: aboutHeight(),
      totalHeight,
    };
  }

  function updateAboutSection(state) {
    const { scrollY, screenH, aboutHeightPx } = state;
    if (scrollY >= aboutHeightPx) return;
    const mumbaiWrap = document.getElementById('about-img-mumbai');
    const londonWrap = document.getElementById('about-img-london');
    const sfWrap = document.getElementById('about-img-sf');
    if (!mumbaiWrap || !londonWrap || !sfWrap) return;

    const wraps = [mumbaiWrap, londonWrap, sfWrap];
    const flyDir = ['left', 'right', 'left']; // Mumbai from left, London from right, SF from left
    const viewportPerBlock = 1; // 1 viewport per culture block; first block starts at 0.5
    const blockStart = [0.5, 1.5, 2.5]; // start of each block in viewports

    for (let i = 0; i < 3; i++) {
      const startVp = blockStart[i];
      const endVp = startVp + viewportPerBlock;
      const scrollVp = scrollY / screenH;
      let t = 0;
      if (scrollVp >= endVp) t = 1;
      else if (scrollVp >= startVp) {
        const local = (scrollVp - startVp) / viewportPerBlock;
        t = local < ABOUT_FLY_IN_RATIO
          ? easeInOutCubic(local / ABOUT_FLY_IN_RATIO)
          : 1;
      }
      const dir = flyDir[i];
      let x = 0; let y = 0;
      const off = 120; // percent off-screen
      if (dir === 'left') x = (1 - t) * -off;
      else if (dir === 'right') x = (1 - t) * off;
      else if (dir === 'bottom') y = (1 - t) * off;
      wraps[i].style.transform = `translate(${x}%, ${y}%)`;
    }
  }

  function updatePieces(state) {
    const { pieceIndex, phase, tPhase } = state;
    pieces.forEach((p, i) => {
      p.group.visible = i === pieceIndex;
    });

    const current = pieceIndex >= 0 ? pieces[pieceIndex] : null;
    if (!current) return;

    current.sectionData.forEach(({ mesh, startPos, endPos, staggerDelay = 0, pieceMaxStagger = 0 }) => {
      const pos = mesh.position;
      const denom = Math.max(1 - pieceMaxStagger, 0.001);
      const effectiveT = clamp((tPhase - staggerDelay) / denom, 0, 1);
      if (phase === 'in') {
        pos.lerpVectors(startPos, endPos, effectiveT);
      } else if (phase === 'hold') {
        pos.copy(endPos);
      } else {
        pos.lerpVectors(endPos, startPos, effectiveT);
      }
    });

    const filenameStr = current.sourceFilename.replace(/_/g, ' ');
    labelEl.textContent = current.food ? `${filenameStr} — ${current.food}` : filenameStr;
    if (pieceLabelNoteEl) {
      const note = ARTWORK_NOTES_BY_FOOD[current.food];
      if (note) {
        pieceLabelNoteEl.textContent = note;
        pieceLabelNoteEl.removeAttribute('hidden');
        pieceLabelNoteEl.classList.add('is-visible');
      } else {
        pieceLabelNoteEl.textContent = '';
        pieceLabelNoteEl.setAttribute('hidden', '');
        pieceLabelNoteEl.classList.remove('is-visible');
      }
    }
    document.querySelectorAll('.progress-dots-artworks .dot').forEach((el, i) => {
      el.classList.toggle('active', i === pieceIndex);
    });
  }

  /** Which culture block (0=Mumbai, 1=London, 2=SF) is in view; -1 during intro */
  function getAboutCultureIndex(state) {
    const { scrollY, screenH } = state;
    const scrollVp = scrollY / screenH;
    if (scrollVp < 0.5) return -1;
    if (scrollVp < 1.5) return 0;
    if (scrollVp < 2.5) return 1;
    if (scrollVp < 3.5) return 2;
    return -1;
  }

  function updateUIForSection(state) {
    const inAbout = state.pieceIndex < 0;
    const aboutCulture = getAboutCultureIndex(state);
    const dotsAboutElInner = document.getElementById('progress-dots-about');
    const dotsArtworksElInner = document.getElementById('progress-dots-artworks');
    const pieceLabel = document.getElementById('piece-label');
    if (dotsAboutElInner) {
      dotsAboutElInner.style.opacity = '1';
      dotsAboutElInner.querySelectorAll('.dot').forEach((el) => {
        const cultureIndex = parseInt(el.getAttribute('data-culture'), 10);
        el.classList.toggle('active', inAbout && cultureIndex === aboutCulture);
      });
    }
    if (dotsArtworksElInner) {
      dotsArtworksElInner.style.opacity = '1';
      dotsArtworksElInner.querySelectorAll('.dot').forEach((el, i) => {
        el.classList.toggle('active', !inAbout && i === state.pieceIndex);
      });
    }
    if (pieceLabel) {
      pieceLabel.style.opacity = '0.85';
      const docLabel = document.querySelector('.piece-label-doc');
      if (docLabel) docLabel.textContent = inAbout ? 'Section' : 'Current artwork';
      if (inAbout) pieceLabel.textContent = aboutCulture >= 0 ? aboutLabels[aboutCulture] : 'About';
    }
    if (pieceLabelNoteEl && inAbout) {
      pieceLabelNoteEl.textContent = '';
      pieceLabelNoteEl.setAttribute('hidden', '');
      pieceLabelNoteEl.classList.remove('is-visible');
    }
  }

  function onScroll() {
    const state = getScrollState();

    updateAboutSection(state);
    updatePieces(state);
    updateUIForSection(state);
  }

  function onResize() {
    viewport.width = window.innerWidth;
    viewport.height = window.innerHeight;
    updateLayoutHeights();
    updateScrollHeight();
    updateAboutSection(getScrollState());
    renderer.setSize(viewport.width, viewport.height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    const a = window.innerWidth / window.innerHeight;
    camera.left = -2.5 * a;
    camera.right = 2.5 * a;
    camera.top = 2.5;
    camera.bottom = -2.5;
    camera.updateProjectionMatrix();
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onResize);
  window.addEventListener('wheel', stopAutoScroll, { passive: true });
  window.addEventListener('touchstart', stopAutoScroll, { passive: true });
  window.addEventListener('keydown', (event) => {
    if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', 'Space'].includes(event.code)) {
      stopAutoScroll();
    }
  });
  bindNavigatorClicks();
  onResize();
  onScroll();

  function animate() {
    requestAnimationFrame(animate);
    renderer.render(scene, camera);
  }
  animate();

  const loadingEl = document.getElementById('loading');
  if (loadingEl) {
    loadingEl.classList.add('hidden');
    setTimeout(() => loadingEl.remove(), 600);
  }
}

init().catch((err) => {
  console.error(err);
  document.body.innerHTML = '<div style="padding:2rem;font-family:sans-serif;color:#fff;">Failed to load portfolio. Ensure <code>output_defaults</code> and <code>data/art-index.json</code> exist. Run <code>./run-web.sh</code> to build and serve.</div>';
});
