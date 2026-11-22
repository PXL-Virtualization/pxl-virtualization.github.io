// Bij kopiëren van een codeblok met meerdere commando's: zet ; tussen de commando's,
// zodat je alles in één keer kan plakken en uitvoeren.
(function () {
  function regels(code) {
    var lijnen = code.querySelectorAll(':scope > span[id^="__span"]');
    var uit = [], prompts = {};
    lijnen.forEach(function (l) {
      if (l.querySelector('.go')) return;              // uitvoer overslaan
      var kloon = l.cloneNode(true);
      var gp = kloon.querySelector('.gp');
      if (gp) prompts[gp.textContent.trim().replace(/:.*$/, '').replace(/^PS .*/, 'PS')] = true;   // gebruiker@server, zonder map
      kloon.querySelectorAll('.gp').forEach(function (p) { p.remove(); });  // prompt weg
      var t = kloon.textContent.replace(/\s+$/, '');
      if (t.trim()) uit.push(t);
    });
    if (Object.keys(prompts).length > 1) return [];   // verschillende servers: niet samenvoegen
    return uit;
  }
  function samen(cmds) {
    if (cmds.some(function (c) { return /<<\s*-?['"]?\w/.test(c); })) return null;  // heredoc: niet aankomen
    var s = cmds[0];
    for (var i = 1; i < cmds.length; i++) {
      var vorige = cmds[i - 1].trim();
      if (/(\\|`|\||&&|\|\||\{|\(|,)$/.test(vorige)) s += '\n' + cmds[i];   // vervolg van hetzelfde commando
      else s += '; ' + cmds[i].trim();
    }
    return s;
  }
  function zet() {
    document.querySelectorAll('.language-console pre, .language-ps1con pre').forEach(function (pre) {
      var code = pre.querySelector('code');
      if (!code || pre.hasAttribute('data-copy')) return;
      var cmds = regels(code);
      if (cmds.length < 2) return;
      var tekst = samen(cmds);
      if (tekst) pre.setAttribute('data-copy', tekst);
    });
  }
  if (window.document$ && window.document$.subscribe) { window.document$.subscribe(zet); }
  else if (document.readyState !== 'loading') { zet(); }
  else { document.addEventListener('DOMContentLoaded', zet); }
})();
