# ADR 0024 — App sem Homebrew; o que falta para distribuir

## Contexto
Varredura de todo Mach-O do bundle: só o shim do tradutor (`libmacapk-bionic-shim.dylib`)
dependia de fora do sistema (`/opt/homebrew/.../libcapstone.5.dylib` e `libpng16.16.dylib`).
A JVM já é a JRE 25 embutida (ADR 0019).

## Decisão
`scripts/bundle-host-libs.sh <app>` copia para `Contents/Resources/runtime/lib-host/` toda
biblioteca de `/opt/homebrew` ou `/usr/local` usada por um binário do bundle (recursivo),
reaponta por `@loader_path`, reassina ad-hoc preservando entitlements/flags e falha se sobrar
alguma dependência de fora. Etapa 7a do `build-instamac.sh`. O runtime aceita as cópias
porque tem `disable-library-validation`.

## Medição
No clone, `lsof` do processo: capstone e libpng carregadas de dentro do app; nada de
`/opt/homebrew`. Gate 10/10.

## O que falta para distribuir (não feito)
- **Assinatura e notarização:** o Mac não tem identidade "Developer ID Application" (`security
  find-identity`: 0). Exige a conta Apple Developer do dono. Com ela: assinar todo código com
  hardened runtime e carimbo de tempo, `notarytool submit`, `stapler`.
- **Dados fora do bundle:** o app grava em `Contents/android` (sessão, preferências). Um app
  notarizado não pode mudar o próprio bundle (e, baixado, roda em pasta só-leitura). Os dados
  têm de ir para `~/Library/Application Support/Instamac`, com migração do login atual.
