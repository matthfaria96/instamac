# ADR 0022 — Links do WhatsApp abertos pelo Mac (pacote companheiro)

## Contexto
O dono clicou no link de WhatsApp de um perfil e o navegador abriu uma página quebrada. Log:
`host open(https://play.google.com/d?id=com.whatsapp&referrer=…ig_profile_links)`. O Instagram
(`X.0MOr`) pergunta `getPackageInfo("com.whatsapp")` (`X.01gi.A07`, sem checar assinatura) e,
sem o pacote, troca o link pela loja.

## Decisão
`com.whatsapp` é um "companheiro": um pacote cujo trabalho o Mac faz (`HostCompanions`, mesmo
princípio do navegador sintético `com.macapk.host`, que existe porque o Mac realmente abre a URL).
- Listado como instalado (`PackageInfo`/`ApplicationInfo` habilitados, assinatura nossa e vazia:
  quem verificar o certificado do WhatsApp vê que não é ele).
- Sua atividade resolve só para o que o Mac faz: `VIEW` de endereço http(s)/whatsapp e `SEND`
  de texto. Um início endereçado a ele abre no Mac pelo mesmo portão de clique do usuário:
  `VIEW` → o link puro (`wa.me/<número>`, sem `source_surface`/`token`; `text` fica);
  `SEND` → `https://wa.me/?text=<texto>`. O navegador passa ao WhatsApp do Mac, ou ao WhatsApp Web.
- `MACAPK_HOST_COMPANIONS=0` desliga.

## Medição (clone, com `MACAPK_EXTERNAL_URLS=0` para não abrir o navegador)
Perfil com link wa.me → folha "Links" → toque: `REFUSED android.intent.action.VIEW for
com.whatsapp -> host open(https://wa.me/<número>)`. Antes: a URL da Play Store.

## Consequências
- O botão WhatsApp da folha de compartilhar passa a mandar o texto (link do post) para o
  WhatsApp pelo Mac; não exercitado.
- Patch 0029.
