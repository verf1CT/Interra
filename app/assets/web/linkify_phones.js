(function(){
  var box = document.querySelector('.b-informer');
  if(!box || box.__telLinked) return;
  box.__telLinked = true;
  // +7/8, затем ещё 10 цифр через любые разделители
  var re = /(?:\+7|8)[\s\-–()]*\d(?:[\s\-–()]*\d){9}/g;
  var walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT, null);
  var targets = [];
  while(walker.nextNode()){
    var n = walker.currentNode;
    if(n.parentNode && n.parentNode.closest && n.parentNode.closest('a')) continue;
    re.lastIndex = 0;
    if(re.test(n.nodeValue)) targets.push(n);
  }
  targets.forEach(function(n){
    re.lastIndex = 0;
    var html = n.nodeValue.replace(re, function(m){
      var d = m.replace(/\D/g,'');
      if(d.length !== 11) return m;
      if(d[0] === '8') d = '7' + d.slice(1);
      return '<a href="tel:+' + d + '">' + m + '</a>';
    });
    if(html !== n.nodeValue){
      var span = document.createElement('span');
      span.innerHTML = html;
      n.parentNode.replaceChild(span, n);
    }
  });
})();
