// Página para onde os links de confirmação do Supabase levam.
// O Supabase devolve o resultado no endereço: #error=... quando o link venceu
// ou já foi usado; ?app=cliente|profissional diz qual app destacar.
(function () {
  var hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  var busca = new URLSearchParams(location.search);
  var app = busca.get("app");
  var main = document.querySelector(".confirma");

  if (app === "cliente" || app === "profissional") {
    document.querySelectorAll("[data-app]").forEach(function (a) {
      if (a.getAttribute("data-app") !== app) a.remove();
    });
  }

  var erro = hash.get("error") || busca.get("error");
  if (erro) {
    var codigo = hash.get("error_code") || busca.get("error_code") || "";
    main.classList.add("erro");
    main.setAttribute("data-estado", "erro");
    document.querySelector("[data-icone]").textContent = "schedule";
    document.querySelector("[data-titulo]").textContent =
      codigo === "otp_expired" ? "Este link venceu" : "Não deu para confirmar";
    document.querySelector("[data-texto]").textContent =
      "O link pode ter vencido ou já ter sido usado. Abra o app e entre na sua conta: se ainda faltar confirmar, ele mostra como receber um novo código por e-mail ou SMS.";
    var nota = document.querySelector(".confirma small");
    if (nota) nota.remove();
  }

  // Não deixa o token do link no endereço nem no histórico.
  if (location.hash) history.replaceState(null, "", location.pathname + location.search);
})();
