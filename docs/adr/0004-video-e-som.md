# ADR 0004 — Vídeo e som (P3)

**Status:** funcionando em 2026-11-11 (PRODUTO.md F1t; patches 0010, 0011)

Eram três bloqueios em cadeia, todos corrigidos: buffers de entrada do `MediaCodec` não
eram limpos ao serem reentregues (vídeo sem saída, amostras de áudio descartadas); o item
de Reel era o método estubado `X/09IF.A0p`; e o áudio dos Reels é **xHE-AAC**
(`mp4a.40.42`), que o decoder abria como AAC comum. Medido no app, aba Reels: VP9 ~24
quadros/s, `track_bytes=962560/5s`, `nonsilent_renders=469/469`.

Em aberto: no **feed** o Instagram toca mudo por padrão e tocar no vídeo abre o
visualizador de Reels (com som); stories, vídeo em DM e H.264/HEVC (VideoToolbox) não
foram exercitados nesta rodada. Verificar com `MACAPK_MEDIA_PROBE=1 MACAPK_AUDIO_PROBE=1`.
