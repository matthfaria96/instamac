# ADR 0001 — Boot determinístico: o passe de canário (P0)

**Status:** resolvido em 2026-11-11 (PRODUTO.md F1q; patches 0005, 0006)

Não era corrida: era determinístico **com sessão logada**. Só com `UserSession` o app
chama `CacheKeyGenerator.initializeKeyGenerator(json)` com o JSON de cache-key do
MobileConfig, e o passe de neutralização de canário (braço *backstop*) tinha reescrito
`libstartup+0x445258` (`ldr x20,[x10,#0x28]`, o `begin()` de um `std::map`) para
`mov x20,#0`. Correção no passe (`arm64_native.cpp`, patch `0006`): o backstop só reescreve
se a comparação recarrega o slot onde o prólogo salvou o canário.

Medido: 6 árvores logadas guardadas travavam 6/6 → abrem 6/6 no feed; 10/10 aberturas
seguidas com a mesma árvore logada; auditoria offline dos 5.764 sites restantes do
backstop: todos alimentam `__stack_chk_fail`/epílogo. Árvores de teste: `/tmp/instamac-data-*`.

Ao mexer no passe de canário ou no shim: repetir `boot-loop.sh 10 <árvore logada>` e a
auditoria (`MACAPK_CANARY_TRACE=1` + desmontagem dos sites `backstop`).
