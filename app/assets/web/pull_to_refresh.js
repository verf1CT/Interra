(function(){
  if(window.__interraPTR) return; window.__interraPTR = true;

  var THRESHOLD = 70, MAX = 120;
  var startY = 0, pull = 0, pulling = false, triggered = false;

  var st = document.createElement('style');
  st.textContent =
    '@keyframes interraSpin{to{transform:rotate(360deg)}}' +
    '#interraPTR{position:fixed;top:0;left:50%;margin-left:-18px;' +
    'width:36px;height:36px;z-index:2147483647;opacity:0;' +
    'pointer-events:none;will-change:transform,opacity;}' +
    '#interraPTR svg{display:block;width:36px;height:36px;}' +
    '#interraPTR .ring{fill:none;stroke:#3C98D4;stroke-width:4;' +
    'stroke-linecap:round;stroke-dasharray:80;stroke-dashoffset:20;}';
  document.head.appendChild(st);

  var ind = document.createElement('div');
  ind.id = 'interraPTR';
  ind.innerHTML =
    '<svg viewBox="0 0 36 36"><circle class="ring" cx="18" cy="18" r="15"/></svg>';
  document.documentElement.appendChild(ind);

  var doc = document.documentElement;
  function atTop(){ return (window.scrollY||doc.scrollTop||0) <= 0; }

  function setPull(p){
    pull = p;
    var clamped = Math.min(p, MAX);
    document.body.style.transform = 'translateY(' + clamped + 'px)';
    ind.style.opacity = Math.min(clamped / THRESHOLD, 1);
    var iy = clamped - 40;
    var scale = 0.6 + Math.min(clamped / MAX, 1) * 0.4;
    ind.style.transform =
      'translateY(' + iy + 'px) rotate(' + (clamped * 3) + 'deg) scale(' + scale + ')';
  }

  function reset(animate){
    if(animate){
      document.body.style.transition = 'transform .25s ease';
      ind.style.transition = 'transform .25s ease, opacity .25s ease';
    }
    document.body.style.transform = '';
    ind.style.opacity = 0;
    ind.style.transform = 'translateY(0) rotate(0deg) scale(0.6)';
    ind.style.animation = '';
    setTimeout(function(){
      document.body.style.transition = '';
      ind.style.transition = '';
    }, 260);
    pull = 0; pulling = false; triggered = false;
  }

  document.addEventListener('touchstart', function(e){
    if(triggered) return;
    if(atTop()){ startY = e.touches[0].clientY; pulling = true; }
    else { pulling = false; }
  }, {passive:true});

  document.addEventListener('touchmove', function(e){
    if(!pulling || triggered) return;
    var delta = e.touches[0].clientY - startY;
    if(delta <= 0 || !atTop()){
      if(pull > 0) reset(true);
      return;
    }
    e.preventDefault();
    setPull(delta * 0.5);
  }, {passive:false});

  function end(){
    if(!pulling || triggered) return;
    if(Math.min(pull, MAX) >= THRESHOLD){
      triggered = true;
      document.body.style.transition = 'transform .2s ease';
      document.body.style.transform = 'translateY(50px)';
      ind.style.transition = 'transform .2s ease, opacity .2s ease';
      ind.style.transform = 'translateY(8px) scale(1)';
      var svg = ind.querySelector('svg');
      svg.style.transformOrigin = '50% 50%';
      svg.style.animation = 'interraSpin .8s linear infinite';
      ind.style.opacity = 1;
      if(window.PullRefresh) window.PullRefresh.postMessage('refresh');
    } else {
      reset(true);
    }
  }
  document.addEventListener('touchend', end, {passive:true});
  document.addEventListener('touchcancel', function(){
    if(!triggered) reset(true);
  }, {passive:true});
})();
