'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const viewer = $('viewer');
  let photos = [], visible = [], current = 0, activeAlbum = '', lastFocus;
  let touchStart = null;
  $('year').textContent = $('copyright-year').textContent = String(new Date().getFullYear());
  function safeImagePath(value) {
    return typeof value === 'string' && /^photos\/[a-f0-9]{64}(?:-thumb)?\.jpg$/.test(value);
  }
  function updateViewer() {
    const p = visible[current];
    if (!p) return;
    $('viewer-image').src = p.src;
    $('viewer-image').alt = p.title || 'Photograph';
    $('viewer-title').textContent = p.title;
    $('viewer-album').textContent = p.album;
    $('viewer-count').textContent = `${String(current + 1).padStart(2, '0')} / ${String(visible.length).padStart(2, '0')}`;
    $('previous').disabled = $('next').disabled = visible.length < 2;
  }
  function move(offset) {
    if (!visible.length) return;
    current = (current + offset + visible.length) % visible.length;
    updateViewer();
  }
  function openPhoto(index, trigger) {
    current = index;
    lastFocus = trigger;
    updateViewer();
    viewer.showModal();
    document.body.classList.add('viewing');
    $('close').focus();
  }
  function render() {
    const fragment = document.createDocumentFragment();
    visible.forEach((p, index) => {
      const figure = document.createElement('figure');
      figure.className = 'photo-card';
      const button = document.createElement('button');
      button.className = 'photo-button';
      button.type = 'button';
      button.setAttribute('aria-label', `View ${p.title || 'photograph'}${p.album ? `, ${p.album}` : ''}`);
      const img = document.createElement('img');
      img.src = p.thumb;
      img.alt = p.title || 'Photograph';
      img.width = p.thumbWidth;
      img.height = p.thumbHeight;
      img.loading = index < 3 ? 'eager' : 'lazy';
      img.decoding = 'async';
      const icon = document.createElement('span');
      icon.className = 'photo-open';
      icon.textContent = '↗';
      icon.setAttribute('aria-hidden', 'true');
      button.append(img, icon);
      button.addEventListener('click', () => openPhoto(index, button));
      const caption = document.createElement('figcaption');
      caption.className = 'photo-caption';
      const title = document.createElement('span'), album = document.createElement('span');
      title.className = 'title';
      album.className = 'album';
      title.textContent = p.title;
      album.textContent = p.album;
      caption.append(title, album);
      figure.append(button, caption);
      fragment.append(figure);
    });
    $('gallery').replaceChildren(fragment);
    $('empty').hidden = photos.length > 0;
    $('photo-total').textContent = photos.length ? `${String(visible.length).padStart(2, '0')} photographs` : '';
  }
  function filter(album) {
    activeAlbum = album;
    visible = photos.filter(p => !album || p.album === album);
    document.querySelectorAll('.filter').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.album === activeAlbum)));
    render();
  }
  function createFilters() {
    const albums = [...new Set(photos.map(p => p.album))].filter(Boolean).sort((a,b) => a.localeCompare(b));
    ['', ...albums].forEach(album => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'filter';
      button.textContent = album || 'All photographs';
      button.dataset.album = album;
      button.setAttribute('aria-pressed', String(!album));
      button.addEventListener('click', () => filter(album));
      $('filters').append(button);
    });
  }
  $('close').addEventListener('click', () => viewer.close());
  viewer.addEventListener('close', () => {
    document.body.classList.remove('viewing');
    $('viewer-image').removeAttribute('src');
    lastFocus?.focus();
  });
  $('previous').addEventListener('click', () => move(-1));
  $('next').addEventListener('click', () => move(1));
  viewer.addEventListener('keydown', e => {
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      e.preventDefault();
      move(e.key === 'ArrowLeft' ? -1 : 1);
    }
  });
  $('viewer-stage').addEventListener('touchstart', e => {
    touchStart = e.touches.length === 1 ? {x:e.touches[0].clientX,y:e.touches[0].clientY} : null;
  }, {passive:true});
  $('viewer-stage').addEventListener('touchend', e => {
    if (!touchStart || !e.changedTouches.length) return;
    const dx = e.changedTouches[0].clientX - touchStart.x, dy = e.changedTouches[0].clientY - touchStart.y;
    if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.5) move(dx < 0 ? 1 : -1);
    touchStart = null;
  }, {passive:true});
  $('viewer-stage').addEventListener('touchcancel', () => { touchStart = null; });
  $('shuffle').addEventListener('click', () => {
    for (let i = visible.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [visible[i], visible[j]] = [visible[j], visible[i]];
    }
    render();
  });
  fetch('./data/photos.json', {cache:'no-cache'})
    .then(r => { if (!r.ok) throw new Error('Gallery unavailable'); return r.json(); })
    .then(data => {
      if (!Array.isArray(data.photos)) throw new Error('Invalid gallery');
      photos = data.photos.filter(p => safeImagePath(p.src) && safeImagePath(p.thumb) && typeof p.title === 'string' && typeof p.album === 'string' && p.thumbWidth > 0 && p.thumbHeight > 0);
      $('gallery-toolbar').hidden = photos.length === 0;
      createFilters();
      filter('');
    })
    .catch(() => { $('empty').hidden = true; $('load-error').hidden = false; });
})();
