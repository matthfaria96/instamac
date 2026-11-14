// InstamacMain — o executável do Instamac.app.
//
// Uma tarefa: achar o runtime embutido e o Instagram que VIVE dentro deste
// bundle, e virar o runtime via execv.
//
// O contrato de argumentos é o mesmo do stub do Mac.apk
// (launcher/AppStubMain.swift:1230): --apk <arquivo> --android-root <dir>.
// O runtime instala o APK sozinho no android-root quando ele ainda não está lá
// (medido: "cold install (DEX->JAR)" + "installed lib/arm64 ..."); no Instamac
// isso já aconteceu no build (scripts/preseed.sh), não no primeiro uso.
//
// Não existe seletor de APK. O payload é parte do app: se ele não está aqui, o
// build está incompleto e o Instamac diz isso — não pede um arquivo emprestado.

import Cocoa
import Foundation

private let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
private let embeddedDir = contents.appendingPathComponent("app/embedded")
// Build autocontido: o Instagram instalado (data/app, código convertido, libs
// traduzidas) mora dentro do bundle, e escreve dentro dele como um device.
private let embeddedRoot = contents.appendingPathComponent("android")

private func fail(_ title: String, _ detail: String, code: Int32) -> Never {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = detail
    a.alertStyle = .critical
    a.addButton(withTitle: "OK")
    a.runModal()
    exit(code)
}

/// Maior APK sob um diretório — aceita o container original (`.apk`, `.xapk`,
/// `.apkm`, `.apks`) ou o `base.apk` que o runtime já instalou.
private func largestApk(under dir: URL) -> URL? {
    guard let walk = FileManager.default.enumerator(
        at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
    var best: (URL, Int)?
    for case let url as URL in walk {
        let ext = url.pathExtension.lowercased()
        guard url.lastPathComponent == "base.apk"
                || ["apk", "xapk", "apkm", "apks", "apkx"].contains(ext) else { continue }
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > (best?.1 ?? 0) { best = (url, size) }
    }
    return best?.0
}

/// `open -a Instamac --args --apk /caminho/instagram.xapk` troca o payload de
/// um app já construído: copia para dentro do bundle, derruba o código da
/// versão anterior e deixa o runtime reinstalar no próximo lançamento. É o
/// único caminho de atualização — e ele é explícito, não um diálogo.
private func payloadFromArguments() -> URL? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--apk"), i + 1 < args.count else { return nil }
    let src = URL(fileURLWithPath: args[i + 1])
    let fm = FileManager.default
    guard fm.fileExists(atPath: src.path) else {
        fail("APK não encontrado", "\(src.path) não existe.", code: 66)
    }
    try? fm.createDirectory(at: embeddedDir, withIntermediateDirectories: true)
    let dst = embeddedDir.appendingPathComponent(src.lastPathComponent)
    do {
        if dst.path != src.path {
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        // Um payload por bundle: o container antigo sai, senão a resolução
        // poderia escolher o arquivo errado.
        for n in (try? fm.contentsOfDirectory(atPath: embeddedDir.path)) ?? [] {
            if n != dst.lastPathComponent && n != "EMBEDDED" {
                try? fm.removeItem(at: embeddedDir.appendingPathComponent(n))
            }
        }
        try? "\(dst.lastPathComponent)\n".write(
            to: embeddedDir.appendingPathComponent("EMBEDDED"),
            atomically: true, encoding: .utf8)
    } catch {
        fail("Não consegui trocar o APK",
             "Copiar de \(src.path) para \(dst.path) falhou: \(error.localizedDescription)",
             code: 73)
    }
    // Código preparado é função do APK: o antigo não serve para o novo.
    let codeRoot = embeddedRoot.appendingPathComponent(".macapk/code")
    for d in (try? fm.contentsOfDirectory(atPath: codeRoot.path)) ?? [] {
        try? fm.removeItem(at: codeRoot.appendingPathComponent(d))
    }
    return dst
}

// ---------------------------------------------------------------------------
// Log: o runtime escreve tudo em stderr; lançado pelo Finder/Dock esse stderr
// vai para o vazio do launchd e cada falha vira adivinhação. Aqui ele é
// redirecionado para ~/Library/Logs/macapk/app_<data>.log antes do execv, no
// mesmo formato do stub do Mac.apk. Mantém os 3 mais recentes.
// ---------------------------------------------------------------------------

// O cache do Instagram (vídeo e imagens: centenas de MB, cresce com o uso) é
// descartável. Fica em ~/Library/Caches/<bundle id>, onde o macOS o espera, e
// não dentro do .app; no lugar dele fica um link, e o app continua vendo
// /data/data/<pkg>/cache. O link é refeito a cada abertura: o destino depende
// do usuário, e o sistema pode ter limpado a pasta.
private func keepCachesOutOfBundle() {
    let fm = FileManager.default
    let dataRoot = embeddedRoot.appendingPathComponent("data/data")
    let cachesRoot = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches")
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.instamac.app")
    for pkg in (try? fm.contentsOfDirectory(atPath: dataRoot.path)) ?? [] where !pkg.hasPrefix(".") {
        let inside = dataRoot.appendingPathComponent(pkg).appendingPathComponent("cache")
        let outside = cachesRoot.appendingPathComponent(pkg).appendingPathComponent("cache")
        if let target = try? fm.destinationOfSymbolicLink(atPath: inside.path) {
            if target != outside.path {
                try? fm.removeItem(at: inside)
                try? fm.createSymbolicLink(atPath: inside.path, withDestinationPath: outside.path)
            }
            try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
            continue
        }
        try? fm.createDirectory(at: outside.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if fm.fileExists(atPath: inside.path) {
            if fm.fileExists(atPath: outside.path) {
                try? fm.removeItem(at: inside)
            } else if (try? fm.moveItem(at: inside, to: outside)) == nil {
                continue
            }
        }
        try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: inside.path, withDestinationPath: outside.path)
    }
}

private func beginRunLog(apk: URL) -> URL {
    let fm = FileManager.default
    let dir = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/macapk")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let stamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let log = dir.appendingPathComponent("app_com.instagram.android_\(stamp).log")

    // Um arquivo por execução: cresce só o desta sessão (o runtime é verboso).
    for old in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter({ $0.hasPrefix("app_com.instagram.android_") }).sorted().dropLast(3) {
        try? fm.removeItem(at: dir.appendingPathComponent(old))
    }

    let fd = open(log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    guard fd >= 0 else { return log }
    dup2(fd, STDOUT_FILENO)
    dup2(fd, STDERR_FILENO)
    if fd > STDERR_FILENO { close(fd) }

    let header = "---- Instamac run \(stamp) ----\n"
        + "     apk: \(apk.path)\n"
        + "     root: \(embeddedRoot.path)\n"
    FileHandle.standardError.write(header.data(using: .utf8)!)
    return log
}

// ---------------------------------------------------------------------------
// Resolução: payload do bundle > Instagram já instalado no bundle.
// ---------------------------------------------------------------------------

let runtime = contents.appendingPathComponent("Resources/runtime/Resources/macapk-runtime")
let apk = payloadFromArguments()
    ?? largestApk(under: embeddedDir)
    ?? largestApk(under: embeddedRoot.appendingPathComponent("data/app"))

guard let apk else {
    fail("Instamac sem o Instagram",
         "Este bundle não carrega o APK do Instagram em Contents/app/embedded. "
         + "Rode scripts/build-instamac.sh de novo (ele embute o payload/ e "
         + "pré-instala o app).",
         code: 66)
}

try? FileManager.default.createDirectory(at: embeddedRoot, withIntermediateDirectories: true)

guard FileManager.default.fileExists(atPath: runtime.path) else {
    fail("Instamac incompleto",
         "O runtime embutido não está em \(runtime.path). Rode scripts/build-instamac.sh de novo.",
         code: 70)
}

// GALERIA: Imagens e Filmes do Mac são as pastas Pictures e Movies do
// armazenamento do app (links absolutos, que o MediaStore do runtime reconhece
// pelo nome e pelo destino). Assim a galeria do Instagram lista o que está no
// Mac e "salvar" cai em ~/Pictures/Instagram. Documentos e Downloads ficam de
// fora: o macOS pergunta antes de um app tocar neles, e a pergunta trava a
// thread. Só troca uma pasta vazia; o que o app já gravou ali fica onde está.
private func mapUserMediaFolders() {
    let fm = FileManager.default
    let volume = embeddedRoot.appendingPathComponent("sdcard")
    guard fm.fileExists(atPath: volume.path) else { return }
    for name in ["Pictures", "Movies"] {
        let inside = volume.appendingPathComponent(name)
        let outside = fm.homeDirectoryForCurrentUser.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: outside.path, isDirectory: &isDir), isDir.boolValue else { continue }
        if let target = try? fm.destinationOfSymbolicLink(atPath: inside.path) {
            if target != outside.path {     // bundle copiado de outro usuário
                try? fm.removeItem(at: inside)
                try? fm.createSymbolicLink(atPath: inside.path, withDestinationPath: outside.path)
            }
            continue
        }
        if fm.fileExists(atPath: inside.path) {
            guard let entries = try? fm.contentsOfDirectory(atPath: inside.path), entries.isEmpty,
                  (try? fm.removeItem(at: inside)) != nil else { continue }
        }
        try? fm.createSymbolicLink(atPath: inside.path, withDestinationPath: outside.path)
    }
}

keepCachesOutOfBundle()
mapUserMediaFolders()
let runLog = beginRunLog(apk: apk)

// ---------------------------------------------------------------------------
// Ambiente do Instagram: o runtime lê estes MACAPK_* e o app se comporta como
// TABLET (tela grande), em vez de telefone.
//
// MACAPK_LETTERBOX_ASPECT=display: a atividade tem orientação fixa (Instagram
// pede "locked" no launcher), e a regra padrão do runtime letterboxa o app em
// 4:3 dentro da janela -- barras pretas nas laterais e app preso a um retângulo
// de telefone. "display" deixa o app ocupar a janela inteira: em janela
// horizontal ele recebe um canvas horizontal grande (sw1284dp: classe tablet),
// em janela vertical recebe o vertical. É a diferença entre "Instagram de
// telefone dentro de uma janela" e "Instagram de tablet".
//
// Override: `<android-root>/.macapk/runtime_env`, uma linha KEY=VALUE por
// linha. O que estiver lá vence o default, e o que já estiver no ambiente do
// processo vence o arquivo.
// ---------------------------------------------------------------------------

private func applyDefaultEnvironment() {
    let fm = FileManager.default
    var env: [String: String] = [:]
    let file = embeddedRoot.appendingPathComponent(".macapk/runtime_env")
    if let text = try? String(contentsOf: file, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"),
                  let eq = t.firstIndex(of: "=") else { continue }
            env[String(t[..<eq]).trimmingCharacters(in: .whitespaces)] =
                String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
    }
    // Tablet por padrão; arquivo e ambiente mandam mais.
    if getenv("MACAPK_LETTERBOX_ASPECT") == nil {
        env["MACAPK_LETTERBOX_ASPECT"] = env["MACAPK_LETTERBOX_ASPECT"] ?? "display"
    }
    // NÃO pausar a apresentação quando a janela estiver coberta. O runtime
    // pausa/reduz a 2 Hz ao detectar oclusão, e a janela volta PRETA quando o
    // usuário a traz para frente (medido: captura da janela ocluída = preto,
    // captura da mesma janela ativa = tela de login renderizada). Um app de
    // desktop precisa estar pronto quando você olha para ele; o custo é
    // continuar desenhando enquanto está coberto, e isso é aceitável aqui.
    if getenv("MACAPK_PAUSE_WHEN_HIDDEN") == nil {
        env["MACAPK_PAUSE_WHEN_HIDDEN"] = "0"
    }
    // Tela parada = quase nenhum quadro (ADR 0038). O runtime faz um quadro
    // completo de segurança a cada 30 vsyncs; com isto, quando esses quadros não
    // mudam nenhum pixel (medido no Instagram: heartbeat-diff changed=0), o
    // intervalo dobra até 120 vsyncs. Qualquer mudança, toque ou layout volta a 30.
    if getenv("MACAPK_FRAMESPEED_HEARTBEAT") == nil {
        env["MACAPK_FRAMESPEED_HEARTBEAT"] = "1"
    }
    // NOME: o app é Instamac em toda superfície — barra de menu, título da
    // janela, Dock. O runtime usa este rótulo para tudo isso; sem ele cai no
    // nome genérico do motor.
    if getenv("MACAPK_APP_LABEL") == nil {
        env["MACAPK_APP_LABEL"] = "Instamac"
    }
    // DENSIDADE: 320 dpi (xhdpi, o padrão de tablet Android), não 160.
    // MEDIDO: num monitor 1x o runtime reporta 160 dpi, então o Instagram vê
    // uma tela de 2560dp de largura -- o rail de navegação sai com ícones
    // gigantes e o último item cortado na borda (a captura do Kai). Com 320 o
    // canvas vira 1280x642dp, que é tamanho de tablet de verdade, e o rail
    // renderiza certo.
    // (Densidade 320 foi testada e TRAVAVA o boot com frequência; fica no
    // padrão do runtime, 160 em tela 1x.)
    //
    // TAMANHO: a janela nasce com o orçamento de uma TABLET lógica, não do
    // monitor inteiro. Num monitor 1x o runtime mapeia 1dp = 1px, então uma
    // janela de 2560px faz o Instagram ver uma tela de 2560dp -- o rail sai
    // com ícones gigantes e o último item cortado (captura do Kai). Com
    // 1280x800pt o app vê 1280x800dp: tamanho de tablet, rail correto. A
    // janela continua redimensionável; o usuário decide o tamanho final.
    // Girar (View > Girar, Cmd+R) troca entre a tela de telefone e a de tablet.
    // O Instagram só decide telefone x tablet no onCreate, então o giro relança
    // a atividade na tela nova, como o Android faz ao girar o aparelho.
    if getenv("MACAPK_ROTATE_RELAUNCH") == nil {
        env["MACAPK_ROTATE_RELAUNCH"] = "1"
    }
    // Dois modos de janela (menu Visualizar), cada um abrindo no tamanho de um
    // aparelho: celular em pé 412x915 e tablet deitado 1280x800 (pontos = dp).
    // Os dois redimensionam, mas dentro do próprio layout: o celular nunca chega
    // aos 600 dp de largura em que o Instagram vira tablet, e o tablet não desce
    // perto disso. MACAPK_RESOLUTION_UI liga esse comportamento e os itens
    // "Tamanho Padrão" / "Travar Tamanho da Janela".
    // Tamanho da Interface (menu Visualizar: 100/125/150%, em .macapk/ui_scale):
    // a densidade passa a ser 160 x escala da tela x tamanho e as janelas crescem
    // na mesma proporção, então o Instagram continua vendo 412 dp de celular (ou
    // 1280 dp de tablet), desenhados com mais pixels. Numa tela 1x, 125% dá aos
    // ícones de 24 dp 30 px em vez de 24 (ADR 0040).
    // Sem escolha gravada (ou "auto"): a maior escala em que a janela de celular
    // (mais a barra de título) cabe inteira na área útil da tela e, se o tablet
    // cabe a 100%, ele também cabe na escala escolhida.
    let uiScale: Double = {
        let f = embeddedRoot.appendingPathComponent(".macapk/ui_scale")
        let saved = (try? String(contentsOf: f, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let v = Int(saved), v == 100 || v == 125 || v == 150 { return Double(v) / 100.0 }
        guard let area = NSScreen.main?.visibleFrame.size else { return 1.0 }
        let titlebar = 32.0, margin = 16.0
        let tablet_fits = 1280.0 <= area.width && 800.0 + titlebar <= area.height
        for s in [1.5, 1.25] {
            let phone = 915.0 * s + titlebar + margin <= area.height && 412.0 * s <= area.width
            let tablet = !tablet_fits ||
                (1280.0 * s <= area.width && 800.0 * s + titlebar + margin <= area.height)
            if phone && tablet { return s }
        }
        return 1.0
    }()
    func scaledSize(_ w: Double, _ h: Double) -> String {
        "\(Int((w * uiScale).rounded()))x\(Int((h * uiScale).rounded()))"
    }
    if uiScale != 1.0 && getenv("MACAPK_DISPLAY_DENSITY") == nil {
        let backing = Double(NSScreen.main?.backingScaleFactor ?? 1.0)
        env["MACAPK_DISPLAY_DENSITY"] = String(Int((160.0 * backing * uiScale).rounded()))
    }
    for (k, v) in [("MACAPK_RESOLUTION_UI", "1"),
                   ("MACAPK_WINDOW_SIZE_PORTRAIT", scaledSize(412, 915)),
                   ("MACAPK_WINDOW_SIZE_DEFAULT", scaledSize(1280, 800)),
                   // "Controls" são perfis de teclado para jogos: não é deste app.
                   ("MACAPK_MENU_CONTROLS", "0")] where getenv(k) == nil {
        env[k] = v
    }
    if getenv("MACAPK_WINDOW_BUDGET") == nil {
        env["MACAPK_WINDOW_BUDGET"] = scaledSize(1280, 800)
    }
    // PERFORMANCE: o log era o maior custo escondido -- 55 mil linhas de
    // carregamento de classe por sessão (180 mil linhas totais), escritas em
    // arquivo a cada frame de boot. O runtime tem a porta certa para isso:
    // MACAPK_QUIET_CLASSLOAD corta o ruído de AppCl e MACAPK_LOG_LEVEL=4 fica
    // no piso INFO do AOSP.
    if getenv("MACAPK_QUIET_CLASSLOAD") == nil {
        env["MACAPK_QUIET_CLASSLOAD"] = env["MACAPK_QUIET_CLASSLOAD"] ?? "1"
    }
    if getenv("MACAPK_LOG_LEVEL") == nil {
        env["MACAPK_LOG_LEVEL"] = env["MACAPK_LOG_LEVEL"] ?? "4"
    }
    // CRIAR: o "+" do feed abriria a página de câmera do Instagram, que o
    // runtime ainda não mostra (fica em branco). Em vez disso ele abre o painel
    // de arquivos do Mac, em Imagens, com destino Feed (0 = primeira linha de
    // kShareTargets no runtime; ADR 0015).
    if getenv("MACAPK_HOST_CLICK") == nil {
        env["MACAPK_HOST_CLICK"] = env["MACAPK_HOST_CLICK"] ?? "id/action_bar_left_button=0"
    }
    // GALERIA: no runtime as permissões de mídia (READ_MEDIA_IMAGES/VIDEO) são
    // pedidas por um diálogo do instalador do projeto de origem, que este
    // bundle não tem; sem resposta, o MediaStore nega tudo e a galeria do
    // Instagram fica vazia. O dono pediu a galeria com as Imagens do Mac, e só
    // Imagens e Filmes estão mapeados (mapUserMediaFolders): concedidas.
    // CACHE AOT (ADR 0019): com a JRE 25 embutida, as classes já carregadas e
    // ligadas num treino (scripts/train-aot.sh) são mapeadas de um arquivo em
    // ~/Library/Caches/Mac.apk/aot, em vez de lidas e verificadas a cada abertura.
    // Sem o arquivo (ou numa JVM 21) o runtime só registra MISS e segue igual.
    if getenv("MACAPK_AOT_CACHE") == nil {
        env["MACAPK_AOT_CACHE"] = env["MACAPK_AOT_CACHE"] ?? "1"
    }
    // CHIPS: o APK 455 declara igds_chip_radius = 99dp (pílula); no celular do
    // dono os chips do perfil são retângulos de cantos arredondados, o mesmo
    // canto dos botões da tela (8dp). Valor por nome, sobre o do APK.
    if getenv("MACAPK_RES_OVERRIDES") == nil {
        env["MACAPK_RES_OVERRIDES"] = env["MACAPK_RES_OVERRIDES"] ?? "dimen/igds_chip_radius=8dp"
    }
    if getenv("MACAPK_MEDIA_PERMS_ASK") == nil {
        env["MACAPK_MEDIA_PERMS_ASK"] = env["MACAPK_MEDIA_PERMS_ASK"] ?? "0"
    }
    // COLAR: o Android 12+ avisa com um toast ("<app> colou da área de
    // transferência") a cada leitura. No Mac, ⌘V já é o gesto explícito do
    // usuário, e o aviso sai em inglês com o rótulo do pacote.
    if getenv("MACAPK_CLIPBOARD_ACCESS_NOTICE") == nil {
        env["MACAPK_CLIPBOARD_ACCESS_NOTICE"] = env["MACAPK_CLIPBOARD_ACCESS_NOTICE"] ?? "0"
    }
    // ÍCONE: fixo, o do bundle (assets/Instamac.icns; trocar com
    // scripts/set-icon.sh). O launcher aponta MACAPK_APP_ICON para o PNG do
    // bundle, então o Dock nunca mostra o ícone extraído do APK nem muda com ele.
    if getenv("MACAPK_APP_ICON") == nil {
        env["MACAPK_APP_ICON"] = contents
            .appendingPathComponent("Resources/InstamacIcon.png").path
    }
    // O PNG do bundle JÁ está na grade de ícones da Apple (corpo de 824 px num
    // canvas de 1024, sombra na margem). O runtime, por padrão, trata
    // MACAPK_APP_ICON como ícone Android quadrado: encolhe para 80,47% e mascara
    // em squircle. Aplicado a um ícone que já está na grade, isso o encolhe uma
    // segunda vez (medido: corpo de ~663 px no Dock, 20% menor que os vizinhos)
    // e corta a sombra. MACAPK_ICON_ROUND=0 entrega a imagem como ela é.
    if getenv("MACAPK_ICON_ROUND") == nil {
        env["MACAPK_ICON_ROUND"] = "0"
    }
    for (k, v) in env where getenv(k) == nil {
        setenv(k, v, 1)
    }
    _ = fm
}

applyDefaultEnvironment()

// Args extras persistidos: `<android-root>/.macapk/runtime_args`, um token por
// espaço. Serve para fixar geometria/orientação sem recompilar (o runtime lê
// switches irmãos do mesmo diretório, ex. window_policy). Ex.: "--width 1280
// --height 960" ou "--orientation landscape".
private func extraRuntimeArgs() -> [String] {
    let file = embeddedRoot.appendingPathComponent(".macapk/runtime_args")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
}

// ---------------------------------------------------------------------------
// Lançamento: execv, sem processo pai.
//
// MEDIDO: rodar o runtime como FILHO do launcher deixava o boot travado em
// `CacheKeyGenerator.initializeKeyGenerator` em boa parte das aberturas (o
// child não tem identidade de bundle: `lsappinfo` reporta bundleID NULL, o
// AppKit o trata como processo avulso e o init do app perdia a corrida). Rodando
// o runtime DIRETO -- o launcher virando ele com execv -- três aberturas
// seguidas passaram sem tocar em nada.
//
// Com execv o processo do runtime É o app do bundle: identidade, menu, Dock,
// foco e aviso de encerramento ficam todos com o mesmo dono, sem pai no meio.
// Recuperação de estado ruim é manual e explícita: scripts/reset-app-data.sh.
// ---------------------------------------------------------------------------

// Limpeza de pré-voo: locks efêmeros de sessões mortas. Single-instance, então
// nada os segura aqui; um lock velho só pode atrapalhar o init do app.
private func clearStaleLocks() {
    let fm = FileManager.default
    let dataRoot = embeddedRoot.appendingPathComponent("data/data")
    guard let entries = try? fm.contentsOfDirectory(atPath: dataRoot.path) else { return }
    var removed = 0
    for name in entries where name.hasPrefix("com.instagram.") {
        let pkg = dataRoot.appendingPathComponent(name)
        let dirs = [pkg.appendingPathComponent("cache"),
                    pkg.appendingPathComponent("files"),
                    pkg.appendingPathComponent("lib-compressed")]
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files where f.hasSuffix(".lock") || f.hasSuffix(".lck") || f == "dso_lock" {
                if (try? fm.removeItem(at: dir.appendingPathComponent(f))) != nil { removed += 1 }
            }
        }
    }
    if removed > 0 {
        FileHandle.standardError.write("---- pre-flight: \(removed) lock(s) velho(s) removido(s) ----\n"
            .data(using: .utf8)!)
    }
}

clearStaleLocks()

var args = ["--apk", apk.path, "--android-root", embeddedRoot.path]
args.append(contentsOf: extraRuntimeArgs())

var argv: [UnsafeMutablePointer<CChar>?] = [strdup(runtime.path)]
for a in args { argv.append(strdup(a)) }
argv.append(nil)

execv(runtime.path, &argv)
fail("Falha ao iniciar o Instagram",
     "exec de \(runtime.path) falhou: \(String(cString: strerror(errno)))", code: 69)
