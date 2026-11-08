'use strict';

const byId = id => document.getElementById(id);
const viewer = byId('viewer');
const portfolioOrder = [
  'd6a6533cd71be748905b4a1a6ff86f4cff6f2e5e13a864dd7908fc9c0371e43d',
  '7ea869b47666a92eb0f01054c923c2580d395af02417830c57c4d4c4ebcb91db',
  '982c4ca43178bcde8cdcd6852eef09886f8fd11d6577a5113686242922e8d1be',
  '2e908dbcbef54db701baf97396bb4d907871e868fca989a4147bf426b7b554b4',
  'e92637f1ba561fe5d1172d544046540e5d8ec26ca39bef4c25b3c4012dbd06a8',
  'f23e36705bed9a40e246ea88363b0ef2ef26db395a4364e604b6d35748893533',
  '8cb967159c12d53b2edef6ad3589295dbc1c6f02ea2d515a9c73398dd5ae35e1',
];
let portfolio = [];
let photographs = [];
let selection = [];
let index = 0;
let thumbnails = false;

function namedTitle(photo) {
  return /^(PXL|IMG|DSC|DSCF|DJI)[ _.-]*\d/i.test(photo.title) ? '' : photo.title;
}

function showPhotograph() {
  const photo = selection[index];
  const caption = [photo.album, namedTitle(photo)].filter(Boolean).join(' — ');
  const position = (index + 1) + ' / ' + selection.length;
  byId('print').src = photo.src;
  byId('print').alt = namedTitle(photo) || photo.album + ', photograph ' + (index + 1);
  byId('caption').textContent = caption;
  byId('count').textContent = position;
  if (viewer.open) {
    byId('large').src = photo.src;
    byId('large').alt = byId('print').alt;
    byId('large-caption').textContent = caption + ' · ' + position;
  }
  for (const id of ['previous', 'next', 'back', 'forward']) byId(id).disabled = selection.length < 2;
}

function move(step) {
  if (!selection.length || thumbnails) return;
  index = (index + step + selection.length) % selection.length;
  showPhotograph();
}

function showGrid() {
  const fragment = document.createDocumentFragment();
  selection.forEach((photo, number) => {
    const button = document.createElement('button');
    const image = document.createElement('img');
    image.src = photo.thumb;
    image.alt = namedTitle(photo) || photo.album + ', photograph ' + (number + 1);
    image.width = photo.thumbWidth;
    image.height = photo.thumbHeight;
    image.loading = 'lazy';
    button.append(image);
    button.addEventListener('click', () => {
      index = number;
      setMode(false);
      byId('enlarge').focus();
    });
    fragment.append(button);
  });
  byId('grid').replaceChildren(fragment);
}

function setMode(gridMode) {
  thumbnails = gridMode;
  byId('grid').hidden = !gridMode;
  byId('feature').hidden = gridMode;
  byId('paging').hidden = gridMode;
  byId('shuffle').hidden = !gridMode || selection.length < 2;
  byId('mode').textContent = gridMode ? 'Show photograph' : 'Show thumbnails';
  byId('mode').setAttribute('aria-pressed', String(gridMode));
  if (gridMode) showGrid();
  else showPhotograph();
}

function selectAlbum(album) {
  selection = album ? photographs.filter(photo => photo.album === album) : [...portfolio];
  index = 0;
  for (const button of byId('albums').children) {
    button.setAttribute('aria-pressed', String(button.dataset.album === album));
  }
  setMode(thumbnails);
}

async function initialize() {
  const response = await fetch('./data/photos.json', {cache: 'no-cache'});
  if (!response.ok) throw new Error('Gallery unavailable');
  const data = await response.json();
  const validPath = path => /^photos\/[a-f0-9]{64}(?:-thumb)?\.jpg$/.test(path);
  photographs = data.photos.filter(photo => validPath(photo.src) && validPath(photo.thumb));
  if (!photographs.length) {
    byId('status').textContent = 'No photographs yet.';
    return;
  }
  // Lead with the Edinburgh skyline when it is present in the published selection.
  const cover = photographs.findIndex(photo => photo.id === 'd6a6533cd71be748905b4a1a6ff86f4cff6f2e5e13a864dd7908fc9c0371e43d');
  if (cover > 0) photographs.unshift(photographs.splice(cover, 1)[0]);
  const albums = [...new Set(photographs.map(photo => photo.album))].filter(Boolean).sort();
  const publishedPhotos = new Map(photographs.map(photo => [photo.id, photo]));
  portfolio = portfolioOrder.map(id => publishedPhotos.get(id)).filter(Boolean);
  const navigation = portfolio.length ? ['', ...albums] : albums;
  for (const album of navigation) {
    const button = document.createElement('button');
    button.textContent = album || 'Portfolio';
    button.dataset.album = album;
    button.addEventListener('click', () => selectAlbum(album));
    byId('albums').append(button);
  }
  byId('tools').hidden = false;
  byId('status').hidden = true;
  selectAlbum(navigation[0]);
}

byId('mode').onclick = () => setMode(!thumbnails);
byId('shuffle').onclick = () => {
  for (let i = selection.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [selection[i], selection[j]] = [selection[j], selection[i]];
  }
  index = 0;
  showGrid();
};
byId('previous').onclick = byId('back').onclick = () => move(-1);
byId('next').onclick = byId('forward').onclick = () => move(1);
byId('enlarge').onclick = () => {
  viewer.showModal();
  showPhotograph();
  byId('close').focus();
};
byId('close').onclick = () => viewer.close();
document.addEventListener('keydown', event => {
  if (event.altKey || event.ctrlKey || event.metaKey || thumbnails) return;
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault();
    move(event.key === 'ArrowLeft' ? -1 : 1);
  }
});
for (const element of [byId('enlarge'), byId('large')]) {
  let start;
  let swiped = false;
  element.addEventListener('touchstart', event => {
    swiped = false;
    start = event.touches.length === 1 ? event.touches[0] : null;
  }, {passive: true});
  element.addEventListener('touchend', event => {
    if (!start) return;
    const dx = event.changedTouches[0].clientX - start.clientX;
    const dy = event.changedTouches[0].clientY - start.clientY;
    start = null;
    swiped = Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5;
    if (swiped) move(dx < 0 ? 1 : -1);
  }, {passive: true});
  element.addEventListener('touchcancel', () => { start = null; });
  element.addEventListener('click', event => {
    if (swiped) { event.stopImmediatePropagation(); swiped = false; }
  }, true);
}
initialize().catch(() => { byId('status').textContent = 'The photographs could not load. Please refresh to try again.'; });

