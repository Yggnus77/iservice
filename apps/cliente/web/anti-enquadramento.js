// Paliativo contra clickjacking: se o painel for aberto dentro de um iframe de
// outro site, a página some e tenta abrir no lugar da página de fora.
// A proteção definitiva é o cabeçalho HTTP frame-ancestors / X-Frame-Options.
(function () {
  if (window.top === window.self) return;
  document.documentElement.style.setProperty('display', 'none', 'important');
  try { window.top.location.replace(window.location.href); } catch (e) { /* bloqueado pelo navegador */ }
})();
