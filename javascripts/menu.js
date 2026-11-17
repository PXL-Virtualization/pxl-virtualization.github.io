// Knop in de kopbalk om het linkermenu in en uit te klappen
(function () {
  var ICOON = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/></svg>';
  function lees() { try { return localStorage.getItem("menu-dicht") === "1"; } catch (e) { return false; } }
  function bewaar(d) { try { localStorage.setItem("menu-dicht", d ? "1" : "0"); } catch (e) {} }
  function zet(d) {
    document.body.classList.toggle("menu-dicht", d);
    var b = document.querySelector(".md-menu-toggle");
    if (b) b.title = d ? "Menu tonen" : "Menu verbergen";
  }
  function plaats() {
    zet(lees());
    if (document.querySelector(".md-menu-toggle")) return;
    var titel = document.querySelector(".md-header__title");
    if (!titel) return;
    var b = document.createElement("button");
    b.className = "md-menu-toggle";
    b.type = "button";
    b.setAttribute("aria-label", "Menu in- of uitklappen");
    b.innerHTML = ICOON;
    b.addEventListener("click", function () {
      var d = !document.body.classList.contains("menu-dicht");
      zet(d); bewaar(d);
    });
    titel.parentNode.insertBefore(b, titel);
    zet(lees());
  }
  if (window.document$ && window.document$.subscribe) { window.document$.subscribe(plaats); }
  else if (document.readyState !== "loading") { plaats(); }
  else { document.addEventListener("DOMContentLoaded", plaats); }
})();
