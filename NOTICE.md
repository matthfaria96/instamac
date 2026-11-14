# Atribuição, licença e limites

## Derivado do Mac.apk

O Instamac é um trabalho derivado do [Mac.apk](https://github.com/kksimp/Mac.apk), de
Kaleb Simpson / Voltare, licenciado sob **GNU AGPL v3.0**. O fonte do upstream é mantido
em `vendor/macapk`, fixado no commit `57c9912`.

Sob a AGPL-3.0:

- este repositório é licenciado sob a mesma licença ([LICENSE](LICENSE));
- toda modificação do Instamac sobre o upstream é publicada aqui, em `src/`;
- se o Instamac for distribuído como app, o código correspondente (incluindo os scripts
  de build e o jar gerado a partir de `src/`) acompanha a distribuição.

O Mac.apk está disponível gratuitamente em sua página oficial; o Instamac não
redistribui o app assinado do upstream, e sim a sua própria construção sobre o fonte.

## Marcas

- "Mac.apk" e o logo do Mac.apk são marcas do projeto original e **não** são usados como
  nome, ícone ou identidade deste fork.
- "Instagram" é marca da Meta Platforms, Inc. O Instamac não é afiliado, patrocinado ou
  endossado pela Meta. O app do Instagram não é distribuído por este projeto: o usuário
  instala o APK que já tem direito de usar.

## Limites do que este projeto faz

O Instamac **não**:

- modifica, patcheia ou redistribui o APK do Instagram;
- contorna licenciamento, cobrança ou DRM;
- falsifica Play Integrity, SafetyNet, DeviceCheck ou qualquer atestado de hardware;
- contorna bloqueio geográfico, banimento ou controle de acesso da Meta.

O Instamac **faz**: implementa a camada de compatibilidade que permite a um app Android
legítimo executar no macOS. No Brasil, a reverse engineering para interoperabilidade é
expressamente permitida pela Lei 9.609/98, art. 6º, I e II. Ainda assim, executar o
Instagram fora do ambiente oficial pode contrariar os Termos de Uso da Meta — a decisão e
o risco de conta são do usuário.

## Componentes de terceiros

O runtime do Mac.apk embarca componentes com licenças próprias (ANGLE, MoltenVK/Vulkan
loader, Capstone, libpng, libvpx, stb_vorbis, Bouncy Castle, JRE construído a partir do
OpenJDK, FreeType, HarfBuzz, GLib, recursos de plataforma do AOSP). As notas completas
estão em `vendor/macapk/THIRD_PARTY_NOTICES.txt` e acompanham o app distribuído.

O pacote de conveniência `com.google.android.gms`/Play Store **não** é redistribuído
aqui; se o Instamac vier a precisar dele, o usuário o obtém de uma imagem de emulador
própria, como o Mac.apk já documenta.
